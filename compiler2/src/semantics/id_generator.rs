use super::NodeId;

pub struct IdGenerator {
    nxt: usize,
}

impl IdGenerator {
    pub fn new() -> Self {
        IdGenerator { nxt: 0 }
    }

    /// Generate a new unique ID.
    pub fn gimme(&mut self) -> NodeId {
        let x = self.nxt;
        self.nxt += 1;
        x
    }
}
