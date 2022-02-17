/* Ideas:

- the type checker is the last pass requiring location info. It will create a typed AST.

Tasks involved here:
- Resolve symbols
- Assign types everywhere

If we pass the typechecker, code is in pretty good shape!

*/

use super::generics::instantiate_type;
use super::type_system::{
    ArrayType, ClassField, ClassType, ClassTypeRef, EnumOption, EnumType, FunctionType, SlangType,
    StructField, StructType,
};
use super::typed_ast;
use super::{Diagnostics, Scope, Symbol};
use crate::parsing::{ast, Location};
use crate::CompilationError;
use std::collections::HashMap;

pub fn type_check(
    prog: ast::Program,
    module_scope: Scope,
) -> Result<typed_ast::Program, CompilationError> {
    let checker = TypeChecker::new();
    checker.check_prog(prog, module_scope)
}

struct TypeChecker {
    scopes: Vec<Scope>,
    diagnostics: Diagnostics,
    loops: Vec<()>,
    typed_imports: Vec<typed_ast::Import>,
    class_defs: Vec<typed_ast::ClassDef>,
    local_variables: Vec<typed_ast::LocalVariable>,
    dump_scope: bool,
}

impl TypeChecker {
    fn new() -> Self {
        TypeChecker {
            scopes: vec![],
            diagnostics: Default::default(),
            loops: vec![],
            typed_imports: vec![],
            class_defs: vec![],
            local_variables: vec![],
            dump_scope: false,
        }
    }
    fn define_builtins(&mut self) {
        // Built in types:
        let location: Location = Default::default();
        self.define("str", Symbol::Typ(SlangType::String), &location);
        self.define("int", Symbol::Typ(SlangType::Int), &location);
        self.define("float", Symbol::Typ(SlangType::Float), &location);
        self.define("bool", Symbol::Typ(SlangType::Bool), &location);
        let list_class_typ = ClassTypeRef::new(ClassType {
            name: "List".to_owned(),
            fields: vec![],
            methods: vec![],
        });

        let list_generic_type: SlangType = SlangType::Generic {
            base: Box::new(SlangType::Class(list_class_typ)),
            type_parameters: vec!["x".to_string()],
        };
        self.define("list", Symbol::Typ(list_generic_type), &location);
    }

    fn check_prog(
        mut self,
        prog: ast::Program,
        module_scope: Scope,
    ) -> Result<typed_ast::Program, CompilationError> {
        self.enter_scope();
        self.define_builtins();
        self.scopes.push(module_scope);
        self.enter_scope();
        for import in &prog.imports {
            // Check if module can be found
            match self.lookup2(&import.name) {
                None => self.error(
                    import.location.clone(),
                    format!("Module {} not loaded", import.name),
                ),
                Some(symbol) => match symbol {
                    Symbol::Module { .. } => {
                        // Ok!
                    }
                    other => {
                        self.error(
                            import.location.clone(),
                            format!("Cannot import: {:?}", other),
                        );
                    }
                },
            }

            // self.define(&import.name, Symbol::Module, &import.location);
        }

        let mut type_defs = vec![];
        for type_def in prog.typedefs {
            match self.check_type_def(type_def) {
                Ok(typedef) => type_defs.push(typedef),
                Err(()) => {}
            }
        }

        for function_def in &prog.functions {
            self.declare_function(function_def).ok();
        }

        let mut typed_function_defs = vec![];
        for function_def in prog.functions {
            match self.check_function_def(function_def) {
                Ok(typed_function_def) => typed_function_defs.push(typed_function_def),
                Err(()) => {}
            }
        }

        self.leave_scope(); // module scope
        self.leave_scope(); // Other module scope
        self.leave_scope(); // universe scope

        let typed_imports = std::mem::take(&mut self.typed_imports);
        let class_defs = std::mem::take(&mut self.class_defs);

        if self.diagnostics.errors.is_empty() {
            Ok(typed_ast::Program {
                class_defs,
                imports: typed_imports,
                type_defs,
                functions: typed_function_defs,
            })
        } else {
            Err(CompilationError::multi(self.diagnostics.errors))
        }
    }

    fn check_type_def(&mut self, type_def: ast::TypeDef) -> Result<typed_ast::TypeDef, ()> {
        match type_def {
            ast::TypeDef::Struct(struct_def) => self.check_struct_def(struct_def),
            ast::TypeDef::Class(class_def) => self.check_class_def(class_def),
            ast::TypeDef::Enum(enum_def) => self.check_enum_def(enum_def),
            ast::TypeDef::Generic {
                name,
                location,
                base,
                parameters,
            } => {
                let mut type_parameters = vec![];
                self.enter_scope();
                for type_var in parameters {
                    self.define(
                        &type_var.name,
                        Symbol::Typ(SlangType::TypeVar(type_var.name.clone())),
                        &type_var.location,
                    );
                    // TBD: we might as well use indici here?
                    type_parameters.push(type_var.name.clone());
                }
                let base = self.check_type_def(*base)?.typ;
                self.leave_scope();
                let typ = SlangType::Generic {
                    base: Box::new(base),
                    type_parameters,
                };
                self.define(&name, Symbol::Typ(typ.clone()), &location);
                Ok(typed_ast::TypeDef { name, typ })
            }
        }
    }

