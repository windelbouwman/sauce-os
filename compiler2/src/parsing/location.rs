#[derive(Clone, Debug, Eq, PartialEq, Default)]
pub struct Location {
    pub row: i32,
    pub column: i32,
}

impl std::fmt::Display for Location {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        // [line {}, column {}]
        // write!(f, "[line {}, column{}]", self.row, self.column)
        write!(f, "[{}:{}]", self.row, self.column)
    }
}
