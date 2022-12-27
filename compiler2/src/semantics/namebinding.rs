/*

Name binding

Loop over the AST and resolve references to things.

This phase mutates the AST such that objref nodes are
replaced by proper references.

TBD: could be combined with the type checker?

*/

use super::type_system::{Generic, SlangType, UserType};
use super::typed_ast;
use super::visitor::{visit_program, VisitedNode, VisitorApi};
use super::{Diagnostics, Scope, Symbol};
use crate::errors::CompilationError;
use crate::parsing::{ast, Location};
use std::rc::Rc;
use std::sync::Arc;

/// Modify the AST such that all symbols are resolved.
pub fn bind_names(
    program: &mut typed_ast::Program,
    builtin_scope: Arc<Scope>,
) -> Result<(), CompilationError> {
    log::debug!("Name binding '{}'", program.name);
    let mut binder = NameBinder::new(&program.path);
    binder.enter_scope(builtin_scope);
    visit_program(&mut binder, program);
    binder.leave_scope();
    binder.diagnostics.value_or_error(())
}

struct NameBinder {
    scopes: Vec<Arc<Scope>>,
    diagnostics: Diagnostics,
}

impl NameBinder {
    fn new(path: &std::path::Path) -> Self {
        Self {
            scopes: vec![],
            diagnostics: Diagnostics::new(path),
        }
    }

    /// Check if expression is an unresolved reference
    /// resolve it, and update the expression to the resolved object.
    fn check_expr(&mut self, expression: &mut typed_ast::Expression) {
        match &expression.kind {
            typed_ast::ExpressionKind::Object(obj_ref) => {
                if let Some(symbol) = self.resolve_obj(&obj_ref) {
                    expression.kind = typed_ast::ExpressionKind::LoadSymbol(symbol);
                }
            }
            _ => {}
        }
    }

    fn check_type_expression(&mut self, type_expression: &mut SlangType) {
        match type_expression {
            SlangType::Unresolved(obj_ref) => {
                if let Some(symbol) = self.resolve_obj(&obj_ref) {
                    match symbol {
                        Symbol::Typ(typ) => {
                            *type_expression = typ;
                        }
                        other => {
                            let location: Location = obj_ref.location();
                            self.error(&location, format!("Symbol is no type, but: {}", other));
                        }
                    }
                }
            }
            SlangType::GenericInstance { generic, .. } => match generic {
                Generic::Unresolved(obj_ref) => {
                    if let Some(symbol) = self.resolve_obj(obj_ref) {
                        match symbol {
                            Symbol::Generic(generic_def) => {
                                *generic = Generic::Generic(generic_def);
                            }
                            other => {
                                let location: Location = obj_ref.location();
                                self.error(
                                    &location,
                                    format!("Expected generic, but got: {}", other),
                                );
                            }
                        }
                    }
                }
                _ => {}
            },
            _ => {
                // Fine?
            }
        }
    }

    /// Try to resolve a reference to an object.
    ///
    /// Registers an error when the object cannot be resolved.
    fn resolve_obj(&mut self, obj_ref: &ast::ObjRef) -> Option<Symbol> {
        match obj_ref {
            ast::ObjRef::Name { location, name } => {
                if let Ok(symbol) = self.lookup(location, name) {
                    Some(symbol)
                } else {
                    None
                }
            }
            ast::ObjRef::Inner {
                location,
                base,
                member,
            } => {
                let base = self.resolve_obj(base)?;
                if let Ok(x) = self.access_symbol(location, base, member) {
                    Some(x)
                } else {
                    None
                }
            }
        }
    }

    fn access_symbol(
        &mut self,
        location: &Location,
        base: Symbol,
        member: &str,
    ) -> Result<Symbol, ()> {
        match base {
            Symbol::Module(module_ref) => {
                if module_ref.scope.is_defined(member) {
                    let obj = module_ref.scope.get(member).expect("We checked!").clone();
                    Ok(obj)
                } else {
                    self.error(
                        location,
                        format!("Module '{}' has no member: {}", module_ref.name, member),
                    );
                    Err(())
                }
            }

            Symbol::Typ(SlangType::User(UserType::Enum(enum_type))) => {
                let enum_type = enum_type.upgrade().unwrap();
                if let Some(variant) = enum_type.lookup(member) {
                    Ok(Symbol::EnumVariant(Rc::downgrade(&variant)))
                } else {
                    self.error(location, format!("Enum has no variant named '{}'", member));
                    Err(())
                }
            }

            other => {
                self.error(location, format!("Cannot scope-access: {}", other));
                Err(())
            }
        }
    }

    fn enter_scope(&mut self, scope: Arc<Scope>) {
        log::trace!("Enter scope");
        scope.dump();
        self.scopes.push(scope);
    }

    fn leave_scope(&mut self) {
        self.scopes.pop();
        log::trace!("Leave scope");
    }

    /// Lookup a name in the current stack of scopes.
    /// produce an error when the symbol is not found.
    fn lookup(&mut self, location: &Location, name: &str) -> Result<Symbol, ()> {
        let symbol = self.lookup2(name);
        match symbol {
            Some(symbol) => Ok(symbol),
            None => {
                self.error(location, format!("Name '{}' undefined", name));
                Err(())
            }
        }
    }

    /// Lookup a name in the current stack of scopes.
    fn lookup2(&self, name: &str) -> Option<Symbol> {
        for scope in self.scopes.iter().rev() {
            if scope.is_defined(name) {
                return scope.get(name).cloned();
            }
        }
        None
    }

    fn error(&mut self, location: &Location, message: String) {
        self.diagnostics.error(location.clone(), message);
    }
}

/// Given a visited node, retrieve its scope!
fn get_scope(node: &VisitedNode) -> Option<Arc<Scope>> {
    match node {
        VisitedNode::Program(program) => Some(program.scope.clone()),
        VisitedNode::Generic(generic) => Some(generic.scope.clone()),
        VisitedNode::Definition(definition) => match definition {
            typed_ast::Definition::Function(function_def) => {
                Some(function_def.borrow().scope.clone())
            }
            _ => None,
        },
        VisitedNode::Function(function_def) => Some(function_def.scope.clone()),
        VisitedNode::CaseArm(case_arm) => Some(case_arm.scope.clone()),
        // VisitedNode::Statement(statement) => match statement.kind {
        //     typed_ast::StatementKind::Case(case_statement) => Some(case_statement.scope.clone()),
        //     _ => None,
        // },
        _ => None,
    }
}

impl VisitorApi for NameBinder {
    fn pre_node(&mut self, node: VisitedNode) {
        if let Some(scope) = get_scope(&node) {
            self.enter_scope(scope);
        }

        match node {
            VisitedNode::TypeExpr(type_expression) => {
                self.check_type_expression(type_expression);
            }
            VisitedNode::Expression(expression) => {
                self.check_expr(expression);
            }
            _ => {}
        }
    }

    fn post_node(&mut self, node: VisitedNode) {
        if get_scope(&node).is_some() {
            self.leave_scope();
        }
    }
}
