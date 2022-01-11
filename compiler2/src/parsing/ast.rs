use super::token::Location;

pub struct Program {
    pub name: Option<String>,
    pub imports: Vec<Import>,
    pub typedefs: Vec<TypeDef>,
    pub functions: Vec<FunctionDef>,
}

impl Program {
    pub fn deps(&self) -> Vec<String> {
        self.imports.iter().map(|i| i.name.clone()).collect()
    }
}

pub struct Import {
    pub location: Location,
    pub name: String,
}

pub enum TypeDef {
    Struct(StructDef),
    Generic {
        name: String,
        location: Location,
        parameters: Vec<TypeVar>,
        base: Box<TypeDef>,
    },
    Class(ClassDef),
}

pub struct ClassDef {
    pub name: String,
    pub location: Location,
    pub fields: Vec<VarDef>,
    pub methods: Vec<FunctionDef>,
}

pub struct VarDef {
    pub location: Location,
    pub name: String,
    pub typ: Type,
    pub value: Expression,
}

/// A user defined struct data type.
pub struct StructDef {
    pub location: Location,
    pub name: String,
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
    pub typ: Type,
}

pub struct FunctionDef {
    pub location: Location,
    pub name: String,
    pub public: bool,
    pub parameters: Vec<Parameter>,
    pub return_type: Option<Type>,
    pub body: Block,
}

pub struct Parameter {
    pub location: Location,
    pub name: String,
    pub typ: Type,
}

pub type Block = Vec<Statement>;

pub struct Statement {
    pub location: Location,
    pub kind: StatementType,
}

pub enum StatementType {
    Expression(Expression),

    /// Assign and define variable
    Let {
        name: String,
        mutable: bool,
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
        body: Vec<Statement>,
    },
    Loop {
        body: Vec<Statement>,
    },
    While {
        condition: Expression,
        body: Vec<Statement>,
    },
    Return {
        value: Option<Expression>,
    },
    Pass,
    Break,
    Continue,
}

#[derive(Debug)]
pub struct Expression {
    pub location: Location,
    pub kind: ExpressionType,
}

#[derive(Debug)]
pub enum ExpressionType {
    Object(ObjRef),
    String(String),
    Integer(i64),
    Float(f64),
    Bool(bool),
    StructLiteral {
        typ: Type,
        fields: Vec<StructLiteralField>,
    },
    Call {
        callee: Box<Expression>,
        arguments: Vec<Expression>,
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

/// A type specification
#[derive(Debug)]
pub struct Type {
    pub location: Location,
    pub kind: TypeKind,
}

#[derive(Debug)]
pub enum TypeKind {
    Object(ObjRef),

    // generic types!
    GenericInstantiate {
        base_type: Box<Type>,
        type_parameters: Vec<Type>,
    },
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

#[derive(Debug)]
pub struct StructLiteralField {
    pub location: Location,
    pub name: String,
    pub value: Expression,
}

#[derive(Debug)]
pub enum BinaryOperator {
    Math(MathOperator),
    Comparison(ComparisonOperator),
    Logic(LogicOperator),
}

#[derive(Debug)]
pub enum LogicOperator {
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
