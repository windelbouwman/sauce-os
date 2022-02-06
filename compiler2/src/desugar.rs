//! Apply simplifications on AST
//!
//! Main tasks here:
//!
//! - translate classes into structs and functions
//! - translate enum's into structs/unions
//! - pattern matching compilation into switch statements

use super::semantics::type_system::{ClassType, MyType, StructField, StructType};
use super::semantics::typed_ast;
use super::simple_ast;
use crate::parsing::ast;
use std::sync::Arc;

/// Transform a typed_ast program into a simple_ast program
pub fn desugar(program: typed_ast::Program) -> simple_ast::Program {
    log::info!("Desugaring");
    Desugarino::new().do_program(program)
}

struct Desugarino {
    functions: Vec<simple_ast::FunctionDef>,
    local_variables: Vec<typed_ast::LocalVariable>,
}

impl Desugarino {
    fn new() -> Self {
        Desugarino {
            functions: vec![],
            local_variables: vec![],
        }
    }

    fn do_program(&mut self, program: typed_ast::Program) -> simple_ast::Program {
        let imports = program.imports;

        for class_def in program.class_defs {
            self.do_class_def(class_def);
        }

        for function in program.functions {
            self.do_function(function);
        }

        let functions = std::mem::take(&mut self.functions);
        simple_ast::Program { imports, functions }
    }

    /// Transform class definition into struct type with
    /// constructor, and associated functions
    fn do_class_def(&mut self, class_def: typed_ast::ClassDef) {
        // Be smart about it, and create default constructor function!
        let class_type = class_def.typ.inner;
        let ctor_name = class_type.ctor_func_name();

        let struct_type = Self::struct_for_class(class_type.clone());

        // Initialize functions:
        let initial_values = class_def
            .field_defs
            .into_iter()
            .map(|f| self.lower_expression(f.value))
            .collect();
        let lit_val = simple_ast::Expression::StructLiteral {
            typ: struct_type.clone(),
            values: initial_values,
        };

        let constructor_function = simple_ast::FunctionDef {
            body: vec![simple_ast::Statement::Return {
                value: Some(lit_val),
            }],
            name: ctor_name,
            parameters: vec![],
            locals: vec![],
            return_type: Some(struct_type),
        };

        self.functions.push(constructor_function);
        // Generate member functions:
        for function in class_def.function_defs {
            self.lower_method(class_def.name.clone(), class_type.clone(), function);
        }
    }

    fn type_fold(typ: MyType) -> MyType {
        match typ {
            MyType::Bool => MyType::Bool,
            MyType::Int => MyType::Int,
            MyType::Float => MyType::Float,
            MyType::String => MyType::String,
            MyType::Void => MyType::Void,
            MyType::Struct(struct_type) => MyType::Struct(struct_type),
            MyType::Array(array_type) => MyType::Array(array_type),
            MyType::Class(class_type) => Self::struct_for_class(class_type.inner),
            MyType::Enum(enum_type) => enum_type.get_struct_type(),
            other => {
                panic!("Cannot fold: {:?}", other);
            }
        }
    }

    /// Create a structured type for a class
    fn struct_for_class(class_type: Arc<ClassType>) -> MyType {
        let fields: Vec<StructField> = class_type
            .fields
            .iter()
            .map(|f| StructField {
                name: f.name.clone(),
                typ: f.typ.clone(),
            })
            .collect();
        MyType::Struct(StructType {
            name: Some(class_type.name.clone()),
            fields,
        })
    }

    fn new_local_variable(&mut self, name: String, typ: MyType) -> usize {
        let index = self.local_variables.len();
        self.local_variables.push(typed_ast::LocalVariable {
            name: name.clone(),
            typ: typ.clone(),
        });
        index
    }

