//! A typed version of the AST.
//!
//! Expressions are assigned types here.

use super::type_system::{MyType, StructType};
use crate::parsing::ast;

pub struct Program {
    pub imports: Vec<Import>,
    pub type_defs: Vec<TypeDef>,
    pub functions: Vec<FunctionDef>,
}

pub struct TypeDef {
    pub name: String,
    pub typ: MyType,
}

pub struct Import {
    pub name: String,
    pub typ: MyType,
}

pub struct FunctionDef {
    pub name: String,
    pub parameters: Vec<Parameter>,
    pub return_type: Option<MyType>,
    pub locals: Vec<LocalVariable>,
    pub body: Block,
}

pub struct LocalVariable {
    pub name: String,
    pub typ: MyType,
}

pub struct Parameter {
    pub name: String,
    pub typ: MyType,
}

pub type Block = Vec<Statement>;

pub struct Statement {
    pub kind: StatementType,
}

pub enum StatementType {
    Expression(Expression),
    Let {
        name: String,
        index: usize,
        value: Expression,
    },
    Assignment {
        target: Expression,
        value: Expression,
    },
    If {
        condition: Expression,
        if_true: Block,
        if_false: Option<Block>,
    },
    Loop {
        body: Block,
    },
    While {
        condition: Expression,
        body: Block,
    },
    Return {
        value: Option<Expression>,
    },
    Pass,
    Break,
    Continue,
}

pub struct Expression {
    pub typ: MyType,
    pub kind: ExpressionType,
}

pub enum ExpressionType {
    Bool(bool),
    String(String),
    Integer(i64),
    Float(f64),
    StructLiteral(Vec<Expression>),
    LoadFunction(String),
    LoadParameter {
        name: String,
        index: usize,
    },
    LoadLocal {
        name: String,
        index: usize,
    },
    Call {
        callee: Box<Expression>,
        arguments: Vec<Expression>,
    },
    GetAttr {
        base: Box<Expression>,
        attr: String,
    },
    Binop {
        lhs: Box<Expression>,
        op: ast::BinaryOperator,
        rhs: Box<Expression>,
    },
}
