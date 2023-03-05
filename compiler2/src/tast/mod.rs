//! TAST (typed abstract syntax tree)
//!
//! This is working format of programs.
//!
//! First, the program is analyzed, and types are added.
//!
//! Next the program is transformed in several passes.
//!

// Own modules
pub mod api;
mod class_type;
mod definitions;
mod enum_type;
mod expressions;
mod functions;
mod generics;
mod printer;
mod scope;
mod statements;
mod struct_type;
mod symbol;
mod typed_ast;
mod types;
mod visitor;

use std::cell::RefCell;
use std::rc::{Rc, Weak};

// re-exports:
pub use class_type::{ClassDef, ClassType};
pub use definitions::{Definition, DefinitionRef};
pub use enum_type::{EnumDef, EnumType, EnumVariant};
pub use expressions::{EnumLiteral, Expression, ExpressionKind, LabeledField, Literal};
pub use functions::{Function, FunctionDef, FunctionSignature, LocalVariable, Parameter};
pub use generics::{
    get_binding_text, get_substitution_map, get_type_vars_text, replace_type_vars_sub,
};
pub use generics::{TypeVar, TypeVarRef};
pub use printer::print_ast;
pub use scope::Scope;
pub use statements::{
    AssignmentStatement, Block, CaseArm, CaseStatement, ForStatement, IfStatement, Statement,
    StatementKind, SwitchArm, SwitchStatement, WhileStatement,
};
pub use struct_type::{FieldDef, StructDef, StructDefBuilder, StructType};
pub use symbol::Symbol;
pub use typed_ast::{Program, VariantRef};
pub use types::{ArrayType, BasicType, SlangType, TypeExpression, UserType};
pub use visitor::{visit_program, VisitedNode, VisitorApi};

pub type NodeId = usize;
pub type Ref<T> = Weak<RefCell<T>>;

/// Refer to the given reference
pub fn refer<'t, T>(r: &'t Ref<T>) -> Rc<RefCell<T>> {
    r.upgrade().unwrap()
}

#[derive(Debug, Clone)]
pub struct NameNodeId {
    pub name: String,
    pub id: NodeId,
}

impl std::fmt::Display for NameNodeId {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{}(id={})", self.name, self.id)
    }
}
