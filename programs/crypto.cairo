/// Stress test cryptographique pour le prover STWO.
///
/// Combine trois charges de calcul lourdes :
///   1. Poseidon : permutations repetees (n_hash iterations)
///   2. RSA-style : exponentiation modulaire par carres successifs (n_exp squarings)
///   3. EC : multiplication scalaire manuelle sur courbe de test (n_exp additions)
///
/// Entrees :
///   - n_hash : nombre de rounds Poseidon (felt252)
///   - n_exp  : nombre d'iterations pour RSA modexp et EC scalar mul (felt252)
///
/// Sorties : (poseidon_digest, rsa_result, ec_x, ec_y)
use core::poseidon::PoseidonTrait;
use core::hash::HashStateTrait;
use core::num::traits::WideMul;
use core::integer::u512_safe_div_rem_by_u256;

// =============================================================================
// 1. Poseidon repeated permutations
//    Hash-chain deterministe : digest_{i+1} = Poseidon(digest_i, i)
// =============================================================================

fn poseidon_stress(rounds: u32) -> felt252 {
    let mut digest: felt252 = 0;
    let mut i: u32 = 0;
    while i < rounds {
        let mut state = PoseidonTrait::new();
        state = state.update(digest);
        state = state.update(i.into());
        digest = state.finalize();
        i += 1;
    };
    digest
}

// =============================================================================
// 2. RSA-style modular exponentiation (u256)
//    Repeated squaring: result = 3^(2^n_exp) mod MODULUS
//    MODULUS = secp256k1 curve order (256-bit prime)
// =============================================================================

fn mulmod_u256(a: u256, b: u256, m: NonZero<u256>) -> u256 {
    let wide = a.wide_mul(b);
    let (_, rem) = u512_safe_div_rem_by_u256(wide, m);
    rem
}

fn rsa_modexp_stress(rounds: u32) -> felt252 {
    let modulus: u256 = u256 {
        low: 0xBAAEDCE6AF48A03BBFD25E8CD0364141,
        high: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE,
    };
    let m: NonZero<u256> = modulus.try_into().unwrap();
    let mut result: u256 = 3;
    let mut i: u32 = 0;
    while i < rounds {
        result = mulmod_u256(result, result, m);
        i += 1;
    };
    result.low.into()
}

// =============================================================================
// 3. EC scalar multiplication (pure felt252, pas de builtin ec_op)
//    Courbe : y^2 = x^3 + x + 1 sur le corps de Stark (p = 2^251 + 17*2^192 + 1)
//    Generateur : G = (0, 1)
//    Calcul : rounds * G par additions successives
// =============================================================================

fn felt_div(num: felt252, den: felt252) -> felt252 {
    let den_nz: NonZero<felt252> = den.try_into().unwrap();
    core::felt252_div(num, den_nz)
}

fn ec_double(px: felt252, py: felt252) -> (felt252, felt252) {
    // lambda = (3*x^2 + a) / (2*y),  a = 1
    let lambda = felt_div(3 * px * px + 1, 2 * py);
    let x3 = lambda * lambda - 2 * px;
    let y3 = lambda * (px - x3) - py;
    (x3, y3)
}

fn ec_add_distinct(x1: felt252, y1: felt252, x2: felt252, y2: felt252) -> (felt252, felt252) {
    let lambda = felt_div(y2 - y1, x2 - x1);
    let x3 = lambda * lambda - x1 - x2;
    let y3 = lambda * (x1 - x3) - y1;
    (x3, y3)
}

fn ec_scalar_mul_stress(rounds: u32) -> (felt252, felt252) {
    let gx: felt252 = 0;
    let gy: felt252 = 1;
    if rounds <= 1 {
        return (gx, gy);
    }
    // 2G par doubling, puis additions distinctes de G
    let (mut rx, mut ry) = ec_double(gx, gy);
    let mut i: u32 = 2;
    while i < rounds {
        let (nx, ny) = ec_add_distinct(rx, ry, gx, gy);
        rx = nx;
        ry = ny;
        i += 1;
    };
    (rx, ry)
}

// =============================================================================
// Main
// =============================================================================

#[executable]
fn main(n_hash: felt252, n_exp: felt252) -> (felt252, felt252, felt252, felt252) {
    let hash_rounds: u32 = n_hash.try_into().unwrap();
    let exp_rounds: u32 = n_exp.try_into().unwrap();

    let poseidon_digest = poseidon_stress(hash_rounds);
    let rsa_result = rsa_modexp_stress(exp_rounds);
    let (ec_x, ec_y) = ec_scalar_mul_stress(exp_rounds);

    (poseidon_digest, rsa_result, ec_x, ec_y)
}
