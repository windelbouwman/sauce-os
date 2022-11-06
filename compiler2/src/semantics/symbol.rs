//! Representation of a symbol.
//!
//! Symbols can refer to variables, parameters, functions etc..
//!

use super::type_system::SlangType;
use super::typed_ast;
use super::Ref;

use std::rc::{Rc, Weak};

#[derive(Clone)]
pub enum Symbol {
    Generic(Weak<typed_ast::GenericDef>),
    Typ(SlangType),
    Function(Ref<typed_ast::FunctionDef>),
    ExternFunction { name: String, typ: SlangType },
    Module(Rc<typed_ast::Program>),
    Parameter(Ref<typed_ast::Parameter>),
    LocalVariable(Ref<typed_ast::LocalVariable>),
    Field(Ref<typed_ast::FieldDef>),
    EnumVariant(Ref<typed_ast::EnumVariant>),
}

impl std::fmt::Display for Symbol {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            Symbol::Generic(generic) => {
                let generic = generic.upgrade().unwrap();
                write!(f, "symbol-generic({})", generic.name)
            }
            Symbol::Typ(typ) => {
                write!(f, "symbol-typ({})", typ)
            }
            Symbol::Function(_) => {
                write!(f, "symbol-function(..)")
            }
            Symbol::ExternFunction { name, typ: _ } => {
                write!(f, "symbol-extern-function(name={})", name)
            }
            Symbol::Module(_) => {
                write!(f, "symbol-module(..)")
            }
            Symbol::Parameter(_) => {
                write!(f, "symbol-parameter(..)")
            }
            Symbol::LocalVariable(_) => {
                write!(f, "symbol-local(..)")
            }
            Symbol::Field(_) => {
                write!(f, "symbol-field(..)")
            }
            Symbol::EnumVariant(_) => {
                write!(f, "symbol-enum-variant(..)")
            }
        }
    }
}

impl std::fmt::Debug for Symbol {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        // Use the display logic for debug as well:
        write!(f, "{}", self)
    }
}
