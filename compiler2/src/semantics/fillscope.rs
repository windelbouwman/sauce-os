//! Transform AST into typed AST (TAST) and fill scopes
//! during this process.
//!
//! Tasks involved here:
//! - Translate ast into typed_ast.
//! - Fill scopes with symbols.
//! - Assign unique ID to each symbol.

use super::context::Context;
use super::Diagnostics;
use crate::parsing::{ast, Location};
use crate::tast;
use crate::tast::{
    DefinitionRef, NameNodeId, NodeId, Ref, Scope, SlangType, Symbol, TypeExpression, TypeVar,
    UserType,
};
use crate::CompilationError;
use std::cell::RefCell;
use std::rc::{Rc, Weak};
use std::sync::Arc;

pub fn ast_to_nodes(
    program: ast::Program,
    context: &mut Context,
) -> Result<tast::Program, CompilationError> {
    log::debug!("Filling scopes");
    let phase1 = Phase1::new(&program.path, context);
    let prog = phase1.on_prog(program)?;
    log::debug!("Fill scope done & done");
    Ok(prog)
}

struct Phase1<'g> {
    context: &'g mut Context,
    scopes: Vec<Scope>,
    diagnostics: Diagnostics,
    local_variables: Vec<Rc<RefCell<tast::LocalVariable>>>,
}

impl<'g> Phase1<'g> {
    fn new(path: &std::path::Path, context: &'g mut Context) -> Self {
        Self {
            context,
            scopes: vec![],
            diagnostics: Diagnostics::new(path),
            local_variables: vec![],
        }
    }

    fn on_prog(mut self, prog: ast::Program) -> Result<tast::Program, CompilationError> {
        self.enter_scope();
        for import in &prog.imports {
            match import {
                ast::Import::Import { location, modname } => {
                    if let Some(module_ref) = self.load_module(location, modname) {
                        self.define(modname, Symbol::Module(module_ref), location);
                    }
                }
                ast::Import::ImportFrom {
                    location,
                    modname,
                    names,
                } => {
                    if let Some(module_ref) = self.load_module(location, modname) {
                        for name in names {
                            if module_ref.scope.is_defined(name) {
                                let symbol = module_ref.scope.get(name).expect("We checked!");
                                self.define(name, symbol.clone(), location);
                            } else {
                                self.error(
                                    location,
                                    format!("Module has no item member: {}", name),
                                );
                            }
                        }
                    }
                }
            }
        }

        let mut definitions = vec![];
        for definition in prog.definitions {
            if let Ok(definition) = self.on_definition(definition) {
                definitions.push(definition);
            }
        }

        let prog_scope = self.leave_scope();
        assert!(self.scopes.is_empty());

        let typed_prog = tast::Program {
            name: prog.name,
            path: prog.path,
            scope: Arc::new(prog_scope),
            definitions,
        };

        self.diagnostics.value_or_error(typed_prog)
    }

    /// Try to load a module by the given name.
    fn load_module(&mut self, location: &Location, modname: &str) -> Option<Rc<tast::Program>> {
        if self.context.modules_scope.is_defined(modname) {
            match self
                .context
                .modules_scope
                .get(modname)
                .expect("We checked this!")
            {
                Symbol::Module(module_ref) => Some(module_ref.clone()),
                other => {
                    panic!("Did not expect this symbol in module scope: {}", other);
                }
            }
        } else {
            self.error(location, format!("No such module: {}", modname));
            None
        }
    }

    fn on_definition(&mut self, type_def: ast::Definition) -> Result<tast::Definition, ()> {
        match type_def {
            ast::Definition::Class(class_def) => self.check_class_def(class_def),
            ast::Definition::Struct(struct_def) => self.on_struct_def(struct_def),
            ast::Definition::Enum(enum_def) => self.on_enum_def(enum_def),
            ast::Definition::Function(function_def) => {
                match self.on_function_def(function_def, None) {
                    Ok(typed_function_def) => Ok(tast::Definition::Function(typed_function_def)),
                    Err(()) => Err(()),
                }
            }
        }
    }

    fn on_type_parameters(&mut self, parameters: Vec<ast::TypeVar>) -> Vec<Rc<TypeVar>> {
        let mut type_parameters = vec![];
        // Register type variables as parameters!
        for type_var in parameters {
            let type_var2 = Rc::new(TypeVar {
                name: NameNodeId {
                    name: type_var.name.clone(),
                    id: self.new_id(),
                },
                location: type_var.location.clone(),
            });
            self.define(
                &type_var.name,
                Symbol::Typ(SlangType::type_var(&type_var2)),
                &type_var.location,
            );
            type_parameters.push(type_var2);
        }
        type_parameters
    }

