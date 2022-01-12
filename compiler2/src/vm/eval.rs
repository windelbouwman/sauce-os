use super::Vm;
use crate::bytecode;

use super::{Frame, Value};

pub enum ExecResult {
    Continue,
    Return(Option<Value>),
}

pub fn dispatch(vm: &Vm, frame: &mut Frame, opcode: bytecode::Instruction) -> ExecResult {
    use bytecode::Instruction;
    // Execute:
    match opcode {
        Instruction::IntLiteral(value) => frame.push(Value::Integer(value)),
        Instruction::StringLiteral(value) => frame.push(Value::String(value)),
        Instruction::BoolLiteral(value) => frame.push(Value::Bool(value)),
        Instruction::FloatLiteral(value) => frame.push(Value::Float(value)),
        Instruction::Duplicate => {
            let value = frame.pop();
            frame.push(value.clone());
            frame.push(value);
        }
        Instruction::Malloc(typ) => match typ {
            bytecode::Typ::Struct(_index) => {
                // TODO: lookup type!
                // self.push(Value::Struct(Arc::new(Struct::default())));
                unimplemented!("TODO!");
            }
            other => {
                unimplemented!("Malloc: {:?}", other);
            }
        },
        Instruction::Operator { op, typ } => {
            let rhs = frame.pop();
            let lhs = frame.pop();
            let result: Value = match typ {
                bytecode::Typ::Float => {
                    let lhs = lhs.as_float();
                    let rhs = rhs.as_float();
                    let result: f64 = match op {
                        bytecode::Operator::Add => lhs + rhs,
                        bytecode::Operator::Sub => lhs - rhs,
                        bytecode::Operator::Mul => lhs * rhs,
                        bytecode::Operator::Div => lhs / rhs,
                    };
                    Value::Float(result)
                }
                bytecode::Typ::Int => {
                    let lhs = lhs.as_int();
                    let rhs = rhs.as_int();
                    let result: i64 = match op {
                        bytecode::Operator::Add => lhs + rhs,
                        bytecode::Operator::Sub => lhs - rhs,
                        bytecode::Operator::Mul => lhs * rhs,
                        bytecode::Operator::Div => lhs / rhs,
                    };
                    Value::Integer(result)
                }
                other => {
                    unimplemented!("operator for {:?}", other);
                }
            };
            frame.push(result);
        }
        Instruction::Comparison { op, typ } => {
            let rhs = frame.pop();
            let lhs = frame.pop();

            let result: bool = match typ {
                bytecode::Typ::Int => {
                    let lhs = lhs.as_int();
                    let rhs = rhs.as_int();
                    match op {
                        bytecode::Comparison::Equal => lhs == rhs,
                        bytecode::Comparison::NotEqual => lhs == rhs,
                        bytecode::Comparison::Gt => lhs > rhs,
                        bytecode::Comparison::GtEqual => lhs >= rhs,
                        bytecode::Comparison::Lt => lhs < rhs,
                        bytecode::Comparison::LtEqual => lhs <= rhs,
                    }
                }
                other => {
                    unimplemented!("operator for {:?}", other);
                }
            };
            frame.push(Value::Bool(result));
        }
        Instruction::LoadGlobalName(name) => {
            let val = vm.lookup(&name);
            frame.push(val);
        }
        Instruction::LoadParameter { index } => {
            let value = frame.get_parameter(index);
            frame.push(value);
        }
        Instruction::LoadLocal { index, typ: _ } => {
            let value = frame.get_local(index);
            frame.push(value);
        }
        Instruction::StoreLocal { index } => {
            let value = frame.pop();
            frame.set_local(index, value);
        }
        Instruction::GetAttr { index, typ: _ } => {
            let base = frame.pop();
            match base {
                Value::Struct(s) => {
                    frame.push(s.get_field(index));
                }
                other => {
                    panic!("Cannot get attr of non-struct: {:?}", other);
                }
            }
        }
        Instruction::SetAttr { index } => {
            let base = frame.pop();
            let value = frame.pop();
            match base {
                Value::Struct(s) => {
                    s.set_field(index, value);
                }
                other => {
                    panic!("Cannot get attr of non-struct: {:?}", other);
                }
            }
            unimplemented!("???");
        }
        Instruction::Call { n_args, typ: _ } => {
            let mut args: Vec<Value> = vec![];
            for _ in 1..=n_args {
                let arg = frame.pop();
                args.push(arg);
            }
            args.reverse();
            assert_eq!(args.len(), n_args);
            let callee = frame.pop();
            log::trace!("Invoking: {:?} ({:?})", callee, args);
            super::invoke(vm, callee, args);
        }
        Instruction::Label(_id) => {}
        Instruction::Jump(label) => {
            frame.jump(label);
        }
        Instruction::Return(amount) => match amount {
            0 => {
                return ExecResult::Return(None);
            }
            1 => {
                let value = frame.pop();
                return ExecResult::Return(Some(value));
            }
            other => {
                unimplemented!("Returning of {} values", other);
            }
        },
        Instruction::JumpIf(true_target, false_label) => {
            if frame.pop().as_bool() {
                frame.jump(true_target);
            } else {
                frame.jump(false_label);
            }
        }
    }

    ExecResult::Continue
}
