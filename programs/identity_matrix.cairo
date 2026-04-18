/// Construit une matrice identite de taille n et une chaine de m caracteres 'a'.
///
/// Entrees (via `scarb execute --arguments`) :
///   - n : taille de la matrice identite (felt252)
///   - m : longueur de la chaine a generer (felt252)
///
/// Sorties :
///   - La matrice identite I(n) aplatie en ligne (n*n felt252 : 1 sur la diagonale, 0 ailleurs)
///   - Une ByteArray de m caracteres 'a'
#[executable]
fn main(n: felt252, m: felt252) -> (Array<felt252>, ByteArray) {
    let size: u32 = n.try_into().unwrap();
    let repeat: u32 = m.try_into().unwrap();

    let mut matrix: Array<felt252> = array![];
    let mut row: u32 = 0;
    while row < size {
        let mut col: u32 = 0;
        while col < size {
            if row == col {
                matrix.append(1);
            } else {
                matrix.append(0);
            }
            col += 1;
        };
        row += 1;
    };

    let mut s: ByteArray = "";
    let mut i: u32 = 0;
    while i < repeat {
        s.append_byte('a');
        i += 1;
    };

    (matrix, s)
}