    fn lower_method(
        &mut self,
        class_name: String,
        _class_typ: Arc<ClassType>,
        method: typed_ast::FunctionDef,
    ) {
        log::debug!("Desugaring class-method: {}", method.name);
        let parameters = method.parameters;
        // TODO: do name mangling?
        let name = format!("{}_{}", class_name, method.name);
        self.local_variables = method
            .locals
            .into_iter()
            .map(|loc| typed_ast::LocalVariable {
                name: loc.name,
                typ: Self::type_fold(loc.typ),
            })
            .collect();
        let return_type = method.return_type;

        let body = self.lower_block(method.body);

        let func = simple_ast::FunctionDef {
            body,
            name,
            parameters,
            locals: std::mem::take(&mut self.local_variables),
            return_type,
        };

        self.functions.push(func);
    }

    fn do_function(&mut self, function: typed_ast::FunctionDef) {
        log::debug!("Desugaring function: {}", function.name);
        let parameters = function.parameters;
        let name = function.name;
        self.local_variables = function
            .locals
            .into_iter()
            .map(|loc| typed_ast::LocalVariable {
                name: loc.name,
                typ: Self::type_fold(loc.typ),
            })
            .collect();
        let body = self.lower_block(function.body);
        let return_type = function.return_type;
        let func = simple_ast::FunctionDef {
            body,
            name,
            parameters,
            locals: std::mem::take(&mut self.local_variables),
            return_type,
        };

        self.functions.push(func);
    }

    fn lower_block(&mut self, block: typed_ast::Block) -> simple_ast::Block {
        let mut statements = vec![];
        for statement in block {
            statements.push(self.lower_statement(statement));
        }

        statements
    }

    fn lower_statement(&mut self, statement: typed_ast::Statement) -> simple_ast::Statement {
        match statement {
            typed_ast::Statement::Assignment(assignment) => self.lower_assignment(assignment),
            typed_ast::Statement::Let {
                name: _,
                index,
                value,
            } => {
                let value = self.lower_expression(value);
                simple_ast::Statement::StoreLocal { index, value }
            }
            typed_ast::Statement::Match { value: _, arms: _ } => {
                unimplemented!("match lowering!");
            }
            typed_ast::Statement::Case(case_statement) => self.lower_case_statement(case_statement),
            typed_ast::Statement::Switch {
                value,
                arms,
                default,
            } => {
                let value = self.lower_expression(value);
                let mut arms2 = vec![];
                for arm in arms {
                    let body = self.lower_block(arm.body);
                    arms2.push(simple_ast::SwitchArm { body });
                }
                let default = self.lower_block(default);
                simple_ast::Statement::Switch(simple_ast::SwitchStatement {
                    value,
                    arms: arms2,
                    default,
                })
                // unimplemented!();
            }
            typed_ast::Statement::Return { value } => {
                let value = value.map(|v| self.lower_expression(v));
                simple_ast::Statement::Return { value }
            }
            typed_ast::Statement::Pass => simple_ast::Statement::Pass,
            typed_ast::Statement::Break => simple_ast::Statement::Break,
            typed_ast::Statement::Continue => simple_ast::Statement::Continue,
            typed_ast::Statement::Expression(expression) => {
                let expression = self.lower_expression(expression);
                simple_ast::Statement::Expression(expression)
            }
            typed_ast::Statement::If(if_statement) => {
                let condition = self.lower_expression(if_statement.condition);
                let if_true = self.lower_block(if_statement.if_true);
                let if_false = if_statement.if_false.map(|b| self.lower_block(b));
                simple_ast::Statement::If(simple_ast::IfStatement {
                    condition,
                    if_true,
                    if_false,
                })
            }
            typed_ast::Statement::While(while_statement) => {
                let condition = self.lower_expression(while_statement.condition);
                let body = self.lower_block(while_statement.body);
                simple_ast::Statement::While(simple_ast::WhileStatement { condition, body })
            }
            typed_ast::Statement::Loop { body } => {
                let body = self.lower_block(body);
                simple_ast::Statement::Loop { body }
            }
            typed_ast::Statement::For(for_statement) => self.lower_for_statement(for_statement),
        }
    }

