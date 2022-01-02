//! Transform a typed ast into some byte-code ish format
//!
//! Idea section:
//! - introduce a de-sugar phase, to eliminate wildly complicated contraptions on source level.

use super::bytecode;
use super::bytecode::Instruction;
use super::parsing::ast;
use super::semantics::type_system::{MyType, StructType};
use super::semantics::typed_ast;
use std::collections::HashMap;

pub fn gen(prog: typed_ast::Program) -> bytecode::Program {
    log::info!("Generating IR bytecode");
    let mut g = Generator::new();
    g.gen_prog(prog)
}

struct Generator {
    instructions: Vec<Instruction>,
    id_counter: usize,
    loop_stack: Vec<(usize, usize)>,
    struct_types: Vec<bytecode::StructDef>,
    struct_id_map: HashMap<StructType, usize>,
}

impl Generator {
    fn new() -> Self {
        Generator {
            instructions: vec![],
            id_counter: 0,
            loop_stack: vec![],
            struct_types: vec![],
            struct_id_map: HashMap::new(),
        }
    }

    fn gen_prog(&mut self, prog: typed_ast::Program) -> bytecode::Program {
        for typedef in prog.type_defs {
            self.get_struct_index(&typedef);
        }

        let mut imports = vec![];
        for imp in prog.imports {
            match imp.typ {
                MyType::Function {
                    argument_types,
                    return_type,
                } => {
                    let bc_import = bytecode::Import {
                        name: imp.name,
                        parameter_types: argument_types
                            .iter()
                            .map(|t| self.get_bytecode_typ(t))
                            .collect(),
                        return_type: return_type.as_ref().map(|t| self.get_bytecode_typ(t)),
                    };
                    imports.push(bc_import);
                }
                other => {
                    unimplemented!("Not implemented: {:?}", other);
                }
            }
        }

        let mut functions = vec![];
        for function in prog.functions {
            functions.push(self.gen_func(function));
        }

        bytecode::Program {
            imports,
            struct_types: std::mem::take(&mut self.struct_types),
            functions,
        }
    }

    fn gen_func(&mut self, func: typed_ast::FunctionDef) -> bytecode::Function {
        log::debug!("Gen code for {}", func.name);

        let parameters = func
            .parameters
            .into_iter()
            .map(|p| bytecode::Parameter {
                name: p.name,
                typ: self.get_bytecode_typ(&p.typ),
            })
            .collect();

        let return_type = func.return_type.as_ref().map(|t| self.get_bytecode_typ(t));

        let locals = func
            .locals
            .into_iter()
            .map(|v| bytecode::Local {
                name: v.name,
                typ: self.get_bytecode_typ(&v.typ),
            })
            .collect();

        self.gen_block(func.body);

        // Hmm, a bit of a hack, to inject a void return here ..
        if !self.instructions.last().unwrap().is_terminator() {
            self.emit(Instruction::Return(0));
        }

        let instructions = std::mem::take(&mut self.instructions);
        bytecode::Function {
            name: func.name,
            parameters,
            return_type,
            locals,
            code: instructions,
        }
    }

    fn new_label(&mut self) -> usize {
        let x = self.id_counter;
        self.id_counter += 1;
        x
    }

    fn set_label(&mut self, label: usize) {
        self.emit(Instruction::Label(label));
    }

    fn gen_block(&mut self, block: typed_ast::Block) {
        for statement in block {
            self.gen_statement(statement);
        }
    }

