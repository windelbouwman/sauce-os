//! Various types to deal with structs and unions.
//!
use super::scope::Scope;
use super::symbol::Symbol;
use super::type_system::SlangType;
use crate::parsing::Location;

use super::typed_ast::FieldDef;
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::Arc;
pub type NodeId = usize;

pub struct StructDef {
    pub location: Location,
    pub name: String,
    pub id: NodeId,
    pub scope: Arc<Scope>,
    pub fields: Vec<Rc<RefCell<FieldDef>>>,
}

impl std::fmt::Display for StructDef {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "struct(name={}, id={})", self.name, self.id)
    }
}

impl StructDef {
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

    pub fn get_struct_fields(&self) -> Vec<(String, SlangType)> {
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

/// A C-style union type.
///
/// This type is not exposed in the language, but is an
/// helper type.
pub struct UnionDef {
    pub location: Location,
    pub name: String,
    pub id: NodeId,
    pub scope: Arc<Scope>,
    pub fields: Vec<Rc<RefCell<FieldDef>>>,
}

impl std::fmt::Display for UnionDef {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "union(name={}, id={})", self.name, self.id)
    }
}

impl UnionDef {
    /// Retrieve the given field from this struct
    pub fn get_field(&self, name: &str) -> Option<Rc<RefCell<FieldDef>>> {
        match self.get_attr(name) {
            Some(symbol) => match symbol {
                Symbol::Field(field_ref) => Some(field_ref.upgrade().unwrap()),
                other => {
                    panic!("Union can only contain fields, not {}", other);
                }
            },
            None => None,
        }
    }

    pub fn get_attr(&self, name: &str) -> Option<Symbol> {
        self.scope.get(name).cloned()
    }
}

pub struct StructDefBuilder {
    name: String,
    id: NodeId,
    location: Location,
    scope: Scope,
    fields: Vec<Rc<RefCell<FieldDef>>>,
}

impl StructDefBuilder {
    pub fn new(name: String, id: NodeId) -> Self {
        StructDefBuilder {
            name,
            id,
            location: Default::default(),
            scope: Scope::new(),
            fields: vec![],
        }
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

    // pub fn set_name(&mut self, name: String) {
    //     self.name = name;
    // }

    pub fn finish_struct(self) -> StructDef {
        StructDef {
            name: self.name,
            id: self.id,
            location: self.location,
            fields: self.fields,
            scope: Arc::new(self.scope),
        }
    }

    pub fn finish_union(self) -> UnionDef {
        UnionDef {
            name: self.name,
            id: self.id,
            location: self.location,
            fields: self.fields,
            scope: Arc::new(self.scope),
        }
    }
}