    fn check_struct_def(&mut self, struct_def: ast::StructDef) -> Result<typed_ast::TypeDef, ()> {
        let mut fields = vec![];
        for field in struct_def.fields {
            let name = field.name;
            let typ = self.eval_type_expr(&field.typ)?;
            fields.push(StructField { name, typ });
        }
        let struct_type = StructType {
            name: Some(struct_def.name.clone()),
            fields,
        };
        let typ = SlangType::Struct(struct_type);

        self.define(
            &struct_def.name,
            Symbol::Typ(typ.clone()),
            &struct_def.location,
        );
        Ok(typed_ast::TypeDef {
            name: struct_def.name,
            typ,
        })
    }

    fn check_enum_def(&mut self, enum_def: ast::EnumDef) -> Result<typed_ast::TypeDef, ()> {
        let mut choices = vec![];
        for option in enum_def.options {
            let mut payload = vec![];
            for typ in option.data {
                payload.push(self.eval_type_expr(&typ)?);
            }
            choices.push(EnumOption {
                name: option.name,
                data: payload,
            });
        }
        let enum_type = EnumType {
            name: enum_def.name.clone(),
            choices,
        };
        let typ = SlangType::Enum(enum_type);
        self.define(&enum_def.name, Symbol::Typ(typ.clone()), &enum_def.location);

        Ok(typed_ast::TypeDef {
            name: enum_def.name,
            typ,
        })
    }

    fn check_class_def(&mut self, class_def: ast::ClassDef) -> Result<typed_ast::TypeDef, ()> {
        // Create class type:
        let class_name = class_def.name.clone();

        let mut class_fields = vec![];
        for field in &class_def.fields {
            let field_typ = self.eval_type_expr(&field.typ)?;
            class_fields.push(ClassField {
                name: field.name.clone(),
                typ: field_typ.clone(),
            });
        }

        let mut class_methods = vec![];
        for method in &class_def.methods {
            let field_typ = self.get_function_typ(method)?;
            class_methods.push(ClassField {
                name: method.name.clone(),
                typ: field_typ.clone(),
            });
        }

        let class_typ = ClassTypeRef::new(ClassType {
            name: class_def.name.clone(),
            fields: class_fields,
            methods: class_methods,
        });

        let class_typ2 = SlangType::Class(class_typ.clone());

        self.enter_scope();

        let mut field_defs = vec![];
        for (index, field) in class_def.fields.into_iter().enumerate() {
            let field_typ = self.eval_type_expr(&field.typ)?;
            let value = self.coerce(&field_typ, field.value)?;
            field_defs.push(typed_ast::FieldDef {
                name: field.name.clone(),
                index,
                typ: field_typ.clone(),
                value,
            });
            self.define(
                &field.name,
                Symbol::Field {
                    class_typ: class_typ2.clone(),
                    name: field.name.clone(),
                    index,
                    typ: field_typ.clone(),
                },
                &field.location,
            );
        }

        let mut typed_functions = vec![];
        for method in class_def.methods {
            let typed_func = self.check_function_def(method)?;
            typed_functions.push(typed_func);
        }

        // TBD: we might use this scope?
        self.leave_scope();

        self.class_defs.push(typed_ast::ClassDef {
            name: class_name.clone(),
            field_defs,
            function_defs: typed_functions,
            typ: class_typ,
        });

        self.define(
            &class_name,
            Symbol::Typ(class_typ2.clone()),
            &class_def.location,
        );
        Ok(typed_ast::TypeDef {
            name: class_name,
            typ: class_typ2,
        })
    }

    /// Resolve expression into type!
    /// Wonky, this is resolved during compilation!
    fn eval_type_expr(&mut self, typ: &ast::Type) -> Result<SlangType, ()> {
        match &typ.kind {
            ast::TypeKind::Object(obj_ref) => {
                let symbol = self.resolve_obj(obj_ref)?;

                // let symbol = self.lookup(&expression.location, name)?;
                match symbol {
                    Symbol::Typ(t) => Ok(t),
                    other => {
                        self.error(
                            typ.location.clone(),
                            format!("Symbol is no type, but: {:?}", other),
                        );
                        Err(())
                    }
                }
            }
            ast::TypeKind::GenericInstantiate {
                base_type,
                type_parameters: actual_types,
            } => {
                let base_type = self.eval_type_expr(base_type)?;
                let mut actual_types2 = vec![];
                for actual_type in actual_types {
                    actual_types2.push(self.eval_type_expr(actual_type)?);
                }
                instantiate_type(
                    &mut self.diagnostics,
                    &typ.location,
                    base_type,
                    actual_types2,
                )
            }
        }
    }

