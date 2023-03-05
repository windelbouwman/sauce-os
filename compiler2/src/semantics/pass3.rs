//! Pass 3.
//!
//! - Change object initializers into tuple literals.
//!

use super::Diagnostics;
use crate::errors::CompilationError;
use crate::parsing::Location;
use crate::tast::{visit_program, VisitedNode, VisitorApi};
use crate::tast::{Expression, ExpressionKind, LabeledField, Program, SlangType};
use std::collections::{HashMap, HashSet};

pub fn pass3(program: &mut Program) -> Result<(), CompilationError> {
    log::debug!("Pass 3: '{}'", program.name);
    let mut pass3 = Pass3::new(&program.path);
    visit_program(&mut pass3, program);
    pass3.diagnostics.value_or_error(())
}

struct Pass3 {
    diagnostics: Diagnostics,
}

impl Pass3 {
    fn new(path: &std::path::Path) -> Self {
        Self {
            diagnostics: Diagnostics::new(path),
        }
    }

    /// Check struct initialization.
    ///
    /// Checks:
    /// - missing fields
    /// - extra fields
    /// - duplicate fields
    /// - field types
    fn struct_literal_to_tuple(
        &mut self,
        location: &Location,
        typ: &SlangType,
        init_fields: Vec<LabeledField>,
    ) -> Result<Vec<Expression>, ()> {
        if !typ.is_struct() {
            self.error(location, format!("Must be struct type, not {}", typ));
            return Err(());
        }

        let struct_type = typ.as_struct();

        let struct_fields = struct_type.get_struct_fields();
        let mut required_fields: HashSet<String> = HashSet::new();
        let mut value_map: HashMap<String, Expression> = HashMap::new();

        for (field_name, _field_type) in &struct_fields {
            required_fields.insert(field_name.clone());
        }

        let mut ok = true;

        for init_field in init_fields {
            if required_fields.contains(&init_field.name) {
                required_fields.remove(&init_field.name);
                assert!(!value_map.contains_key(&init_field.name));
                value_map.insert(init_field.name, *init_field.value);
            } else {
                // Error here on duplicate and non-existing fields
                self.error(
                    &init_field.location,
                    format!("Superfluous field: {}", init_field.name),
                );
                ok = false;
            }
        }

        // Check missed fields:
        for field in required_fields {
            self.error(location, format!("Missing field: {}", field));
            ok = false;
        }

        if ok {
            // Now create a linear list with struct fields
            let mut values = vec![];
            for (name, _typ) in struct_fields {
                values.push(
                    value_map
                        .remove(&name)
                        .expect("Struct initializer must be legit!"),
                );
            }

            Ok(values)
        } else {
            Err(())
        }
    }

    fn error(&mut self, location: &Location, message: String) {
        self.diagnostics.error(location.clone(), message);
    }
}

impl VisitorApi for Pass3 {
    fn pre_node(&mut self, _node: VisitedNode) {}

    fn post_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::Expression(expression) => match &mut expression.kind {
                ExpressionKind::ObjectInitializer { typ, fields } => {
                    if let Ok(values) = self.struct_literal_to_tuple(
                        &expression.location,
                        typ,
                        std::mem::take(fields),
                    ) {
                        expression.kind = ExpressionKind::TupleLiteral {
                            typ: typ.clone(),
                            values,
                        }
                    }
                }
                _ => {}
            },
            _ => {}
        }
    }
}
