mod eval;
mod frame;
mod runtime;
mod value;

use crate::bytecode;
use frame::{run_frame, Frame};
use std::collections::HashMap;
use std::sync::Arc;
use value::Value;

pub fn execute(prog: bytecode::Program) {
    let vm = Vm::new(prog);
    // Assume our entry is 'main()'
    run_func(&vm, "main", vec![]);
}

/// A virtual machine, interpreting bytecodes!
pub struct Vm {
    // prog: bytecode::Program,
    func_map: HashMap<String, Arc<bytecode::Function>>,
    // call_stack?
    types: Vec<bytecode::StructDef>,
}

fn run_func(vm: &Vm, name: &str, parameters: Vec<Value>) -> Option<Value> {
    log::debug!("Running function: {}", name);
    let func = vm.lookup(name);
    invoke(vm, func, parameters)
}

fn invoke(vm: &Vm, callee: Value, parameters: Vec<Value>) -> Option<Value> {
    match callee {
        Value::Function(func) => {
            let mut frame = Frame::new(func, parameters);
            run_frame(vm, &mut frame)
        }
        Value::External(name) => match name.as_str() {
            "std_print" => runtime::std_print(parameters),
            other => {
                panic!("ARG!{}", other);
            }
        },
        other => {
            panic!("Cannot invoke: {:?}", other);
        }
    }
}

impl Vm {
    fn new(program: bytecode::Program) -> Self {
        let mut func_map = HashMap::new();
        for func in program.functions {
            func_map.insert(func.name.clone(), Arc::new(func));
        }
        let types = program.struct_types;
        Self { func_map, types }
    }

    pub fn get_type(&self, index: usize) -> &bytecode::StructDef {
        &self.types[index]
    }

    fn lookup(&self, name: &str) -> Value {
        // Value::External(name)
        match self.func_map.get(name) {
            Some(func) => Value::Function(func.clone()),
            None => Value::External(name.to_owned()),
        }
        // .unwrap().clone();
        // Arc<bytecode::Function>
        // Value::Function(func)
    }
}
