use super::generics::TypeVar;
use super::{Scope, Symbol};

use super::typed_ast::{FieldDef, FunctionDef};
use super::NameNodeId;
use crate::parsing::Location;
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::Arc;

/// A class definition.
pub struct ClassDef {
    pub location: Location,
    pub name: NameNodeId,
    pub type_parameters: Vec<Rc<TypeVar>>,
    pub scope: Arc<Scope>,
    pub fields: Vec<Rc<RefCell<FieldDef>>>,
    pub methods: Vec<Rc<RefCell<FunctionDef>>>,
}

impl ClassDef {
    pub fn get_attr(&self, name: &str) -> Option<Symbol> {
        self.scope.get(name).cloned()
    }

    pub fn get_method(&self, name: &str) -> Option<Rc<RefCell<FunctionDef>>> {
        match self.get_attr(name) {
            Some(symbol) => match symbol {
                Symbol::Function(function_ref) => Some(function_ref.upgrade().unwrap()),
                _other => None,
            },
            None => None,
        }
    }
}

impl std::fmt::Display for ClassDef {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "user-class({})", self.name)
    }
}