    /// Transform for-loop into a while loop.
    fn lower_for_statement(
        &mut self,
        for_statement: typed_ast::ForStatement,
    ) -> simple_ast::Statement {
        // Check if we loop over an array:
        match for_statement.iterable.typ.clone() {
            MyType::Array(array_type) => {
                let mut for_body = self.lower_block(for_statement.body);
                let index_local_id: usize =
                    self.new_local_variable("index".to_owned(), MyType::Int);
                let iter_local_id: usize =
                    self.new_local_variable("iter".to_owned(), MyType::Array(array_type.clone()));

                // index = 0
                let zero_loop_index = simple_ast::Statement::StoreLocal {
                    index: index_local_id,
                    value: simple_ast::Expression::Literal(typed_ast::Literal::Integer(0)),
                };

                // iter_var = iterator
                let set_iter_var = simple_ast::Statement::StoreLocal {
                    index: iter_local_id,
                    value: self.lower_expression(for_statement.iterable),
                };

                // Get current element: loop_var = array[index]
                let get_loop_var = simple_ast::Statement::StoreLocal {
                    index: for_statement.loop_var,
                    value: simple_ast::Expression::GetIndex {
                        base: Box::new(simple_ast::Expression::LoadLocal {
                            index: iter_local_id,
                            typ: MyType::Array(array_type.clone()),
                        }),
                        index: Box::new(simple_ast::Expression::LoadLocal {
                            index: index_local_id,
                            typ: MyType::Int,
                        }),
                    },
                };
                for_body.insert(0, get_loop_var);

                // Increment index variable:
                let inc_loop_index = simple_ast::Statement::StoreLocal {
                    index: index_local_id,
                    value: simple_ast::Expression::Binop {
                        lhs: Box::new(simple_ast::Expression::LoadLocal {
                            typ: MyType::Int,
                            index: index_local_id,
                        }),
                        typ: MyType::Int,
                        op_typ: MyType::Int,
                        op: ast::BinaryOperator::Math(ast::MathOperator::Add),
                        rhs: Box::new(simple_ast::Expression::Literal(
                            typed_ast::Literal::Integer(1),
                        )),
                    },
                };
                for_body.push(inc_loop_index);

                // While condition:
                let loop_condition = simple_ast::Expression::Binop {
                    lhs: Box::new(simple_ast::Expression::LoadLocal {
                        typ: MyType::Int,
                        index: index_local_id,
                    }),
                    typ: MyType::Int,
                    op_typ: MyType::Int,
                    op: ast::BinaryOperator::Comparison(ast::ComparisonOperator::Lt),
                    rhs: Box::new(simple_ast::Expression::Literal(
                        typed_ast::Literal::Integer(array_type.size as i64),
                    )),
                };

                // Translate for-loop into while loop:
                let while_statement = simple_ast::Statement::While(simple_ast::WhileStatement {
                    condition: loop_condition,
                    body: for_body,
                });

                let new_block = vec![zero_loop_index, set_iter_var, while_statement];

                simple_ast::Statement::Compound(new_block)
            }
            other => {
                unimplemented!("Cannot iterate {:?}", other);
            }
        }
    }

    fn lower_case_statement(
        &mut self,
        case_statement: typed_ast::CaseStatement,
    ) -> simple_ast::Statement {
        // Post-pone compilation of case statement to ir-gen phase.
        let enum_type = case_statement.value.typ.clone().into_enum();
        let value = self.lower_expression(case_statement.value);

        let mut arms = vec![];
        for arm in case_statement.arms {
            let body = self.lower_block(arm.body);
            arms.push(simple_ast::CaseArm {
                choice: arm.choice,
                local_ids: arm.local_ids,
                body,
            });
        }

        simple_ast::Statement::Case(simple_ast::CaseStatement {
            enum_type,
            value,
            arms,
        })
    }

