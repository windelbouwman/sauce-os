/* Ideas:

- the type checker is the last pass requiring location info. It will create a typed AST.

Tasks involved here:
- Resolve symbols
- Assign types everywhere

If we pass the typechecker, code is in pretty good shape!

*/

use super::type_system::{MyType, StructType};
use super::typed_ast;
use super::CompilationError;
use crate::parsing::{ast, Location};
use std::collections::HashMap;

#[derive(Debug, Clone)]
enum Symbol {
    Typ(MyType),
    Function {
        typ: MyType,
    },
    Module {
        // typ: MyType,
        exposed: HashMap<String, MyType>,
    },
    Parameter {
        typ: MyType,
        index: usize,
    },
    LocalVariable {
        mutable: bool,
        index: usize,
        typ: MyType,
    },
}

impl Symbol {
    // fn get_type(&self) -> &MyType {
    //     match self {
    //         Symbol::Typ(_t) => &MyType::Typ,
    //         Symbol::Function { typ } => &typ,
    //         Symbol::Module { typ } => typ,
    //         Symbol::Parameter { typ } => typ,
    //         // Symbol::Variable { typ } => typ,
    //     }
    // }
}

struct Scope {
    symbols: HashMap<String, Symbol>,
}

impl Scope {
    fn new() -> Self {
        Scope {
            symbols: HashMap::new(),
        }
    }
}

pub fn type_check(prog: ast::Program) -> Result<typed_ast::Program, CompilationError> {
    let checker = TypeChecker::new();
    checker.check_prog(prog)
}

struct TypeChecker {
    scopes: Vec<Scope>,
    errors: Vec<CompilationError>,
    loops: Vec<()>,
    typed_imports: Vec<typed_ast::Import>,
    local_variables: Vec<typed_ast::LocalVariable>,
}

impl TypeChecker {
    fn new() -> Self {
        TypeChecker {
            scopes: vec![],
            errors: vec![],
            loops: vec![],
            typed_imports: vec![],
            local_variables: vec![],
        }
    }
    fn define_builtins(&mut self) {
        // Built in types:
        let location: Location = Default::default();
        self.define("str", Symbol::Typ(MyType::String), &location);
        self.define("int", Symbol::Typ(MyType::Int), &location);
        self.define("float", Symbol::Typ(MyType::Float), &location);
        let mut std_exposed: HashMap<String, MyType> = HashMap::new();
        std_exposed.insert(
            "print".to_owned(),
            MyType::Function {
                argument_types: vec![MyType::String],
                return_type: None,
            },
        );

        self.define(
            "std",
            Symbol::Module {
                exposed: std_exposed,
            },
            &location,
        );
    }

    fn check_prog(mut self, prog: ast::Program) -> Result<typed_ast::Program, CompilationError> {
        self.enter_scope();
        self.define_builtins();
        self.enter_scope();
        for _import in &prog.imports {
            // TODO: load module?
            // self.define(&import.name, Symbol::Module, &import.location);
        }

        let mut type_defs = vec![];
        for typedef in prog.typedefs {
            match self.check_struct_def(typedef) {
                Ok(s) => type_defs.push(s),
                Err(()) => {}
            }
        }

        // let mut funcs = vec![];
        for function_def in &prog.functions {
            // Deal with parameter types:
            let mut argument_types = vec![];
            for parameter in &function_def.parameters {
                let arg_typ = self.get_type(&parameter.typ).unwrap_or(MyType::Void);
                argument_types.push(arg_typ);
            }

            let return_type = function_def
                .return_type
                .as_ref()
                .map(|t| Box::new(self.get_type(t).unwrap_or(MyType::Void)));

            // function_def.
            let function_typ = MyType::Function {
                argument_types,
                return_type,
            };
            log::debug!("Signature of {}: {:?}", function_def.name, function_typ);
            self.define(
                &function_def.name,
                Symbol::Function { typ: function_typ },
                &function_def.location,
            );
            // funcs.push(())
        }

        let mut typed_function_defs = vec![];
        for function_def in prog.functions {
            match self.check_function_def(function_def) {
                Ok(typed_function_def) => typed_function_defs.push(typed_function_def),
                Err(()) => {}
            }
        }

        self.leave_scope(); // module scope
        self.leave_scope(); // universe scope

        let typed_imports = std::mem::take(&mut self.typed_imports);

        if self.errors.is_empty() {
            Ok(typed_ast::Program {
                imports: typed_imports,
                type_defs,
                functions: typed_function_defs,
            })
        } else {
            Err(CompilationError::multi(self.errors))
        }
    }