    /// Process a struct definition.
    fn on_struct_def(&mut self, struct_def: ast::StructDef) -> Result<tast::Definition, ()> {
        self.enter_scope();
        let type_parameters = self.on_type_parameters(struct_def.type_parameters);

        let mut inner_defs = vec![];
        for (index, field) in struct_def.fields.into_iter().enumerate() {
            let field_typ = self.on_type_expression(field.typ)?;

            let field_def = Rc::new(RefCell::new(tast::FieldDef {
                location: field.location.clone(),
                name: field.name.clone(),
                typ: field_typ,
                index,
                value: None, // optional default value?
            }));

            // TBD: use scope system for struct fields?
            // Might be a bad plan / overkill?
            self.define(
                &field.name,
                Symbol::Field(Rc::downgrade(&field_def)),
                &field.location,
            );
            inner_defs.push(field_def);
        }

        let struct_scope = self.leave_scope();

        let struct_ref = Rc::new(tast::StructDef {
            location: struct_def.location.clone(),
            name: NameNodeId {
                name: struct_def.name.clone(),
                id: self.new_id(),
            },
            type_parameters,
            scope: Arc::new(struct_scope),
            fields: inner_defs,
        });

        self.define(
            &struct_def.name,
            Symbol::Definition(DefinitionRef::Struct(Rc::downgrade(&struct_ref))),
            &struct_def.location,
        );

        Ok(tast::Definition::Struct(struct_ref))
    }

    fn on_enum_def(&mut self, enum_def: ast::EnumDef) -> Result<tast::Definition, ()> {
        self.enter_scope();
        let type_parameters = self.on_type_parameters(enum_def.type_parameters);

        let mut variants = vec![];
        for (index, option) in enum_def.options.into_iter().enumerate() {
            let mut payload_types = vec![];
            for typ in option.data {
                payload_types.push(self.on_type_expression(typ)?);
            }

            let variant = Rc::new(RefCell::new(tast::EnumVariant {
                location: option.location.clone(),
                name: option.name.clone(),
                data: payload_types,
                index,
                parent: Weak::new(),
            }));
            self.define(
                &option.name,
                Symbol::EnumVariant(Rc::downgrade(&variant)),
                &option.location,
            );
            variants.push(variant);
        }
        let enum_scope = self.leave_scope();

        let typed_enum_def = Rc::new(tast::EnumDef {
            location: enum_def.location.clone(),
            name: NameNodeId {
                name: enum_def.name.clone(),
                id: self.new_id(),
            },
            variants,
            scope: Arc::new(enum_scope),
            type_parameters,
        });

        let enum_ref = Rc::downgrade(&typed_enum_def);

        // Patch in references to enum type in variants:
        for variant_ref in &typed_enum_def.variants {
            variant_ref.borrow_mut().parent = enum_ref.clone();
        }

        self.define(
            &enum_def.name,
            Symbol::Definition(DefinitionRef::Enum(enum_ref)),
            &enum_def.location,
        );

        Ok(tast::Definition::Enum(typed_enum_def))
    }

    /// Process a class definition.
    ///
    /// - Store class in current scope
    /// - Process individual fields in class in new scope
    fn check_class_def(&mut self, class_def: ast::ClassDef) -> Result<tast::Definition, ()> {
        self.enter_scope();

        let mut fields = vec![];
        for (index, field) in class_def.fields.into_iter().enumerate() {
            let field_typ = self.on_type_expression(field.typ)?;
            let value = self.on_expression(field.value)?;
            let field_def = Rc::new(RefCell::new(tast::FieldDef {
                location: field.location.clone(),
                name: field.name.clone(),
                typ: field_typ,
                index,
                value: Some(value),
            }));

            fields.push(field_def.clone());

            self.define(
                &field.name,
                Symbol::Field(Rc::downgrade(&field_def)),
                &field.location,
            );
        }

        let mut methods = vec![];
        for method in class_def.methods {
            let typed_func = self.on_function_def(method, Some("this".to_owned()))?;
            methods.push(typed_func);
        }

        let class_scope = self.leave_scope();

        let class_ref = Rc::new(tast::ClassDef {
            location: class_def.location.clone(),
            name: NameNodeId {
                name: class_def.name.clone(),
                id: self.new_id(),
            },
            type_parameters: vec![],
            fields,
            methods,
            scope: Arc::new(class_scope),
        });

        self.define(
            &class_def.name,
            Symbol::Definition(DefinitionRef::Class(Rc::downgrade(&class_ref))),
            &class_def.location,
        );

        Ok(tast::Definition::Class(class_ref))
    }

