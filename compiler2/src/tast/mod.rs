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
mod scope;
mod statements;
mod struct_type;
mod symbol;
mod type_system;
mod typed_ast;
mod typed_ast_printer;
mod visitor;

use std::cell::RefCell;
use std::rc::{Rc, Weak};

// re-exports:
pub use class_type::ClassDef;
pub use enum_type::{EnumDef, EnumType, EnumVariant};
pub use expressions::{Expression, ExpressionKind, Literal};
pub use generics::{get_substitution_map, TypeVar};
pub use scope::Scope;
pub use statements::{
    AssignmentStatement, CaseArm, CaseStatement, ForStatement, IfStatement, Statement,
    StatementKind, SwitchArm, SwitchStatement, WhileStatement,
};
pub use struct_type::{StructDef, StructDefBuilder, StructType, UnionDef};
pub use symbol::{DefinitionRef, Symbol};
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
pub use typed_ast_printer::print_ast;
pub use visitor::{visit_program, VisitedNode, VisitorApi};

pub type NodeId = usize;
pub type Ref<T> = Weak<RefCell<T>>;

/// Refer to the given reference
pub fn refer<'t, T>(r: &'t Ref<T>) -> Rc<RefCell<T>> {
    r.upgrade().unwrap()
}

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