    fn check_struct_def(&mut self, struct_def: ast::StructDef) -> Result<StructType, ()> {
        let mut fields = vec![];
        for field in struct_def.fields {
            let name = field.name;
            let typ = self.get_type(&field.typ)?;
            fields.push((name, typ));
        }
        let struct_type = StructType {
            name: Some(struct_def.name.clone()),
            fields,
        };
        let typ = MyType::Struct(struct_type.clone());
        // Check struct type:
        self.define(&struct_def.name, Symbol::Typ(typ), &struct_def.location);
        Ok(struct_type)
    }

    /// Resolve expression into type!
    fn get_type(&mut self, expression: &ast::Expression) -> Result<MyType, ()> {
        // let kind_expr = self.check_expresion(expression.clone())?;

        self.eval_type_expr(expression)
    }

    /// Wonky, this is resolved during compilation!
    fn eval_type_expr(&mut self, expression: &ast::Expression) -> Result<MyType, ()> {
        match &expression.kind {
            ast::ExpressionType::Identifier(name) => {
                let symbol = self.lookup(&expression.location, name)?;
                match symbol {
                    Symbol::Typ(t) => Ok(t),
                    x => {
                        self.error(
                            expression.location.clone(),
                            format!("Symbol is no type: {:?}", x),
                        );
                        Err(())
                    }
                }
            }
            unknown_expression => {
                self.error(
                    expression.location.clone(),
                    format!("Unexpected type expression: {:?}", unknown_expression),
                );
                Err(())
            }
        }
    }

