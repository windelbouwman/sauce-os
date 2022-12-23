//! Symbol table related code.

use super::type_system::{SlangType, UserType};
use super::typed_ast;
use super::Context;
use super::Symbol;
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

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
        log::trace!("Symbol table:");
        for sym in self.symbols.keys() {
            log::trace!(" - {}", sym);
        }
    }

    pub fn define_func(
        &mut self,
        context: &mut Context,
        name: &str,
        argument_types: Vec<(String, SlangType)>,
        return_type: Option<SlangType>,
    ) {
        let mut parameters = vec![];
        for (name, typ) in argument_types {
            parameters.push(Rc::new(RefCell::new(typed_ast::Parameter {
                location: Default::default(),
                id: context.id_generator.gimme(),
                name,
                typ,
            })));
        }

        let signature = Rc::new(RefCell::new(typed_ast::FunctionSignature {
            parameters,
            return_type,
        }));
        let typ = SlangType::User(UserType::Function(signature));

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
