/// Wonky bytecode!
///
/// This is intended to be serialized to disk (as json?)
/// Then it can be loaded by the bootstrap compiler, by
/// an interpreter, by a wasm backend, an llvm backend
/// etc..
use serde::Serialize;

#[derive(Serialize)]
pub struct Program {
    pub imports: Vec<String>,
    pub functions: Vec<Function>,
}

#[derive(Serialize)]
pub struct Function {
    pub name: String,
    pub parameters: Vec<Parameter>,
    pub code: Vec<Instruction>,
}

#[derive(Debug, Serialize)]
pub struct Parameter {
    pub name: String,
    pub typ: Typ,
}

#[derive(Debug, Serialize)]
pub enum Instruction {
    Nop,
    StringLiteral(String),
    IntLiteral(i64),
    FloatLiteral(f64),
    Call { n_args: usize, typ: Option<Typ> },
    Operator { op: Operator, typ: Typ },
    Comparison { op: Comparison, typ: Typ },
    LoadGlobalName(String),
    LoadName { name: String, typ: Typ },
    Label(usize),
    Jump(usize),
    JumpIf(usize, usize),
    // GetAttr(String),
}

#[derive(Debug, Serialize)]
pub enum Operator {
    Add,
    Sub,
    Mul,
}

#[derive(Debug, Serialize)]
pub enum Typ {
    Int,
    Float,
    Ptr,
}

#[derive(Debug, Serialize)]
pub enum Comparison {
    Lt,
    Gt,
    Equal,
}
