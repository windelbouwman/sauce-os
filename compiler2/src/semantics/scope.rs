//! Symbol table related code.

use super::MyType;
use std::collections::HashMap;

#[derive(Debug, Clone)]
pub enum Symbol {
    Typ(MyType),
    Function {
        name: String,
        typ: MyType,
    },
    Module {
        // typ: MyType,
        name: String,
        exposed: HashMap<String, MyType>,
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

impl Symbol {
    // fn get_type(&self) -> &MyType {
    //     match self {
    //         Symbol::Typ(_t) => &MyType::Typ,
    //         Symbol::Function { typ } => &typ,
    //         Symbol::Module { typ } => typ,
    //         Symbol::Parameter { typ } => typ,
    //         // Symbol::Variable { typ } => typ,
    //     }
    // }
}

pub struct Scope {
    // TODO: should be private?
    pub symbols: HashMap<String, Symbol>,
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
}
