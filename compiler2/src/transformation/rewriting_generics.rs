//! Rewrite generics using type erasure, and insert type casting at the proper
//! places.
//!
//! Basically there is two ways to implement generics:
//! - Templates / code expansion: (example languages: C++)
//! - type erasure: Java, C#
//!
//! Tasks involved in type erasure:
//! - When accessing a struct member which is a type variable,
//!   introduce a cast from opaque pointer to the specific type.
//! - When setting a struct member, create a cast to an opaque pointer.
//!
//!

use crate::tast::get_substitution_map;
use crate::tast::{visit_program, VisitedNode, VisitorApi};
use crate::tast::{Definition, FunctionDef, Program};
use crate::tast::{Expression, ExpressionKind, SlangType, StatementKind, UserType};

pub fn rewrite_generics(program: &mut Program) {
    log::info!("Erasing types, where generics are involved");
    let mut rewriter = GenericRewriter::new();
    visit_program(&mut rewriter, program);
}

struct GenericRewriter {}

impl GenericRewriter {
    fn new() -> Self {
        Self {}
    }

    /// Modify definitions and rewrite types used
    fn update_definition(&self, definition: &Definition) {
        match definition {
            Definition::Struct(struct_def) => {
                for field in &struct_def.fields {
                    self.update_type(&mut field.borrow_mut().typ);
                }
            }
            Definition::Function(function_def) => {
                self.update_function(&function_def.borrow());
            }
            _ => {}
        }
    }

    fn update_function(&self, function_def: &FunctionDef) {
        log::trace!(
            "Rewrite types in function parameters: {}",
            function_def.name
        );
        let signature = function_def.signature.borrow();
        for parameter in &signature.parameters {
            self.update_type(&mut parameter.borrow_mut().typ);
        }
    }

    /// Look at several constructs:
    ///
    /// - Get-attr:
    ///     check if we get an attribute of a bound-generic
    ///     and upcast the opaque pointer
    /// - Object initializer:
    ///     Check if we initialize a bound generic
    ///     Cast specifics to opaque pointers.
    /// - Call:
    ///     Each argument which should be a type-var, should be casted to opaque.
    fn update_expression(&self, expression: &mut Expression) {
        match &mut expression.kind {
            ExpressionKind::GetAttr { base, attr } => {
                if let SlangType::User(UserType::Struct(struct_type)) = &base.typ {
                    // If we get an attribute which is a type var
                    // Introduce a cast from opaque, to the concrete type.

                    // Store original type with generic info, this is required for later get-attrs..
                    // A bit lame to do it like this ..
                    let original_expr_type = expression.typ.clone();

                    let struct_def = struct_type.struct_ref.upgrade().unwrap();
                    let attr_typ = struct_def
                        .get_attr(attr)
                        .expect("We checked this")
                        .get_type();

                    if let SlangType::TypeVar(type_var) = attr_typ {
                        let type_var_map = get_substitution_map(
                            &struct_def.type_parameters,
                            &struct_type.type_arguments,
                        );
                        let mut typ = type_var_map
                            .get(&type_var.get_type_var().name.name)
                            .cloned()
                            .expect("We checked!");
                        self.update_type(&mut typ);

                        // Patch expression!
                        let expr2 = std::mem::take(expression);
                        *expression = expr2.cast(typ);
                        expression.typ = original_expr_type;
                    }
                }
            }
            ExpressionKind::TupleLiteral { typ, values } => {
                let struct_type = typ.as_struct();
                let struct_def = struct_type.struct_ref.upgrade().unwrap();
                // Insert type-casts of some field values.

                for (value, field) in values.iter_mut().zip(struct_def.fields.iter()) {
                    if field.borrow().typ.is_type_var() {
                        // If we initialize a field whose type is a type variable
                        // Transform this initial value into an opaque pointer.
                        Self::cast_to_opaque(value);
                    }
                }

                self.update_type(typ);
            }
            ExpressionKind::UnionLiteral { typ, attr, value } => {
                let struct_type = typ.as_struct();
                let struct_def = struct_type.struct_ref.upgrade().unwrap();
                let field = struct_def.get_field(attr).unwrap();
                if field.borrow().typ.is_type_var() {
                    Self::cast_to_opaque(value.as_mut());
                }
            }

            ExpressionKind::ObjectInitializer { .. } => {
                panic!("Object initializers should be rewritten");
            }
            ExpressionKind::Call { callee, arguments } => {
                let signature = callee.as_function().get_original_signature();
                for (parameter, argument) in signature
                    .borrow()
                    .parameters
                    .iter()
                    .zip(arguments.iter_mut())
                {
                    if parameter.borrow().typ.is_type_var() {
                        Self::cast_to_opaque(argument);
                    }
                }
            }
            _ => {}
        }
    }

    fn cast_to_opaque(value: &mut Expression) {
        let old_value = std::mem::take(value);
        *value = old_value.cast(SlangType::Opaque);
    }

    /// Do two things:
    ///
    /// - Replace type variable by an opaque type (void*)
    /// - Replace Generic instances, by the concrete type for this generic.
    fn update_type(&self, typ: &mut SlangType) {
        match typ {
            /*
            SlangType::GenericInstance(generic_instance) => {
                // Okay, if we refer to a generic instance, replace with opaque generic type!
                *typ = self
                .type_map
                .get(&generic_instance.get_def().id)
                .unwrap()
                .clone();
            }
            */
            SlangType::TypeVar(_) => {
                // Replace type variables with opaque pointers!
                *typ = SlangType::Opaque;
            }
            _ => {}
        }
    }
}

impl VisitorApi for GenericRewriter {
    fn pre_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::Program(_program) => {
                // Promote internal definitions from generics to
                // top level definition
                // for generic in &program.generics {
                //     // Take each generic, and move it up a notch:
                //     let new_def = generic.base.clone();
                //     let new_type = new_def.create_type();
                //     self.type_map.insert(generic.id, new_type);
                //     self.new_definitions.push(new_def);
                // }

                // program.definitions.append(&mut self.new_definitions);
            }
            VisitedNode::Definition(_definition) => {
                // match definition {
                // Definition::
                // }
            }
            VisitedNode::Expression(_expression) => {
                // Update own type:
                // self.update_type(&mut expression.typ);
            }
            VisitedNode::TypeExpr(_type_expr) => {
                // self.update_type(type_expr);
            }
            VisitedNode::Statement(statement) => match &statement.kind {
                StatementKind::Case(_case_statement) => {
                    panic!("Unsupported, case statements must be rewritten first.");
                }
                _ => {}
            },
            _ => {}
        }
    }

    fn post_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::Program(program) => {
                for definition in &program.definitions {
                    self.update_definition(definition);
                }

                // Strip out all generics!
                // program.generics.clear();
            }
            VisitedNode::Expression(expression) => {
                self.update_expression(expression);
            }
            VisitedNode::Function(function_def) => {
                self.update_function(function_def);
            }
            _ => {}
        }
    }
}
