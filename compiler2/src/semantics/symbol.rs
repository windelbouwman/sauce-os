use super::scope::Scope;
use super::type_system::{EnumType, SlangType};

#[derive(Debug, Clone)]
pub enum Symbol {
    Typ(SlangType),
    Function {
        name: String,
        typ: SlangType,
    },
    Module {
        name: String,
        scope: Scope,
    },
    Parameter {
        typ: SlangType,
        name: String,
        index: usize,
    },
    LocalVariable {
        mutable: bool,
        name: String,
        index: usize,
        typ: SlangType,
    },
    Field {
        class_typ: SlangType,
        name: String,
        index: usize,
        typ: SlangType,
    },
    EnumOption {
        /// An index in the enum type's options
        choice: usize,
        enum_type: EnumType,
    },
}
