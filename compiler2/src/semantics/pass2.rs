//! We can do some things now.
//!
//! Can do:
//! - Instantiate generics
//! - Create enum literals

use super::Diagnostics;
use crate::errors::CompilationError;
use crate::parsing::Location;
use crate::tast::{visit_program, VisitedNode, VisitorApi};
use crate::tast::{DefinitionRef, EnumLiteral, Program, SlangType, TypeExpression, TypeVar};
use crate::tast::{Expression, ExpressionKind, Symbol};
use std::rc::Rc;

pub fn pass2(program: &mut Program) -> Result<(), CompilationError> {
    log::debug!("Evaluating type expressions for '{}'", program.name);
    let mut pass2 = Pass2::new(&program.path);
    visit_program(&mut pass2, program);
    pass2.diagnostics.value_or_error(())
}

struct Pass2 {
    diagnostics: Diagnostics,
}

impl Pass2 {
    fn new(path: &std::path::Path) -> Self {
        Self {
            diagnostics: Diagnostics::new(path),
        }
    }

    fn check_type_expression(&mut self, type_expression: &mut SlangType) {
        if let SlangType::Unresolved(expr) = type_expression {
            let t_expr = std::mem::replace(
                expr,
                TypeExpression {
                    expr: Default::default(),
                },
            );

            if let Ok(typ) = self.transform_into_type(*t_expr.expr) {
                *type_expression = typ;
            }
        }
    }

    /// Try to create a type from an expression.
    ///
    /// - Load a symbol => Check if it is a type, and use it.
    /// - get-index => array indexing, used for generic instantiation.
    fn transform_into_type(&mut self, type_expr: Expression) -> Result<SlangType, ()> {
        match type_expr.kind {
            ExpressionKind::Typ(typ) => Ok(typ),
            ExpressionKind::LoadSymbol(Symbol::Definition(definition_ref)) => {
                if definition_ref.is_type_constructor() {
                    // If we have no type parameters, we can access this directly.

                    if definition_ref.get_type_parameters().is_empty() {
                        Ok(definition_ref.create_type(vec![]))
                    } else {
                        let location: &Location = &type_expr.location;
                        self.error(location, "We need type arguments".to_owned());
                        Err(())
                    }
                } else {
                    let location: &Location = &type_expr.location;
                    self.error(location, "Expected type constructor".to_owned());
                    Err(())
                }
            }

            ExpressionKind::GetIndex { base, index } => {
                let type_arguments = vec![*index];
                self.instantiate_generic(&type_expr.location, *base, type_arguments)
            }

            _other => {
                // Ai!
                let location: &Location = &type_expr.location;
                self.error(location, "Invalid type expression is no type".to_string());
                Err(())
            }
        }
    }

    fn instantiate_generic(
        &mut self,
        location: &Location,
        generic: Expression,
        type_expressions: Vec<Expression>,
    ) -> Result<SlangType, ()> {
        // Check bound generic for:
        // 2. types supplied must be pointer types
        let definition_ref = self.on_generic_ref(generic)?;
        let type_arguments = self.check_type_arguments(
            location,
            &definition_ref.get_type_parameters(),
            type_expressions,
        )?;
        let typ = definition_ref.create_type(type_arguments);
        Ok(typ)
    }

    /// Check if the type arguments passed are properly suited for the given type variables.
    fn check_type_arguments(
        &mut self,
        location: &Location,
        type_parameters: &[Rc<TypeVar>],
        type_expressions: Vec<Expression>,
    ) -> Result<Vec<SlangType>, ()> {
        let mut type_arguments: Vec<SlangType> = vec![];
        for type_expr in type_expressions {
            let type_argument = self.transform_into_type(type_expr)?;

            // Check generic types to be of complicated type
            if !type_argument.is_heap_type() {
                self.error(
                    location,
                    format!("Expect only heap allocated type, not {}", type_argument),
                );
                return Err(());
            }

            type_arguments.push(type_argument);
        }

        // Check: amount of type parameters
        if type_parameters.len() != type_arguments.len() {
            self.error(
                location,
                format!(
                    "Wrong number of types for generic, expected {}, but got {} types",
                    type_parameters.len(),
                    type_arguments.len()
                ),
            );
            return Err(());
        }

        Ok(type_arguments)
    }

