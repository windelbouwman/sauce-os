use super::type_system::{SlangType, StructField, StructType};
pub use super::Diagnostics;
use crate::parsing::Location;
use std::collections::HashMap;

pub fn instantiate_type(
    diagnostics: &mut Diagnostics,
    location: &Location,
    base_type: SlangType,
    actual_types: Vec<SlangType>,
) -> Result<SlangType, ()> {
    match base_type {
        SlangType::Generic {
            base,
            type_parameters,
        } => {
            if type_parameters.len() == actual_types.len() {
                let mut substitution_map: HashMap<String, SlangType> = HashMap::new();
                for (type_parameter, actual_type) in
                    type_parameters.into_iter().zip(actual_types.into_iter())
                {
                    substitution_map.insert(type_parameter, actual_type);
                }
                let t = substitute_types(*base, &substitution_map)?;
                Ok(t)
            } else {
                diagnostics.error(
                    location.clone(),
                    format!(
                        "Expected {} type parameters, but got {}",
                        type_parameters.len(),
                        actual_types.len()
                    ),
                );
                Err(())
            }
        }
        other => {
            diagnostics.error(
                location.clone(),
                format!("Type {:?} is not generic.", other),
            );
            Err(())
        }
    }
}

fn substitute_types(
    typ: SlangType,
    substitutions: &HashMap<String, SlangType>,
) -> Result<SlangType, ()> {
    let t = match typ {
        SlangType::Bool => SlangType::Bool,
        SlangType::Int => SlangType::Int,
        SlangType::Float => SlangType::Float,
        SlangType::String => SlangType::String,
        SlangType::Struct(StructType { name, fields }) => {
            let mut new_fields = vec![];
            for field in fields {
                new_fields.push(StructField {
                    name: field.name,
                    typ: substitute_types(field.typ, substitutions)?,
                });
            }

            SlangType::Struct(StructType {
                name,
                fields: new_fields,
            })
        }
        SlangType::Class(_class_ref) => {
            // TODO: actually replace some types!
            // SlangType::Class(class_ref)
            unimplemented!("Class template instantiation");
        }
        SlangType::TypeVar(name) => {
            if let Some(typ) = substitutions.get(&name) {
                typ.clone()
            } else {
                panic!("Type parameter {} not found", name);
            }
        }
        SlangType::Generic { .. } => {
            panic!("Unexpected generic");
            // self.error(Location::default(), "Unexpected generic".to_owned());
            // return Err(());
        }
        other => {
            unimplemented!("TODO: {:?} with {:?}", other, substitutions);
        }
    };
    Ok(t)
}