    /// Have a closer look at a reference to a scoped object reference.
    fn resolve_obj(&mut self, obj_ref: &ast::ObjRef) -> Result<Symbol, ()> {
        match obj_ref {
            ast::ObjRef::Name { location, name } => {
                let symbol = self.lookup(location, name)?;
                // let typ = symbol.get_type().clone();
                Ok(symbol)
            }
            ast::ObjRef::Inner {
                location,
                base,
                member,
            } => {
                let base = self.resolve_obj(base)?;
                self.access_symbol(location, base, member)
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
            Symbol::Module {
                name: mod_name,
                scope,
            } => {
                if scope.is_defined(member) {
                    let obj = scope.get(member).unwrap().clone();
                    match obj {
                        Symbol::Function {
                            name: func_name,
                            typ,
                        } => {
                            // This might be too much desugaring at this point
                            // Maybe introduce a new phase?
                            // IDEA: Symbol::ImportedSymbol()
                            let full_name = format!("{}_{}", mod_name, func_name);
                            self.add_import(full_name.clone(), typ.clone());
                            Ok(Symbol::Function {
                                name: full_name,
                                typ,
                            })
                        }
                        Symbol::Typ(typ) => Ok(Symbol::Typ(typ)),
                        other => {
                            unimplemented!("Cannot import: {:?}", other);
                            // Err(())
                        }
                    }
                } else {
                    self.error(
                        location.clone(),
                        format!("Module has no member: {}", member),
                    );
                    Err(())
                }
            }
            Symbol::Typ(typ) => match typ {
                SlangType::Enum(enum_type) => {
                    if let Some(option) = enum_type.lookup(member) {
                        Ok(Symbol::EnumOption {
                            enum_type: enum_type.clone(),
                            choice: option,
                        })
                    } else {
                        self.error(
                            location.clone(),
                            format!("Enum has no option named: {}", member),
                        );
                        Err(())
                    }
                }
                other => {
                    self.error(
                        location.clone(),
                        format!("Cannot scope-access type: {:?}", other),
                    );
                    Err(())
                }
            },
            other => {
                self.error(
                    location.clone(),
                    format!("Cannot scope-access: {:?}", other),
                );
                Err(())
            }
        }
    }

    /// Given an function def, extract a function type.
    fn get_function_typ(&mut self, function_def: &ast::FunctionDef) -> Result<SlangType, ()> {
        let mut argument_types = vec![];
        for parameter in &function_def.parameters {
            let arg_typ = self.eval_type_expr(&parameter.typ)?;
            argument_types.push(arg_typ);
        }

        let return_type = if let Some(t) = &function_def.return_type {
            Some(Box::new(self.eval_type_expr(t)?))
        } else {
            None
        };

        Ok(SlangType::Function(FunctionType {
            argument_types,
            return_type,
        }))
    }

    fn declare_function(&mut self, function_def: &ast::FunctionDef) -> Result<(), ()> {
        // Deal with parameter types:
        let function_typ = self.get_function_typ(function_def)?;
        log::debug!("Signature of {}: {:?}", function_def.name, function_typ);
        self.define(
            &function_def.name,
            Symbol::Function {
                name: function_def.name.clone(),
                typ: function_typ,
            },
            &function_def.location,
        );
        Ok(())
    }

    fn check_function_def(
        &mut self,
        function: ast::FunctionDef,
    ) -> Result<typed_ast::FunctionDef, ()> {
        log::debug!("Checking function {}", function.name);
        self.enter_scope();
        let mut typed_parameters = vec![];
        for (index, parameter) in function.parameters.into_iter().enumerate() {
            let param_typ = self.eval_type_expr(&parameter.typ)?;
            self.define(
                &parameter.name,
                Symbol::Parameter {
                    index,
                    name: parameter.name.clone(),
                    typ: param_typ.clone(),
                },
                &parameter.location,
            );
            typed_parameters.push(typed_ast::Parameter {
                name: parameter.name,
                typ: param_typ,
            });
        }
        let body = self.check_block(function.body);
        self.leave_scope();

        let return_type = if let Some(t) = &function.return_type {
            Some(self.eval_type_expr(t)?)
        } else {
            None
        };

        let local_variables = std::mem::take(&mut self.local_variables);
        // IDEA: store scope on typed function?
        Ok(typed_ast::FunctionDef {
            name: function.name,
            parameters: typed_parameters,
            return_type,
            locals: local_variables,
            body,
        })
    }

    fn check_block(&mut self, block: Vec<ast::Statement>) -> Vec<typed_ast::Statement> {
        let mut typed_statements = vec![];
        for statement in block {
            match self.check_statement(statement) {
                Ok(typed_statement) => typed_statements.push(typed_statement),
                Err(()) => {}
            }
        }
        typed_statements
    }

    fn new_local_variable(
        &mut self,
        location: &Location,
        name: String,
        mutable: bool,
        typ: SlangType,
    ) -> usize {
        let index = self.local_variables.len();
        self.local_variables.push(typed_ast::LocalVariable {
            name: name.clone(),
            typ: typ.clone(),
        });
        self.define(
            &name,
            Symbol::LocalVariable {
                mutable,
                index,
                name: name.clone(),
                typ,
            },
            location,
        );
        index
    }

    fn check_statement(&mut self, statement: ast::Statement) -> Result<typed_ast::Statement, ()> {
        let (location, kind) = (statement.location, statement.kind);
        match kind {
            ast::StatementType::Let {
                name,
                mutable,
                type_hint,
                value,
            } => {
                let (typ, value) = if let Some(type_hint) = type_hint {
                    let typ = self.eval_type_expr(&type_hint)?;
                    let value = self.coerce(&typ, value)?;
                    (typ, value)
                } else {
                    let value = self.check_expresion(value)?;
                    let typ = value.typ.clone();
                    (typ, value)
                };
                let index = self.new_local_variable(&location, name.clone(), mutable, typ);
                Ok(typed_ast::Statement::Let { name, index, value })
            }
            ast::StatementType::Assignment { target, value } => {
                let target = self.check_expresion(target)?;
                let value = self.check_expresion(value)?;
                self.check_equal_types(&location, &target.typ, &value.typ)?;
                Ok(typed_ast::Statement::Assignment(
                    typed_ast::AssignmentStatement { target, value },
                ))
            }
            ast::StatementType::For { name, it, body } => {
                self.check_for_statement(location, name, it, body)
            }
            ast::StatementType::If {
                condition,
                if_true,
                if_false,
            } => {
                let condition = self.check_condition(condition)?;
                let if_true = self.check_block(if_true);
                let if_false = if_false.map(|e| self.check_block(e));
                Ok(typed_ast::Statement::If(typed_ast::IfStatement {
                    condition,
                    if_true,
                    if_false,
                }))
            }
            ast::StatementType::Expression(expr) => {
                let expr = self.check_expresion(expr)?;
                Ok(typed_ast::Statement::Expression(expr))
            }
            ast::StatementType::Pass => Ok(typed_ast::Statement::Pass),
            ast::StatementType::Continue => Ok(typed_ast::Statement::Continue),
            ast::StatementType::Return { value } => {
                let value = if let Some(value) = value {
                    Some(self.check_expresion(value)?)
                } else {
                    None
                };
                Ok(typed_ast::Statement::Return { value })
            }
            ast::StatementType::Break => Ok(typed_ast::Statement::Break),
            ast::StatementType::Loop { body } => {
                self.enter_loop();
                let body = self.check_block(body);
                self.leave_loop();
                Ok(typed_ast::Statement::Loop { body })
            }
            ast::StatementType::While { condition, body } => {
                let condition = self.check_condition(condition)?;
                self.enter_loop();
                let body = self.check_block(body);
                self.leave_loop();
                Ok(typed_ast::Statement::While(typed_ast::WhileStatement {
                    condition,
                    body,
                }))
            }
            ast::StatementType::Match { .. } => {
                unimplemented!("TODO: match statement");
            }
            ast::StatementType::Case { value, arms } => {
                self.check_case_statement(location, value, arms)
            }
            ast::StatementType::Switch {
                value,
                arms,
                default,
            } => {
                let value = self.coerce(&SlangType::Int, value)?;
                let mut new_arms = vec![];
                for arm in arms {
                    let arm_value = self.coerce(&SlangType::Int, arm.value)?;
                    let arm_body = self.check_block(arm.body);
                    new_arms.push(typed_ast::SwitchArm {
                        body: arm_body,
                        value: arm_value,
                    });
                }
                let default = self.check_block(default);
                Ok(typed_ast::Statement::Switch {
                    value,
                    arms: new_arms,
                    default,
                })
            }
        }
    }

    /// Inspect for-statement.
    ///
    /// For example:
    /// `for a in [1,2,3,4]:`
    fn check_for_statement(
        &mut self,
        location: Location,
        name: String,
        it: ast::Expression,
        body: ast::Block,
    ) -> Result<typed_ast::Statement, ()> {
        let iterable = self.check_expresion(it)?;
        match iterable.typ.clone() {
            SlangType::Array(array_type) => {
                let iterated_typ = *array_type.element_type.clone();
                let loop_var = self.new_local_variable(&location, name, true, iterated_typ);
                self.enter_scope();
                let body = self.check_block(body);
                self.leave_scope();
                Ok(typed_ast::Statement::For(typed_ast::ForStatement {
                    loop_var,
                    iterable,
                    body,
                }))
            }
            other => {
                self.error(location, format!("Cannot loop over {:?}", other));
                Err(())
            }
        }
    }

    /// Check a case-statement.
    ///
    /// This construct should match all variants of the enum.
    fn check_case_statement(
        &mut self,
        location: Location,
        value: ast::Expression,
        raw_arms: Vec<ast::CaseArm>,
    ) -> Result<typed_ast::Statement, ()> {
        let value_location = value.location.clone();
        let typed_value = self.check_expresion(value)?;
        if let SlangType::Enum(enum_type) = typed_value.typ.clone() {
            // Check for:
            // - duplicate arms
            // - and for missing arms
            // - correct amount of constructor arguments
            let mut value_map: HashMap<String, bool> = HashMap::new();
            let mut typed_arms = vec![];
            for arm in raw_arms {
                let choice = self.resolve_obj(&arm.constructor)?;
                self.enter_scope();

                // Ensure we referred to an enum constructor
                match choice {
                    Symbol::EnumOption { choice, enum_type } => {
                        let arg_types: Vec<SlangType> = enum_type.choices[choice].data.clone();
                        let variant_name: String = enum_type.choices[choice].name.clone();

                        // Check for arm compatibility:
                        self.check_equal_types(
                            &arm.location,
                            &typed_value.typ,
                            &SlangType::Enum(enum_type),
                        )?;

                        // Check for duplicate arms:
                        if value_map.contains_key(&variant_name) {
                            self.error(arm.location, format!("Duplicate field: {}", variant_name));
                            continue;
                        } else {
                            value_map.insert(variant_name.to_owned(), true);
                        }

                        if arg_types.len() == arm.arguments.len() {
                            let mut local_ids = vec![];
                            for (arg_typ, arg_name) in arg_types.iter().zip(arm.arguments.iter()) {
                                let local_id = self.new_local_variable(
                                    &arm.location,
                                    arg_name.to_owned(),
                                    false,
                                    arg_typ.clone(),
                                );
                                local_ids.push(local_id);
                            }

                            let body = self.check_block(arm.body);
                            typed_arms.push(typed_ast::CaseArm {
                                choice,
                                local_ids,
                                body,
                            });
                        } else {
                            self.error(
                                arm.location,
                                format!(
                                    "Got {} constructor arguments, but expected {}",
                                    arm.arguments.len(),
                                    arg_types.len()
                                ),
                            );
                            continue;
                        }
                    }
                    other => {
                        // Err!
                        self.error(
                            arm.location,
                            format!("Expected enum constructor, not {:?}", other),
                        );
                        continue;
                    }
                }

                self.leave_scope();
            }

            // Check if all cases are covered:
            for option in enum_type.choices {
                if !value_map.contains_key(&option.name) {
                    self.error(
                        location.clone(),
                        format!("Enum case '{}' not covered", option.name),
                    );
                }
            }

            Ok(typed_ast::Statement::Case(typed_ast::CaseStatement {
                value: typed_value,
                arms: typed_arms,
            }))
        } else {
            self.error(
                value_location,
                format!("Expected enum type, not {:?}", typed_value.typ),
            );
            Err(())
        }
    }

    /// Check if a condition is boolean type.
    fn check_condition(&mut self, condition: ast::Expression) -> Result<typed_ast::Expression, ()> {
        let location = condition.location.clone();
        let typed_condition = self.check_expresion(condition)?;
        self.check_equal_types(&location, &SlangType::Bool, &typed_condition.typ)?;
        Ok(typed_condition)
    }

    fn check_equal_types(
        &mut self,
        location: &Location,
        expected: &SlangType,
        actual: &SlangType,
    ) -> Result<(), ()> {
        if expected == actual {
            Ok(())
        } else {
            self.error(
                location.clone(),
                format!("Expected {:?}, but got {:?}", expected, actual),
            );
            Err(())
        }
    }

    fn check_expresion(
        &mut self,
        expression: ast::Expression,
    ) -> Result<typed_ast::Expression, ()> {
        let (kind, location) = (expression.kind, expression.location);
        match kind {
            ast::ExpressionType::Call { callee, arguments } => {
                self.check_call(location, *callee, arguments)
            }
            ast::ExpressionType::Binop { lhs, op, rhs } => {
                self.check_binary_operator(location, *lhs, op, *rhs)
            }
            ast::ExpressionType::Object(obj_ref) => {
                self.check_obj_ref_expression(location, obj_ref)
            }
            ast::ExpressionType::Literal(value) => match value {
                ast::Literal::Bool(value) => Ok(typed_ast::Expression {
                    typ: SlangType::Bool,
                    kind: typed_ast::ExpressionType::Literal(typed_ast::Literal::Bool(value)),
                }),
                ast::Literal::Integer(value) => Ok(typed_ast::Expression {
                    typ: SlangType::Int,
                    kind: typed_ast::ExpressionType::Literal(typed_ast::Literal::Integer(value)),
                }),
                ast::Literal::String(value) => Ok(typed_ast::Expression {
                    typ: SlangType::String,
                    kind: typed_ast::ExpressionType::Literal(typed_ast::Literal::String(value)),
                }),
                ast::Literal::Float(value) => Ok(typed_ast::Expression {
                    typ: SlangType::Float,
                    kind: typed_ast::ExpressionType::Literal(typed_ast::Literal::Float(value)),
                }),
            },
            ast::ExpressionType::ListLiteral(values) => self.check_list_literal(values),
            ast::ExpressionType::ArrayIndex { base, indici } => {
                self.check_array_index(location, *base, indici)
            }
            ast::ExpressionType::GetAttr { base, attr } => {
                self.check_get_attr(location, *base, attr)
            }
            ast::ExpressionType::StructLiteral { typ, fields } => {
                self.check_struct_literal(location, typ, fields)
            }
        }
    }

    /// Check the occurrence of a referred object as an expression.
    fn check_obj_ref_expression(
        &mut self,
        location: Location,
        obj_ref: ast::ObjRef,
    ) -> Result<typed_ast::Expression, ()> {
        let symbol = self.resolve_obj(&obj_ref)?;
        match symbol {
            Symbol::Module { name, scope: _ } => {
                self.error(location, format!("Unexpected usage of module {}", name));
                Err(())
            }
            Symbol::Parameter { typ, name, index } => {
                let kind = typed_ast::ExpressionType::LoadParameter { name, index };
                Ok(typed_ast::Expression { typ, kind })
            }
            Symbol::LocalVariable {
                mutable: _,
                name,
                index,
                typ,
            } => {
                let kind = typed_ast::ExpressionType::LoadLocal { name, index };
                Ok(typed_ast::Expression { typ, kind })
            }
            Symbol::Field {
                class_typ,
                name,
                index: _,
                typ,
            } => {
                let kind = typed_ast::ExpressionType::GetAttr {
                    base: Box::new(typed_ast::Expression {
                        typ: class_typ,
                        kind: typed_ast::ExpressionType::ImplicitSelf,
                    }),
                    attr: name,
                    // index,
                };
                Ok(typed_ast::Expression { typ, kind })
            }
            Symbol::EnumOption { enum_type, choice } => {
                // Handle special case of enum without data here:
                if enum_type.choices[choice].data.is_empty() {
                    Ok(typed_ast::Expression {
                        typ: SlangType::Enum(enum_type),
                        kind: typed_ast::ExpressionType::EnumLiteral {
                            choice,
                            arguments: vec![],
                        },
                    })
                } else {
                    Ok(typed_ast::Expression {
                        typ: SlangType::TypeConstructor,
                        kind: typed_ast::ExpressionType::TypeConstructor(
                            typed_ast::TypeConstructor::EnumOption { enum_type, choice },
                        ),
                    })
                }
            }
            Symbol::Function { name, typ } => {
                let kind = typed_ast::ExpressionType::LoadFunction(name);
                Ok(typed_ast::Expression { typ, kind })
            }
            Symbol::Typ(typ) => {
                // TBD: is allowing type as expression a good idea?
                let kind = typed_ast::ExpressionType::TypeConstructor(
                    typed_ast::TypeConstructor::Any(typ),
                );
                Ok(typed_ast::Expression {
                    typ: SlangType::TypeConstructor,
                    kind,
                })
            }
        }
    }

    fn check_call(
        &mut self,
        location: Location,
        callee: ast::Expression,
        arguments: Vec<ast::Expression>,
    ) -> Result<typed_ast::Expression, ()> {
        let callee = self.check_expresion(callee)?;
        let (callee_typ, callee_kind) = (callee.typ, callee.kind);
        match callee_typ.clone() {
            SlangType::Function(function_type) => self.check_function_call(
                callee_typ,
                callee_kind,
                location,
                function_type,
                arguments,
            ),
            SlangType::TypeConstructor => match callee_kind {
                typed_ast::ExpressionType::TypeConstructor(type_constructor) => {
                    self.check_type_construction(location, type_constructor, arguments)
                }
                _other => {
                    panic!("Should not get here.");
                }
            },
            other => {
                self.error(location.clone(), format!("Cannot call: {:?} ", other));
                Err(())
            }
        }
    }

    fn check_function_call(
        &mut self,
        callee_typ: SlangType,
        callee_kind: typed_ast::ExpressionType,
        location: Location,
        function_type: FunctionType,
        arguments: Vec<ast::Expression>,
    ) -> Result<typed_ast::Expression, ()> {
        let typed_arguments =
            self.check_call_arguments(&location, &function_type.argument_types, arguments)?;
        let return_type2 = match function_type.return_type {
            None => SlangType::Void,
            Some(t) => *t,
        };

        let kind = match callee_kind {
            typed_ast::ExpressionType::GetAttr { base, attr } => {
                typed_ast::ExpressionType::MethodCall {
                    instance: base,
                    method: attr,
                    arguments: typed_arguments,
                }
            }
            other_kind => typed_ast::ExpressionType::Call {
                callee: Box::new(typed_ast::Expression {
                    kind: other_kind,
                    typ: callee_typ,
                }),
                arguments: typed_arguments,
            },
        };

        Ok(typed_ast::Expression {
            typ: return_type2,
            kind,
        })
    }

    /// Check number of arguments and type of each argument.
    fn check_call_arguments(
        &mut self,
        location: &Location,
        argument_types: &[SlangType],
        arguments: Vec<ast::Expression>,
    ) -> Result<Vec<typed_ast::Expression>, ()> {
        if argument_types.len() == arguments.len() {
            let mut typed_arguments = vec![];
            for (argument, arg_typ) in arguments.into_iter().zip(argument_types.iter()) {
                typed_arguments.push(self.coerce(arg_typ, argument)?);
            }
            Ok(typed_arguments)
        } else {
            self.error(
                location.clone(),
                format!(
                    "Expected {}, but got {} arguments ",
                    argument_types.len(),
                    arguments.len()
                ),
            );
            Err(())
        }
    }

    /// We are calling a type constructor type, evaluate to type and/or
    /// create instance
    fn check_type_construction(
        &mut self,
        location: Location,
        type_constructor: typed_ast::TypeConstructor,
        arguments: Vec<ast::Expression>,
    ) -> Result<typed_ast::Expression, ()> {
        match type_constructor {
            typed_ast::TypeConstructor::Any(typ) => {
                self.check_instantiation(location, typ, arguments)
            }
            typed_ast::TypeConstructor::EnumOption { enum_type, choice } => {
                self.check_enum_instantiation(location, enum_type, choice, arguments)
            }
        }
    }

    fn check_instantiation(
        &mut self,
        location: Location,
        typ: SlangType,
        arguments: Vec<ast::Expression>,
    ) -> Result<typed_ast::Expression, ()> {
        match typ {
            SlangType::Class { .. } => {
                self.check_call_arguments(&location, &[], arguments)?;
                // Class instantiate!
                Ok(typed_ast::Expression {
                    typ,
                    kind: typed_ast::ExpressionType::Instantiate,
                })
            }
            other => {
                self.error(
                    location,
                    format!("Cannot instantiate non-class {:?}", other),
                );
                Err(())
            }
        }
    }

    fn check_enum_instantiation(
        &mut self,
        location: Location,
        enum_type: EnumType,
        enum_choice: usize,
        arguments: Vec<ast::Expression>,
    ) -> Result<typed_ast::Expression, ()> {
        let typed_arguments =
            self.check_call_arguments(&location, &enum_type.choices[enum_choice].data, arguments)?;
        Ok(typed_ast::Expression {
            typ: SlangType::Enum(enum_type),
            kind: typed_ast::ExpressionType::EnumLiteral {
                choice: enum_choice,
                arguments: typed_arguments,
            },
        })
    }

    fn add_import(&mut self, name: String, typ: SlangType) {
        // Hmm, not super efficient:
        for x in &self.typed_imports {
            if x.name == name {
                return;
            }
        }
        self.typed_imports.push(typed_ast::Import { name, typ });
    }

    fn check_binary_operator(
        &mut self,
        location: Location,
        lhs: ast::Expression,
        op: ast::BinaryOperator,
        rhs: ast::Expression,
    ) -> Result<typed_ast::Expression, ()> {
        let (typ, lhs, rhs) = match &op {
            ast::BinaryOperator::Comparison(_compare_op) => {
                let lhs = self.check_expresion(lhs)?;
                let rhs = self.check_expresion(rhs)?;
                self.check_equal_types(&location, &lhs.typ, &rhs.typ)?;
                (SlangType::Bool, lhs, rhs)
            }
            ast::BinaryOperator::Math(_math_op) => {
                let lhs = self.check_expresion(lhs)?;
                let rhs = self.check_expresion(rhs)?;
                self.check_equal_types(&location, &lhs.typ, &rhs.typ)?;
                (lhs.typ.clone(), lhs, rhs)
            }
            ast::BinaryOperator::Logic(_logic_op) => {
                let lhs = self.check_condition(lhs)?;
                let rhs = self.check_condition(rhs)?;
                (SlangType::Bool, lhs, rhs)
            }
            ast::BinaryOperator::Bit(_op) => {
                unimplemented!();
            }
        };
        Ok(typed_ast::Expression {
            typ,
            kind: typed_ast::ExpressionType::Binop {
                lhs: Box::new(lhs),
                op,
                rhs: Box::new(rhs),
            },
        })
    }

    fn check_struct_literal(
        &mut self,
        location: Location,
        typ: ast::Type,
        fields: Vec<ast::StructLiteralField>,
    ) -> Result<typed_ast::Expression, ()> {
        // Create a new instance of a struct typed value!
        // let symbol = self.lookup(&location, &name)?;
        let typ = self.eval_type_expr(&typ)?;
        match typ {
            SlangType::Struct(struct_type) => {
                let typed_values =
                    self.check_fields(location, fields, struct_type.fields.clone())?;
                Ok(typed_ast::Expression {
                    typ: SlangType::Struct(struct_type),
                    kind: typed_ast::ExpressionType::StructLiteral(typed_values),
                })
            }
            other => {
                self.error(location, format!("Must be struct type, not {:?}", other));
                Err(())
            }
        }
    }

    fn check_list_literal(
        &mut self,
        // location: Location,
        values: Vec<ast::Expression>,
    ) -> Result<typed_ast::Expression, ()> {
        assert!(!values.is_empty());
        let mut value_iter = values.into_iter();
        let mut typed_values = vec![];
        let first_value = self.check_expresion(value_iter.next().unwrap())?;
        let element_typ = first_value.typ.clone();
        typed_values.push(first_value);
        for value in value_iter {
            typed_values.push(self.coerce(&element_typ, value)?);
        }
        // let list_generic: SlangType = self.lookup(&location, "list")?.into_type();
        // let list_type = self.instantiate_type(&location, list_generic, vec![element_typ])?;
        let array_type = SlangType::Array(ArrayType {
            element_type: Box::new(element_typ),
            size: typed_values.len(),
        });
        Ok(typed_ast::Expression {
            typ: array_type,
            kind: typed_ast::ExpressionType::ListLiteral(typed_values),
        })
    }

    /// Try to fit an expression onto the given type.
    fn coerce(
        &mut self,
        typ: &SlangType,
        value: ast::Expression,
    ) -> Result<typed_ast::Expression, ()> {
        let location = value.location.clone();
        let value = self.check_expresion(value)?;
        self.check_equal_types(&location, typ, &value.typ)?;
        Ok(value)
    }

    /// Check struct initialization.
    ///
    /// Checks:
    /// - missing fields
    /// - extra fields
    /// - duplicate fields
    /// - field types
    fn check_fields(
        &mut self,
        location: Location,
        field_values: Vec<ast::StructLiteralField>,
        struct_fields: Vec<StructField>,
    ) -> Result<Vec<typed_ast::Expression>, ()> {
        let mut typed_values: Vec<typed_ast::Expression> = vec![];
        let mut type_map: HashMap<String, SlangType> = HashMap::new();

        let mut ok = true;

        for field in &struct_fields {
            type_map.insert(field.name.clone(), field.typ.clone());
        }

        let mut value_map: HashMap<String, typed_ast::Expression> = HashMap::new();
        for field in field_values {
            if type_map.contains_key(&field.name) {
                if value_map.contains_key(&field.name) {
                    self.error(field.location, format!("Duplicate field: {}", field.name));
                    ok = false;
                } else {
                    let wanted_typ = type_map
                        .get(&field.name)
                        .expect("Has this key, we checked above");
                    let value = self.coerce(wanted_typ, field.value)?;
                    value_map.insert(field.name, value);
                }
            } else {
                self.error(field.location, format!("Superfluous field: {}", field.name));
                ok = false;
            }
        }

        for field in &struct_fields {
            if value_map.contains_key(&field.name) {
                let field_value = value_map.remove(&field.name).unwrap();
                typed_values.push(field_value);
            } else {
                self.error(location.clone(), format!("Missing field: {}", field.name));
                ok = false;
            }
        }

        if ok {
            Ok(typed_values)
        } else {
            Err(())
        }
    }

    /// Check array indexing!
    ///
    /// Base must be an array or a list like thingy
    fn check_array_index(
        &mut self,
        location: Location,
        base: ast::Expression,
        indici: Vec<ast::Expression>,
    ) -> Result<typed_ast::Expression, ()> {
        let base = self.check_expresion(base)?;
        match base.typ.clone() {
            SlangType::Array(array_type) => {
                // { element_type, size }
                if indici.len() == 1 {
                    let index = indici.into_iter().next().expect("1 element");
                    let index = self.coerce(&SlangType::Int, index)?;
                    Ok(typed_ast::Expression {
                        typ: *array_type.element_type,
                        kind: typed_ast::ExpressionType::GetIndex {
                            base: Box::new(base),
                            index: Box::new(index),
                        },
                    })
                } else {
                    unimplemented!("Multi-indexing");
                }
            }
            other => {
                self.error(location, format!("Cannot array-index '{:?}' type.", other));
                Err(())
            }
        }
    }

    fn check_get_attr(
        &mut self,
        location: Location,
        base: ast::Expression,
        attr: String,
    ) -> Result<typed_ast::Expression, ()> {
        let base = self.check_expresion(base)?;
        match &base.typ {
            SlangType::Struct(struct_type) => {
                // Access field in struct!
                // Check if struct has this field.
                let field = struct_type.get_field(&attr);
                if let Some(typ) = field {
                    Ok(typed_ast::Expression {
                        typ,
                        kind: typed_ast::ExpressionType::GetAttr {
                            base: Box::new(base),
                            attr,
                        },
                    })
                } else {
                    self.error(location, format!("Struct has no field named: {}", attr));
                    Err(())
                }
            }
            SlangType::Class(class_type) => {
                if let Some(value) = class_type.lookup(&attr) {
                    Ok(typed_ast::Expression {
                        typ: value,
                        kind: typed_ast::ExpressionType::GetAttr {
                            base: Box::new(base),
                            attr,
                        },
                    })
                } else {
                    self.error(
                        location,
                        format!("Class '{}' has no field named: {}", class_type.name(), attr),
                    );
                    Err(())
                }
            }
            other => {
                self.error(
                    location,
                    format!("Cannot get attribute of '{:?}' type.", other),
                );
                Err(())
            }
        }
    }

    fn error(&mut self, location: Location, message: String) {
        self.diagnostics.error(location, message);
    }

    fn define(&mut self, name: &str, symbol: Symbol, location: &Location) {
        let scope = self.scopes.last_mut().unwrap();
        if scope.is_defined(name) {
            self.error(
                location.clone(),
                format!("Symbol {} already defined!", name),
            );
        } else {
            scope.define(name.to_string(), symbol);
        }
    }

    fn lookup(&mut self, location: &Location, name: &str) -> Result<Symbol, ()> {
        let symbol = self.lookup2(name);
        match symbol {
            Some(symbol) => Ok(symbol),
            None => {
                self.error(location.clone(), format!("Name '{}' undefined", name));
                Err(())
            }
        }
    }

    fn lookup2(&self, name: &str) -> Option<Symbol> {
        for scope in self.scopes.iter().rev() {
            if scope.is_defined(name) {
                return scope.get(name).cloned();
            }
        }
        None
    }

    fn enter_scope(&mut self) {
        self.scopes.push(Scope::new());
    }

    fn leave_scope(&mut self) {
        let scope = self.scopes.pop();
        if let Some(scope) = scope {
            if self.dump_scope {
                scope.dump();
            }
        }
    }

    fn enter_loop(&mut self) {
        self.loops.push(());
    }
    fn leave_loop(&mut self) {
        self.loops.pop();
    }
}
