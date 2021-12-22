//! A typed version of the AST.
//!
//! Expressions are assigned types here.

use super::type_system::MyType;
use crate::parsing::ast;

pub struct Program {
    pub imports: Vec<ast::Import>,
    pub functions: Vec<TypedFunctionDef>,
}

pub struct TypedFunctionDef {
    pub name: String,
    pub parameters: Vec<Parameter>,
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
    Break,
    Continue,
}

pub struct Expression {
    pub typ: MyType,
    pub kind: ExpressionType,
}

pub enum ExpressionType {
    String(String),
    Integer(i64),
    Float(f64),
    // Identifier(String), // This is resolved in this version of the refined AST.
    LoadGlobal(String),
    LoadFunction(String),
    LoadParameter(String),
    LoadLocal(String),
    Call {
        callee: Box<Expression>,
        arguments: Vec<Expression>,
    },
    // GetAttr {
    //     base: Box<Expression>,
    //     attr: String,
    // },
    Binop {
        lhs: Box<Expression>,
        op: ast::BinaryOperator,
        rhs: Box<Expression>,
    },
}
