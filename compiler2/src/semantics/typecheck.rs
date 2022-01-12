/* Ideas:

- the type checker is the last pass requiring location info. It will create a typed AST.

Tasks involved here:
- Resolve symbols
- Assign types everywhere

If we pass the typechecker, code is in pretty good shape!

*/

use super::type_system::{ClassField, ClassType, MyType, StructField, StructType};
use super::typed_ast;
use super::{Scope, Symbol};
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
    errors: Vec<CompilationError>,
    loops: Vec<()>,
    typed_imports: Vec<typed_ast::Import>,
    class_defs: Vec<typed_ast::ClassDef>,
    local_variables: Vec<typed_ast::LocalVariable>,
}

impl TypeChecker {
    fn new() -> Self {
        TypeChecker {
            scopes: vec![],
            errors: vec![],
            loops: vec![],
            typed_imports: vec![],
            class_defs: vec![],
            local_variables: vec![],
        }
    }
    fn define_builtins(&mut self) {
        // Built in types:
        let location: Location = Default::default();
        self.define("str", Symbol::Typ(MyType::String), &location);
        self.define("int", Symbol::Typ(MyType::Int), &location);
        self.define("float", Symbol::Typ(MyType::Float), &location);
        self.define("bool", Symbol::Typ(MyType::Bool), &location);
        // self.define("list", Symbol::Typ(MyType::Float), &location);
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

        // let mut funcs = vec![];
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

        if self.errors.is_empty() {
            Ok(typed_ast::Program {
                class_defs,
                imports: typed_imports,
                type_defs,
                functions: typed_function_defs,
            })
        } else {
            Err(CompilationError::multi(self.errors))
        }
    }

    fn check_type_def(&mut self, type_def: ast::TypeDef) -> Result<typed_ast::TypeDef, ()> {
        match type_def {
            ast::TypeDef::Struct(struct_def) => self.check_struct_def(struct_def),
            ast::TypeDef::Class(class_def) => self.check_class_def(class_def),
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
                        Symbol::Typ(MyType::TypeVar(type_var.name.clone())),
                        &type_var.location,
                    );
                    // TBD: we might as well use indici here?
                    type_parameters.push(type_var.name.clone());
                }
                let base = self.check_type_def(*base)?.typ;
                self.leave_scope();
                let typ = MyType::Generic {
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
        let typ = MyType::Struct(struct_type);

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

        let class_typ = ClassType {
            name: class_def.name.clone(),
            fields: class_fields,
            methods: class_methods,
        };

        let class_typ2 = MyType::Class(class_typ.clone());

        self.enter_scope();

        let mut field_defs = vec![];
        for (index, field) in class_def.fields.into_iter().enumerate() {
            let field_typ = self.eval_type_expr(&field.typ)?;
            let value = self.coerce(&field.location, &field_typ, field.value)?;
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
    fn eval_type_expr(&mut self, typ: &ast::Type) -> Result<MyType, ()> {
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
            } => self.instantiate_type(&typ.location, base_type, actual_types),
        }
    }

