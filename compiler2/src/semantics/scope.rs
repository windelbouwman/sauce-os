//! Symbol table related code.

use super::type_system::{EnumType, FunctionType, MyType};
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
    Field {
        class_typ: MyType,
        name: String,
        index: usize,
        typ: MyType,
    },
    EnumOption {
        /// An index in the enum type's options
        choice: usize,
        enum_type: EnumType,
    },
}

impl Symbol {
    pub fn into_type(self) -> MyType {
        match self {
            Symbol::Typ(t) => t,
            other => {
                panic!("Expected type, but got {:?}", other);
            }
        }
    }
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
        println!("Symbol table:");
        for sym in self.symbols.keys() {
            println!(" - {}", sym);
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
                typ: MyType::Function(FunctionType {
                    argument_types,
                    return_type: return_type.map(Box::new),
                }),
            },
        );
    }

    pub fn define_type(&mut self, name: &str, typ: MyType) {
        self.define(name.to_owned(), Symbol::Typ(typ));
    }

    // pub fn define_struct(&mut self, name: String, fields: Vec<StructField>) {
    //     self.define(
    //         name.clone(),
    //         Symbol::Typ(MyType::Struct(StructType {
    //             name: Some(name),
    //             fields,
    //         })),
    //     );
    // }

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
