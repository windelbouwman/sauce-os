use crate::bytecode;
use std::sync::Arc;
use std::sync::Mutex;

#[derive(Clone, Debug)]
pub enum Value {
    Uninitialized,
    // Void,
    Integer(i64),
    String(String),
    Bool(bool),
    Float(f64),
    External(String),

    Function(Arc<bytecode::Function>),

    /// A structured type is a vector of values!
    Struct(Arc<Struct>),

    Union(Arc<Union>),
    // Enum(i64, Box<Value>),
    Array(Arc<ArrayValue>),
}

#[derive(Debug, Default)]
pub struct Struct {
    fields: Mutex<Vec<Value>>,
}

impl Struct {
    pub fn new(typ: &bytecode::StructDef) -> Self {
        let fields: Vec<Value> = typ.fields.iter().map(|_| Value::Uninitialized).collect();
        Self {
            fields: Mutex::new(fields),
        }
    }

    pub fn get_field(&self, index: usize) -> Value {
        self.fields.lock().unwrap()[index].clone()
    }

    pub fn set_field(&self, index: usize, value: Value) {
        self.fields.lock().unwrap()[index] = value;
    }
}

#[derive(Debug)]
pub struct Union {
    value: Mutex<Value>,
}

impl Union {
    pub fn new(_typ: &bytecode::UnionDef) -> Self {
        Self {
            value: Mutex::new(Value::Uninitialized),
        }
    }

    pub fn get_field(&self, _index: usize) -> Value {
        // TODO: use index?
        self.value.lock().unwrap().clone()
    }

    pub fn set_field(&self, _index: usize, value: Value) {
        // TBD: use index?
        *self.value.lock().unwrap() = value;
    }
}

#[derive(Debug, Default)]
pub struct ArrayValue {
    values: Mutex<Vec<Value>>,
}

impl ArrayValue {
    pub fn new(size: i64) -> Self {
        let mut values = vec![];
        for i in 0..size {
            // println!("i={}", i);
            values.push(Value::Uninitialized);
        }

        Self {
            values: Mutex::new(values),
        }
    }

    pub fn get_element(&self, index: usize) -> Value {
        self.values.lock().unwrap()[index].clone()
    }

    pub fn set_element(&self, index: usize, value: Value) {
        self.values.lock().unwrap()[index] = value;
    }
}

impl Value {
    /// Narrow value to f64, panics if not possible.
    pub fn as_float(&self) -> f64 {
        match self {
            Value::Float(val) => *val,
            other => panic!("Cannot convert {:?} into float", other),
        }
    }

    pub fn as_int(&self) -> i64 {
        match self {
            Value::Integer(val) => *val,
            other => panic!("Cannot convert {:?} into int", other),
        }
    }

    pub fn as_bool(&self) -> bool {
        match self {
            Value::Bool(val) => *val,
            other => panic!("Cannot convert {:?} into bool", other),
        }
    }

    pub fn as_string(&self) -> String {
        match self {
            Value::String(val) => val.clone(),
            other => panic!("Cannot use {:?} as string", other),
        }
    }

    pub fn into_array(self) -> Arc<ArrayValue> {
        match self {
            Value::Array(array_value) => array_value,
            other => panic!("Cannot convert {:?} into array", other),
        }
    }
}
