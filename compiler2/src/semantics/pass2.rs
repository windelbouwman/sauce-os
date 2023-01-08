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
        match type_expression {
            SlangType::Unresolved(expr) => {
                let t_expr = std::mem::replace(
                    expr,
                    TypeExpression {
                        expr: Default::default(),
                    },
                );

                match self.transform_into_type(*t_expr.expr) {
                    Ok(typ) => {
                        *type_expression = typ;
                    }
                    Err(()) => {}
                }
            }

            _ => {
                // Fine? Yes, we have a good type.
            }
        }
    }

    /// Try to create a type from an expression.
    ///
    /// - Load a symbol => Check if it is a type, and use it.
    /// - get-index => array indexing, used for generic instantiation.
    fn transform_into_type(&mut self, type_expr: Expression) -> Result<SlangType, ()> {
        match type_expr.kind {
            ExpressionKind::LoadSymbol(Symbol::Typ(typ)) => Ok(typ),
            ExpressionKind::LoadSymbol(Symbol::Definition(definition_ref)) => {
                // If we have no type parameters, we can access this directly.
                if definition_ref.get_type_parameters().is_empty() {
                    Ok(definition_ref.into_definition().create_type(vec![]))
                } else {
                    let location: &Location = &type_expr.location;
                    self.error(location, "We need type arguments".to_owned());
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
                self.error(location, format!("Invalid type expression is no type"));
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
        let typ = definition_ref.into_definition().create_type(type_arguments);
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
                self.error(&expr.location, format!("Invalid generic"));
                Err(())
            }
        }
    }

    fn error(&mut self, location: &Location, message: String) {
        self.diagnostics.error(location.clone(), message);
    }
}

impl VisitorApi for Pass2 {
    fn pre_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::TypeExpr(_type_expression) => {
                // self.check_type_expression(type_expression);
            }
            VisitedNode::Expression(_expression) => {
                // self.check_expr(expression);
            }
            _ => {}
        }
    }

    fn post_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::TypeExpr(type_expression) => {
                self.check_type_expression(type_expression);
            }
            VisitedNode::Expression(expression) => {
                match &mut expression.kind {
                    // TBD: this could be a whole seperate pass?
                    ExpressionKind::GetIndex { base, index: _ } => match &base.kind {
                        ExpressionKind::LoadSymbol(Symbol::Definition(_definition_ref)) => {
                            let old_expr = std::mem::take(expression);
                            // self.instantiate_generic(old_expr);
                            let typ = self.transform_into_type(old_expr).unwrap();
                            *expression = ExpressionKind::LoadSymbol(Symbol::Typ(typ)).into_expr();
                            //
                            // let t = self.instantiate_generic(&expression.location, base, type_arguments)
                        }
                        _ => {}
                    },
                    ExpressionKind::Call { callee, arguments } => {
                        match &callee.kind {
                            ExpressionKind::GetAttr { base, attr } => {
                                match &base.kind {
                                    ExpressionKind::LoadSymbol(Symbol::Typ(typ)) => {
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
                                                    panic!("Error, no variant named: {}", attr);
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
                        // Maybe we can directly use it (without type arguments)
                        if definition_ref.get_type_parameters().is_empty() {
                            let typ = definition_ref.clone().into_definition().create_type(vec![]);
                            expression.kind = ExpressionKind::LoadSymbol(Symbol::Typ(typ));
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
