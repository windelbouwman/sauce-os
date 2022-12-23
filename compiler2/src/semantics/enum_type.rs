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
                    panic!("Scope must contain only enum variants, not {}", other);
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

pub struct EnumDefBuilder {
    name: String,
    id: NodeId,
    location: Location,
    scope: Scope,
    variants: Vec<Rc<RefCell<EnumVariant>>>,
}

impl EnumDefBuilder {
    pub fn new(name: String, id: NodeId) -> Self {
        EnumDefBuilder {
            name,
            id,
            location: Default::default(),
            scope: Scope::new(),
            variants: vec![],
        }
    }

    pub fn add_variant(&mut self, name: &str, data: Vec<SlangType>) {
        let index = self.variants.len();
        let variant = Rc::new(RefCell::new(EnumVariant {
            location: Default::default(),
            name: name.to_owned(),
            index,
            data,
            parent: Default::default(),
        }));

        self.scope.define(
            name.to_owned(),
            Symbol::EnumVariant(Rc::downgrade(&variant)),
        );

        self.variants.push(variant);
    }

    pub fn finish(self) -> Rc<EnumDef> {
        let enum_def = Rc::new(EnumDef {
            name: self.name,
            id: self.id,
            location: self.location,
            variants: self.variants,
            scope: self.scope,
        });

        for variant in &enum_def.variants {
            variant.borrow_mut().parent = Rc::downgrade(&enum_def);
        }

        enum_def
    }
}
