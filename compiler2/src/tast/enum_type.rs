use super::generics::{
    get_binding_text, get_substitution_map, get_type_vars_text, replace_type_vars_sub, TypeVar,
};
use super::{NameNodeId, NodeId};
use super::{Scope, SlangType, Symbol};

use crate::parsing::Location;
use std::cell::RefCell;
use std::rc::{Rc, Weak};
use std::sync::Arc;

pub struct EnumDef {
    pub location: Location,
    pub name: NameNodeId,
    pub variants: Vec<Rc<RefCell<EnumVariant>>>,
    pub scope: Arc<Scope>,
    pub type_parameters: Vec<Rc<TypeVar>>,
}

impl EnumDef {
    /// See if this enum contains a variant with the given name
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

    #[allow(dead_code)]
    pub fn get_attr(&self, name: &str) -> Option<Symbol> {
        self.scope.get(name).cloned()
    }
}

impl std::fmt::Display for EnumDef {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        let type_txt = get_type_vars_text(&self.type_parameters);
        write!(f, "enum-{}[{}]", self.name, type_txt)
    }
}

pub struct EnumVariant {
    pub location: Location,
    pub name: String,
    pub data: Vec<SlangType>,
    pub index: usize,
    pub parent: Weak<EnumDef>,
}

impl EnumVariant {
    /*
    /// Get the enum type which this is a variant for.
    pub fn get_parent_type(&self) -> SlangType {
        SlangType::User(UserType::Enum(self.parent.clone()))
    }
    */
}

pub struct EnumDefBuilder {
    name: String,
    id: NodeId,
    location: Location,
    scope: Scope,
    variants: Vec<Rc<RefCell<EnumVariant>>>,
}

impl EnumDefBuilder {
    #[allow(dead_code)]
    pub fn new(name: String, id: NodeId) -> Self {
        EnumDefBuilder {
            name,
            id,
            location: Default::default(),
            scope: Scope::new(),
            variants: vec![],
        }
    }

    #[allow(dead_code)]
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

    #[allow(dead_code)]
    pub fn finish(self) -> Rc<EnumDef> {
        let enum_def = Rc::new(EnumDef {
            name: NameNodeId {
                name: self.name,
                id: self.id,
            },
            location: self.location,
            variants: self.variants,
            scope: Arc::new(self.scope),
            type_parameters: vec![],
        });

        for variant in &enum_def.variants {
            variant.borrow_mut().parent = Rc::downgrade(&enum_def);
        }

        enum_def
    }
}

/// Representation for an enum type.
#[derive(Clone)]
pub struct EnumType {
    pub enum_ref: Weak<EnumDef>,
    pub type_arguments: Vec<SlangType>,
}

impl PartialEq for EnumType {
    fn eq(&self, other: &Self) -> bool {
        self.enum_ref.ptr_eq(&other.enum_ref) && self.type_arguments == other.type_arguments
    }
}

impl Eq for EnumType {}

impl std::fmt::Display for EnumType {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        if let Some(enum_def) = self.enum_ref.upgrade() {
            let bounds = get_binding_text(&enum_def.type_parameters, &self.type_arguments);
            write!(f, "enum-{}[{}]", enum_def.name, bounds)
        } else {
            write!(f, "enum(NULL)")
        }
    }
}

impl EnumType {
    pub fn from_def(enum_def: &Rc<EnumDef>, type_arguments: Vec<SlangType>) -> Self {
        assert!(type_arguments.len() == enum_def.type_parameters.len());
        Self {
            enum_ref: Rc::downgrade(enum_def),
            type_arguments,
        }
    }

    fn get_def(&self) -> Rc<EnumDef> {
        self.enum_ref.upgrade().unwrap()
    }

    pub fn lookup_variant(&self, name: &str) -> Option<Rc<RefCell<EnumVariant>>> {
        let enum_def = self.get_def();
        enum_def.lookup(name)
    }

    pub fn get_variants(&self) -> Vec<Rc<RefCell<EnumVariant>>> {
        let enum_def = self.get_def();
        enum_def.variants.clone()
    }

    pub fn get_variant_data_types(&self, index: usize) -> Vec<SlangType> {
        let enum_def = self.get_def();
        let enum_variant = enum_def.variants[index].borrow();
        let data_types = enum_variant.data.clone();

        let type_var_map = get_substitution_map(&enum_def.type_parameters, &self.type_arguments);

        data_types
            .into_iter()
            .map(|t| replace_type_vars_sub(t, &type_var_map))
            .collect()
    }
}