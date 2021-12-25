//! Transform a typed ast into some byte-code ish format
//!
//! Idea section:
//! - introduce a de-sugar phase, to eliminate wildly complicated contraptions on source level.

use super::bytecode;
use super::bytecode::Instruction;
use super::parsing::ast;
use super::type_system::MyType;
use super::typed_ast;

pub fn gen(prog: typed_ast::Program) -> bytecode::Program {
    log::info!("Generating IR bytecode");
    let mut g = Generator::new();
    g.gen_prog(prog)
}

struct Generator {
    instructions: Vec<Instruction>,
    _id_counter: usize,
    loop_stack: Vec<(usize, usize)>,
}

impl Generator {
    fn new() -> Self {
        Generator {
            instructions: vec![],
            _id_counter: 0,
            loop_stack: vec![],
        }
    }

    fn gen_prog(&mut self, prog: typed_ast::Program) -> bytecode::Program {
        let imports = vec![];
        let mut functions = vec![];
        for function in prog.functions {
            functions.push(self.gen_func(function));
        }

        bytecode::Program { imports, functions }
    }

    fn gen_func(&mut self, func: typed_ast::FunctionDef) -> bytecode::Function {
        log::debug!("Gen code for {}", func.name);
        self.gen_block(func.body);

        let parameters = func
            .parameters
            .into_iter()
            .map(|p| bytecode::Parameter {
                name: p.name,
                typ: Self::get_bytecode_typ(&p.typ),
            })
            .collect();

        let instructions = std::mem::take(&mut self.instructions);
        bytecode::Function {
            name: func.name,
            parameters,
            code: instructions,
        }
    }

    fn new_label(&mut self) -> usize {
        let x = self._id_counter;
        self._id_counter += 1;
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
            typed_ast::StatementType::Let { name, value } => {
                let typ = Self::get_bytecode_typ(&value.typ);
                self.gen_expression(value);
                // store value in local variable:
                self.emit(Instruction::StoreLocal { name, typ });
            }
            typed_ast::StatementType::Break => {
                let target_label = self.loop_stack.last().unwrap().1;
                self.emit(Instruction::Jump(target_label));
            }
            typed_ast::StatementType::Continue => {
                let target_label = self.loop_stack.last().unwrap().0;
                self.emit(Instruction::Jump(target_label));
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

    fn get_bytecode_typ(ty: &MyType) -> bytecode::Typ {
        match ty {
            MyType::Bool => bytecode::Typ::Bool,
            MyType::Int => bytecode::Typ::Int,
            MyType::Float => bytecode::Typ::Float,
            MyType::String => bytecode::Typ::Ptr,
            MyType::Struct(_) => bytecode::Typ::Ptr,
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
                for value in values {
                    // self.emit(Instruction::Dup());
                    // TODO: get index!
                    let index = 0;
                    self.gen_expression(value);
                    self.emit(Instruction::SetAttr(index));
                }
            }
            typed_ast::ExpressionType::Binop { lhs, op, rhs } => {
                let typ = Self::get_bytecode_typ(&lhs.typ);
                self.gen_expression(*lhs);
                self.gen_expression(*rhs);
                match op {
                    ast::BinaryOperator::Math(op2) => {
                        let op = match op2 {
                            ast::MathOperator::Add => bytecode::Operator::Add,
                            ast::MathOperator::Sub => bytecode::Operator::Sub,
                            ast::MathOperator::Mul => bytecode::Operator::Mul,
                            ast::MathOperator::Div => {
                                // self.emit(Instruction::Div);
                                // unimplemented!("TODO");
                                bytecode::Operator::Div
                            }
                        };
                        self.emit(Instruction::Operator { op, typ });
                    }
                    ast::BinaryOperator::Comparison(op2) => {
                        let op = match op2 {
                            ast::ComparisonOperator::Equal => bytecode::Comparison::Equal,
                            ast::ComparisonOperator::NotEqual => bytecode::Comparison::NotEqual,
                            ast::ComparisonOperator::Gt => bytecode::Comparison::Gt,
                            ast::ComparisonOperator::GtEqual => {
                                // unimplemented!("TODO: swap lhs and rhs?");
                                bytecode::Comparison::GtEqual
                            }
                            ast::ComparisonOperator::Lt => bytecode::Comparison::Lt,
                            ast::ComparisonOperator::LtEqual => {
                                // unimplemented!("TODO: swap lhs and rhs?");
                                bytecode::Comparison::LtEqual
                            }
                        };

                        self.emit(Instruction::Comparison { op, typ });
                    }
                    ast::BinaryOperator::Logic(op) => {
                        unimplemented!("TODO : {:?}", op);
                    }
                }
            }
            typed_ast::ExpressionType::Call { callee, arguments } => {
                self.gen_expression(*callee);
                let n_args = arguments.len();
                for argument in arguments {
                    self.gen_expression(argument);
                }
                let return_type = None; // TODO!
                self.emit(Instruction::Call {
                    n_args,
                    typ: return_type,
                });
            }
            typed_ast::ExpressionType::GetAttr { base, attr } => {
                self.gen_expression(*base);
                // TODO! proper indexing here!
                let index = 0;
                self.emit(Instruction::GetAttr(index));
            }
            typed_ast::ExpressionType::LoadFunction(name) => {
                self.emit(Instruction::LoadGlobalName(name));
            }
            typed_ast::ExpressionType::LoadParameter(name) => {
                let typ = Self::get_bytecode_typ(&expression.typ);
                self.emit(Instruction::LoadName { name, typ });
            }
            typed_ast::ExpressionType::LoadLocal(name) => {
                let typ = Self::get_bytecode_typ(&expression.typ);
                self.emit(Instruction::LoadName { name, typ });
            }
            typed_ast::ExpressionType::LoadGlobal(_name) => {
                // self.emit(Instruction::LoadName(name));
                unimplemented!("TODO!");
            }
        }
    }

    fn emit(&mut self, instruction: Instruction) {
        self.instructions.push(instruction);
    }
}