    fn instantiate_type(
        &mut self,
        location: &Location,
        base_type: &ast::Type,
        actual_types: &[ast::Type],
    ) -> Result<MyType, ()> {
        let base_type = self.eval_type_expr(base_type)?;
        match base_type {
            MyType::Generic {
                base,
                type_parameters,
            } => {
                if type_parameters.len() == actual_types.len() {
                    let mut substitution_map: HashMap<String, MyType> = HashMap::new();
                    for (type_parameter, actual_type) in
                        type_parameters.into_iter().zip(actual_types.iter())
                    {
                        let actual_type = self.eval_type_expr(actual_type)?;
                        substitution_map.insert(type_parameter, actual_type);
                    }
                    let t = self.substitute_types(*base, &substitution_map)?;
                    Ok(t)
                } else {
                    self.error(
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
                self.error(
                    location.clone(),
                    format!("Type {:?} is not generic.", other),
                );
                Err(())
            }
        }
    }

    fn substitute_types(
        &mut self,
        typ: MyType,
        substitutions: &HashMap<String, MyType>,
    ) -> Result<MyType, ()> {
        let t = match typ {
            MyType::Bool => MyType::Bool,
            MyType::Int => MyType::Int,
            MyType::Float => MyType::Float,
            MyType::String => MyType::String,
            MyType::Struct(StructType { name, fields }) => {
                let mut new_fields = vec![];
                for field in fields {
                    new_fields.push(StructField {
                        name: field.name,
                        typ: self.substitute_types(field.typ, substitutions)?,
                    });
                }

                MyType::Struct(StructType {
                    name,
                    fields: new_fields,
                })
            }
            MyType::TypeVar(name) => {
                if let Some(typ) = substitutions.get(&name) {
                    typ.clone()
                } else {
                    panic!("Type parameter {} not found", name);
                }
            }
            MyType::Generic { .. } => {
                self.error(Location::default(), "Unexpected generic".to_owned());
                return Err(());
            }
            other => {
                unimplemented!("TODO: {:?} with {:?}", other, substitutions);
            }
        };
        Ok(t)
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
                                format!("Module has no field: {}", member),
                            );
                            Err(())
                        }
                    }
                    other => {
                        self.error(
                            location.clone(),
                            format!("Cannot scope-access: {:?}", other),
                        );
                        Err(())
                    }
                }
            }
        }
    }

    /// Given an function def, extract a function type.
    fn get_function_typ(&mut self, function_def: &ast::FunctionDef) -> Result<MyType, ()> {
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

        Ok(MyType::Function {
            argument_types,
            return_type,
        })
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

    fn check_statement(&mut self, statement: ast::Statement) -> Result<typed_ast::Statement, ()> {
        let (location, kind) = (statement.location, statement.kind);
        match kind {
            ast::StatementType::Let {
                name,
                mutable,
                value,
            } => {
                let value = self.check_expresion(value)?;
                let typ = value.typ.clone();
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
                    &location,
                );
                Ok(typed_ast::Statement {
                    kind: typed_ast::StatementType::Let { name, index, value },
                })
            }
            ast::StatementType::Assignment { target, value } => {
                let target = self.check_expresion(target)?;
                let value = self.check_expresion(value)?;
                self.check_equal_types(&location, &target.typ, &value.typ)?;
                Ok(typed_ast::Statement {
                    kind: typed_ast::StatementType::Assignment { target, value },
                })
            }
            ast::StatementType::For { name, it, body } => {
                self.check_expresion(it)?;
                self.enter_scope();
                self.check_block(body);
                self.leave_scope();
                unimplemented!("TODO: for loop {}!", name);
            }
            ast::StatementType::If {
                condition,
                if_true,
                if_false,
            } => {
                let condition = self.check_condition(condition)?;
                let if_true = self.check_block(if_true);
                let if_false = if_false.map(|e| self.check_block(e));
                Ok(typed_ast::Statement {
                    kind: typed_ast::StatementType::If {
                        condition,
                        if_true,
                        if_false,
                    },
                })
            }
            ast::StatementType::Expression(e) => {
                let e = self.check_expresion(e)?;
                Ok(typed_ast::Statement {
                    kind: typed_ast::StatementType::Expression(e),
                })
            }
            ast::StatementType::Pass => Ok(typed_ast::Statement {
                kind: typed_ast::StatementType::Pass,
            }),
            ast::StatementType::Continue => Ok(typed_ast::Statement {
                kind: typed_ast::StatementType::Continue,
            }),
            ast::StatementType::Return { value } => {
                let value = if let Some(value) = value {
                    Some(self.check_expresion(value)?)
                } else {
                    None
                };
                Ok(typed_ast::Statement {
                    kind: typed_ast::StatementType::Return { value },
                })
            }
            ast::StatementType::Break => Ok(typed_ast::Statement {
                kind: typed_ast::StatementType::Break,
            }),
            ast::StatementType::Loop { body } => {
                self.enter_loop();
                let body = self.check_block(body);
                self.leave_loop();
                Ok(typed_ast::Statement {
                    kind: typed_ast::StatementType::Loop { body },
                })
            }
            ast::StatementType::While { condition, body } => {
                let condition = self.check_condition(condition)?;
                self.enter_loop();
                let body = self.check_block(body);
                self.leave_loop();
                Ok(typed_ast::Statement {
                    kind: typed_ast::StatementType::While { condition, body },
                })
            }
        }
    }

    /// Check if a condition is boolean type.
    fn check_condition(&mut self, condition: ast::Expression) -> Result<typed_ast::Expression, ()> {
        let location = condition.location.clone();
        let typed_condition = self.check_expresion(condition)?;
        self.check_equal_types(&location, &MyType::Bool, &typed_condition.typ)?;
        Ok(typed_condition)
    }

    fn check_equal_types(
        &mut self,
        location: &Location,
        expected: &MyType,
        actual: &MyType,
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
                self.check_function_call(location, *callee, arguments)
            }
            ast::ExpressionType::Binop { lhs, op, rhs } => {
                let (typ, lhs, rhs) = match &op {
                    ast::BinaryOperator::Comparison(_compare_op) => {
                        let lhs = self.check_expresion(*lhs)?;
                        let rhs = self.check_expresion(*rhs)?;
                        self.check_equal_types(&location, &lhs.typ, &rhs.typ)?;
                        (MyType::Bool, lhs, rhs)
                    }
                    ast::BinaryOperator::Math(_math_op) => {
                        let lhs = self.check_expresion(*lhs)?;
                        let rhs = self.check_expresion(*rhs)?;
                        self.check_equal_types(&location, &lhs.typ, &rhs.typ)?;
                        (lhs.typ.clone(), lhs, rhs)
                    }
                    ast::BinaryOperator::Logic(_logic_op) => {
                        let lhs = self.check_condition(*lhs)?;
                        let rhs = self.check_condition(*rhs)?;
                        (MyType::Bool, lhs, rhs)
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
            ast::ExpressionType::Object(obj_ref) => {
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
                        index,
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
                    Symbol::Function { name, typ } => {
                        let kind = typed_ast::ExpressionType::LoadFunction(name);
                        Ok(typed_ast::Expression { typ, kind })
                    }
                    Symbol::Typ(typ) => {
                        // TBD: is allowing type as expression a good idea?
                        let kind = typed_ast::ExpressionType::Typ(typ);
                        Ok(typed_ast::Expression {
                            typ: MyType::Typ,
                            kind,
                        })
                        // self.error(
                        //     location.clone(),
                        //     format!("Unexpected usage of type {:?} ", typ),
                        // );
                        // Err(())
                    }
                }
            }
            ast::ExpressionType::Bool(val) => Ok(typed_ast::Expression {
                typ: MyType::Bool,
                kind: typed_ast::ExpressionType::Bool(val),
            }),
            ast::ExpressionType::Integer(val) => Ok(typed_ast::Expression {
                typ: MyType::Int,
                kind: typed_ast::ExpressionType::Integer(val),
            }),
            ast::ExpressionType::String(text) => Ok(typed_ast::Expression {
                typ: MyType::String,
                kind: typed_ast::ExpressionType::String(text),
            }),
            ast::ExpressionType::Float(value) => Ok(typed_ast::Expression {
                typ: MyType::Float,
                kind: typed_ast::ExpressionType::Float(value),
            }),
            ast::ExpressionType::GetAttr { base, attr } => {
                self.check_get_attr(location, *base, attr)
            }
            ast::ExpressionType::StructLiteral { typ, fields } => {
                self.check_struct_literal(location, typ, fields)
            }
        }
    }

    fn check_function_call(
        &mut self,
        location: Location,
        callee: ast::Expression,
        arguments: Vec<ast::Expression>,
    ) -> Result<typed_ast::Expression, ()> {
        let callee = self.check_expresion(callee)?;
        let (callee_typ, callee_kind) = (callee.typ, callee.kind);
        match callee_typ.clone() {
            MyType::Function {
                argument_types,
                return_type,
            } => {
                let typed_arguments =
                    self.check_call_arguments(&location, argument_types, arguments)?;
                let return_type2 = match return_type {
                    None => MyType::Void,
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
            MyType::Typ => match callee_kind {
                typed_ast::ExpressionType::Typ(typ) => self.check_instantiation(location, typ),
                _other => {
                    panic!("Should not get here.");
                }
            },
            other => {
                self.error(
                    location.clone(),
                    format!("Cannot call non-function type {:?} ", other),
                );
                Err(())
            }
        }
    }

    fn check_call_arguments(
        &mut self,
        location: &Location,
        argument_types: Vec<MyType>,
        arguments: Vec<ast::Expression>,
    ) -> Result<Vec<typed_ast::Expression>, ()> {
        if argument_types.len() == arguments.len() {
            let mut typed_arguments = vec![];
            for (argument, arg_typ) in arguments.into_iter().zip(argument_types.iter()) {
                let location = argument.location.clone();
                let typed_argument = self.coerce(&location, arg_typ, argument)?;
                typed_arguments.push(typed_argument);
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

    fn check_instantiation(
        &mut self,
        location: Location,
        typ: MyType,
    ) -> Result<typed_ast::Expression, ()> {
        match typ {
            MyType::Class { .. } => {
                // unimplemented!("TODO: ");
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

    fn add_import(&mut self, name: String, typ: MyType) {
        // Hmm, not super efficient:
        for x in &self.typed_imports {
            if x.name == name {
                return;
            }
        }
        self.typed_imports.push(typed_ast::Import { name, typ });
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
            MyType::Struct(struct_type) => {
                let typed_values =
                    self.check_fields(location, fields, struct_type.fields.clone())?;
                Ok(typed_ast::Expression {
                    typ: MyType::Struct(struct_type),
                    kind: typed_ast::ExpressionType::StructLiteral(typed_values),
                })
            }
            other => {
                self.error(location, format!("Must be struct type, not {:?}", other));
                Err(())
            }
        }
    }

    /// Try to fit an expression onto the given type.
    fn coerce(
        &mut self,
        location: &Location,
        typ: &MyType,
        value: ast::Expression,
    ) -> Result<typed_ast::Expression, ()> {
        let value = self.check_expresion(value)?;
        self.check_equal_types(location, typ, &value.typ)?;
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
        let mut type_map: HashMap<String, MyType> = HashMap::new();

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
                    let value = self.coerce(&field.location, wanted_typ, field.value)?;
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

    fn check_get_attr(
        &mut self,
        location: Location,
        base: ast::Expression,
        attr: String,
    ) -> Result<typed_ast::Expression, ()> {
        let base = self.check_expresion(base)?;
        match &base.typ {
            MyType::Struct(struct_type) => {
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
            MyType::Class(class_type) => {
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
                        format!("Class '{}' has no field named: {}", class_type.name, attr),
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
        log::info!("Error: {}", message);
        self.errors.push(CompilationError::new(location, message))
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
            scope.dump();
        }
    }

    fn enter_loop(&mut self) {
        self.loops.push(());
    }
    fn leave_loop(&mut self) {
        self.loops.pop();
    }
}
