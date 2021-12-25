/* Ideas:

- the type checker is the last pass requiring location info. It will create a typed AST.

Tasks involved here:
- Resolve symbols
- Assign types everywhere

If we pass the typechecker, code is in pretty good shape!

*/

use super::type_system::MyType;
use super::typed_ast;
use super::CompilationError;
use crate::parsing::{ast, Location};
use std::collections::HashMap;

#[derive(Debug, Clone)]
enum Symbol {
    Typ(MyType),
    Function { typ: MyType },
    Module { typ: MyType },
    Parameter { typ: MyType },
    LocalVariable { mutable: bool, typ: MyType },
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
    local_variables: Vec<typed_ast::LocalVariable>,
}

impl TypeChecker {
    fn new() -> Self {
        TypeChecker {
            scopes: vec![],
            errors: vec![],
            loops: vec![],
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
                typ: MyType::Module {
                    exposed: std_exposed,
                },
            },
            &location,
        );
    }

    fn check_prog(mut self, prog: ast::Program) -> Result<typed_ast::Program, CompilationError> {
        self.enter_scope();
        self.define_builtins();
        self.enter_scope();
        let typed_imports = vec![];
        for _import in &prog.imports {
            // TODO: load module?
            // self.define(&import.name, Symbol::Module, &import.location);
        }

        for typedef in prog.typedefs {
            self.check_struct_def(typedef).ok();
        }

        // let mut funcs = vec![];
        for function_def in &prog.functions {
            let mut argument_types2 = vec![];
            for parameter in &function_def.parameters {
                let arg_typ = match self.get_type(&parameter.typ) {
                    Ok(t) => t,
                    Err(()) => MyType::Void,
                };
                argument_types2.push(arg_typ);
            }
            // function_def.
            let function_typ = MyType::Function {
                argument_types: argument_types2,
                return_type: None, // TODO!
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

        if self.errors.is_empty() {
            Ok(typed_ast::Program {
                imports: typed_imports,
                functions: typed_function_defs,
            })
        } else {
            Err(CompilationError::multi(self.errors))
        }
    }

    fn check_struct_def(&mut self, struct_def: ast::StructDef) -> Result<(), ()> {
        let mut fields = vec![];
        for field in struct_def.fields {
            let name = field.name;
            let typ = self.get_type(&field.typ)?;
            fields.push((name, typ));
        }
        let typ = MyType::new_struct(fields);
        // Check struct type:
        self.define(&struct_def.name, Symbol::Typ(typ), &struct_def.location);
        Ok(())
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
        for parameter in function.parameters {
            let param_typ = self.get_type(&parameter.typ)?;
            self.define(
                &parameter.name,
                Symbol::Parameter {
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

        let local_variables = std::mem::take(&mut self.local_variables);
        // IDEA: store scope on typed function?
        Ok(typed_ast::FunctionDef {
            name: function.name,
            parameters: typed_parameters,
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
                self.define(&name, Symbol::LocalVariable { mutable, typ }, &location);
                Ok(typed_ast::Statement {
                    kind: typed_ast::StatementType::Let { name, value },
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
            ast::StatementType::Continue => Ok(typed_ast::Statement {
                kind: typed_ast::StatementType::Continue,
            }),
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
                    Symbol::Module { typ } => {
                        let kind = typed_ast::ExpressionType::LoadGlobal(name);
                        Ok(typed_ast::Expression { typ, kind })
                    }
                    Symbol::Parameter { typ } => {
                        let kind = typed_ast::ExpressionType::LoadParameter(name);
                        Ok(typed_ast::Expression { typ, kind })
                    }
                    Symbol::LocalVariable { mutable: _, typ } => {
                        let kind = typed_ast::ExpressionType::LoadLocal(name);
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
                        let typed_values: Vec<typed_ast::Expression> = vec![];
                        for field in fields {
                            let _value = self.check_expresion(field.value)?;
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

    fn check_get_attr(
        &mut self,
        location: Location,
        base: ast::Expression,
        attr: String,
    ) -> Result<typed_ast::Expression, ()> {
        let base = self.check_expresion(base)?;
        match &base.typ {
            MyType::Module { exposed } => {
                if exposed.contains_key(&attr) {
                    let modname: String =
                        if let typed_ast::ExpressionType::LoadGlobal(name) = base.kind {
                            name
                        } else {
                            panic!("Oh my")
                        };
                    let typ = exposed.get(&attr).unwrap().clone();

                    // This might be too much desugaring at this point
                    // Maybe introduce a new phase?
                    let full_name = format!("{}_{}", modname, attr);
                    Ok(typed_ast::Expression {
                        typ,
                        kind: typed_ast::ExpressionType::LoadFunction(full_name),
                    })
                } else {
                    self.error(location, format!("Module has no field: {}", attr));
                    Err(())
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
                self.error(location, format!("Don't know ... {:?}", x));
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
