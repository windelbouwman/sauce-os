/// Wonky bytecode!
///
/// This is intended to be serialized to disk (as json?)
/// Then it can be loaded by the bootstrap compiler, by
/// an interpreter, by a wasm backend, an llvm backend
/// etc..
use serde::Serialize;

#[derive(Clone, Serialize)]
pub struct Program {
    pub imports: Vec<Import>,

    /// A list of types, usable via an index.
    pub struct_types: Vec<StructDef>,

    pub functions: Vec<Function>,
}

#[derive(Clone, Serialize)]
pub struct Import {
    pub name: String,
    pub parameter_types: Vec<Typ>,
    pub return_type: Option<Typ>,
}

#[derive(Clone, Serialize, PartialEq, Eq, Hash)]
pub struct StructDef {
    pub name: Option<String>,
    pub fields: Vec<Typ>,
}

#[derive(Clone, Debug, Serialize)]
pub struct Function {
    pub name: String,
    pub parameters: Vec<Parameter>,
    pub return_type: Option<Typ>,
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
    Nop,

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

    /// Load function parameter value on the stack.
    LoadParameter {
        index: usize,
    },

    /// Load local variable onto the stack.
    LoadLocal {
        index: usize,
        typ: Typ,
    },

    /// Store value in local variable
    StoreLocal {
        index: usize,
    },

    // Label(usize),
    /// Jump to a location in bytecode.
    Jump(usize),

    JumpIf(usize, usize),

    /// Return n values.
    /// For now return 0 or 1 values.
    Return(usize),

    /// Get the n-th attribute of a struct typed object
    GetAttr {
        index: usize,
        typ: Typ,
    },

    /// Set the n-th attribute of a struct typed thing
    SetAttr {
        index: usize,
    },
}

impl Instruction {
    pub fn is_terminator(&self) -> bool {
        match self {
            Instruction::Return(_) | Instruction::Jump(_) | Instruction::JumpIf(_, _) => true,
            _ => false,
        }
    }
}

#[derive(Clone, Debug, Serialize)]
pub enum Operator {
    Add,
    Sub,
    Mul,
    Div,
}

#[derive(Clone, Debug, Serialize, PartialEq, Eq, Hash)]
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
            "type: name={} types={:?}",
            typedef.name.as_ref().unwrap_or(&"".to_owned()),
            &typedef.fields
        );
    }

    for import in &bc.imports {
        println!(
            "Import name={} ({:?}) -> {:?}",
            import.name, import.parameter_types, import.return_type
        );
    }

    for func in &bc.functions {
        println!("Function: {} : {:?}", func.name, func.return_type);
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
    println!("  Code:");
    for (index, instruction) in instructions.iter().enumerate() {
        println!("    {} : {:?}", index, instruction);
    }
}
