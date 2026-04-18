//! Generic recursive STARK prover for Cairo programs.
//!
//! Two phases:
//!
//! 1. **Cairo proving** — loads `prover_input.json` (from `scarb execute
//!    --target bootloader`) and proves it with stwo-cairo `prove_cairo`.
//!
//! 2. **Recursive circuit proving** — verifies the Cairo proof inside a
//!    stwo-circuits arithmetic circuit and produces a level-1 recursive
//!    `Proof<QM31>`.
//!
//! Usage:
//!
//! ```text
//! recursive_prover --input <prover_input.json> [--output proof.json] [--vk vk.json]
//! ```

use std::array;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Instant;

use circuit_cairo_air::statement::MEMORY_VALUES_LIMBS;
use circuit_cairo_air::verify::{
    CairoVerifierConfig, build_fixed_cairo_circuit,
    enabled_components, prepare_cairo_proof_for_circuit_verifier as cairo_proof_to_qm31,
};

use circuit_prover::prover::{
    BaseColumnPool, CircuitProof, SimdBackend,
    prepare_circuit_proof_for_circuit_verifier as circuit_proof_to_qm31,
    prove_circuit_assignment,
};

use circuit_air::statement::{
    INTERACTION_POW_BITS as CIRCUIT_POW_BITS, all_circuit_components,
};
use circuit_air::verify::{CircuitConfig, CircuitPublicData, verify_circuit};

use circuit_common::preprocessed::PreprocessedCircuit;
use circuit_serialize::serialize::CircuitSerialize;
use circuits_stark_verifier::proof::{Proof as VerifierProof, ProofConfig, ProofInfo};

use cairo_air::CairoProof;
use cairo_air::flat_claims::FlatClaim;
use cairo_air::verifier::INTERACTION_POW_BITS as CAIRO_POW_BITS;
use stwo_cairo_adapter::ProverInput;
use stwo_cairo_common::preprocessed_columns::preprocessed_trace::PreProcessedTraceVariant;
use stwo_cairo_prover::prover::{ChannelHash, ProverParameters, prove_cairo};

use stwo::core::fields::m31::M31;
use stwo::core::fields::qm31::QM31;
use stwo::core::pcs::PcsConfig;
use stwo::core::vcs_lifted::blake2_merkle::{Blake2sM31MerkleChannel, Blake2sM31MerkleHasher};

use clap::Parser;
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

#[derive(Parser, Debug)]
#[command(name = "recursive_prover")]
struct Args {
    /// prover_input.json from `scarb execute --target bootloader`
    #[arg(long = "input", short = 'i')]
    input: PathBuf,

    /// Output path for the recursive proof JSON
    #[arg(long = "output", short = 'o', default_value = "proof.json")]
    output: PathBuf,

    /// Output path for the verification key JSON
    #[arg(long = "vk", default_value = "vk.json")]
    vk_output: PathBuf,

    /// Optional path to save the base Cairo proof (before recursion)
    #[arg(long = "base-proof")]
    base_proof: Option<PathBuf>,
}

// ---------------------------------------------------------------------------
// JSON output
// ---------------------------------------------------------------------------

#[derive(Serialize, Deserialize)]
pub struct ProofOutput {
    pub proof_hex: String,
    pub cairo_prove_ms: u64,
    pub cairo_proof_bytes: usize,
    pub recursive_prove_ms: u64,
    pub proof_bytes: usize,
    pub verify_ms: u64,
}

// ---------------------------------------------------------------------------
// Verification key
// ---------------------------------------------------------------------------

#[derive(Serialize)]
pub struct VkFriConfig {
    pub log_trace_size: usize,
    pub log_blowup_factor: usize,
    pub n_queries: usize,
    pub log_n_last_layer_coefs: usize,
    pub fold_step: usize,
}

#[derive(Serialize)]
pub struct VkProofConfig {
    pub n_pow_bits: u32,
    pub n_interaction_pow_bits: u32,
    pub n_preprocessed_columns: usize,
    pub n_trace_columns: usize,
    pub n_interaction_columns: usize,
    pub n_components: usize,
    pub trace_columns_per_component: Vec<usize>,
    pub interaction_columns_per_component: Vec<usize>,
    pub cumulative_sum_columns: Vec<bool>,
    pub fri: VkFriConfig,
}