    fn on_generic_ref(&mut self, expr: Expression) -> Result<DefinitionRef, ()> {
        match expr.kind {
            ExpressionKind::LoadSymbol(Symbol::Definition(definition_ref)) => Ok(definition_ref),
            _other => {
                self.error(&expr.location, "Invalid generic".to_string());
                Err(())
            }
        }
    }

    fn error(&mut self, location: &Location, message: String) {
        self.diagnostics.error(location.clone(), message);
    }
}

impl VisitorApi for Pass2 {
    fn pre_node(&mut self, _node: VisitedNode) {}

    fn post_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::TypeExpr(type_expression) => {
                self.check_type_expression(type_expression);
            }
            VisitedNode::Expression(expression) => {
                match &mut expression.kind {
                    // TBD: this could be a whole seperate pass?

                    // Handle MyStruct[int]
                    ExpressionKind::GetIndex { base, index } => match &base.kind {
                        ExpressionKind::LoadSymbol(Symbol::Definition(definition_ref)) => {
                            let type_parameters = definition_ref.get_type_parameters();
                            let type_expressions = vec![*std::mem::take(index)];
                            if let Ok(type_arguments) = self.check_type_arguments(
                                &expression.location,
                                &type_parameters,
                                type_expressions,
                            ) {
                                if definition_ref.is_type_constructor() {
                                    let typ = definition_ref.create_type(type_arguments);
                                    expression.kind = ExpressionKind::Typ(typ);
                                } else {
                                    let function = definition_ref.create_function(type_arguments);
                                    expression.kind = ExpressionKind::Function(function);
                                }
                            }
                        }
                        _ => {}
                    },
                    ExpressionKind::Call { callee, arguments } => {
                        match &callee.kind {
                            ExpressionKind::GetAttr { base, attr } => {
                                match &base.kind {
                                    ExpressionKind::Typ(typ) => {
                                        // Is typ an enum?
                                        if typ.is_enum() {
                                            let enum_type = typ.as_enum();
                                            match enum_type.lookup_variant(attr) {
                                                Some(variant) => {
                                                    let variant = Rc::downgrade(&variant);
                                                    let arguments = std::mem::take(arguments);
                                                    let enum_literal = EnumLiteral {
                                                        enum_type,
                                                        variant,
                                                        arguments,
                                                    };
                                                    expression.kind =
                                                        ExpressionKind::EnumLiteral(enum_literal)
                                                }
                                                None => {
                                                    // error!
                                                    self.error(
                                                        &callee.location,
                                                        format!(
                                                            "Error, no variant named: {}",
                                                            attr
                                                        ),
                                                    );
                                                }
                                            }
                                        }
                                        // ?
                                    }
                                    _ => {}
                                }
                                // ?
                            }
                            _ => {}
                        }
                    }
                    ExpressionKind::LoadSymbol(Symbol::Definition(definition_ref)) => {
                        // Short-hand when we refer to a definition without type parameters!
                        if definition_ref.get_type_parameters().is_empty() {
                            if definition_ref.is_type_constructor() {
                                // Maybe we can directly use it (without type arguments)
                                let typ = definition_ref.create_type(vec![]);
                                expression.kind = ExpressionKind::Typ(typ);
                            } else {
                                // Assume function :-) ....
                                let function = definition_ref.create_function(vec![]);
                                expression.kind = ExpressionKind::Function(function);
                            }
                        }
                    }
                    _ => {}
                }
                // self.check_expr(expression);
            }
            _ => {}
        }
    }
}
