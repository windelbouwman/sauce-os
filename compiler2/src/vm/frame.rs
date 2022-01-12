//! Run bytecode at will!

use std::sync::Arc;

use super::eval::{dispatch, ExecResult};
use super::value::Value;
use super::Vm;
use crate::bytecode;

/// A single stack frame.
///
/// Created per function call to bytecode.
pub struct Frame {
    pc: usize,
    function: Arc<bytecode::Function>,
    stack: Vec<Value>,
    locals: Vec<Value>,
    parameters: Vec<Value>,
}

pub fn run_frame(vm: &Vm, frame: &mut Frame) -> Option<Value> {
    loop {
        let opcode = frame.fetch();

        log::trace!("Executing: {:?}", opcode);
        match dispatch(vm, frame, opcode) {
            ExecResult::Continue => {}
            ExecResult::Return(value) => break value,
        }
    }
}

// fn step(&mut frame) -> ExecResult {
// Fetch!
// let opcode = &self.prog.functions[0].code[self.pc].clone();

// Should not require implicit return!
// if self.pc >= self.func.code.len() {
//     return Some(Value::Void);
// }

// }
impl Frame {
    pub fn new(function: Arc<bytecode::Function>, parameters: Vec<Value>) -> Self {
        Self {
            pc: 0,
            function,
            stack: vec![],
            locals: vec![],
            parameters,
        }
    }

    pub fn fetch(&mut self) -> bytecode::Instruction {
        let opcode = self.function.code[self.pc].clone();
        self.pc += 1;
        opcode
    }

    pub fn get_parameter(&self, index: usize) -> Value {
        self.parameters[index].clone()
    }

    pub fn get_local(&self, index: usize) -> Value {
        self.locals[index].clone()
    }

    pub fn set_local(&mut self, index: usize, value: Value) {
        self.locals[index] = value;
    }

    pub fn jump(&mut self, target: usize) {
        self.pc = target;
    }

    pub fn pop(&mut self) -> Value {
        self.stack.pop().unwrap()
    }

    pub fn push(&mut self, value: Value) {
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
