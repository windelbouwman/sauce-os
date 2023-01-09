//! Representation of a symbol.
//!
//! Symbols can refer to variables, parameters, functions etc..
//!

use super::{
    DefinitionRef, EnumVariant, FieldDef, FunctionDef, LocalVariable, Parameter, Program, Ref,
    SlangType,
};

use std::rc::Rc;

#[derive(Clone)]
pub enum Symbol {
    Typ(SlangType),
    Definition(DefinitionRef),
    Function(Ref<FunctionDef>),
    ExternFunction {
        name: String,
        typ: SlangType,
    },
    Module(Rc<Program>),
    Parameter(Ref<Parameter>),
    LocalVariable(Ref<LocalVariable>),
    Field(Ref<FieldDef>),
    EnumVariant(
        // typ: SlangType,
        // variant:
        Ref<EnumVariant>,
    ),
}

impl Symbol {
    /// Try to retrieve a type from this symbol.
    pub fn get_type(&self) -> SlangType {
        match self {
            Symbol::Field(field_ref) => field_ref.upgrade().unwrap().borrow().typ.clone(),
            Symbol::Function(func_ref) => func_ref.upgrade().unwrap().borrow().get_type(),
            Symbol::Parameter(param_ref) => param_ref.upgrade().unwrap().borrow().typ.clone(),
            Symbol::LocalVariable(local_ref) => local_ref.upgrade().unwrap().borrow().typ.clone(),
            Symbol::ExternFunction { name: _, typ } => typ.clone(),
            other => {
                panic!("Unexpected user-type member: {}", other);
            }
        }
    }
}

impl std::fmt::Display for Symbol {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            Symbol::Definition(definition_ref) => definition_ref.fmt(f),
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
