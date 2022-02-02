//! A typed version of the AST.
//!
//! Expressions are assigned types here.
//!
//! This intermediate form has most language
//! constructs, and types attached.

use super::type_system::{ClassTypeRef, EnumType, MyType};
use crate::parsing::ast;

pub struct Program {
    pub imports: Vec<Import>,
    pub type_defs: Vec<TypeDef>,
    pub functions: Vec<FunctionDef>,
    pub class_defs: Vec<ClassDef>,
}

pub struct ClassDef {
    pub name: String,
    pub field_defs: Vec<FieldDef>,
    pub function_defs: Vec<FunctionDef>,
    // Hmm, having this type here is a bit odd..
    pub typ: ClassTypeRef,
}

pub struct FieldDef {
    pub name: String,
    pub index: usize,
    pub typ: MyType,
    pub value: Expression,
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

pub enum Statement {
    Expression(Expression),
    Let {
        name: String,
        index: usize,
        value: Expression,
    },
    Assignment(AssignmentStatement),
    If(IfStatement),
    Loop {
        body: Block,
    },
    While(WhileStatement),
    Return {
        value: Option<Expression>,
    },
    Match {
        value: Expression,
        arms: Vec<MatchArm>,
    },
    Case(CaseStatement),
    Pass,
    Break,
    Continue,
}

pub struct CaseStatement {
    pub value: Expression,
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

pub struct AssignmentStatement {
    pub target: Expression,
    pub value: Expression,
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

pub struct MatchArm {
    pub pattern: MatchPattern,
    pub body: Vec<Statement>,
}

pub enum MatchPattern {
    Constructor {
        constructor: TypeConstructor,
        arguments: Vec<MatchPattern>,
    },
    WildCard(String),
    // Constant(Literal),
}

pub struct Expression {
    pub typ: MyType,
    pub kind: ExpressionType,
}

pub enum Literal {
    Bool(bool),
    String(String),
    Integer(i64),
    Float(f64),
}

pub enum ExpressionType {
    Literal(Literal),
    StructLiteral(Vec<Expression>),

    /// An enum literal value
    EnumLiteral {
        choice: usize,
        arguments: Vec<Expression>,
    },

    LoadFunction(String),

    // A TypeConstructor is an expression that can create
    // an instance of a type.
    //
    // TBD: this muight be a dubious expression kind:
    TypeConstructor(TypeConstructor),

    /// Implicit 'self' in a class method.
    ImplicitSelf,

    Instantiate,
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
    MethodCall {
        instance: Box<Expression>,
        method: String,
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

pub enum TypeConstructor {
    Any(MyType),
    EnumOption { enum_type: EnumType, choice: usize },
}
