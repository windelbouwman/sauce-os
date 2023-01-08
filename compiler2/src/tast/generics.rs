//! Types to describe generics.
//!

use super::{NameNodeId, SlangType, UserType};
use crate::parsing::Location;
use std::collections::HashMap;
use std::rc::Rc;

/*

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
 */

pub struct TypeVar {
    pub location: Location,
    pub name: NameNodeId,
}

impl std::fmt::Display for TypeVar {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "type-var-{}", self.name)
    }
}

/// Apply concrete types to a type containing type variables.
///
/// This performs type variable replacing.
#[allow(dead_code)]
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
            .get(&type_var.ptr.upgrade().unwrap().name.name)
            .unwrap()
            .clone(),
        SlangType::User(user_type) => {
            let ut2 = match user_type {
                UserType::Enum(mut enum_type) => {
                    let type_arguments = enum_type
                        .type_arguments
                        .into_iter()
                        .map(|p| replace_type_vars_sub(p, type_var_map))
                        .collect();
                    enum_type.type_arguments = type_arguments;
                    UserType::Enum(enum_type)
                }
                UserType::Struct(mut struct_type) => {
                    let type_arguments = struct_type
                        .type_arguments
                        .into_iter()
                        .map(|p| replace_type_vars_sub(p, type_var_map))
                        .collect();
                    struct_type.type_arguments = type_arguments;
                    UserType::Struct(struct_type)
                }
                _x => {
                    // unimplemented!("TODO!");
                    _x
                }
            };

            SlangType::User(ut2)
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
        type_var_map.insert(v.name.name.clone(), p.clone());
    }
    type_var_map
}

/// Create a string to represent bound type parameters.
pub fn get_binding_text(type_parameters: &[Rc<TypeVar>], type_arguments: &[SlangType]) -> String {
    assert!(type_parameters.len() == type_arguments.len());

    let mut bounds: Vec<String> = vec![];
    for (type_param, typ) in type_parameters.iter().zip(type_arguments.iter()) {
        bounds.push(format!("{}={}", type_param.name, typ));
    }

    bounds.join(", ")
}