#[derive(Serialize)]
pub struct VerificationKey {
    pub preprocessed_root: [u32; 8],
    pub output_addresses: Vec<usize>,
    pub n_blake_gates: usize,
    pub preprocessed_column_ids: Vec<String>,
    pub proof_config: VkProofConfig,
}

fn hash_to_u32s(h: &circuits::blake::HashValue<QM31>) -> [u32; 8] {
    [
        (h.0).0.0.0, (h.0).0.1.0,
        (h.0).1.0.0, (h.0).1.1.0,
        (h.1).0.0.0, (h.1).0.1.0,
        (h.1).1.0.0, (h.1).1.1.0,
    ]
}

fn build_vk(circuit_config: &CircuitConfig, proof_config: &ProofConfig) -> VerificationKey {
    VerificationKey {
        preprocessed_root: hash_to_u32s(&circuit_config.preprocessed_root),
        output_addresses: circuit_config.output_addresses.clone(),
        n_blake_gates: circuit_config.n_blake_gates,
        preprocessed_column_ids: circuit_config
            .preprocessed_column_ids
            .iter()
            .map(|id| id.id.clone())
            .collect(),
        proof_config: VkProofConfig {
            n_pow_bits: proof_config.n_pow_bits,
            n_interaction_pow_bits: proof_config.n_interaction_pow_bits,
            n_preprocessed_columns: proof_config.n_preprocessed_columns,
            n_trace_columns: proof_config.n_trace_columns,
            n_interaction_columns: proof_config.n_interaction_columns,
            n_components: proof_config.n_components,
            trace_columns_per_component: proof_config.trace_columns_per_component.clone(),
            interaction_columns_per_component: proof_config.interaction_columns_per_component.clone(),
            cumulative_sum_columns: proof_config.cumulative_sum_columns.clone(),
            fri: VkFriConfig {
                log_trace_size: proof_config.fri.log_trace_size,
                log_blowup_factor: proof_config.fri.log_blowup_factor,
                n_queries: proof_config.fri.n_queries,
                log_n_last_layer_coefs: proof_config.fri.log_n_last_layer_coefs,
                fold_step: proof_config.fri.fold_step,
            },
        },
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn load_prover_input(path: &Path) -> Result<ProverInput, String> {
    let s = std::fs::read_to_string(path)
        .map_err(|e| format!("read {}: {e}", path.display()))?;
    serde_json::from_str(&s)
        .map_err(|e| format!("parse {}: {e}", path.display()))
}

fn cairo_pcs_config() -> PcsConfig {
    use stwo::core::fri::FriConfig;
    const LOG_BLOWUP: u32 = 1;
    const MAX_SEQUENCE_LOG_SIZE: u32 = 20;
    PcsConfig {
        pow_bits: 26,
        fri_config: FriConfig {
            log_blowup_factor: LOG_BLOWUP,
            log_last_layer_degree_bound: 0,
            n_queries: 70,
            fold_step: 4,
        },
        lifting_log_size: Some(MAX_SEQUENCE_LOG_SIZE + LOG_BLOWUP),
    }
}

fn stwo_prove(input: ProverInput) -> Result<CairoProof<Blake2sM31MerkleHasher>, String> {
    let params = ProverParameters {
        channel_hash: ChannelHash::Blake2sM31,
        pcs_config: cairo_pcs_config(),
        preprocessed_trace: PreProcessedTraceVariant::CanonicalSmall,
        channel_salt: 0,
        store_polynomials_coefficients: true,
        include_all_preprocessed_columns: true,
    };
    prove_cairo::<Blake2sM31MerkleChannel>(input, params)
        .map_err(|e| format!("prove_cairo: {e:?}"))
}

// ---------------------------------------------------------------------------
// Level-1 recursive proving
// ---------------------------------------------------------------------------

struct Level1Output {
    circuit_config: CircuitConfig,
    proof_config: ProofConfig,
    proof_qm31: VerifierProof<QM31>,
    public_data: CircuitPublicData,
    cairo_proof_bytes: usize,
    proof_bytes: usize,
}

fn circuit_config_from_proof(
    circuit_proof: &CircuitProof,
    preprocessed: &PreprocessedCircuit,
) -> CircuitConfig {
    let preprocessed_root = circuit_proof
        .stark_proof
        .as_ref()
        .expect("circuit proof must have succeeded")
        .proof
        .commitments[0]
        .into();

    CircuitConfig {
        config: circuit_proof.pcs_config,
        output_addresses: preprocessed.params.output_addresses.clone(),
        n_blake_gates: preprocessed.params.n_blake_gates,
        preprocessed_column_ids: preprocessed.preprocessed_trace.ids(),
        preprocessed_root,
    }
}

fn recursive_prove(
    cairo_proof: &CairoProof<Blake2sM31MerkleHasher>,
) -> Result<Level1Output, String> {
    let FlatClaim { component_enable_bits, .. } = cairo_proof.claim.flatten_claim();

    let components = enabled_components::<QM31>(&component_enable_bits);

    let pp_ids = cairo_proof
        .preprocessed_trace_variant
        .to_preprocessed_trace()
        .ids();

    let proof_stored_config = &cairo_proof.extended_stark_proof.proof.config;
    let ppt_root = cairo_proof.extended_stark_proof.proof.commitments[0];

    let cairo_proof_config = ProofConfig::from_components(
        &components,
        component_enable_bits.clone(),
        pp_ids.len(),
        proof_stored_config,
        CAIRO_POW_BITS,
    );

    let cairo_proof_bytes = ProofInfo::from_config(&cairo_proof_config).total_bytes();

    let (proof_qm31_cairo, public_data_cairo) =
        cairo_proof_to_qm31(cairo_proof, &cairo_proof_config);

    let (public_claim, outputs_raw, program_raw) = public_data_cairo.pack_into_u32s();

    let outputs: Vec<[M31; MEMORY_VALUES_LIMBS]> = outputs_raw
        .chunks_exact(MEMORY_VALUES_LIMBS)
        .map(|chunk| array::from_fn(|i| M31::from_u32_unchecked(chunk[i])))
        .collect();

    let program: Arc<[[M31; MEMORY_VALUES_LIMBS]]> = program_raw
        .chunks_exact(MEMORY_VALUES_LIMBS)
        .map(|chunk| array::from_fn(|i| M31::from_u32_unchecked(chunk[i])))
        .collect();

    let verifier_cfg = CairoVerifierConfig {
        proof_config: cairo_proof_config,
        program,
        n_outputs: cairo_proof.claim.public_data.public_memory.output.len(),
        preprocessed_root: ppt_root.into(),
        preprocessed_trace_variant: cairo_proof.preprocessed_trace_variant,
    };

    // Build QM31 circuit (with witness), finalize, preprocess, then prove —
    // all from the SAME context, matching the pattern in stwo-circuits tests.
    let mut ctx = build_fixed_cairo_circuit(
        &verifier_cfg,
        proof_qm31_cairo,
        public_claim,
        outputs,
    );
    if !ctx.is_circuit_valid() {
        let gate_err = ctx.circuit.check(ctx.values()).unwrap_err();
        return Err(format!("build_fixed_cairo_circuit: {gate_err}"));
    }

    let preprocessed = PreprocessedCircuit::preprocess_circuit(&mut ctx);

    let circuit_proof = prove_circuit_assignment(
        ctx.values(),
        &preprocessed,
        &BaseColumnPool::<SimdBackend>::new(),
        PcsConfig::default(),
    );

    circuit_proof
        .stark_proof
        .as_ref()
        .map_err(|e| format!("prove_circuit_assignment: {e:?}"))?;

    let circuit_config = circuit_config_from_proof(&circuit_proof, &preprocessed);
    let circuit_proof_config = ProofConfig::from_components(
        &all_circuit_components::<QM31>(),
        vec![true; all_circuit_components::<QM31>().len()],
        circuit_config.preprocessed_column_ids.len(),
        &circuit_config.config,
        CIRCUIT_POW_BITS,
    );
    let proof_bytes = ProofInfo::from_config(&circuit_proof_config).total_bytes();
    let (proof_qm31, public_data) = circuit_proof_to_qm31(circuit_proof, &circuit_proof_config);

    Ok(Level1Output {
        circuit_config,
        proof_config: circuit_proof_config,
        proof_qm31,
        public_data,
        cairo_proof_bytes,
        proof_bytes,
    })
}

fn serialise_proof(level1: &Level1Output) -> Result<String, String> {
    let mut bytes: Vec<u8> = Vec::new();
    level1.proof_qm31.serialize(&mut bytes);
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

fn main() {
    let args = Args::parse();

    // Phase 1: Cairo proving
    eprintln!("  1/3  cairo proving  (prove_cairo) …");
    let t0 = Instant::now();

    let input = load_prover_input(&args.input).unwrap_or_else(|e| {
        eprintln!("ERROR loading input: {e}");
        eprintln!("  hint: run `scarb execute --target bootloader --output standard` first");
        std::process::exit(1);
    });

    let cairo_proof = stwo_prove(input).unwrap_or_else(|e| {
        eprintln!("ERROR (prove_cairo): {e}");
        std::process::exit(1);
    });

    let cairo_prove_ms = t0.elapsed().as_millis() as u64;
    eprintln!("  ✓ Cairo proof done — {cairo_prove_ms}ms");

    if let Some(ref base_path) = args.base_proof {
        let base_json = serde_json::to_string(&cairo_proof)
            .expect("serialise base cairo proof");
        std::fs::write(base_path, &base_json)
            .unwrap_or_else(|e| panic!("write {}: {e}", base_path.display()));
        eprintln!(
            "  wrote base proof ({} bytes) → {}",
            base_json.len(),
            base_path.display()
        );
    }

    // Phase 2: Recursive circuit proving
    eprintln!("  2/3  recursive circuit proving  (stwo-circuits level-1) …");
    let t1 = Instant::now();

    let level1 = recursive_prove(&cairo_proof).unwrap_or_else(|e| {
        eprintln!("ERROR (recursive_prove): {e}");
        std::process::exit(1);
    });

    let recursive_prove_ms = t1.elapsed().as_millis() as u64;
    let cairo_proof_bytes = level1.cairo_proof_bytes;
    let proof_bytes = level1.proof_bytes;
    let vk = build_vk(&level1.circuit_config, &level1.proof_config);
    eprintln!("  ✓ recursive proof done — {recursive_prove_ms}ms");

    let proof_hex = serialise_proof(&level1).unwrap_or_else(|e| {
        eprintln!("ERROR serialising proof: {e}");
        std::process::exit(1);
    });

    // Phase 3: Verify the recursive proof
    eprintln!("  3/3  verifying recursive proof  (circuit_air::verify_circuit) …");
    let t_verify = Instant::now();
    let Level1Output { circuit_config, proof_qm31, public_data, .. } = level1;
    verify_circuit(circuit_config, proof_qm31, public_data).unwrap_or_else(|e| {
        eprintln!("ERROR (verify_circuit): {e}");
        std::process::exit(1);
    });
    let verify_ms = t_verify.elapsed().as_millis() as u64;
    eprintln!("  ✓ proof verified — {verify_ms}ms");

    // Write output
    let out = ProofOutput {
        proof_hex,
        cairo_prove_ms,
        cairo_proof_bytes,
        recursive_prove_ms,
        proof_bytes,
        verify_ms,
    };

    std::fs::write(
        &args.output,
        serde_json::to_string_pretty(&out).expect("serialise output"),
    )
    .unwrap_or_else(|e| panic!("write {}: {e}", args.output.display()));

    std::fs::write(
        &args.vk_output,
        serde_json::to_string_pretty(&vk).expect("serialise vk"),
    )
    .unwrap_or_else(|e| panic!("write {}: {e}", args.vk_output.display()));

    eprintln!(
        "  wrote {}",
        args.output.file_name().unwrap_or(args.output.as_os_str()).to_string_lossy()
    );
    eprintln!(
        "  wrote {}",
        args.vk_output.file_name().unwrap_or(args.vk_output.as_os_str()).to_string_lossy()
    );
}
