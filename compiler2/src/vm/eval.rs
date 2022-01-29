use super::value::Struct;
use super::Vm;
use super::{Frame, Value};
use crate::bytecode;
use std::sync::Arc;

pub enum ExecResult {
    Continue,
    Return(Option<Value>),
}

pub fn dispatch(vm: &Vm, frame: &mut Frame, opcode: bytecode::Instruction) -> ExecResult {
    use bytecode::Instruction;
    // Execute:
    match opcode {
        Instruction::Nop => {}
        Instruction::IntLiteral(value) => frame.push(Value::Integer(value)),
        Instruction::StringLiteral(value) => frame.push(Value::String(value)),
        Instruction::BoolLiteral(value) => frame.push(Value::Bool(value)),
        Instruction::FloatLiteral(value) => frame.push(Value::Float(value)),
        Instruction::Duplicate => {
            let value = frame.pop();
            frame.push(value.clone());
            frame.push(value);
        }
        Instruction::DropTop => {
            frame.pop();
        }
        Instruction::Malloc(typ) => match typ {
            bytecode::Typ::Composite(index) => {
                let typ = vm.get_type(index);
                match typ {
                    bytecode::TypeDef::Struct(struct_def) => {
                        frame.push(Value::Struct(Arc::new(Struct::new(struct_def))));
                    }
                    bytecode::TypeDef::Union(union_def) => {
                        // frame.push(Value::Struct(Arc::new(Struct::new(typ))));
                        unimplemented!("TODO");
                    }
                }
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
                bytecode::Typ::String => {
                    let lhs = lhs.as_string();
                    let rhs = rhs.as_string();
                    let result: String = match op {
                        bytecode::Operator::Add => lhs + &rhs,
                        other => {
                            unimplemented!("Operation not supported for strings: {:?}", other);
                        }
                    };
                    Value::String(result)
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
                bytecode::Typ::Float => {
                    let lhs = lhs.as_float();
                    let rhs = rhs.as_float();
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
            let value = frame.pop();
            let base = frame.pop();
            match base {
                Value::Struct(s) => {
                    s.set_field(index, value);
                }
                other => {
                    panic!("Cannot set attr of non-struct: {:?}", other);
                }
            }
        }
        Instruction::Call { n_args, typ } => {
            let mut args: Vec<Value> = vec![];
            for _ in 1..=n_args {
                let arg = frame.pop();
                args.push(arg);
            }
            args.reverse();
            assert_eq!(args.len(), n_args);
            let callee = frame.pop();
            log::trace!("Invoking: {:?} ({:?})", callee, args);
            if let Some(ret_val) = super::invoke(vm, callee, args) {
                // TODO: check return type?
                assert!(typ.is_some());
                frame.push(ret_val);
            }
            log::trace!("Invoke returned");
        }
        Instruction::Jump(label) => {
            frame.jump(label);
        }
        Instruction::JumpTable(label_table) => {
            let index = frame.pop().as_int();
            // TBD: maybe use last index as default?
            // Or use a default index when out of range?
            frame.jump(label_table[index as usize]);
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
