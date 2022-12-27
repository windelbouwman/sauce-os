//! Types to describe generics.
//!

pub use super::enum_type::{EnumDef, EnumVariant};
use super::scope::Scope;
pub use super::struct_type::{StructDef, StructDefBuilder, UnionDef};
use super::symbol::Symbol;
use super::type_system::SlangType;
use super::typed_ast::Definition;
use crate::parsing::Location;
use std::rc::Rc;
use std::sync::Arc;
pub type NodeId = usize;
use std::collections::HashMap;

/// A parameterized type, may contain subtypes which are type variables.
pub struct GenericDef {
    pub name: String,
    pub id: NodeId,
    pub scope: Arc<Scope>,
    pub base: Definition,
    pub location: Location,
    pub type_parameters: Vec<Rc<TypeVar>>,
    // Idea: keep track of the instances of this template?
    // instantiations: Vec<Definition>,
}

impl GenericDef {
    /// Apply the given set of types to this generic.
    ///
    /// Type application!
    #[allow(dead_code)]
    pub fn apply(&self, types: &[SlangType]) -> Definition {
        let substitution_map = get_substitution_map(&self.type_parameters, types);

        match &self.base {
            Definition::Struct(struct_def) => {
                let new_struct_name = &struct_def.name;
                // Create struct with ID=0
                let mut builder = StructDefBuilder::new(new_struct_name.clone(), 0);

                for field in &struct_def.fields {
                    let field = field.borrow();
                    let typ: SlangType =
                        replace_type_vars_sub(field.typ.clone(), &substitution_map);
                    builder.add_field(&field.name, typ);
                }

                let new_struct_ref = Rc::new(builder.finish_struct());

                // ehm
                // let typ = SlangType::User(UserType::Struct(Rc::downgrade(&new_struct_ref)));
                // (Definition::Struct(new_struct_ref), typ)
                Definition::Struct(new_struct_ref)
            }
            Definition::Enum(_) => {
                unimplemented!("Type application for enum");
            }
            _other => {
                unimplemented!("Type application for ?????");
            }
        }
    }

    pub fn get_attr(&self, name: &str) -> Option<Symbol> {
        self.base.get_attr(name)
    }
}

pub struct TypeVar {
    pub location: Location,
    pub name: String,
    pub id: NodeId,
}

impl std::fmt::Display for TypeVar {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "type-var(name={}, id={})", self.name, self.id)
    }
}

/// Apply concrete types to a type containing type variables.
///
/// This performs type variable replacing.
pub fn replace_type_vars_top(
    type_parameters: &[Rc<TypeVar>],
    types: &[SlangType],
    typ: SlangType,
) -> SlangType {
    let type_var_map = get_substitution_map(type_parameters, types);

    replace_type_vars_sub(typ, &type_var_map)
}

/// Replace type variables, using the given mapping
pub fn replace_type_vars_sub(
    typ: SlangType,
    type_var_map: &HashMap<String, SlangType>,
) -> SlangType {
    match typ {
        SlangType::TypeVar(type_var) => type_var_map
            .get(&type_var.ptr.upgrade().unwrap().name)
            .unwrap()
            .clone(),
        SlangType::GenericInstance {
            generic,
            type_parameters,
        } => {
            let type_parameters = type_parameters
                .into_iter()
                .map(|p| replace_type_vars_sub(p, type_var_map))
                .collect();
            SlangType::GenericInstance {
                generic,
                type_parameters,
            }
        }
        other => other,
    }
}

/// Given a set of type parameter and type values, create a mapping
pub fn get_substitution_map(
    type_parameters: &[Rc<TypeVar>],
    types: &[SlangType],
) -> HashMap<String, SlangType> {
    let mut type_var_map: HashMap<String, SlangType> = HashMap::new();
    assert!(type_parameters.len() == types.len());
    for (v, p) in type_parameters.iter().zip(types.iter()) {
        type_var_map.insert(v.name.clone(), p.clone());
    }
    type_var_map
}
