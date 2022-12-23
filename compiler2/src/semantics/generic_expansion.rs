//! Expand generic types like templates

use super::enum_type::EnumDefBuilder;
use super::type_system::{SlangType, UserType};
use super::typed_ast;
use super::visitor::{visit_program, VisitedNode, VisitorApi};
use super::{Context, Diagnostics, NodeId};
use crate::errors::CompilationError;
use crate::parsing::Location;
use std::collections::HashMap;
use std::rc::Rc;

pub fn expand_generics(
    program: &mut typed_ast::Program,
    context: &mut Context,
) -> Result<(), CompilationError> {
    log::debug!("Expanding generic types");
    let mut expander = Expander::new(context, &program.path);
    visit_program(&mut expander, program);
    expander.diagnostics.value_or_error(())
}

struct Expander<'e> {
    context: &'e mut Context,
    diagnostics: Diagnostics,
    new_definitions: Vec<typed_ast::Definition>,

    /// Boolean to indicate if we are handling a generic currently.
    ///
    /// This feels a bit hacky?
    in_generic: bool,

    instance_cache: HashMap<String, SlangType>,
}

impl<'e> Expander<'e> {
    fn new(context: &'e mut Context, path: &std::path::Path) -> Self {
        Self {
            context,
            diagnostics: Diagnostics::new(path),
            new_definitions: vec![],
            in_generic: false,
            instance_cache: HashMap::new(),
        }
    }

    fn instantiate_type(
        &mut self,
        location: &Location,
        generic: &typed_ast::GenericDef,
        actual_types: &[SlangType],
    ) -> Result<SlangType, ()> {
        log::debug!(
            "Expanding template '{}' with actual types: {:?}",
            generic.name,
            actual_types
        );
        if generic.type_parameters.len() == actual_types.len() {
            // Build mapping from type variables to actual types:
            let mut substitution_map: HashMap<String, SlangType> = HashMap::new();
            for (type_parameter, actual_type) in
                generic.type_parameters.iter().zip(actual_types.iter())
            {
                substitution_map.insert(type_parameter.name.clone(), actual_type.clone());
            }

            // Apply mapping to some template type:
            match &generic.base {
                typed_ast::Definition::Struct(struct_def) => {
                    let types_suffix: Vec<String> =
                        actual_types.iter().map(|t| t.mangle_name()).collect();

                    let new_struct_name = format!("{}_{}", struct_def.name, types_suffix.join("_"));

                    if self.instance_cache.contains_key(&new_struct_name) {
                        let typ = self.instance_cache.get(&new_struct_name).unwrap().clone();
                        Ok(typ)
                    } else {
                        let mut builder = typed_ast::StructDefBuilder::new(
                            new_struct_name.clone(),
                            self.new_id(),
                        );

                        for field in &struct_def.fields {
                            let field = field.borrow();
                            let typ: SlangType =
                                self.substitute_type_var(&field.typ, &substitution_map)?;
                            builder.add_field(&field.name, typ);
                        }

                        let new_struct_ref = Rc::new(builder.finish_struct());

                        // ehm
                        let typ = SlangType::User(UserType::Struct(Rc::downgrade(&new_struct_ref)));

                        self.instance_cache.insert(new_struct_name, typ.clone());
                        self.new_definitions
                            .push(typed_ast::Definition::Struct(new_struct_ref));
                        Ok(typ)
                    }
                }
                typed_ast::Definition::Enum(enum_def) => {
                    log::info!("Expanding generic type");
                    let types_suffix: Vec<String> =
                        actual_types.iter().map(|t| t.mangle_name()).collect();

                    let new_enum_name = format!("{}_{}", enum_def.name, types_suffix.join("_"));
                    if self.instance_cache.contains_key(&new_enum_name) {
                        let typ = self.instance_cache.get(&new_enum_name).unwrap().clone();
                        Ok(typ)
                    } else {
                        let mut builder = EnumDefBuilder::new(new_enum_name.clone(), self.new_id());

                        for variant in &enum_def.variants {
                            let variant = variant.borrow();

                            let mut d_types = vec![];
                            for payload_ty in &variant.data {
                                let typ: SlangType =
                                    self.substitute_type_var(payload_ty, &substitution_map)?;
                                d_types.push(typ);
                            }
                            builder.add_variant(&variant.name, d_types);
                        }
                        let new_enum_ref = builder.finish();
                        let typ = SlangType::User(UserType::Enum(Rc::downgrade(&new_enum_ref)));

                        self.instance_cache.insert(new_enum_name, typ.clone());

                        self.new_definitions
                            .push(typed_ast::Definition::Enum(new_enum_ref));

                        Ok(typ)
                    }
                }
                _other => {
                    unimplemented!("TODO");
                }
            }
        } else {
            self.error(
                location,
                format!(
                    "Expected {} type parameters, but got {}",
                    generic.type_parameters.len(),
                    actual_types.len()
                ),
            );
            Err(())
        }
    }

    fn substitute_type_var(
        &mut self,
        typ: &SlangType,
        substitution_map: &HashMap<String, SlangType>,
    ) -> Result<SlangType, ()> {
        match typ {
            SlangType::TypeVar(type_var_ref) => {
                let type_var = type_var_ref.ptr.upgrade().unwrap();
                Ok(substitution_map.get(&type_var.name).unwrap().clone())
            }
            SlangType::GenericInstance {
                generic,
                type_parameters,
            } => {
                let generic = generic.get_def();
                let mut params2 = vec![];
                for type_parameter in type_parameters {
                    let p: SlangType =
                        self.substitute_type_var(type_parameter, substitution_map)?;
                    params2.push(p);
                }

                let location = Default::default();

                let new_typ = self.instantiate_type(&location, &generic, &params2)?;
                Ok(new_typ)
            }
            SlangType::Unresolved(obj_ref) => {
                panic!(
                    "Unresolved type '{:?}', all symbols must be resolved before hand",
                    obj_ref
                );
            }
            other => Ok(other.clone()),
        }
    }

    fn error(&mut self, location: &Location, message: String) {
        self.diagnostics.error(location.clone(), message);
    }

    /// Create a new unique ID
    fn new_id(&mut self) -> NodeId {
        self.context.id_generator.gimme()
    }
}

impl<'e> VisitorApi for Expander<'e> {
    fn pre_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::Generic(_) => {
                self.in_generic = true;
            }
            _ => {}
        }
    }

    fn post_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::Generic(_) => {
                self.in_generic = false;
            }
            VisitedNode::TypeExpr(type_expression) => {
                // Only expand types in non-generic definitions..
                if !self.in_generic {
                    let res = match type_expression {
                        SlangType::GenericInstance {
                            generic,
                            type_parameters,
                        } => {
                            //
                            // Instantiate type!
                            let location: Location = Default::default();
                            let generic = generic.get_def();
                            self.instantiate_type(&location, &generic, type_parameters)
                                .ok()
                        }
                        _ => None,
                    };

                    if let Some(new_type) = res {
                        *type_expression = new_type;
                    }
                }
            }
            VisitedNode::Expression(expression) => {
                if !self.in_generic {
                    match &expression.kind {
                        typed_ast::ExpressionKind::GetIndex { base, index: _ } => {
                            match base {
                                // typed_ast::ExpressionKind::
                                _ => {}
                            }
                            // unimplemented!("TODO");
                        }
                        _ => {}
                    }
                }
            }
            VisitedNode::Program(program) => {
                program.definitions.append(&mut self.new_definitions);
            }
            _ => {}
        }
    }
}
