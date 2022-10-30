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
    pub types: Vec<TypeDef>,

    /// A set of functions defined in this module.
    pub functions: Vec<Function>,
}

#[derive(Clone, Serialize)]
pub struct Import {
    pub name: String,
    pub parameter_types: Vec<Typ>,
    pub return_type: Option<Typ>,
}

#[derive(Clone, Serialize, PartialEq, Eq, Hash)]
pub enum TypeDef {
    Struct(StructDef),
    Union(UnionDef),
    Array { size: usize, element_type: Typ },
}

#[derive(Clone, Serialize, PartialEq, Eq, Hash)]
pub struct StructDef {
    pub name: Option<String>,
    pub fields: Vec<Typ>,
}

#[derive(Clone, Serialize, PartialEq, Eq, Hash)]
pub struct UnionDef {
    pub name: String,
    pub choices: Vec<Typ>,
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

    UndefinedLiteral,

    /// Duplicate top of stack value.
    Duplicate,

    DropTop,

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
    },

    /// Store value in local variable
    StoreLocal {
        index: usize,
    },

    // Label(usize),
    /// Jump to a location in bytecode.
    Jump(usize),

    JumpIf(usize, usize),

    /// Jump to one of the given targets.
    /// selected by the last value on the stack (must be i64).
    ///
    /// IDEA: Java JVM has lookupswitch and tableswitch opcodes.
    JumpSwitch {
        default: usize,
        options: Vec<(i64, usize)>,
    },

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

    /// Get element from an array
    GetElement {
        typ: Typ,
    },

    /// Set element in an array
    SetElement,
}

impl Instruction {
    pub fn is_terminator(&self) -> bool {
        match self {
            Instruction::Return(_)
            | Instruction::Jump(_)
            | Instruction::JumpIf(_, _)
            | Instruction::JumpSwitch { .. } => true,
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
    // TBD: void type might not be a good idea?
    Void,
    Bool,
    Int,
    Float,
    String,
    Ptr(Box<Typ>),

    /// This is a reference to the types table
    Composite(usize),
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
    println!("=========== BYTECODE ==============>>");
    println!("Types:");
    for (index, typedef) in bc.types.iter().enumerate() {
        match typedef {
            TypeDef::Struct(struct_type) => {
                println!(
                    "  {}: struct name={} types={:?}",
                    index,
                    struct_type.name.as_ref().unwrap_or(&"".to_owned()),
                    &struct_type.fields
                );
            }
            TypeDef::Union(union_type) => {
                println!(
                    "  {}: union name={} types={:?}",
                    index, union_type.name, &union_type.choices
                );
            }
            TypeDef::Array { size, element_type } => {
                println!(
                    "  {}: array size={} element_type={:?}",
                    index, size, element_type
                );
            }
        }
    }

    println!("Imports:");
    for import in &bc.imports {
        println!(
            "  name={} ({:?}) -> {:?}",
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
        for (index, local) in func.locals.iter().enumerate() {
            println!("    {}: {} : {:?}", index, local.name, local.typ);
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
