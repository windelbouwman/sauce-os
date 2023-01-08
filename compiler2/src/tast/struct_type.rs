//! Various types to deal with structs and unions.
//!

use super::{get_binding_text, get_substitution_map, replace_type_vars_sub};
use super::{Definition, Scope, SlangType, Symbol, TypeVar};
use super::{FieldDef, NameNodeId, NodeId};
use crate::parsing::Location;
use std::cell::RefCell;
use std::rc::{Rc, Weak};
use std::sync::Arc;

pub struct StructDef {
    pub location: Location,
    pub name: NameNodeId,

    // Indicator whether this struct is union type.
    pub is_union: bool,

    pub type_parameters: Vec<Rc<TypeVar>>,
    pub scope: Arc<Scope>,
    pub fields: Vec<Rc<RefCell<FieldDef>>>,
}

impl std::fmt::Display for StructDef {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        if self.is_union {
            write!(f, "union-{}", self.name)
        } else {
            write!(f, "struct-{}", self.name)
        }
    }
}

impl StructDef {
    /// Turn this structure into a definition
    pub fn into_def(self) -> Definition {
        Definition::Struct(Rc::new(self))
    }

    /// Retrieve the given field from this struct
    pub fn get_field(&self, name: &str) -> Option<Rc<RefCell<FieldDef>>> {
        match self.get_attr(name) {
            Some(symbol) => match symbol {
                Symbol::Field(field_ref) => Some(field_ref.upgrade().unwrap()),
                other => {
                    panic!("Struct may only contain fields, not {}", other);
                }
            },
            None => None,
        }
    }

    fn get_struct_fields(&self) -> Vec<(String, SlangType)> {
        let mut fields = vec![];

        for field in &self.fields {
            let field_name = field.borrow().name.clone();
            let field_type = field.borrow().typ.clone();
            fields.push((field_name, field_type));
        }
        fields
    }

    pub fn get_attr(&self, name: &str) -> Option<Symbol> {
        self.scope.get(name).cloned()
    }
}

pub struct StructDefBuilder {
    name: String,
    id: NodeId,
    location: Location,
    is_union: bool,
    type_parameters: Vec<Rc<TypeVar>>,
    scope: Scope,
    fields: Vec<Rc<RefCell<FieldDef>>>,
}

impl StructDefBuilder {
    pub fn new(name: String, id: NodeId) -> Self {
        StructDefBuilder {
            name,
            id,
            location: Default::default(),
            is_union: false,
            scope: Scope::new(),
            fields: vec![],
            type_parameters: vec![],
        }
    }

    #[allow(dead_code)]
    pub fn add_type_parameter(&mut self, name: NameNodeId) {
        self.type_parameters.push(Rc::new(TypeVar {
            name,
            location: Default::default(),
        }));
    }

    pub fn add_field(&mut self, name: &str, typ: SlangType) {
        let index = self.fields.len();
        let field = Rc::new(RefCell::new(FieldDef {
            index,
            name: name.to_owned(),
            typ,
            location: Default::default(),
            value: None,
        }));

        self.scope
            .define(name.to_owned(), Symbol::Field(Rc::downgrade(&field)));

        self.fields.push(field);
    }

    pub fn set_is_union(&mut self, is_union: bool) {
        self.is_union = is_union;
    }

    pub fn finish(self) -> StructDef {
        StructDef {
            name: NameNodeId {
                name: self.name,
                id: self.id,
            },
            is_union: self.is_union,
            location: self.location,
            fields: self.fields,
            type_parameters: self.type_parameters,
            scope: Arc::new(self.scope),
        }
    }
}

#[derive(Clone)]
pub struct StructType {
    pub struct_ref: Weak<StructDef>,
    pub type_arguments: Vec<SlangType>,
}

impl PartialEq for StructType {
    fn eq(&self, other: &Self) -> bool {
        self.struct_ref.ptr_eq(&other.struct_ref) && self.type_arguments == other.type_arguments
    }
}

impl Eq for StructType {}

impl std::fmt::Display for StructType {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        let struct_def = self.struct_ref.upgrade().unwrap();
        let bounds = get_binding_text(&struct_def.type_parameters, &self.type_arguments);
        write!(f, "{}[{}]", struct_def, bounds)
    }
}

impl StructType {
    pub fn is_union(&self) -> bool {
        let struct_def = self.struct_ref.upgrade().unwrap();
        struct_def.is_union
    }

    /// Treat this type as a struct, and retrieve struct fields
    ///
    /// In case of a generic instance, this will replace type variables
    /// with concrete type values.
    pub fn get_struct_fields(&self) -> Vec<(String, SlangType)> {
        // Get a firm hold to the struct type:
        let struct_def = self.struct_ref.upgrade().unwrap();

        let type_mapping = get_substitution_map(&struct_def.type_parameters, &self.type_arguments);

        let mut fields = vec![];
        for (field_name, field_type) in struct_def.get_struct_fields() {
            fields.push((field_name, replace_type_vars_sub(field_type, &type_mapping)));
        }
        fields
    }

    /// Retrieve type of the given field
    pub fn get_attr_type(&self, name: &str) -> Option<SlangType> {
        let struct_def = self.struct_ref.upgrade().unwrap();
        let type_mapping = get_substitution_map(&struct_def.type_parameters, &self.type_arguments);

        struct_def
            .get_field(name)
            .map(|f| replace_type_vars_sub(f.borrow().typ.clone(), &type_mapping))
    }

    pub fn get_field(&self, name: &str) -> Option<Rc<RefCell<FieldDef>>> {
        self.struct_ref.upgrade().unwrap().get_field(name)
    }
}
