//! Run bytecode at will!

use super::bytecode;

pub fn execute(prog: bytecode::Program) {
    let vm = Vm { prog };
    vm.run_func();

    // let opcode = &self.prog.functions[0].code[self.pc].clone();
}

/// A virtual machine, interpreting bytecodes!
struct Vm {
    prog: bytecode::Program,
}

/// A single stack frame.
///
/// Created per function call to bytecode.
struct Frame {
    pc: usize,
    instructions: Vec<bytecode::Instruction>,
    stack: Vec<Value>,
    locals: Vec<Value>,
    parameters: Vec<Value>,
}

#[derive(Clone, Debug)]
enum Value {
    Void,
    Integer(i64),
    String(String),
    Bool(bool),
    Float(f64),
    External(String),

    /// A structured type is a vector of values!
    Struct(Vec<Value>),
}

impl Value {
    /// Narrow value to f64, panics if not possible.
    fn as_float(&self) -> f64 {
        match self {
            Value::Float(val) => *val,
            other => panic!("Cannot convert {:?} into float", other),
        }
    }

    fn as_int(&self) -> i64 {
        match self {
            Value::Integer(val) => *val,
            other => panic!("Cannot convert {:?} into int", other),
        }
    }

    fn as_bool(&self) -> bool {
        match self {
            Value::Bool(val) => *val,
            other => panic!("Cannot convert {:?} into bool", other),
        }
    }
}

impl Vm {
    fn run_func(&self) {
        log::debug!("Running function!");
        let mut frame = Frame {
            pc: 0,
            instructions: self.prog.functions[0].code.clone(),
            stack: vec![],
            locals: vec![],
            parameters: vec![],
        };
        frame.run();
    }

    // fn new() -> Self {

    // }
}

impl Frame {
    fn run(&mut self) -> Value {
        loop {
            if let Some(value) = self.step() {
                return value;
            }
        }
    }

    fn step(&mut self) -> Option<Value> {
        // Fetch!
        // let opcode = &self.prog.functions[0].code[self.pc].clone();
        if self.pc >= self.instructions.len() {
            return Some(Value::Void);
        }
        let opcode = self.instructions[self.pc].clone();
        self.pc += 1;

        log::trace!("Executing: {:?}", opcode);

        use bytecode::Instruction;
        // Execute:
        match opcode {
            Instruction::IntLiteral(value) => self.push(Value::Integer(value)),
            Instruction::StringLiteral(value) => self.push(Value::String(value)),
            Instruction::BoolLiteral(value) => self.push(Value::Bool(value)),
            Instruction::FloatLiteral(value) => self.push(Value::Float(value)),
            Instruction::Duplicate => {
                let value = self.pop();
                self.push(value.clone());
                self.push(value);
            }
            Instruction::Malloc(typ) => match typ {
                bytecode::Typ::Struct(_index) => {
                    // TODO: lookup type!
                    let values = vec![];
                    self.push(Value::Struct(values));
                    unimplemented!("TODO!");
                }
                other => {
                    unimplemented!("Malloc: {:?}", other);
                }
            },
            Instruction::Operator { op, typ } => {
                let rhs = self.pop();
                let lhs = self.pop();
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
                self.push(result);
            }
            Instruction::Comparison { op, typ } => {
                let rhs = self.pop();
                let lhs = self.pop();

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
                self.push(Value::Bool(result));
            }
            Instruction::LoadGlobalName(name) => {
                self.push(Value::External(name));
            }
            Instruction::LoadParameter { index, typ: _ } => {
                let value = self.parameters[index].clone();
                self.push(value);
            }
            Instruction::LoadLocal { index, typ: _ } => {
                let value = self.locals[index].clone();
                self.push(value);
            }
            Instruction::StoreLocal { index } => {
                let value = self.pop();
                self.locals[index] = value;
            }
            Instruction::GetAttr { index, typ: _ } => {
                let base = self.pop();
                match base {
                    Value::Struct(fields) => {
                        let value = fields[index].clone();
                        self.push(value);
                    }
                    other => {
                        panic!("Cannot get attr of non-struct: {:?}", other);
                    }
                }
                unimplemented!("???");
            }
            Instruction::SetAttr(_index) => {
                let _base = self.pop();
                unimplemented!("???");
            }
            Instruction::Call { n_args, typ: _ } => {
                let mut args: Vec<Value> = vec![];
                for _ in 1..=n_args {
                    let arg = self.pop();
                    args.push(arg);
                }
                args.reverse();
                assert_eq!(args.len(), n_args);
                let callee = self.pop();
                log::trace!("Invoking: {:?} ({:?})", callee, args);
            }
            Instruction::Label(_id) => {}
            Instruction::Jump(label) => {
                self.jump(label);
            }
            Instruction::Return(amount) => match amount {
                1 => {
                    let value = self.pop();
                    return Some(value);
                }
                other => {
                    unimplemented!("Returning of {} values", other);
                }
            },
            Instruction::JumpIf(true_target, false_label) => {
                if self.pop().as_bool() {
                    self.jump(true_target);
                } else {
                    self.jump(false_label);
                }
            }
        };

        None
    }

    fn jump(&mut self, target: usize) {
        self.pc = target;
    }

    fn pop(&mut self) -> Value {
        self.stack.pop().unwrap()
    }

    fn push(&mut self, value: Value) {
        self.stack.push(value);
    }
}

/*
fn evaluate_operator<T>(lhs: T, op: bytecode::Operator, rhs: T) -> T::Output
where
    T: std::ops::Add + std::ops::Sub + std::ops::Mul + std::ops::Div,
    // T: std::ops::Add,
{
    match op {
        bytecode::Operator::Add => lhs + rhs,
        bytecode::Operator::Sub => lhs - rhs,
        bytecode::Operator::Mul => lhs * rhs,
        bytecode::Operator::Div => lhs / rhs,
    }
}
*/