    /// Process function definition.
    fn on_function_def(
        &mut self,
        function_def: ast::FunctionDef,
        this_param: Option<String>,
    ) -> Result<Rc<RefCell<tast::FunctionDef>>, ()> {
        self.enter_scope();
        let this_param = if let Some(name) = this_param {
            Some(self.new_parameter(function_def.location.clone(), name, SlangType::Undefined))
        } else {
            None
        };

        let signature = self.on_function_signature(function_def.signature)?;

        let body = self.on_block(function_def.body);
        let scope = self.leave_scope();

        let local_variables = std::mem::take(&mut self.local_variables);

        let func = Rc::new(RefCell::new(tast::FunctionDef {
            name: NameNodeId {
                name: function_def.name.clone(),
                id: self.new_id(),
            },
            this_param,
            location: function_def.location.clone(),
            signature,
            scope: Arc::new(scope),
            locals: local_variables,
            body,
        }));

        let func_ref = Rc::downgrade(&func);

        self.define(
            &function_def.name,
            Symbol::Function(func_ref),
            &function_def.location,
        );

        Ok(func)
    }

    fn on_function_signature(
        &mut self,
        signature: ast::FunctionSignature,
    ) -> Result<Rc<RefCell<tast::FunctionSignature>>, ()> {
        let mut typed_parameters: Vec<Rc<RefCell<tast::Parameter>>> = vec![];
        for parameter in signature.parameters.into_iter() {
            let param_typ = self.on_type_expression(parameter.typ)?;
            typed_parameters.push(self.new_parameter(
                parameter.location,
                parameter.name,
                param_typ,
            ));
        }

        let return_type = if let Some(return_type) = signature.return_type {
            Some(self.on_type_expression(return_type)?)
        } else {
            None
        };

        Ok(Rc::new(RefCell::new(tast::FunctionSignature {
            parameters: typed_parameters,
            return_type,
        })))
    }

    fn new_parameter(
        &mut self,
        location: Location,
        name: String,
        typ: SlangType,
    ) -> Rc<RefCell<tast::Parameter>> {
        let param = Rc::new(RefCell::new(tast::Parameter {
            location: location.clone(),
            name: NameNodeId {
                name: name.clone(),
                id: self.new_id(),
            },
            typ,
        }));
        let param_ref = Rc::downgrade(&param);

        self.define(&name, Symbol::Parameter(param_ref), &location);
        param
    }

    fn on_type_expression(&mut self, type_expression: ast::Expression) -> Result<SlangType, ()> {
        let unresolved = self.on_expression(type_expression)?;
        Ok(SlangType::Unresolved(TypeExpression {
            expr: Box::new(unresolved),
        }))
    }

    fn on_block(&mut self, block: Vec<ast::Statement>) -> Vec<tast::Statement> {
        let mut typed_statements = vec![];
        for statement in block {
            match self.on_statement(statement) {
                Ok(typed_statement) => typed_statements.push(typed_statement),
                Err(()) => {}
            }
        }
        typed_statements
    }