    fn check_function_def(
        &mut self,
        function: ast::FunctionDef,
    ) -> Result<typed_ast::FunctionDef, ()> {
        log::debug!("Checking function {}", function.name);
        self.enter_scope();
        let mut typed_parameters = vec![];
        for (index, parameter) in function.parameters.into_iter().enumerate() {
            let param_typ = self.get_type(&parameter.typ)?;
            self.define(
                &parameter.name,
                Symbol::Parameter {
                    index,
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
            Some(self.get_type(t)?)
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
                let callee = self.check_expresion(*callee)?;
                if let MyType::Function {
                    argument_types,
                    return_type,
                } = callee.typ.clone()
                {
                    if argument_types.len() == arguments.len() {
                        let mut typed_arguments = vec![];
                        for (argument, arg_typ) in arguments.into_iter().zip(argument_types.iter())
                        {
                            let location = argument.location.clone();
                            let typed_argument = self.check_expresion(argument)?;
                            self.check_equal_types(&location, arg_typ, &typed_argument.typ)?;
                            typed_arguments.push(typed_argument);
                        }
                        let return_type2 = match return_type {
                            None => MyType::Void,
                            Some(t) => *t,
                        };
                        Ok(typed_ast::Expression {
                            typ: return_type2,
                            kind: typed_ast::ExpressionType::Call {
                                callee: Box::new(callee),
                                arguments: typed_arguments,
                            },
                        })
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
                } else {
                    self.error(
                        location.clone(),
                        format!("Cannot call non-function type {:?} ", callee.typ),
                    );
                    Err(())
                }
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
            ast::ExpressionType::Identifier(name) => {
                let symbol = self.lookup(&location, &name)?;
                // let typ = symbol.get_type().clone();
                match symbol {
                    Symbol::Module { exposed: _ } => {
                        let kind = typed_ast::ExpressionType::LoadModule { modname: name };
                        let typ = MyType::Module;
                        Ok(typed_ast::Expression { typ, kind })
                    }
                    Symbol::Parameter { typ, index } => {
                        let kind = typed_ast::ExpressionType::LoadParameter { name, index };
                        Ok(typed_ast::Expression { typ, kind })
                    }
                    Symbol::LocalVariable {
                        mutable: _,
                        index,
                        typ,
                    } => {
                        let kind = typed_ast::ExpressionType::LoadLocal { name, index };
                        Ok(typed_ast::Expression { typ, kind })
                    }
                    Symbol::Function { typ } => {
                        let kind = typed_ast::ExpressionType::LoadFunction(name);
                        Ok(typed_ast::Expression { typ, kind })
                    }
                    Symbol::Typ(_) => {
                        unimplemented!("TODO? what now?")
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
            ast::ExpressionType::StructLiteral { name, fields } => {
                // Create a new instance of a struct typed value!
                let symbol = self.lookup(&location, &name)?;
                match symbol {
                    Symbol::Typ(MyType::Struct(struct_type)) => {
                        let mut typed_values: Vec<typed_ast::Expression> = vec![];
                        let mut value_map: HashMap<String, typed_ast::Expression> = HashMap::new();
                        for field in fields {
                            let value = self.check_expresion(field.value)?;
                            if value_map.contains_key(&field.name) {
                                self.error(
                                    field.location,
                                    format!("Duplicate field: {}", field.name),
                                );
                            } else {
                                value_map.insert(field.name, value);
                            }
                        }

                        for (field_name, field_type) in &struct_type.fields {
                            if value_map.contains_key(field_name) {
                                let field_value = value_map.remove(field_name).unwrap();
                                self.check_equal_types(&location, field_type, &field_value.typ)?;
                                typed_values.push(field_value);
                            } else {
                                self.error(
                                    location.clone(),
                                    format!("Missing field: {}", field_name),
                                );
                            }
                        }

                        // unimplemented!("TODO!");
                        Ok(typed_ast::Expression {
                            typ: MyType::Struct(struct_type),
                            kind: typed_ast::ExpressionType::StructLiteral(typed_values),
                        })
                    }
                    other => {
                        self.error(
                            location.clone(),
                            format!("Must be struct type, not {:?}", other),
                        );
                        Err(())
                    }
                }
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

    fn check_get_attr(
        &mut self,
        location: Location,
        base: ast::Expression,
        attr: String,
    ) -> Result<typed_ast::Expression, ()> {
        let base = self.check_expresion(base)?;
        match &base.typ {
            MyType::Module => {
                if let typed_ast::ExpressionType::LoadModule { modname } = &base.kind {
                    if let Symbol::Module { exposed } =
                        self.lookup2(modname).expect("Name is present")
                    {
                        // name
                        if exposed.contains_key(&attr) {
                            let typ = exposed.get(&attr).unwrap().clone();
                            // This might be too much desugaring at this point
                            // Maybe introduce a new phase?
                            let full_name = format!("{}_{}", modname, attr);
                            self.add_import(full_name.clone(), typ.clone());

                            Ok(typed_ast::Expression {
                                typ,
                                kind: typed_ast::ExpressionType::LoadFunction(full_name),
                            })
                        } else {
                            self.error(location, format!("Module has no field: {}", attr));
                            Err(())
                        }
                    } else {
                        panic!("Oh my");
                    }
                } else {
                    panic!("Oh my")
                }
            }
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
            x => {
                self.error(location, format!("Cannot get attribute of '{:?}' type.", x));
                Err(())
                // unimplemented!("Ugh");
            }
        }
    }

    fn error(&mut self, location: Location, message: String) {
        self.errors.push(CompilationError::new(location, message))
    }

    fn define(&mut self, name: &str, symbol: Symbol, location: &Location) {
        let scope = self.scopes.last_mut().unwrap();
        if scope.symbols.contains_key(name) {
            self.error(
                location.clone(),
                format!("Symbol {} already defined!", name),
            );
        } else {
            scope.symbols.insert(name.to_string(), symbol);
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
            if scope.symbols.contains_key(name) {
                return scope.symbols.get(name).cloned();
            }
        }
        None
    }

    fn enter_scope(&mut self) {
        self.scopes.push(Scope::new());
    }

    fn leave_scope(&mut self) {
        let s = self.scopes.pop();
        if let Some(s) = s {
            log::debug!("Symbol table:");
            for sym in s.symbols.keys() {
                log::debug!(" - {}", sym);
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