    fn lower_assignment(
        &self,
        assignment: typed_ast::AssignmentStatement,
    ) -> simple_ast::Statement {
        match assignment.target.kind {
            typed_ast::ExpressionType::GetAttr { base, attr } => {
                let base_typ = base.typ.clone();
                match &base_typ {
                    MyType::Struct(struct_typ) => {
                        let index = struct_typ.index_of(&attr).expect("Field must be present");
                        let base = self.lower_expression(*base);
                        let value = self.lower_expression(assignment.value);
                        simple_ast::Statement::SetAttr {
                            base,
                            base_typ,
                            index,
                            value,
                        }
                    }
                    MyType::Class(class_typ) => {
                        let index = class_typ
                            .inner
                            .index_of(&attr)
                            .expect("Field must be present");
                        let base = self.lower_expression(*base);
                        let base_typ = Self::type_fold(base_typ);
                        let value = self.lower_expression(assignment.value);
                        simple_ast::Statement::SetAttr {
                            base,
                            base_typ,
                            index,
                            value,
                        }
                    }
                    other => {
                        panic!("Base type must be structured type, not {:?}.", other);
                    }
                }
            }
            typed_ast::ExpressionType::LoadLocal { name: _, index } => {
                let value = self.lower_expression(assignment.value);
                simple_ast::Statement::StoreLocal { index, value }
            }
            _other => {
                unimplemented!("TODO");
            }
        }
    }

    fn struct_literal(
        &self,
        typ: MyType,
        values: Vec<typed_ast::Expression>,
    ) -> simple_ast::Expression {
        let values = values
            .into_iter()
            .map(|v| self.lower_expression(v))
            .collect();
        simple_ast::Expression::StructLiteral { typ, values }
    }

    fn lower_expression(&self, expression: typed_ast::Expression) -> simple_ast::Expression {
        let (kind, typ) = (expression.kind, expression.typ);
        match kind {
            typed_ast::ExpressionType::Literal(literal) => simple_ast::Expression::Literal(literal),
            typed_ast::ExpressionType::StructLiteral(values) => self.struct_literal(typ, values),
            typed_ast::ExpressionType::ListLiteral(values) => {
                let new_values: Vec<simple_ast::Expression> = values
                    .into_iter()
                    .map(|v| self.lower_expression(v))
                    .collect();
                simple_ast::Expression::ArrayLiteral {
                    typ,
                    values: new_values,
                }
            }
            typed_ast::ExpressionType::LoadParameter { name: _, index } => {
                simple_ast::Expression::LoadParameter { index }
            }
            typed_ast::ExpressionType::LoadLocal { name: _, index } => {
                let typ = Self::type_fold(typ);
                simple_ast::Expression::LoadLocal { index, typ }
            }
            typed_ast::ExpressionType::LoadFunction(name) => {
                simple_ast::Expression::LoadFunction(name)
            }
            typed_ast::ExpressionType::TypeConstructor(_) => {
                panic!("Cannot be here!");
            }
            typed_ast::ExpressionType::Instantiate => self.lower_instantiate(typ),
            typed_ast::ExpressionType::ImplicitSelf => {
                simple_ast::Expression::LoadParameter { index: 0 }
            }
            typed_ast::ExpressionType::Call { callee, arguments } => {
                let callee = Box::new(self.lower_expression(*callee));
                let arguments = arguments
                    .into_iter()
                    .map(|v| self.lower_expression(v))
                    .collect();
                let typ = Self::type_fold(typ);
                simple_ast::Expression::Call {
                    callee,
                    arguments,
                    typ,
                }
            }
            typed_ast::ExpressionType::MethodCall {
                instance,
                method,
                arguments,
            } => self.lower_method_call(*instance, method, arguments, typ),
            typed_ast::ExpressionType::Binop { lhs, op, rhs } => {
                let op_typ = lhs.typ.clone();
                let lhs = Box::new(self.lower_expression(*lhs));
                let rhs = Box::new(self.lower_expression(*rhs));
                simple_ast::Expression::Binop {
                    typ,
                    op_typ,
                    lhs,
                    op,
                    rhs,
                }
            }
            typed_ast::ExpressionType::EnumLiteral { choice, arguments } => {
                self.lower_enum_literal(typ, choice, arguments)
            }
            typed_ast::ExpressionType::GetAttr { base, attr } => self.lower_get_attr(*base, attr),
            typed_ast::ExpressionType::Index { base, index } => {
                let base = self.lower_expression(*base);
                let index = self.lower_expression(*index);
                simple_ast::Expression::GetIndex {
                    base: Box::new(base),
                    index: Box::new(index),
                }
                // unimplemented!();
            }
        }
    }

