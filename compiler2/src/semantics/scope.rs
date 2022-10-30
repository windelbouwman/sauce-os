//! Symbol table related code.

use super::type_system::{FunctionType, SlangType};
use super::Symbol;
use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct Scope {
    pub symbols: HashMap<String, Symbol>,
}

impl Scope {
    pub fn new() -> Self {
        Scope {
            symbols: HashMap::new(),
        }
    }

    // pub fn dump(&self) {
    //     println!("Symbol table:");
    //     for sym in self.symbols.keys() {
    //         println!(" - {}", sym);
    //     }
    // }

    pub fn define_func(
        &mut self,
        name: &str,
        argument_types: Vec<SlangType>,
        return_type: Option<SlangType>,
    ) {
        let typ = SlangType::Function(FunctionType {
            argument_types,
            return_type: return_type.map(Box::new),
        });

        self.define(
            name.to_owned(),
            Symbol::ExternFunction {
                name: name.to_owned(),
                typ,
            },
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
