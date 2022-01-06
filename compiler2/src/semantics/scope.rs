//! Symbol table related code.

use super::{MyType, StructType};
use std::collections::HashMap;

#[derive(Debug, Clone)]
pub enum Symbol {
    Typ(MyType),
    Function {
        name: String,
        typ: MyType,
    },
    Module {
        name: String,
        scope: Scope,
    },
    Parameter {
        typ: MyType,
        name: String,
        index: usize,
    },
    LocalVariable {
        mutable: bool,
        name: String,
        index: usize,
        typ: MyType,
    },
}

#[derive(Debug, Clone)]
pub struct Scope {
    symbols: HashMap<String, Symbol>,
}

impl Scope {
    pub fn new() -> Self {
        Scope {
            symbols: HashMap::new(),
        }
    }

    pub fn dump(&self) {
        log::debug!("Symbol table:");
        for sym in self.symbols.keys() {
            log::debug!(" - {}", sym);
        }
    }

    pub fn define_func(
        &mut self,
        name: &str,
        argument_types: Vec<MyType>,
        return_type: Option<MyType>,
    ) {
        self.define(
            name.to_owned(),
            Symbol::Function {
                name: name.to_owned(),
                typ: MyType::Function {
                    argument_types,
                    return_type: return_type.map(Box::new),
                },
            },
        );
    }

    pub fn define_struct(&mut self, name: String, fields: Vec<(String, MyType)>) {
        self.define(
            name.clone(),
            Symbol::Typ(MyType::Struct(StructType {
                name: Some(name.clone()),
                fields,
            })),
        );
    }

    pub fn is_defined(&self, name: &str) -> bool {
        self.symbols.contains_key(name)
    }

    pub fn define(&mut self, name: String, value: Symbol) {
        self.symbols.insert(name, value);
    }

    pub fn get(&self, name: &str) -> Option<&Symbol> {
        self.symbols.get(name)
    }
}
