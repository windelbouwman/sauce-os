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
    log::info!("IR-gen ");

    let mut g = Generator::new();
    let bc = g.gen_prog(prog);

    // print_bc(&bc);
    bc
}

fn print_bc(bc: &bytecode::Program) {
    for func in &bc.functions {
        println!("Function: {}", func.name);
        print_instructions(&func.code);
    }
}

fn print_instructions(instructions: &Vec<Instruction>) {
    println!("  Instructionzzz:");
    for instruction in instructions {
        println!("    : {:?}", instruction);
    }
}

struct Generator {
    instructions: Vec<Instruction>,
    _id_counter: usize,
}

impl Generator {
    fn new() -> Self {
        Generator {
            instructions: vec![],
            _id_counter: 0,
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

    fn gen_func(&mut self, func: typed_ast::TypedFunctionDef) -> bytecode::Function {
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

        let instructions = std::mem::replace(&mut self.instructions, vec![]);
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
            typed_ast::StatementType::Let { name: _, value } => {
                // TODO: store value?
                self.gen_expression(value);
            }
            typed_ast::StatementType::Break => {
                let target_label = 0; // TODO!
                self.emit(Instruction::Jump(target_label));
            }
            typed_ast::StatementType::Continue => {
                let target_label = 0; // TODO!
                self.emit(Instruction::Jump(target_label));
            }
            typed_ast::StatementType::If {
                condition,
                if_true,
                if_false,
            } => {
                let true_label = self.new_label();
                let final_label = self.new_label();
                self.gen_condition(condition);
                if let Some(if_false) = if_false {
                    let false_label = self.new_label();
                    self.emit(Instruction::JumpIf(true_label, false_label));

                    self.set_label(true_label);
                    self.gen_block(if_true);
                    self.emit(Instruction::Jump(final_label));

                    self.set_label(false_label);
                    self.gen_block(if_false);
                    self.emit(Instruction::Jump(final_label));
                } else {
                    self.emit(Instruction::JumpIf(true_label, final_label));

                    self.set_label(true_label);
                    self.gen_block(if_true);
                    self.emit(Instruction::Jump(final_label));
                }
                self.set_label(final_label);
            }
            typed_ast::StatementType::Loop { body } => {
                self.gen_block(body);
                unimplemented!("TODO");
            }
            typed_ast::StatementType::While { condition, body } => {
                self.gen_condition(condition);
                self.gen_block(body);
                unimplemented!("TODO");
            }
            typed_ast::StatementType::Expression(e) => {
                self.gen_expression(e);
            }
        }
    }

    fn gen_condition(&mut self, expression: typed_ast::Expression) {
        self.gen_expression(expression);
    }

    fn get_bytecode_typ(ty: &MyType) -> bytecode::Typ {
        match ty {
            MyType::Int => bytecode::Typ::Int,
            MyType::Float => bytecode::Typ::Float,
            MyType::String => bytecode::Typ::Ptr,
            other => {
                unimplemented!("{:?}", other);
            }
        }
    }

    fn gen_expression(&mut self, expression: typed_ast::Expression) {
        match expression.kind {
            typed_ast::ExpressionType::Integer(value) => {
                self.emit(Instruction::IntLiteral(value));
            }
            typed_ast::ExpressionType::Float(value) => {
                self.emit(Instruction::FloatLiteral(value));
            }
            typed_ast::ExpressionType::String(value) => {
                self.emit(Instruction::StringLiteral(value));
            }
            typed_ast::ExpressionType::Binop { lhs, op, rhs } => {
                self.gen_expression(*lhs);
                self.gen_expression(*rhs);
                match op {
                    ast::BinaryOperator::Math(op2) => {
                        let op = match op2 {
                            ast::MathOperator::Add => bytecode::Operator::Add,
                            ast::MathOperator::Sub => bytecode::Operator::Sub,
                            ast::MathOperator::Mul => bytecode::Operator::Mul,
                            ast::MathOperator::Div => {
                                self.emit(Instruction::Nop);
                                unimplemented!("TODO");
                            }
                        };
                        let typ = Self::get_bytecode_typ(&expression.typ);
                        self.emit(Instruction::Operator { op, typ });
                    }
                    ast::BinaryOperator::Comparison(op2) => {
                        let op = match op2 {
                            ast::ComparisonOperator::Equal => bytecode::Comparison::Equal,
                            ast::ComparisonOperator::Gt => bytecode::Comparison::Gt,
                            ast::ComparisonOperator::GtEqual => {
                                unimplemented!("TODO: swap lhs and rhs?");
                                // bytecode::Comparison::GtEqual
                            }
                            ast::ComparisonOperator::Lt => bytecode::Comparison::Lt,
                            ast::ComparisonOperator::LtEqual => {
                                unimplemented!("TODO: swap lhs and rhs?");
                                // bytecode::Comparison::LtEqual
                            }
                        };
                        let typ = Self::get_bytecode_typ(&expression.typ);

                        self.emit(Instruction::Comparison { op, typ });
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
            // typed_ast::ExpressionType::GetAttr { base, attr } => {
            //     self.gen_expression(*base);
            //     self.emit(Instruction::GetAttr(attr));
            // }
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
