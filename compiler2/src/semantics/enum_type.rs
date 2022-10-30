use super::scope::Scope;
use super::type_system::{SlangType, UserType};
use super::NodeId;
use super::Symbol;
use crate::parsing::Location;
use std::cell::RefCell;
use std::rc::{Rc, Weak};

// #[derive(Debug)]
pub struct EnumDef {
    pub location: Location,
    pub id: NodeId,
    pub name: String,
    pub variants: Vec<Rc<RefCell<EnumVariant>>>,
    pub scope: Scope,
}

impl EnumDef {
    pub fn lookup(&self, name: &str) -> Option<Rc<RefCell<EnumVariant>>> {
        match self.scope.get(name) {
            Some(symbol) => match symbol {
                Symbol::EnumVariant(variant) => {
                    let variant = variant
                        .upgrade()
                        .expect("Enum variant must be alive, we refer to it.");
                    Some(variant)
                }
                other => {
                    panic!("Scope must contain only enum variants, not {:?}", other);
                }
            },
            None => None,
        }
    }
}

impl std::fmt::Debug for EnumDef {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        f.debug_struct("EnumDef").field("name", &self.name).finish()
    }
}

#[derive(Debug)]
pub struct EnumVariant {
    pub location: Location,
    pub name: String,
    pub data: Vec<SlangType>,
    pub index: usize,
    pub parent: Weak<EnumDef>,
}

impl EnumVariant {
    pub fn get_parent_type(&self) -> SlangType {
        SlangType::User(UserType::Enum(self.parent.clone()))
    }
}