    fn lower_instantiate(&self, typ: MyType) -> simple_ast::Expression {
        if let MyType::Class(class_type) = &typ {
            // Call class constructor auto-contrapted function!
            let ctor_name = class_type.inner.ctor_func_name();
            let callee = simple_ast::Expression::LoadFunction(ctor_name);
            let typ = Self::type_fold(typ);
            simple_ast::Expression::Call {
                callee: Box::new(callee),
                arguments: vec![],
                typ,
            }
        } else {
            panic!("Instantiation requires class type");
        }
    }

    /// Translate method call into normal call
    fn lower_method_call(
        &self,
        instance: typed_ast::Expression,
        method: String,
        arguments: Vec<typed_ast::Expression>,
        typ: MyType,
    ) -> simple_ast::Expression {
        let class_type = instance.typ.clone().into_class();
        let mut arguments: Vec<simple_ast::Expression> = arguments
            .into_iter()
            .map(|v| self.lower_expression(v))
            .collect();
        arguments.insert(0, self.lower_expression(instance));
        let class_name = class_type.name.clone();
        let function_name = format!("{}_{}", class_name, method);
        let callee = simple_ast::Expression::LoadFunction(function_name);
        let typ = Self::type_fold(typ);
        simple_ast::Expression::Call {
            callee: Box::new(callee),
            arguments,
            typ,
        }
    }

    fn lower_get_attr(&self, base: typed_ast::Expression, attr: String) -> simple_ast::Expression {
        let base_typ = Self::type_fold(base.typ.clone());
        match &base_typ {
            MyType::Struct(struct_typ) => {
                let index = struct_typ.index_of(&attr).expect("Field must be present");
                let base = self.lower_expression(base);
                simple_ast::Expression::GetAttr {
                    base: Box::new(base),
                    base_typ,
                    index,
                }
            }
            MyType::Class(class_type_ref) => {
                let index = class_type_ref
                    .inner
                    .index_of(&attr)
                    .expect("Field must be present");
                let base = self.lower_expression(base);
                simple_ast::Expression::GetAttr {
                    base: Box::new(base),
                    base_typ,
                    index,
                }
            }
            other => {
                panic!(
                    "base type for attr {} must be struct, not {:?}",
                    attr, other
                );
            }
        }
    }

    /// Lower enum literal into is a sort of integer/tuple pair
    fn lower_enum_literal(
        &self,
        typ: MyType,
        choice: usize,
        arguments: Vec<typed_ast::Expression>,
    ) -> simple_ast::Expression {
        let struct_typ = Self::type_fold(typ.clone());
        let enum_type = typ.clone().into_enum();
        assert!(enum_type.choices[choice].data.len() == arguments.len());

        let union_type = enum_type.get_data_union_type();
        let union_value: simple_ast::Expression = if arguments.is_empty() {
            // Store void, hence do nothing now.
            simple_ast::Expression::VoidLiteral
        } else {
            // Create a union to store the data:
            // let union_typ = self.get_enum_union_data_typ(&enum_type);
            if arguments.len() == 1 {
                self.lower_expression(arguments.into_iter().next().unwrap())
            } else {
                let payload_struct_type = enum_type.choices[choice].get_payload_type();
                // Create a tuple (unnamed struct) with payload:
                self.struct_literal(payload_struct_type, arguments)
            }
        };

        // TBD: index does not have to be choice, non-data enum's are empty,
        // so they could share a void union tag
        // in general we could reduce the amount of union variants by a
        // mapping from choice to index:
        let payload = simple_ast::Expression::UnionLiteral {
            typ: union_type,
            index: choice,
            value: Box::new(union_value),
        };

        // let struct_typ = Self::type_fold(typ);

        // Create a tagged union:
        simple_ast::Expression::StructLiteral {
            typ: struct_typ,
            values: vec![
                simple_ast::Expression::Literal(typed_ast::Literal::Integer(choice as i64)),
                payload,
            ],
        }
    }
}