    fn on_statement(&mut self, statement: ast::Statement) -> Result<tast::Statement, ()> {
        let (location, kind) = (statement.location, statement.kind);
        let kind: tast::StatementKind = match kind {
            ast::StatementKind::Let {
                name,
                mutable: _,
                type_hint,
                value,
            } => {
                let value = self.on_expression(value)?;
                let type_hint = if let Some(type_hint) = type_hint {
                    Some(self.on_type_expression(type_hint)?)
                } else {
                    None
                };
                let local_var_ref = self.new_local_variable(&location, name);
                tast::StatementKind::Let {
                    local_ref: local_var_ref,
                    type_hint,
                    value,
                }
            }
            ast::StatementKind::Assignment { target, value } => {
                let target = self.on_expression(target)?;
                let value = self.on_expression(value)?;
                tast::StatementKind::Assignment(tast::AssignmentStatement { target, value })
            }
            ast::StatementKind::For { name, it, body } => {
                let iterable = self.on_expression(it)?;
                let loop_var = self.new_local_variable(&location, name);
                let body = self.on_block(body);
                tast::StatementKind::For(tast::ForStatement {
                    loop_var,
                    iterable,
                    body,
                })
            }
            ast::StatementKind::If {
                condition,
                if_true,
                if_false,
            } => {
                let condition = self.on_expression(condition)?;
                let if_true = self.on_block(if_true);
                let if_false = if_false.map(|e| self.on_block(e));
                tast::StatementKind::If(tast::IfStatement {
                    condition,
                    if_true,
                    if_false,
                })
            }
            ast::StatementKind::Expression(expr) => {
                let expr = self.on_expression(expr)?;
                tast::StatementKind::Expression(expr)
            }
            ast::StatementKind::Pass => tast::StatementKind::Pass,
            ast::StatementKind::Continue => tast::StatementKind::Continue,
            ast::StatementKind::Break => tast::StatementKind::Break,
            ast::StatementKind::Return { value } => {
                let value = if let Some(value) = value {
                    Some(self.on_expression(value)?)
                } else {
                    None
                };
                tast::StatementKind::Return { value }
            }
            ast::StatementKind::Loop { body } => {
                let body = self.on_block(body);
                tast::StatementKind::Loop { body }
            }
            ast::StatementKind::While { condition, body } => {
                let condition = self.on_expression(condition)?;
                let body = self.on_block(body);
                tast::StatementKind::While(tast::WhileStatement { condition, body })
            }
            ast::StatementKind::Switch {
                value,
                arms,
                default,
            } => {
                let value = self.on_expression(value)?;
                let mut new_arms = vec![];
                for arm in arms {
                    new_arms.push(tast::SwitchArm {
                        value: self.on_expression(arm.value)?,
                        body: self.on_block(arm.body),
                    });
                }
                let default = self.on_block(default);
                tast::StatementKind::Switch(tast::SwitchStatement {
                    value,
                    arms: new_arms,
                    default,
                })
            }
            ast::StatementKind::Case { value, arms } => self.on_case_statement(value, arms)?,

            ast::StatementKind::Match { .. } => {
                unimplemented!("TODO: match statement");
            }
        };

        let stmt = tast::Statement { location, kind };

        Ok(stmt)
    }

    /// Check a case-statement.
    fn on_case_statement(
        &mut self,
        value: ast::Expression,
        arms: Vec<ast::CaseArm>,
    ) -> Result<tast::StatementKind, ()> {
        let value = self.on_expression(value)?;

        let mut typed_arms = vec![];
        for arm in arms {
            let variant = tast::VariantRef::Name(arm.variant);

            self.enter_scope();

            let mut local_refs = vec![];
            for arg_name in arm.arguments {
                let local_ref = self.new_local_variable(&arm.location, arg_name.clone());
                local_refs.push(local_ref);
            }

            let body = self.on_block(arm.body);
            let scope = Arc::new(self.leave_scope());

            typed_arms.push(tast::CaseArm {
                location: arm.location,
                variant,
                local_refs,
                scope,
                body,
            });
        }

        Ok(tast::StatementKind::Case(tast::CaseStatement {
            value,
            arms: typed_arms,
        }))
    }

