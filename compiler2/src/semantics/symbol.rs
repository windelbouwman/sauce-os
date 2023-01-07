//! Representation of a symbol.
//!
//! Symbols can refer to variables, parameters, functions etc..
//!

use super::tast::{
    ClassDef, Definition, EnumDef, EnumVariant, FieldDef, FunctionDef, LocalVariable, Parameter,
    Program, Ref, SlangType, StructDef, TypeVar,
};

use std::rc::{Rc, Weak};

#[derive(Clone)]
pub enum DefinitionRef {
    Struct(Weak<StructDef>),
    Enum(Weak<EnumDef>),
    Class(Weak<ClassDef>),
}

impl DefinitionRef {
    /// Turn this reference to a definition into a true definition.
    pub fn into_definition(self) -> Definition {
        match self {
            DefinitionRef::Struct(struct_ref) => {
                let struct_def = struct_ref.upgrade().unwrap();
                Definition::Struct(struct_def)
            }
            DefinitionRef::Enum(enum_ref) => {
                let enum_def = enum_ref.upgrade().unwrap();
                Definition::Enum(enum_def)
            }
            DefinitionRef::Class(class_ref) => {
                let class_def = class_ref.upgrade().unwrap();
                Definition::Class(class_def)
            }
        }
    }

    pub fn get_type_parameters(&self) -> Vec<Rc<TypeVar>> {
        match self {
            DefinitionRef::Struct(struct_ref) => {
                let struct_def = struct_ref.upgrade().unwrap();
                struct_def.type_parameters.clone()
            }
            DefinitionRef::Enum(enum_ref) => {
                let enum_def = enum_ref.upgrade().unwrap();
                enum_def.type_parameters.clone()
            }
            DefinitionRef::Class(class_ref) => {
                let class_def = class_ref.upgrade().unwrap();
                class_def.type_parameters.clone()
            }
        }
    }
}

impl std::fmt::Display for DefinitionRef {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            DefinitionRef::Struct(struct_ref) => {
                let struct_def = struct_ref.upgrade().unwrap();
                write!(f, "ref-{}", struct_def)
            }
            DefinitionRef::Enum(enum_ref) => {
                let enum_def = enum_ref.upgrade().unwrap();
                write!(f, "ref-{}", enum_def)
            }
            DefinitionRef::Class(class_ref) => {
                let class_def = class_ref.upgrade().unwrap();
                write!(f, "ref-{}", class_def)
            }
        }
    }
}

#[derive(Clone)]
pub enum Symbol {
    Typ(SlangType),
    Definition(DefinitionRef),
    Function(Ref<FunctionDef>),
    ExternFunction {
        name: String,
        typ: SlangType,
    },
    Module(Rc<Program>),
    Parameter(Ref<Parameter>),
    LocalVariable(Ref<LocalVariable>),
    Field(Ref<FieldDef>),
    EnumVariant(
        // typ: SlangType,
        // variant:
        Ref<EnumVariant>,
    ),
}

impl Symbol {
    /// Try to retrieve a type from this symbol.
    pub fn get_type(&self) -> SlangType {
        match self {
            Symbol::Field(field_ref) => field_ref.upgrade().unwrap().borrow().typ.clone(),
            Symbol::Function(func_ref) => func_ref.upgrade().unwrap().borrow().get_type(),
            Symbol::Parameter(param_ref) => param_ref.upgrade().unwrap().borrow().typ.clone(),
            Symbol::LocalVariable(local_ref) => local_ref.upgrade().unwrap().borrow().typ.clone(),
            Symbol::ExternFunction { name: _, typ } => typ.clone(),
            other => {
                panic!("Unexpected user-type member: {}", other);
            }
        }
    }
}

impl std::fmt::Display for Symbol {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            Symbol::Definition(definition_ref) => definition_ref.fmt(f),
            Symbol::Typ(typ) => {
                write!(f, "symbol-typ({})", typ)
            }
            Symbol::Function(_) => {
                write!(f, "symbol-function(..)")
            }
            Symbol::ExternFunction { name, typ: _ } => {
                write!(f, "symbol-extern-function(name={})", name)
            }
            Symbol::Module(_) => {
                write!(f, "symbol-module(..)")
            }
            Symbol::Parameter(_) => {
                write!(f, "symbol-parameter(..)")
            }
            Symbol::LocalVariable(_) => {
                write!(f, "symbol-local(..)")
            }
            Symbol::Field(_) => {
                write!(f, "symbol-field(..)")
            }
            Symbol::EnumVariant(_) => {
                write!(f, "symbol-enum-variant(..)")
            }
        }
    }
}

impl std::fmt::Debug for Symbol {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        // Use the display logic for debug as well:
        write!(f, "{}", self)
    }
}
