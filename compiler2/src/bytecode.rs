/// Wonky bytecode!
///
/// This is intended to be serialized to disk (as json?)
/// Then it can be loaded by the bootstrap compiler, by
/// an interpreter, by a wasm backend, an llvm backend
/// etc..
use serde::Serialize;

#[derive(Clone, Serialize)]
pub struct Program {
    pub imports: Vec<String>,

    /// A list of types, usable via an index.
    pub struct_types: Vec<StructDef>,

    pub functions: Vec<Function>,
}

#[derive(Clone, Serialize)]
pub struct StructDef {
    pub name: Option<String>,
    pub fields: Vec<Typ>,
}

#[derive(Clone, Serialize)]
pub struct Function {
    pub name: String,
    pub parameters: Vec<Parameter>,
    pub locals: Vec<Local>,
    pub code: Vec<Instruction>,
}

#[derive(Clone, Debug, Serialize)]
pub struct Parameter {
    pub name: String,
    pub typ: Typ,
}

#[derive(Clone, Debug, Serialize)]
pub struct Local {
    pub name: String,
    pub typ: Typ,
}

#[derive(Clone, Debug, Serialize)]
pub enum Instruction {
    // Nop,
    BoolLiteral(bool),
    IntLiteral(i64),
    FloatLiteral(f64),
    StringLiteral(String),

    /// Duplicate top of stack value.
    Duplicate,

    /// Allocate new memory for the given type
    Malloc(Typ),

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
    // LoadName {
    //     name: String,
    //     typ: Typ,
    // },
    LoadParameter {
        // name: String, ??
        index: usize,
        typ: Typ,
    },
    LoadLocal {
        // name: String, ??
        index: usize,
        typ: Typ,
    },
    StoreLocal {
        // name: String,
        index: usize,
        // typ: Typ,
    },

    Label(usize),
    Jump(usize),
    JumpIf(usize, usize),

    /// Get the n-th attribute of a struct typed object
    GetAttr {
        index: usize,
        typ: Typ,
    },

    /// Set the n-th attribute of a struct typed thing
    SetAttr(usize),
}

#[derive(Clone, Debug, Serialize)]
pub enum Operator {
    Add,
    Sub,
    Mul,
    Div,
}

#[derive(Clone, Debug, Serialize)]
pub enum Typ {
    Bool,
    Int,
    Float,
    String,
    Ptr(Box<Typ>),

    /// The structured type, contains a sequence of types.
    /// fields are accessed by index
    /// This is a reference to the types table
    Struct(usize),
}

#[derive(Clone, Debug, Serialize)]
pub enum Comparison {
    Lt,
    LtEqual,
    Gt,
    GtEqual,
    Equal,
    NotEqual,
}

pub fn print_bytecode(bc: &Program) {
    for typedef in &bc.struct_types {
        println!(
            "type: {} types={:?}",
            typedef.name.as_ref().unwrap_or(&"".to_owned()),
            &typedef.fields
        );
    }
    for func in &bc.functions {
        println!("Function: {}", func.name);
        println!("  Parameters:");
        for parameter in &func.parameters {
            println!("    {} : {:?}", parameter.name, parameter.typ);
        }
        println!("  Locals:");
        for loc in &func.locals {
            println!("    {} : {:?}", loc.name, loc.typ);
        }
        print_instructions(&func.code);
    }
}

fn print_instructions(instructions: &[Instruction]) {
    println!("  Instructionzzz:");
    for instruction in instructions {
        println!("    : {:?}", instruction);
    }
}
