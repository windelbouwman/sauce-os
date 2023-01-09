use super::{ClassDef, EnumDef, FunctionDef, StructDef};
use super::{ClassType, EnumType, SlangType, StructType, UserType};
use super::{Symbol, TypeVar};
use std::cell::RefCell;
use std::rc::{Rc, Weak};

#[derive(Clone)]
pub enum Definition {
    Function(Rc<RefCell<FunctionDef>>),
    Class(Rc<ClassDef>),
    Struct(Rc<StructDef>),
    Enum(Rc<EnumDef>),
    // Field(Arc<FieldDef>),
}

impl Definition {
    /// Create type for this definition!
    pub fn create_type(&self, type_arguments: Vec<SlangType>) -> SlangType {
        let user_type = match self {
            Definition::Struct(struct_def) => {
                assert!(type_arguments.len() == struct_def.type_parameters.len());
                UserType::Struct(StructType {
                    struct_ref: Rc::downgrade(struct_def),
                    type_arguments,
                })
            }
            Definition::Enum(enum_def) => {
                let enum_type = EnumType::from_def(enum_def, type_arguments);
                UserType::Enum(enum_type)
            }
            Definition::Class(class_def) => {
                assert!(type_arguments.is_empty());
                UserType::Class(ClassType {
                    class_ref: Rc::downgrade(class_def),
                    type_arguments,
                })
            }
            Definition::Function(_function_def) => {
                // UserType::Function(function_def.borrow().signature.clone())
                unimplemented!();
            }
        };

        SlangType::User(user_type)
    }

    pub fn get_ref(&self) -> DefinitionRef {
        match self {
            Definition::Struct(struct_def) => DefinitionRef::Struct(Rc::downgrade(struct_def)),
            Definition::Enum(enum_def) => DefinitionRef::Enum(Rc::downgrade(enum_def)),
            Definition::Class(class_def) => DefinitionRef::Class(Rc::downgrade(class_def)),
            Definition::Function(_function_def) => {
                unimplemented!();
            }
        }
    }

    /// Narrow the type to struct type.
    #[allow(dead_code)]
    pub fn as_struct(&self) -> Rc<StructDef> {
        if let Definition::Struct(struct_def) = self {
            struct_def.clone()
        } else {
            panic!("Expected struct type");
        }
    }

    /// Get attribute from this definition
    #[allow(dead_code)]
    pub fn get_attr(&self, name: &str) -> Option<Symbol> {
        match self {
            Definition::Struct(struct_def) => struct_def.get_attr(name),
            Definition::Class(class_def) => class_def.get_attr(name),
            _ => None,
        }
    }
}

#[derive(Clone)]
pub enum DefinitionRef {
    Struct(Weak<StructDef>),
    Enum(Weak<EnumDef>),
    Class(Weak<ClassDef>),
}

impl DefinitionRef {
    pub fn create_type(&self, type_arguments: Vec<SlangType>) -> SlangType {
        self.clone().into_definition().create_type(type_arguments)
    }

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
