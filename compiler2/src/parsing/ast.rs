use super::location::Location;

pub struct Program {
    pub docstring: Option<String>,
    pub name: String,

    /// The source file path
    pub path: std::path::PathBuf,

    /// Other used modules
    pub imports: Vec<Import>,

    /// Items defined in this module.
    pub definitions: Vec<Definition>,
}

impl Program {
    pub fn deps<'d>(&'d self) -> Vec<&'d String> {
        self.imports
            .iter()
            .map(|i| match i {
                Import::Import { modname, .. } => modname,
                Import::ImportFrom { modname, .. } => modname,
            })
            .collect()
    }
}

pub enum Import {
    Import {
        location: Location,
        modname: String,
    },
    ImportFrom {
        location: Location,
        modname: String,
        names: Vec<String>,
    },
}

pub enum Definition {
    Struct(StructDef),
    Class(ClassDef),
    Enum(EnumDef),
    Function(FunctionDef),
}

/// A variant declaration
///
/// rust's enum type
/// C's enum + optional data, or so called tagged union
pub struct EnumDef {
    pub name: String,
    pub location: Location,
    pub type_parameters: Vec<TypeVar>,
    pub options: Vec<EnumDefOption>,
}

/// A choice inside a variant type
pub struct EnumDefOption {
    pub name: String,
    pub location: Location,

    // An enum can have payload fields:
    pub data: Vec<Expression>,
}

pub struct ClassDef {
    pub name: String,
    pub location: Location,
    pub type_parameters: Vec<TypeVar>,
    pub fields: Vec<VariableDef>,
    pub methods: Vec<FunctionDef>,
}

pub struct VariableDef {
    pub location: Location,
    pub name: String,
    pub typ: Expression,
    pub value: Expression,
}

/// A user defined struct data type.
pub struct StructDef {
    pub location: Location,
    pub name: String,
    pub type_parameters: Vec<TypeVar>,
    pub fields: Vec<StructDefField>,
}

/// A typevariable, usable in generic types.
pub struct TypeVar {
    pub location: Location,
    pub name: String,
}

pub struct StructDefField {
    pub location: Location,
    pub name: String,
    pub typ: Expression,
}

pub struct FunctionDef {
    pub location: Location,
    pub name: String,
    pub public: bool,
    pub signature: FunctionSignature,
    pub body: Block,
}

#[derive(Debug)]
pub struct FunctionSignature {
    pub parameters: Vec<Parameter>,
    pub return_type: Option<Expression>,
}

#[derive(Debug)]
pub struct Parameter {
    pub location: Location,
    pub name: String,
    pub typ: Expression,
}

pub type Block = Vec<Statement>;

pub struct Statement {
    pub location: Location,
    pub kind: StatementKind,
}

pub enum StatementKind {
    Expression(Expression),

    /// Assign and define variable
    Let {
        name: String,
        mutable: bool,
        type_hint: Option<Expression>,
        value: Expression,
    },

    Assignment {
        target: Expression,
        value: Expression,
    },

    If {
        condition: Expression,
        if_true: Vec<Statement>,
        if_false: Option<Vec<Statement>>,
    },
    For {
        name: String,
        it: Expression,
        body: Block,
    },
    Loop {
        body: Block,
    },
    While {
        condition: Expression,
        body: Vec<Statement>,
    },
    Match {
        value: Expression,
        arms: Vec<MatchArm>,
    },

    /// A case is a simple edition of match.
    ///
    /// Case only works with enum types.
    Case {
        value: Expression,
        arms: Vec<CaseArm>,
    },

    /// Switch statement over an integer value
    /// TBD: maybe fold with the 'case' statement?
    Switch {
        value: Expression,
        arms: Vec<SwitchArm>,
        default: Block,
    },
    Return {
        value: Option<Expression>,
    },
    Pass,
    Break,
    Continue,
}

pub struct MatchArm {
    pub location: Location,
    pub pattern: Expression,
    pub body: Block,
}

pub struct CaseArm {
    pub location: Location,
    pub variant: String,
    pub arguments: Vec<String>,
    pub body: Block,
}

pub struct SwitchArm {
    pub location: Location,
    pub value: Expression,
    pub body: Block,
}

#[derive(Debug)]
pub struct Expression {
    pub location: Location,
    pub kind: ExpressionKind,
}

#[derive(Debug)]
pub enum ExpressionKind {
    Object(ObjRef),
    Literal(Literal),
    ObjectInitializer {
        typ: Box<Expression>,
        fields: Vec<LabeledField>,
    },
    ListLiteral(Vec<Expression>),
    Call {
        callee: Box<Expression>,
        arguments: Vec<Expression>,
    },

    FunctionType(Box<FunctionSignature>),

    ArrayIndex {
        base: Box<Expression>,
        indici: Vec<Expression>,
    },

    GetAttr {
        base: Box<Expression>,
        attr: String,
    },

    /// Binary operator
    Binop {
        lhs: Box<Expression>,
        op: BinaryOperator,
        rhs: Box<Expression>,
    },
}

#[derive(Debug)]
pub enum Literal {
    Bool(bool),
    String(String),
    Integer(i64),
    Float(f64),
}

#[derive(Debug)]
pub enum ObjRef {
    Name {
        location: Location,
        name: String,
    },

    /// Scope access
    Inner {
        location: Location,
        base: Box<ObjRef>,
        member: String,
    },
}
/*
impl ObjRef {
    pub fn location(&self) -> Location {
        match self {
            ObjRef::Name { location, .. } | ObjRef::Inner { location, .. } => location.clone(),
        }
    }
}
*/

#[derive(Debug)]
pub struct LabeledField {
    pub location: Location,
    pub name: String,
    pub value: Expression,
}

#[derive(Debug)]
pub enum BinaryOperator {
    Math(MathOperator),
    Comparison(ComparisonOperator),
    Logic(LogicOperator),
    Bit(BitOperator),
}

#[derive(Debug)]
pub enum LogicOperator {
    And,
    Or,
}

#[derive(Debug)]
pub enum BitOperator {
    ShiftLeft,
    ShiftRight,
    Xor,
    And,
    Or,
}

#[derive(Debug)]
pub enum MathOperator {
    Add,
    Sub,
    Mul,
    Div,
}

#[derive(Debug)]
pub enum ComparisonOperator {
    Lt,
    Gt,
    LtEqual,
    GtEqual,
    Equal,
    NotEqual,
}
