use super::token::Location;

pub struct Program {
    pub imports: Vec<Import>,
    pub functions: Vec<FunctionDef>,
}

pub struct Import {
    pub location: Location,
    pub name: String,
}

pub struct FunctionDef {
    pub location: Location,
    pub name: String,
    pub public: bool,
    pub parameters: Vec<Parameter>,
    pub body: Block,
}

pub struct Parameter {
    pub location: Location,
    pub name: String,
    pub typ: Expression,
}

pub type Block = Vec<Statement>;

pub struct Statement {
    pub location: Location,
    pub kind: StatementType<Statement, Expression>,
}

pub enum StatementType<S, E> {
    Expression(E),

    /// Assign and define variable
    Let {
        name: String,
        mutable: bool,
        value: Expression,
    },

    If {
        condition: E,
        if_true: Vec<S>,
        if_false: Option<Vec<S>>,
    },
    Loop {
        body: Vec<S>,
    },
    While {
        condition: E,
        body: Vec<S>,
    },
    Break,
    Continue,
}

// TODO: remove need for clone!
#[derive(Debug)]
pub struct Expression {
    pub location: Location,
    pub kind: ExpressionType<Expression>,
}

#[derive(Debug)]
pub enum ExpressionType<E> {
    String(String),
    Identifier(String),
    Integer(i64),
    Float(f64),
    Call {
        callee: Box<E>,
        arguments: Vec<E>,
    },
    GetAttr {
        base: Box<E>,
        attr: String,
    },
    Binop {
        lhs: Box<E>,
        op: BinaryOperator,
        rhs: Box<E>,
    },
}

#[derive(Debug)]
pub enum BinaryOperator {
    Math(MathOperator),
    Comparison(ComparisonOperator),
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
}