    fn on_expression(&mut self, expression: ast::Expression) -> Result<tast::Expression, ()> {
        let (kind, location) = (expression.kind, expression.location);
        let kind: tast::ExpressionKind = match kind {
            ast::ExpressionKind::Call { callee, arguments } => {
                self.check_call(*callee, arguments)?
            }
            ast::ExpressionKind::Binop { lhs, op, rhs } => {
                let lhs = self.on_expression(*lhs)?;
                let rhs = self.on_expression(*rhs)?;
                tast::ExpressionKind::Binop {
                    lhs: Box::new(lhs),
                    op,
                    rhs: Box::new(rhs),
                }
            }
            ast::ExpressionKind::Object(obj_ref) => tast::ExpressionKind::Object(obj_ref),
            ast::ExpressionKind::FunctionType(signature) => {
                // Temporary scope to process function signature.
                self.enter_scope();
                let signature = self.on_function_signature(*signature)?;
                let _scope = self.leave_scope();
                let typ = SlangType::User(UserType::Function(signature));
                tast::ExpressionKind::LoadSymbol(Symbol::Typ(typ))
            }
            ast::ExpressionKind::Literal(value) => match value {
                ast::Literal::Bool(value) => {
                    tast::ExpressionKind::Literal(tast::Literal::Bool(value))
                }
                ast::Literal::Integer(value) => {
                    tast::ExpressionKind::Literal(tast::Literal::Integer(value))
                }
                ast::Literal::String(value) => {
                    tast::ExpressionKind::Literal(tast::Literal::String(value))
                }
                ast::Literal::Float(value) => {
                    tast::ExpressionKind::Literal(tast::Literal::Float(value))
                }
            },
            ast::ExpressionKind::ListLiteral(values) => {
                assert!(!values.is_empty());
                let mut typed_values = vec![];
                for value in values {
                    typed_values.push(self.on_expression(value)?);
                }
                tast::ExpressionKind::ListLiteral(typed_values)
            }
            ast::ExpressionKind::ArrayIndex { base, indici } => {
                self.do_array_index(*base, indici)?
            }
            ast::ExpressionKind::GetAttr { base, attr } => {
                let base = self.on_expression(*base)?;
                tast::ExpressionKind::GetAttr {
                    base: Box::new(base),
                    attr,
                }
            }
            ast::ExpressionKind::ObjectInitializer { typ, fields } => {
                let typ = self.on_type_expression(*typ)?;
                let mut fields2 = vec![];
                for field in fields {
                    let value = self.on_expression(field.value)?;
                    fields2.push(tast::LabeledField {
                        location: field.location,
                        name: field.name,
                        value: Box::new(value),
                    });
                }
                tast::ExpressionKind::ObjectInitializer {
                    typ,
                    fields: fields2,
                }
            }
        };

        let expr = tast::Expression::new(location, kind);

        Ok(expr)
    }

    fn check_call(
        &mut self,
        callee: ast::Expression,
        arguments: Vec<ast::Expression>,
    ) -> Result<tast::ExpressionKind, ()> {
        let mut typed_arguments = vec![];
        for argument in arguments {
            typed_arguments.push(self.on_expression(argument)?);
        }

        let kind = match callee {
            // ast::Expression {
            //     location,
            //     kind: ast::ExpressionType::GetAttr { base, attr },
            // } => {
            //     let instance = self.on_expression(*base)?;
            //     tast::ExpressionKind::MethodCall {
            //         instance: Box::new(instance),
            //         method: attr,
            //         arguments: typed_arguments,
            //     }
            // }
            other => {
                let callee = self.on_expression(other)?;
                tast::ExpressionKind::Call {
                    callee: Box::new(callee),
                    arguments: typed_arguments,
                }
            }
        };

        Ok(kind)
    }

    /// Check array indexing!
    ///
    /// Base must be an array or a list like thingy
    fn do_array_index(
        &mut self,
        base: ast::Expression,
        indici: Vec<ast::Expression>,
    ) -> Result<tast::ExpressionKind, ()> {
        let base = self.on_expression(base)?;
        if indici.len() == 1 {
            let index = self.on_expression(indici.into_iter().next().expect("1 element"))?;
            Ok(tast::ExpressionKind::GetIndex {
                base: Box::new(base),
                index: Box::new(index),
            })
        } else {
            unimplemented!("Multi-indexing");
        }
    }

    fn new_local_variable(
        &mut self,
        location: &Location,
        name: String,
    ) -> Ref<tast::LocalVariable> {
        let new_var = Rc::new(RefCell::new(tast::LocalVariable::new(
            location.clone(),
            false,
            name.clone(),
            self.new_id(),
        )));
        let local_ref = Rc::downgrade(&new_var);
        self.define(&name, Symbol::LocalVariable(local_ref.clone()), location);
        self.local_variables.push(new_var.clone());
        local_ref
    }

    /// Generate an error at the given location.
    fn error(&mut self, location: &Location, message: String) {
        self.diagnostics.error(location.clone(), message);
    }

    fn define(&mut self, name: &str, symbol: Symbol, location: &Location) {
        let scope = self.scopes.last_mut().unwrap();
        if scope.is_defined(name) {
            self.error(location, format!("Symbol {} already defined!", name));
        } else {
            log::trace!("define symbol '{}' at {}", name, location);
            scope.define(name.to_string(), symbol);
        }
    }

    fn enter_scope(&mut self) {
        log::trace!("Enter scope");
        self.scopes.push(Scope::new());
    }

    fn leave_scope(&mut self) -> Scope {
        log::trace!("Leave scope");
        let scope = self.scopes.pop().unwrap();
        scope.dump();
        scope
    }

    /// Create a new unique ID
    fn new_id(&mut self) -> NodeId {
        self.context.id_generator.gimme()
    }
}
