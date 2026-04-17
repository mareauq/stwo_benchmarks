/// Calcule le n-ieme nombre de Fibonacci de maniere iterative.
///
/// `n` est passe en entree publique du programme (via `scarb execute --arguments`).
/// La valeur de retour est emise en sortie publique, et sera contrainte par la preuve.
#[executable]
fn main(n: u32) -> felt252 {
    let mut a: felt252 = 0;
    let mut b: felt252 = 1;
    let mut i: u32 = 0;
    while i < n {
        let c = a + b;
        a = b;
        b = c;
        i += 1;
    };
    a
}
