//! A simple typed version of the AST.
//!
//! This is almost a C-like language:
//! almost only functions and structs

use super::semantics::type_system::{EnumType, MyType};
use super::semantics::typed_ast;
use crate::parsing::ast;

pub struct Program {
    pub imports: Vec<typed_ast::Import>,
    pub functions: Vec<FunctionDef>,
}

pub struct FunctionDef {
    pub name: String,
    pub parameters: Vec<typed_ast::Parameter>,
    pub return_type: Option<MyType>,
    pub locals: Vec<typed_ast::LocalVariable>,
    pub body: Block,
}

pub type Block = Vec<Statement>;

pub enum Statement {
    Expression(Expression),
    Let {
        name: String,
        index: usize,
        value: Expression,
    },
    If(IfStatement),
    Loop {
        body: Block,
    },
    While(WhileStatement),

    /// We allow case statements in the simple-ast form.
    /// `match` statements must be converted into case
    /// statements before.
    Case(CaseStatement),
    Return {
        value: Option<Expression>,
    },
    Pass,
    Break,
    Continue,
    StoreLocal {
        index: usize,
        value: Expression,
    },
    SetAttr {
        base: Expression,
        base_typ: MyType,
        index: usize,
        value: Expression,
    },
}

pub struct CaseStatement {
    pub value: Expression,
    pub enum_type: EnumType,
    pub arms: Vec<CaseArm>,
}

pub struct CaseArm {
    /// Index into the chosen enum variant:
    pub choice: usize,

    /// Id's of local variables used for this arms unpacked values
    pub local_ids: Vec<usize>,

    /// The code of this case arm.
    pub body: Block,
}

pub struct IfStatement {
    pub condition: Expression,
    pub if_true: Block,
    pub if_false: Option<Block>,
}

pub struct WhileStatement {
    pub condition: Expression,
    pub body: Block,
}

pub enum Expression {
    Literal(typed_ast::Literal),
    StructLiteral {
        typ: MyType,
        values: Vec<Expression>,
    },

    UnionLiteral {
        typ: MyType,
        index: usize,
        value: Box<Expression>,
    },
    VoidLiteral,

    LoadFunction(String),

    LoadParameter {
        index: usize,
    },
    LoadLocal {
        index: usize,
        typ: MyType,
    },
    Call {
        callee: Box<Expression>,
        arguments: Vec<Expression>,
        typ: MyType,
    },
    GetAttr {
        base: Box<Expression>,
        base_typ: MyType,
        index: usize,
    },
    Binop {
        lhs: Box<Expression>,
        op: ast::BinaryOperator,
        rhs: Box<Expression>,
        /// Result type
        typ: MyType,
        /// Operand type
        op_typ: MyType,
    },
}
