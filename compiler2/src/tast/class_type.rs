use super::{get_binding_text, Scope, Symbol};
use super::{FieldDef, FunctionDef, NameNodeId, SlangType, TypeVar};
use crate::parsing::Location;
use std::cell::RefCell;
use std::rc::{Rc, Weak};
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

#[derive(Clone)]
pub struct ClassType {
    pub class_ref: Weak<ClassDef>,
    pub type_arguments: Vec<SlangType>,
}

impl ClassType {
    pub fn get_attr_type(&self, name: &str) -> Option<SlangType> {
        let class_def = self.class_ref.upgrade().unwrap();
        class_def.get_attr(name).map(|s| s.get_type())
    }
}

impl PartialEq for ClassType {
    fn eq(&self, other: &Self) -> bool {
        self.class_ref.ptr_eq(&other.class_ref) && self.type_arguments == other.type_arguments
    }
}

impl Eq for ClassType {}

impl std::fmt::Display for ClassType {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        let class_def = self.class_ref.upgrade().unwrap();
        let bounds = get_binding_text(&class_def.type_parameters, &self.type_arguments);
        write!(f, "{}[{}]", class_def, bounds)
    }
}
