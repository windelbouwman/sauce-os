use super::tast::NodeId;

pub struct IdGenerator {
    nxt: usize,
}

impl IdGenerator {
    pub fn new() -> Self {
        IdGenerator { nxt: 0 }
    }

    /// Generate a new unique ID.
    pub fn gimme(&mut self) -> NodeId {
        // Skip 0 id:
        self.nxt += 1;
        self.nxt
    }
}
