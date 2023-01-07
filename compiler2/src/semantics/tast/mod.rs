//! TAST (typed abstract syntax tree)
//!
//! This is working format of programs.
//!
//! First, the program is analyzed, and types are added.
//!
//! Next the program is transformed in several passes.
//!

// Own modules
mod class_type;
mod enum_type;
mod expressions;
mod generics;
mod statements;
mod struct_type;
mod type_system;
mod typed_ast;

use std::cell::RefCell;
use std::rc::Weak;

// re-exports:
pub use class_type::ClassDef;
pub use enum_type::{EnumDef, EnumType, EnumVariant};
pub use expressions::{Expression, ExpressionKind, Literal};
pub use generics::TypeVar;
pub use statements::{
    AssignmentStatement, CaseArm, CaseStatement, ForStatement, IfStatement, Statement,
    StatementKind, SwitchArm, SwitchStatement, WhileStatement,
};
pub use struct_type::{StructDef, StructDefBuilder, StructType, UnionDef};
pub use type_system::{ArrayType, BasicType, SlangType, TypeExpression, TypeVarRef, UserType};
pub use typed_ast::{
    comparison, compound, get_attr, get_index, integer_literal, load_function, load_local,
    return_value, store_local, tuple_literal, undefined_value, union_literal, unreachable_code,
    while_loop,
};
pub use typed_ast::{
    Block, Definition, EnumLiteral, FieldDef, FunctionDef, FunctionSignature, LabeledField,
    LocalVariable, Parameter, Program, VariantRef,
};

use super::scope::Scope;
use super::symbol::Symbol;

pub type NodeId = usize;
pub type Ref<T> = Weak<RefCell<T>>;

#[derive(Debug)]
pub struct NameNodeId {
    pub name: String,
    pub id: NodeId,
}

impl std::fmt::Display for NameNodeId {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{}(id={})", self.name, self.id)
    }
}
