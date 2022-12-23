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

    TypeVar(TypeVarRef),

    /// Array type, a flat container type of fixed size.
    Array(ArrayType),

    /// User defined type
    User(UserType),

    Void,

    /// Unresolved type
    Unresolved(ast::ObjRef),

    GenericInstance {
        generic: Generic,
        type_parameters: Vec<SlangType>,
    },
}

#[derive(Clone)]
pub struct TypeVarRef {
    pub ptr: Weak<typed_ast::TypeVar>,
}

impl PartialEq for TypeVarRef {
    fn eq(&self, other: &Self) -> bool {
        self.ptr.ptr_eq(&other.ptr)
    }
}
impl Eq for TypeVarRef {}

impl std::fmt::Display for TypeVarRef {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        let v = self.ptr.upgrade().unwrap();
        write!(f, "{}", v)
    }
}

impl std::fmt::Debug for TypeVarRef {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        // Use the display logic for debug as well:
        write!(f, "{}", self)
    }
}

#[derive(Clone)]
pub enum Generic {
    Unresolved(ast::ObjRef),

    Generic(Weak<typed_ast::GenericDef>),
}

impl Generic {
    pub fn get_def(&self) -> Rc<typed_ast::GenericDef> {
        match self {
            Generic::Unresolved(_obj_ref) => {
                panic!("Unresolved generic!");
            }
            Generic::Generic(generic) => generic.upgrade().unwrap(),
        }
    }
}

impl PartialEq for Generic {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (Generic::Generic(s), Generic::Generic(o)) => s.ptr_eq(o),
            (Generic::Unresolved(s), Generic::Unresolved(o)) => s == o,
            _x => false,
        }
    }
}

impl std::fmt::Display for Generic {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            Generic::Generic(generic) => {
                let generic = generic.upgrade().unwrap();
                write!(f, "generic({})", generic.name)
            }
            Generic::Unresolved(obj_ref) => {
                write!(f, "unresolved-generic({:?})", obj_ref)
            }
        }
    }
}

impl std::fmt::Debug for Generic {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        // Use the display logic for debug as well:
        write!(f, "{}", self)
    }
}

impl Eq for Generic {}

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
            SlangType::TypeVar(v) => {
                write!(f, "type-var({})", v)
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
            SlangType::GenericInstance {
                generic,
                type_parameters,
            } => {
                write!(f, "generic-instance({} -> {:?})", generic, type_parameters)
            }

            SlangType::Unresolved(obj_ref) => {
                write!(f, "unresolved({:?})", obj_ref)
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
    Function(Rc<RefCell<typed_ast::FunctionSignature>>),
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

    pub fn get_method(&self, name: &str) -> Option<Rc<RefCell<typed_ast::FunctionDef>>> {
        match self {
            UserType::Class(class_def) => class_def.upgrade().unwrap().get_method(name),
            _ => None,
        }
    }

    pub fn get_attr(&self, name: &str) -> Option<Symbol> {
        match self {
            UserType::Struct(struct_def) => struct_def.upgrade().unwrap().get_attr(name),
            UserType::Union(union_def) => union_def.upgrade().unwrap().get_attr(name),
            UserType::Class(class_def) => class_def.upgrade().unwrap().get_attr(name),
            _ => None,
        }
    }

    pub fn mangle_name(&self) -> String {
        match self {
            UserType::Struct(struct_def) => {
                let struct_def = struct_def.upgrade().unwrap();
                struct_def.name.clone()
            }
            other => {
                panic!("Cannot name mangle: {}", other);
            }
        }
    }
}

impl PartialEq for UserType {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (UserType::Struct(s), UserType::Struct(o)) => s.ptr_eq(o),
            (UserType::Union(s), UserType::Union(o)) => s.ptr_eq(o),
            (UserType::Enum(s), UserType::Enum(o)) => s.ptr_eq(o),
            (UserType::Class(s), UserType::Class(o)) => s.ptr_eq(o),
            (UserType::Function(s), UserType::Function(o)) => {
                s.borrow().compatible_signature(&o.borrow())
            }
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
                if let Some(enum_ref) = enum_ref.upgrade() {
                    write!(f, "enum(name={}, id={})", enum_ref.name, enum_ref.id)
                } else {
                    write!(f, "enum(NULL)")
                }
            }
            UserType::Class(class_ref) => {
                let class_ref = class_ref.upgrade().unwrap();
                write!(
                    f,
                    "user-class(name={}, id={})",
                    class_ref.name, class_ref.id
                )
            }
            UserType::Function(signature) => {
                let signature = signature.borrow();
                write!(f, "function(")?;

                for parameter in &signature.parameters {
                    let parameter = parameter.borrow();
                    write!(f, "{}, ", parameter.typ)?;
                }

                if let Some(t) = &signature.return_type {
                    write!(f, ") -> {}", t)
                } else {
                    write!(f, ")")
                }
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
    pub fn into_function_type(self) -> Rc<RefCell<typed_ast::FunctionSignature>> {
        if let SlangType::User(UserType::Function(function_type)) = self {
            function_type
        } else {
            panic!("Expected function type!");
        }
    }

    /// Retrieve a name suitable for name mangling
    pub fn mangle_name(&self) -> String {
        match self {
            SlangType::Int => "int".to_owned(),
            SlangType::Bool => "bool".to_owned(),
            SlangType::String => "str".to_owned(),
            SlangType::User(user_type) => user_type.mangle_name(),
            other => {
                panic!("Cannot name mangle: {}", other);
            }
        }
    }

    pub fn is_int(&self) -> bool {
        matches!(self, SlangType::Int)
    }

    pub fn is_float(&self) -> bool {
        matches!(self, SlangType::Float)
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

    pub fn is_class(&self) -> bool {
        matches!(self, SlangType::User(UserType::Class(_)))
    }

    pub fn as_class(&self) -> Rc<typed_ast::ClassDef> {
        if let SlangType::User(UserType::Class(class_def)) = self {
            class_def.upgrade().unwrap()
        } else {
            panic!("Expected class type, but got {}", self);
        }
    }

    pub fn get_attr(&self, name: &str) -> Option<Symbol> {
        match self {
            SlangType::User(user_type) => user_type.get_attr(name),
            _ => None,
        }
    }

    pub fn get_method(&self, name: &str) -> Option<Rc<RefCell<typed_ast::FunctionDef>>> {
        match self {
            SlangType::User(user_type) => user_type.get_method(name),
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

    // pub fn is_void(&self) -> bool {
    //     matches!(self, SlangType::Void)
    // }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArrayType {
    pub element_type: Box<SlangType>,
    pub size: usize,
}
