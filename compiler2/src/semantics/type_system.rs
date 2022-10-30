// use std::collections::HashMap;
use super::typed_ast;
use super::Symbol;
use crate::parsing::ast;
use std::cell::RefCell;
use std::rc::{Rc, Weak};

// unused:
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SlangType {
    /// The type is undefined
    Undefined,

    Bool,
    Int,
    Float,
    String,

    /// Type of a type (inception enable=1!)
    ///
    /// This is the type for type constructors, for example
    /// a user defined class, or an enum option like `Option::None`
    TypeConstructor,

    /// A parameterized type, may contain subtypes which are type variables.
    // Generic {
    //     base: Box<SlangType>,
    //     type_parameters: Vec<String>,
    // },

    // TypeVar(String),

    /// Array type, a flat container type of fixed size.
    Array(ArrayType),

    /// User defined type
    User(UserType),

    Void,

    /// Unresolved type
    Unresolved(ast::ObjRef),

    Function(FunctionType),
}

impl std::fmt::Display for SlangType {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            SlangType::Undefined => {
                write!(f, "undefined")
            }
            SlangType::Int => {
                write!(f, "int")
            }
            SlangType::Bool => {
                write!(f, "bool")
            }
            SlangType::Float => {
                write!(f, "float")
            }
            SlangType::String => {
                write!(f, "str")
            }
            SlangType::TypeConstructor => {
                write!(f, "type-con")
            }
            SlangType::Array(array) => {
                write!(f, "array({} x {})", array.size, array.element_type)
            }
            SlangType::User(user_type) => {
                write!(f, "{}", user_type)
            }
            SlangType::Void => {
                write!(f, "void")
            }
            SlangType::Unresolved(obj_ref) => {
                write!(f, "unresolved({:?})", obj_ref)
            }
            SlangType::Function(function_type) => {
                write!(
                    f,
                    "function({:?} -> {:?})",
                    function_type.argument_types, function_type.return_type
                )
            }
        }
    }
}

#[derive(Clone)]
pub enum UserType {
    /// A custom defined struct type!
    Struct(Weak<typed_ast::StructDef>),
    Union(Weak<typed_ast::UnionDef>),
    Enum(Weak<typed_ast::EnumDef>),
    Class(Weak<typed_ast::ClassDef>),
    // TODO: more user definable types?
}

impl UserType {
    /// Try to retrieve a field from a user defined type
    pub fn get_field(&self, name: &str) -> Option<Rc<RefCell<typed_ast::FieldDef>>> {
        match self {
            UserType::Struct(struct_def) => struct_def.upgrade().unwrap().get_field(name),
            UserType::Union(union_def) => union_def.upgrade().unwrap().get_field(name),
            _ => None,
        }
    }

    pub fn get_attr(&self, name: &str) -> Option<Symbol> {
        match self {
            UserType::Struct(struct_def) => struct_def.upgrade().unwrap().get_attr(name),
            UserType::Union(union_def) => union_def.upgrade().unwrap().get_attr(name),
            UserType::Class(class_def) => class_def.upgrade().unwrap().get_field(name),
            _ => None,
        }
    }
}

impl PartialEq for UserType {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (UserType::Struct(s), UserType::Struct(o)) => s.ptr_eq(o),
            (UserType::Enum(s), UserType::Enum(o)) => s.ptr_eq(o),
            (UserType::Class(s), UserType::Class(o)) => s.ptr_eq(o),
            _x => false,
        }
    }
}

impl Eq for UserType {}

impl std::fmt::Display for UserType {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            UserType::Struct(struct_ref) => {
                let struct_ref = struct_ref.upgrade().unwrap();
                write!(f, "user-{}", struct_ref)
            }
            UserType::Union(union_ref) => {
                let union_ref = union_ref.upgrade().unwrap();
                write!(f, "user-{}", union_ref)
            }
            UserType::Enum(enum_ref) => {
                let enum_ref = enum_ref.upgrade().unwrap();
                write!(f, "enum(name={}, id={})", enum_ref.name, enum_ref.id)
            }
            UserType::Class(_class_ref) => {
                write!(f, "user-class")
            }
        }
    }
}

impl std::fmt::Debug for UserType {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        // Use the display logic for debug as well:
        write!(f, "{}", self)
    }
}

impl SlangType {
    pub fn into_function_type(self) -> FunctionType {
        if let SlangType::Function(function_type) = self {
            function_type
        } else {
            panic!("Expected function type!");
        }
    }

    pub fn is_enum(&self) -> bool {
        matches!(self, SlangType::User(UserType::Enum(_)))
    }

    pub fn as_enum(&self) -> Rc<typed_ast::EnumDef> {
        if let SlangType::User(UserType::Enum(enum_type)) = self {
            enum_type.upgrade().unwrap()
        } else {
            panic!("Expected enum type, but got {}", self);
        }
    }

    pub fn as_union(&self) -> Rc<typed_ast::UnionDef> {
        if let SlangType::User(UserType::Union(union_type)) = self {
            union_type.upgrade().unwrap()
        } else {
            panic!("Expected union type, got {}", self);
        }
    }

    /// Narrow the type to struct type.
    pub fn as_struct(&self) -> Rc<typed_ast::StructDef> {
        if let SlangType::User(UserType::Struct(struct_def)) = self {
            struct_def.upgrade().unwrap()
        } else {
            panic!("Expected struct type, got {}", self);
        }
    }

    pub fn get_attr(&self, name: &str) -> Option<Symbol> {
        match self {
            SlangType::User(user_type) => user_type.get_attr(name),
            _ => None,
        }
    }

    /*
    pub fn into_class(self) -> Arc<ClassType> {
        if let SlangType::Class(class_ref) = self {
            class_ref.inner
        } else {
            panic!("Expected class type!");
        }
    }
    */

    pub fn is_void(&self) -> bool {
        matches!(self, SlangType::Void)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FunctionType {
    pub argument_types: Vec<SlangType>,
    pub return_type: Option<Box<SlangType>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArrayType {
    pub element_type: Box<SlangType>,
    pub size: usize,
}