    fn gen_statement(&mut self, statement: typed_ast::Statement) {
        match statement.kind {
            typed_ast::StatementType::Let {
                name: _,
                index,
                value,
            } => {
                // let typ = Self::get_bytecode_typ(&value.typ);
                self.gen_expression(value);
                // store value in local variable:
                self.emit(Instruction::StoreLocal { index });
            }
            typed_ast::StatementType::Assignment { target, value } => {
                // let typ = Self::get_bytecode_typ(&value.typ);
                match target {
                    typed_ast::Expression {
                        typ: _,
                        kind: typed_ast::ExpressionType::GetAttr { base, attr },
                    } => match &base.typ {
                        MyType::Struct(struct_typ) => {
                            let index = struct_typ.index_of(&attr).expect("Field must be present");
                            self.gen_expression(*base);
                            self.gen_expression(value);
                            self.emit(Instruction::SetAttr(index));
                        }
                        _other => {
                            panic!("Base type must be structured type.");
                        }
                    },
                    typed_ast::Expression {
                        typ: _,
                        kind: typed_ast::ExpressionType::LoadLocal { name: _, index },
                    } => {
                        self.gen_expression(value);
                        self.emit(Instruction::StoreLocal { index });
                    }
                    _other => {
                        unimplemented!("TODO");
                    }
                }
            }
            typed_ast::StatementType::Break => {
                let target_label = self.loop_stack.last().unwrap().1;
                self.emit(Instruction::Jump(target_label));
            }
            typed_ast::StatementType::Continue => {
                let target_label = self.loop_stack.last().unwrap().0;
                self.emit(Instruction::Jump(target_label));
            }
            typed_ast::StatementType::Pass => {}
            typed_ast::StatementType::Return { value } => {
                if let Some(value) = value {
                    self.gen_expression(value);
                    self.emit(Instruction::Return(1));
                } else {
                    self.emit(Instruction::Return(0));
                }
                // TBD: generate a new label here?
            }
            typed_ast::StatementType::If {
                condition,
                if_true,
                if_false,
            } => {
                let true_label = self.new_label();
                let final_label = self.new_label();
                if let Some(if_false) = if_false {
                    let false_label = self.new_label();
                    self.gen_condition(condition, true_label, false_label);

                    self.set_label(true_label);
                    self.gen_block(if_true);
                    self.emit(Instruction::Jump(final_label));

                    self.set_label(false_label);
                    self.gen_block(if_false);
                } else {
                    self.gen_condition(condition, true_label, final_label);

                    self.set_label(true_label);
                    self.gen_block(if_true);
                }
                self.emit(Instruction::Jump(final_label));
                self.set_label(final_label);
            }
            typed_ast::StatementType::Loop { body } => {
                let loop_start_label = self.new_label();
                let final_label = self.new_label();
                self.emit(Instruction::Jump(loop_start_label));
                self.set_label(loop_start_label);
                self.loop_stack.push((loop_start_label, final_label));
                self.gen_block(body);
                self.loop_stack.pop();
                self.emit(Instruction::Jump(loop_start_label));
                self.set_label(final_label);
            }
            typed_ast::StatementType::While { condition, body } => {
                let loop_start_label = self.new_label();
                let true_label = self.new_label();
                let final_label = self.new_label();
                self.emit(Instruction::Jump(loop_start_label));
                self.set_label(loop_start_label);
                self.gen_condition(condition, true_label, final_label);
                self.set_label(true_label);
                self.loop_stack.push((loop_start_label, final_label));
                self.gen_block(body);
                self.loop_stack.pop();
                self.emit(Instruction::Jump(loop_start_label));
                self.set_label(final_label);
            }
            typed_ast::StatementType::Expression(e) => {
                self.gen_expression(e);
            }
        }
    }

    /// Generate bytecode for condition statement.
    fn gen_condition(
        &mut self,
        expression: typed_ast::Expression,
        true_label: usize,
        false_label: usize,
    ) {
        // Implement short-circuit logic for 'or' and 'and'
        // TODO: add 'not' operator
        match expression.kind {
            typed_ast::ExpressionType::Binop {
                lhs,
                op: ast::BinaryOperator::Logic(op2),
                rhs,
            } => {
                let middle_label = self.new_label();
                match op2 {
                    ast::LogicOperator::And => {
                        self.gen_condition(*lhs, middle_label, false_label);
                        self.set_label(middle_label);
                        self.gen_condition(*rhs, true_label, false_label);
                    }
                    ast::LogicOperator::Or => {
                        self.gen_condition(*lhs, true_label, middle_label);
                        self.set_label(middle_label);
                        self.gen_condition(*rhs, true_label, false_label);
                    }
                }
            }
            _ => {
                // Fall back to evaluation an expression!
                self.gen_expression(expression);
                self.emit(Instruction::JumpIf(true_label, false_label));
            }
        }
    }

    fn get_struct_index(&mut self, struct_type: &StructType) -> usize {
        if self.struct_id_map.contains_key(struct_type) {
            *self.struct_id_map.get(struct_type).unwrap()
        } else {
            let idx = self.struct_types.len();
            self.struct_id_map.insert(struct_type.clone(), idx);
            let fields: Vec<bytecode::Typ> = struct_type
                .fields
                .iter()
                .map(|f| self.get_bytecode_typ(&f.1))
                .collect();
            self.struct_types.push(bytecode::StructDef {
                name: struct_type.name.clone(),
                fields,
            });
            idx
        }
    }

    fn get_bytecode_typ(&mut self, ty: &MyType) -> bytecode::Typ {
        match ty {
            MyType::Bool => bytecode::Typ::Bool,
            MyType::Int => bytecode::Typ::Int,
            MyType::Float => bytecode::Typ::Float,
            MyType::String => bytecode::Typ::String,
            MyType::Struct(struct_typ) => bytecode::Typ::Ptr(Box::new(bytecode::Typ::Struct(
                self.get_struct_index(struct_typ),
            ))),
            other => {
                unimplemented!("{:?}", other);
            }
        }
    }

