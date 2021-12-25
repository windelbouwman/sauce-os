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
    // Nop,
    BoolLiteral(bool),
    IntLiteral(i64),
    FloatLiteral(f64),
    StringLiteral(String),

    Call {
        n_args: usize,
        typ: Option<Typ>,
    },
    Operator {
        op: Operator,
        typ: Typ,
    },
    Comparison {
        op: Comparison,
        typ: Typ,
    },
    LoadGlobalName(String),
    LoadName {
        name: String,
        typ: Typ,
    },
    StoreLocal {
        name: String,
        typ: Typ,
    },

    Label(usize),
    Jump(usize),
    JumpIf(usize, usize),

    /// Get the n-th attribute of a struct typed object
    GetAttr(usize),

    /// Set the n-th attribute of a struct typed thing
    SetAttr(usize),
}

#[derive(Debug, Serialize)]
pub enum Operator {
    Add,
    Sub,
    Mul,
    Div,
}

#[derive(Debug, Serialize)]
pub enum Typ {
    Bool,
    Int,
    Float,
    Ptr,

    /// The structured type, contains a sequence of types.
    /// fields are accessed by index
    Struct(Vec<Typ>),
}

#[derive(Debug, Serialize)]
pub enum Comparison {
    Lt,
    LtEqual,
    Gt,
    GtEqual,
    Equal,
    NotEqual,
}

pub fn print_bytecode(bc: &Program) {
    for func in &bc.functions {
        println!("Function: {}", func.name);
        print_instructions(&func.code);
    }
}

fn print_instructions(instructions: &[Instruction]) {
    println!("  Instructionzzz:");
    for instruction in instructions {
        println!("    : {:?}", instruction);
    }
}
