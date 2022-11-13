//! Transform AST into typed AST and fill scopes
//! in during this process.
//!
//! Ideas:
//! Tasks involved here:
//! - Translate ast into typed_ast.
//! - Fill scopes with symbols.
//! - Assign unique ID to each symbol.

use super::context::Context;
use super::type_system::{Generic, SlangType, TypeVarRef, UserType};
use super::typed_ast;
use super::NodeId;
use super::Ref;
use super::{Diagnostics, Scope, Symbol};
use crate::parsing::{ast, Location};
use crate::CompilationError;
use std::cell::RefCell;
use std::rc::{Rc, Weak};
use std::sync::Arc;

pub fn ast_to_nodes(
    program: ast::Program,
    context: &mut Context,
) -> Result<typed_ast::Program, CompilationError> {
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
    local_variables: Vec<Rc<RefCell<typed_ast::LocalVariable>>>,
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

    fn on_prog(mut self, prog: ast::Program) -> Result<typed_ast::Program, CompilationError> {
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

        let mut defs = vec![];
        let mut generics = vec![];
        for type_def in prog.typedefs {
            if let Some(definition) = self.on_type_def(type_def, &mut generics) {
                defs.push(definition);
            }
        }

        for function_def in prog.functions {
            match self.on_function_def(function_def, None) {
                Ok(typed_function_def) => {
                    defs.push(typed_ast::Definition::Function(typed_function_def))
                }
                Err(()) => {}
            }
        }

        let prog_scope = self.leave_scope();
        assert!(self.scopes.is_empty());

        let typed_prog = typed_ast::Program {
            name: prog.name,
            path: prog.path,
            scope: Arc::new(prog_scope),
            generics,
            definitions: defs,
        };

        self.diagnostics.value_or_error(typed_prog)
    }

    /// Try to load a module by the given name.
    fn load_module(
        &mut self,
        location: &Location,
        modname: &str,
    ) -> Option<Rc<typed_ast::Program>> {
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

    fn on_type_def(
        &mut self,
        type_def: ast::TypeDef,
        generics: &mut Vec<Rc<typed_ast::GenericDef>>,
    ) -> Option<typed_ast::Definition> {
        match type_def {
            ast::TypeDef::Class(class_def) => self.check_class_def(class_def).ok(),
            ast::TypeDef::Struct(struct_def) => self.check_struct_def(struct_def).ok(),
            ast::TypeDef::Enum(enum_def) => self.check_enum_def(enum_def).ok(),
            ast::TypeDef::Generic {
                name,
                location,
                base,
                parameters,
            } => {
                self.enter_scope();
                let mut type_parameters = vec![];
                // Register type variables as parameters!
                for type_var in parameters {
                    let type_var2 = Rc::new(typed_ast::TypeVar {
                        name: type_var.name.clone(),
                        location: type_var.location.clone(),
                        id: self.new_id(),
                    });
                    self.define(
                        &type_var.name,
                        Symbol::Typ(SlangType::TypeVar(TypeVarRef {
                            ptr: Rc::downgrade(&type_var2),
                        })),
                        &type_var.location,
                    );
                    type_parameters.push(type_var2);
                }

                // TODO: this code needs cleaning...
                let mut temp_vec = vec![];
                let base = self.on_type_def(*base, &mut temp_vec).unwrap();
                assert!(temp_vec.is_empty());

                let scope = Arc::new(self.leave_scope());

                let generic_def = Rc::new(typed_ast::GenericDef {
                    base,
                    scope,
                    name: name.clone(),
                    id: self.new_id(),
                    location: location.clone(),
                    type_parameters,
                });

                self.define(
                    &name,
                    Symbol::Generic(Rc::downgrade(&generic_def)),
                    &location,
                );

                generics.push(generic_def);

                None
            }
        }
    }

    /// Process a struct definition.
    fn check_struct_def(
        &mut self,
        struct_def: ast::StructDef,
    ) -> Result<typed_ast::Definition, ()> {
        self.enter_scope();

        let mut inner_defs = vec![];
        for (index, field) in struct_def.fields.into_iter().enumerate() {
            let field_typ = self.on_type_expression(field.typ);

            let field_def = Rc::new(RefCell::new(typed_ast::FieldDef {
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

        let struct_ref = Rc::new(typed_ast::StructDef {
            location: struct_def.location.clone(),
            name: struct_def.name.clone(),
            id: self.new_id(),
            scope: Arc::new(struct_scope),
            fields: inner_defs,
        });

        self.define(
            &struct_def.name,
            Symbol::Typ(SlangType::User(UserType::Struct(Rc::downgrade(
                &struct_ref,
            )))),
            &struct_def.location,
        );

        Ok(typed_ast::Definition::Struct(struct_ref))
    }

    fn check_enum_def(&mut self, enum_def: ast::EnumDef) -> Result<typed_ast::Definition, ()> {
        self.enter_scope();
        let mut variants = vec![];
        for (index, option) in enum_def.options.into_iter().enumerate() {
            let mut payload_types = vec![];
            for typ in option.data {
                payload_types.push(self.on_type_expression(typ));
            }

            let variant = Rc::new(RefCell::new(typed_ast::EnumVariant {
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

        let typed_enum_def = Rc::new(typed_ast::EnumDef {
            location: enum_def.location.clone(),
            id: self.new_id(),
            name: enum_def.name.clone(),
            variants,
            scope: enum_scope,
        });

        let enum_ref = Rc::downgrade(&typed_enum_def);

        // Patch in references to enum type in variants:
        for variant_ref in &typed_enum_def.variants {
            variant_ref.borrow_mut().parent = enum_ref.clone();
        }

        self.define(
            &enum_def.name,
            Symbol::Typ(SlangType::User(UserType::Enum(enum_ref))),
            &enum_def.location,
        );

        Ok(typed_ast::Definition::Enum(typed_enum_def))
    }

    /// Process a class definition.
    ///
    /// - Store class in current scope
    /// - Process individual fields in class in new scope
    fn check_class_def(&mut self, class_def: ast::ClassDef) -> Result<typed_ast::Definition, ()> {
        self.enter_scope();

        let mut fields = vec![];
        for (index, field) in class_def.fields.into_iter().enumerate() {
            let field_typ = self.on_type_expression(field.typ);
            let value = self.on_expression(field.value)?;
            let field_def = Rc::new(RefCell::new(typed_ast::FieldDef {
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

        let class_ref = Rc::new(typed_ast::ClassDef {
            location: class_def.location.clone(),
            id: self.new_id(),
            name: class_def.name.clone(),
            fields,
            methods,
            scope: Arc::new(class_scope),
        });

        self.define(
            &class_def.name,
            Symbol::Typ(SlangType::User(UserType::Class(Rc::downgrade(&class_ref)))),
            &class_def.location,
        );

        Ok(typed_ast::Definition::Class(class_ref))
    }

    /// Process function definition.
    fn on_function_def(
        &mut self,
        function_def: ast::FunctionDef,
        this_param: Option<String>,
    ) -> Result<Rc<RefCell<typed_ast::FunctionDef>>, ()> {
        self.enter_scope();
        let this_param = if let Some(name) = this_param {
            Some(self.new_parameter(function_def.location.clone(), name, SlangType::Undefined))
        } else {
            None
        };

        let mut typed_parameters: Vec<Rc<RefCell<typed_ast::Parameter>>> = vec![];
        for parameter in function_def.parameters.into_iter() {
            let param_typ = self.on_type_expression(parameter.typ);
            typed_parameters.push(self.new_parameter(
                parameter.location,
                parameter.name,
                param_typ,
            ));
        }
        let body = self.on_block(function_def.body);
        let scope = self.leave_scope();

        let return_type = if let Some(return_type) = function_def.return_type {
            Some(self.on_type_expression(return_type))
        } else {
            None
        };

        let local_variables = std::mem::take(&mut self.local_variables);

        let func = Rc::new(RefCell::new(typed_ast::FunctionDef {
            name: function_def.name.clone(),
            id: self.new_id(),
            this_param,
            location: function_def.location.clone(),
            parameters: typed_parameters,
            return_type,
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

    fn new_parameter(
        &mut self,
        location: Location,
        name: String,
        typ: SlangType,
    ) -> Rc<RefCell<typed_ast::Parameter>> {
        let param = Rc::new(RefCell::new(typed_ast::Parameter {
            location: location.clone(),
            name: name.clone(),
            typ,
            id: self.new_id(),
        }));
        let param_ref = Rc::downgrade(&param);

        self.define(&name, Symbol::Parameter(param_ref), &location);
        param
    }

    fn on_type_expression(&mut self, type_expression: ast::Type) -> SlangType {
        match type_expression.kind {
            ast::TypeKind::Object(obj_ref) => SlangType::Unresolved(obj_ref),
            ast::TypeKind::GenericInstantiate {
                base_type,
                type_parameters,
            } => {
                let generic = Generic::Unresolved(base_type);
                let type_parameters = type_parameters
                    .into_iter()
                    .map(|p| self.on_type_expression(p))
                    .collect();
                SlangType::GenericInstance {
                    generic,
                    type_parameters,
                }
            }
        }
    }

    fn on_block(&mut self, block: Vec<ast::Statement>) -> Vec<typed_ast::Statement> {
        let mut typed_statements = vec![];
        for statement in block {
            match self.on_statement(statement) {
                Ok(typed_statement) => typed_statements.push(typed_statement),
                Err(()) => {}
            }
        }
        typed_statements
    }

    fn on_statement(&mut self, statement: ast::Statement) -> Result<typed_ast::Statement, ()> {
        let (location, kind) = (statement.location, statement.kind);
        let kind: typed_ast::StatementKind = match kind {
            ast::StatementType::Let {
                name,
                mutable: _,
                type_hint,
                value,
            } => {
                let value = self.on_expression(value)?;
                let type_hint = if let Some(type_hint) = type_hint {
                    Some(self.on_type_expression(type_hint))
                } else {
                    None
                };
                let local_var_ref = self.new_local_variable(&location, name);
                typed_ast::StatementKind::Let {
                    local_ref: local_var_ref,
                    type_hint,
                    value,
                }
            }
            ast::StatementType::Assignment { target, value } => {
                let target = self.on_expression(target)?;
                let value = self.on_expression(value)?;
                typed_ast::StatementKind::Assignment(typed_ast::AssignmentStatement {
                    target,
                    value,
                })
            }
            ast::StatementType::For { name, it, body } => {
                let iterable = self.on_expression(it)?;
                let loop_var = self.new_local_variable(&location, name);
                let body = self.on_block(body);
                typed_ast::StatementKind::For(typed_ast::ForStatement {
                    loop_var,
                    iterable,
                    body,
                })
            }
            ast::StatementType::If {
                condition,
                if_true,
                if_false,
            } => {
                let condition = self.on_expression(condition)?;
                let if_true = self.on_block(if_true);
                let if_false = if_false.map(|e| self.on_block(e));
                typed_ast::StatementKind::If(typed_ast::IfStatement {
                    condition,
                    if_true,
                    if_false,
                })
            }
            ast::StatementType::Expression(expr) => {
                let expr = self.on_expression(expr)?;
                typed_ast::StatementKind::Expression(expr)
            }
            ast::StatementType::Pass => typed_ast::StatementKind::Pass,
            ast::StatementType::Continue => typed_ast::StatementKind::Continue,
            ast::StatementType::Break => typed_ast::StatementKind::Break,
            ast::StatementType::Return { value } => {
                let value = if let Some(value) = value {
                    Some(self.on_expression(value)?)
                } else {
                    None
                };
                typed_ast::StatementKind::Return { value }
            }
            ast::StatementType::Loop { body } => {
                let body = self.on_block(body);
                typed_ast::StatementKind::Loop { body }
            }
            ast::StatementType::While { condition, body } => {
                let condition = self.on_expression(condition)?;
                let body = self.on_block(body);
                typed_ast::StatementKind::While(typed_ast::WhileStatement { condition, body })
            }
            ast::StatementType::Switch {
                value,
                arms,
                default,
            } => {
                let value = self.on_expression(value)?;
                let mut new_arms = vec![];
                for arm in arms {
                    new_arms.push(typed_ast::SwitchArm {
                        value: self.on_expression(arm.value)?,
                        body: self.on_block(arm.body),
                    });
                }
                let default = self.on_block(default);
                typed_ast::StatementKind::Switch(typed_ast::SwitchStatement {
                    value,
                    arms: new_arms,
                    default,
                })
            }
            ast::StatementType::Case { value, arms } => self.on_case_statement(value, arms)?,

            ast::StatementType::Match { .. } => {
                unimplemented!("TODO: match statement");
            }
        };

        let stmt = typed_ast::Statement { location, kind };

        Ok(stmt)
    }

    /// Check a case-statement.
    fn on_case_statement(
        &mut self,
        value: ast::Expression,
        arms: Vec<ast::CaseArm>,
    ) -> Result<typed_ast::StatementKind, ()> {
        let value = self.on_expression(value)?;

        let mut typed_arms = vec![];
        for arm in arms {
            let constructor = typed_ast::obj_ref(arm.constructor).at(arm.location.clone());

            self.enter_scope();

            let mut local_refs = vec![];
            for arg_name in arm.arguments {
                let local_ref = self.new_local_variable(&arm.location, arg_name.clone());
                local_refs.push(local_ref);
            }

            let body = self.on_block(arm.body);
            let scope = Arc::new(self.leave_scope());

            typed_arms.push(typed_ast::CaseArm {
                location: arm.location,
                constructor,
                local_refs,
                scope,
                body,
            });
        }

        Ok(typed_ast::StatementKind::Case(typed_ast::CaseStatement {
            value,
            arms: typed_arms,
        }))
    }

    fn on_expression(&mut self, expression: ast::Expression) -> Result<typed_ast::Expression, ()> {
        let (kind, location) = (expression.kind, expression.location);
        let kind: typed_ast::ExpressionKind = match kind {
            ast::ExpressionType::Call { callee, arguments } => {
                self.check_call(*callee, arguments)?
            }
            ast::ExpressionType::Binop { lhs, op, rhs } => {
                let lhs = self.on_expression(*lhs)?;
                let rhs = self.on_expression(*rhs)?;
                typed_ast::ExpressionKind::Binop {
                    lhs: Box::new(lhs),
                    op,
                    rhs: Box::new(rhs),
                }
            }
            ast::ExpressionType::Object(obj_ref) => typed_ast::ExpressionKind::Object(obj_ref),
            ast::ExpressionType::Literal(value) => match value {
                ast::Literal::Bool(value) => {
                    typed_ast::ExpressionKind::Literal(typed_ast::Literal::Bool(value))
                }
                ast::Literal::Integer(value) => {
                    typed_ast::ExpressionKind::Literal(typed_ast::Literal::Integer(value))
                }
                ast::Literal::String(value) => {
                    typed_ast::ExpressionKind::Literal(typed_ast::Literal::String(value))
                }
                ast::Literal::Float(value) => {
                    typed_ast::ExpressionKind::Literal(typed_ast::Literal::Float(value))
                }
            },
            ast::ExpressionType::ListLiteral(values) => {
                assert!(!values.is_empty());
                let mut typed_values = vec![];
                for value in values {
                    typed_values.push(self.on_expression(value)?);
                }
                typed_ast::ExpressionKind::ListLiteral(typed_values)
            }
            ast::ExpressionType::ArrayIndex { base, indici } => {
                self.do_array_index(*base, indici)?
            }
            ast::ExpressionType::GetAttr { base, attr } => {
                let base = self.on_expression(*base)?;
                typed_ast::ExpressionKind::GetAttr {
                    base: Box::new(base),
                    attr,
                }
            }
            ast::ExpressionType::ObjectInitializer { typ, fields } => {
                let typ = self.on_type_expression(typ);
                let mut fields2 = vec![];
                for field in fields {
                    let value = self.on_expression(field.value)?;
                    fields2.push(typed_ast::LabeledField {
                        location: field.location,
                        name: field.name,
                        value: Box::new(value),
                    });
                }
                typed_ast::ExpressionKind::ObjectInitializer {
                    typ,
                    fields: fields2,
                }
            }
        };

        let expr = typed_ast::Expression::new(location, kind);

        Ok(expr)
    }

    fn check_call(
        &mut self,
        callee: ast::Expression,
        arguments: Vec<ast::Expression>,
    ) -> Result<typed_ast::ExpressionKind, ()> {
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
            //     typed_ast::ExpressionKind::MethodCall {
            //         instance: Box::new(instance),
            //         method: attr,
            //         arguments: typed_arguments,
            //     }
            // }
            other => {
                let callee = self.on_expression(other)?;
                typed_ast::ExpressionKind::Call {
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
    ) -> Result<typed_ast::ExpressionKind, ()> {
        let base = self.on_expression(base)?;
        if indici.len() == 1 {
            let index = self.on_expression(indici.into_iter().next().expect("1 element"))?;
            Ok(typed_ast::ExpressionKind::GetIndex {
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
    ) -> Ref<typed_ast::LocalVariable> {
        let new_var = Rc::new(RefCell::new(typed_ast::LocalVariable::new(
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
            log::trace!("define symbol '{}' at {:?}", name, location);
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