    fn gen_expression(&mut self, expression: typed_ast::Expression) {
        match expression.kind {
            typed_ast::ExpressionType::Bool(value) => {
                self.emit(Instruction::BoolLiteral(value));
            }
            typed_ast::ExpressionType::Integer(value) => {
                self.emit(Instruction::IntLiteral(value));
            }
            typed_ast::ExpressionType::Float(value) => {
                self.emit(Instruction::FloatLiteral(value));
            }
            typed_ast::ExpressionType::String(value) => {
                self.emit(Instruction::StringLiteral(value));
            }
            typed_ast::ExpressionType::StructLiteral(values) => {
                let typ = self.get_bytecode_typ(&expression.typ);
                if let bytecode::Typ::Ptr(typ) = typ {
                    self.emit(Instruction::Malloc(*typ));
                    for (index, value) in values.into_iter().enumerate() {
                        self.emit(Instruction::Duplicate);
                        self.gen_expression(value);
                        self.emit(Instruction::SetAttr(index));
                    }
                } else {
                    panic!("Assumed struct literal is pointer to thing.");
                }
            }
            typed_ast::ExpressionType::Binop { lhs, op, rhs } => {
                match op {
                    ast::BinaryOperator::Math(op2) => {
                        let typ = self.get_bytecode_typ(&lhs.typ);
                        self.gen_expression(*lhs);
                        self.gen_expression(*rhs);
                        let op = match op2 {
                            ast::MathOperator::Add => bytecode::Operator::Add,
                            ast::MathOperator::Sub => bytecode::Operator::Sub,
                            ast::MathOperator::Mul => bytecode::Operator::Mul,
                            ast::MathOperator::Div => bytecode::Operator::Div,
                        };
                        self.emit(Instruction::Operator { op, typ });
                    }
                    ast::BinaryOperator::Comparison(op2) => {
                        let typ = self.get_bytecode_typ(&lhs.typ);
                        self.gen_expression(*lhs);
                        self.gen_expression(*rhs);
                        // TBD: we could simplify by swapping lhs and rhs and using Lt instead of GtEqual
                        let op = match op2 {
                            ast::ComparisonOperator::Equal => bytecode::Comparison::Equal,
                            ast::ComparisonOperator::NotEqual => bytecode::Comparison::NotEqual,
                            ast::ComparisonOperator::Gt => bytecode::Comparison::Gt,
                            ast::ComparisonOperator::GtEqual => bytecode::Comparison::GtEqual,
                            ast::ComparisonOperator::Lt => bytecode::Comparison::Lt,
                            ast::ComparisonOperator::LtEqual => bytecode::Comparison::LtEqual,
                        };

                        self.emit(Instruction::Comparison { op, typ });
                    }
                    ast::BinaryOperator::Logic(op) => {
                        let true_label = self.new_label();
                        let false_label = self.new_label();
                        let final_label = self.new_label();
                        let recreated_expression = typed_ast::Expression {
                            typ: expression.typ,
                            kind: typed_ast::ExpressionType::Binop {
                                lhs,
                                op: ast::BinaryOperator::Logic(op),
                                rhs,
                            },
                        };
                        self.gen_condition(recreated_expression, true_label, false_label);
                        self.set_label(true_label);
                        self.emit(Instruction::BoolLiteral(true));
                        self.emit(Instruction::Jump(final_label));
                        self.set_label(false_label);
                        self.emit(Instruction::BoolLiteral(false));
                        self.emit(Instruction::Jump(final_label));
                        self.set_label(final_label);
                    }
                }
            }
            typed_ast::ExpressionType::Call { callee, arguments } => match &callee.typ {
                MyType::Function {
                    argument_types: _,
                    return_type,
                } => {
                    let return_type = return_type.as_ref().map(|t| self.get_bytecode_typ(t));

                    self.gen_expression(*callee);
                    let n_args = arguments.len();
                    for argument in arguments {
                        self.gen_expression(argument);
                    }
                    self.emit(Instruction::Call {
                        n_args,
                        typ: return_type,
                    });
                }
                other => {
                    panic!("Can only call function types, not {:?}", other);
                }
            },
            typed_ast::ExpressionType::GetAttr { base, attr } => match &base.typ {
                MyType::Struct(struct_typ) => {
                    let index = struct_typ.index_of(&attr).expect("Field must be present");
                    let typ = self.get_bytecode_typ(&struct_typ.fields[index].1);
                    self.gen_expression(*base);
                    self.emit(Instruction::GetAttr { index, typ });
                }
                other => {
                    panic!("base type must be struct, not {:?}", other);
                }
            },
            typed_ast::ExpressionType::LoadFunction(name) => {
                self.emit(Instruction::LoadGlobalName(name));
            }
            typed_ast::ExpressionType::LoadParameter { name: _, index } => {
                // TBD: use name as a hint?
                let typ = self.get_bytecode_typ(&expression.typ);
                self.emit(Instruction::LoadParameter { index, typ });
            }
            typed_ast::ExpressionType::LoadLocal { name: _, index } => {
                let typ = self.get_bytecode_typ(&expression.typ);
                self.emit(Instruction::LoadLocal { index, typ });
            }
        }
    }

    fn emit(&mut self, instruction: Instruction) {
        self.instructions.push(instruction);
    }
}
