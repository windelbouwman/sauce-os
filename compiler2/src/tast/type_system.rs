//! Various types to describe types in the SLANG lang.
//!

use super::{
    ClassType, EnumType, Expression, FieldDef, FunctionDef, FunctionSignature, StructType, Symbol,
    TypeVar, TypeVarRef,
};

use std::cell::RefCell;
use std::rc::Rc;

// unused:
#[derive(Clone, PartialEq, Eq)]
pub enum SlangType {
    /// The type is undefined
    Undefined,

    Basic(BasicType),

    /// Type of a type (inception enable=1!)
    ///
    /// This is the type for type constructors, for example
    /// a user defined class, or an enum option like `Option::None`
    TypeConstructor(Box<SlangType>),

    /// An opaque object
    ///
    /// Useful when rewriting generic types into opaque
    /// pointers with type casts.
    Opaque,

    TypeVar(TypeVarRef),

    /// Array type, a flat container type of fixed size.
    Array(ArrayType),

    /// User defined type
    User(UserType),

    Void,

    /// Unresolved type, expression must be evaluated as a type.
    Unresolved(TypeExpression),
}

#[derive(Clone, PartialEq, Eq)]
pub enum BasicType {
    Bool,
    Int,
    Float,
    String,
}

/// Unresolved type expression
pub struct TypeExpression {
    pub expr: Box<Expression>,
}

impl PartialEq for TypeExpression {
    fn eq(&self, _other: &Self) -> bool {
        panic!("Bad idea to compare type expressions.");
    }
}

impl Eq for TypeExpression {}

impl Clone for TypeExpression {
    fn clone(&self) -> Self {
        panic!("Must not clone.");
    }
}

impl From<UserType> for SlangType {
    fn from(user_type: UserType) -> Self {
        SlangType::User(user_type)
    }
}

impl From<EnumType> for SlangType {
    fn from(enum_type: EnumType) -> Self {
        SlangType::User(UserType::Enum(enum_type))
    }
}

impl std::fmt::Display for SlangType {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            SlangType::Undefined => {
                write!(f, "undefined")
            }
            SlangType::Basic(basic_type) => basic_type.fmt(f),
            SlangType::TypeConstructor(typ) => {
                write!(f, "type-con({})", typ)
            }
            SlangType::Opaque => {
                write!(f, "opaque")
            }
            SlangType::TypeVar(type_var_ref) => type_var_ref.fmt(f),
            SlangType::Array(array) => {
                write!(f, "array({} x {})", array.size, array.element_type)
            }
            SlangType::User(user_type) => {
                write!(f, "{}", user_type)
            }
            SlangType::Void => {
                write!(f, "void")
            }
            SlangType::Unresolved(_type_expr) => {
                write!(f, "unresolved-expr")
            }
        }
    }
}

impl std::fmt::Display for BasicType {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            BasicType::Int => {
                write!(f, "int")
            }
            BasicType::Bool => {
                write!(f, "bool")
            }
            BasicType::Float => {
                write!(f, "float")
            }
            BasicType::String => {
                write!(f, "str")
            }
        }
    }
}
#[derive(Clone)]
pub enum UserType {
    /// A custom defined struct type!
    Struct(StructType),
    Enum(EnumType),
    Class(ClassType),
    Function(Rc<RefCell<FunctionSignature>>),
    // TODO: more user definable types?
}

impl From<EnumType> for UserType {
    fn from(enum_type: EnumType) -> Self {
        UserType::Enum(enum_type)
    }
}

impl UserType {
    /// Try to retrieve a field from a user defined type
    pub fn get_field(&self, name: &str) -> Option<Rc<RefCell<FieldDef>>> {
        match self {
            UserType::Struct(struct_type) => struct_type.get_field(name),
            _ => None,
        }
    }

    pub fn get_method(&self, name: &str) -> Option<Rc<RefCell<FunctionDef>>> {
        match self {
            UserType::Class(class_def) => class_def.class_ref.upgrade().unwrap().get_method(name),
            _ => None,
        }
    }

    /// Retrieve attribute from user type.
    pub fn get_attr(&self, name: &str) -> Option<Symbol> {
        match self {
            UserType::Struct(struct_type) => {
                struct_type.struct_ref.upgrade().unwrap().get_attr(name)
            }
            UserType::Class(class_type) => class_type.class_ref.upgrade().unwrap().get_attr(name),
            _ => None,
        }
    }

    pub fn get_attr_type(&self, name: &str) -> Option<SlangType> {
        match self {
            UserType::Struct(struct_type) => struct_type.get_attr_type(name),
            UserType::Class(class_type) => class_type.get_attr_type(name),
            _ => None,
        }
    }

    pub fn mangle_name(&self) -> String {
        match self {
            UserType::Struct(struct_type) => {
                let struct_def = struct_type.struct_ref.upgrade().unwrap();
                struct_def.name.name.clone()
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
            (UserType::Struct(s), UserType::Struct(o)) => s == o,
            (UserType::Enum(s), UserType::Enum(o)) => s == o,
            (UserType::Class(s), UserType::Class(o)) => s == o,
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
            UserType::Struct(struct_type) => struct_type.fmt(f),
            UserType::Enum(enum_ref) => enum_ref.fmt(f),
            UserType::Class(class_type) => {
                let class_def = class_type.class_ref.upgrade().unwrap();
                class_def.fmt(f)
            }
            UserType::Function(signature) => {
                let signature = signature.borrow();

                let mut parameter_text: Vec<String> = vec![];
                for parameter in &signature.parameters {
                    let parameter = parameter.borrow();
                    parameter_text.push(format!("{}", parameter.typ));
                }

                if let Some(t) = &signature.return_type {
                    write!(f, "function({}) -> {}", parameter_text.join(", "), t)
                } else {
                    write!(f, "function({})", parameter_text.join(", "))
                }
            }
        }
    }
}

impl SlangType {
    /// Create a new type of integer type
    pub fn int() -> Self {
        SlangType::Basic(BasicType::Int)
    }

    pub fn bool() -> Self {
        SlangType::Basic(BasicType::Bool)
    }

    pub fn float() -> Self {
        SlangType::Basic(BasicType::Float)
    }

    pub fn string() -> Self {
        SlangType::Basic(BasicType::String)
    }

    pub fn type_var(type_var: &Rc<TypeVar>) -> Self {
        SlangType::TypeVar(TypeVarRef::new(type_var))
    }

    pub fn into_function_type(self) -> Rc<RefCell<FunctionSignature>> {
        if let SlangType::User(UserType::Function(function_type)) = self {
            function_type
        } else {
            panic!("Expected function type!");
        }
    }

    /// Retrieve a name suitable for name mangling
    #[allow(dead_code)]
    pub fn mangle_name(&self) -> String {
        match self {
            SlangType::Basic(basic_type) => format!("{}", basic_type),
            SlangType::User(user_type) => user_type.mangle_name(),
            other => {
                panic!("Cannot name mangle: {}", other);
            }
        }
    }

    #[allow(dead_code)]
    pub fn is_void(&self) -> bool {
        matches!(self, SlangType::Void)
    }

    pub fn is_type_var(&self) -> bool {
        matches!(self, SlangType::TypeVar(_))
    }

    pub fn is_int(&self) -> bool {
        matches!(self, SlangType::Basic(BasicType::Int))
    }

    pub fn is_float(&self) -> bool {
        matches!(self, SlangType::Basic(BasicType::Float))
    }

    /// Check if this type is a user defined type.
    pub fn is_user(&self) -> bool {
        matches!(self, SlangType::User(_))
    }

    pub fn is_heap_type(&self) -> bool {
        self.is_user() || self.is_type_var()
    }

    pub fn is_enum(&self) -> bool {
        matches!(self, SlangType::User(UserType::Enum(_)))
    }

    pub fn as_enum(&self) -> EnumType {
        if let SlangType::User(UserType::Enum(enum_type)) = self {
            enum_type.clone()
        } else {
            panic!("Expected enum type, but got {}", self);
        }
    }

    pub fn is_struct(&self) -> bool {
        matches!(self, SlangType::User(UserType::Struct(_)))
    }

    /// Narrow the type to struct type.
    pub fn as_struct(&self) -> StructType {
        if let SlangType::User(UserType::Struct(struct_type)) = self {
            struct_type.clone()
        } else {
            panic!("Expected struct type, got {}", self);
        }
    }

    pub fn is_class(&self) -> bool {
        matches!(self, SlangType::User(UserType::Class(_)))
    }

    pub fn as_class(&self) -> ClassType {
        if let SlangType::User(UserType::Class(class_type)) = self {
            class_type.clone()
        } else {
            panic!("Expected class type, but got {}", self);
        }
    }

    #[allow(dead_code)]
    fn get_attr(&self, name: &str) -> Option<Symbol> {
        match self {
            SlangType::User(user_type) => user_type.get_attr(name),
            SlangType::TypeConstructor(type_con) => match type_con.as_ref() {
                SlangType::User(UserType::Enum(_enum_def)) => {
                    // enum_def.upgrade().unwrap().get_attr(name)
                    unimplemented!("TODO?");
                }
                _ => None,
            },
            _ => None,
        }
    }

    /// Try to retrieve an attribute and get its type
    pub fn get_attr_type(&self, name: &str) -> Option<SlangType> {
        match self {
            SlangType::User(user_type) => user_type.get_attr_type(name),
            _ => None,
        }
    }

    pub fn get_method(&self, name: &str) -> Option<Rc<RefCell<FunctionDef>>> {
        match self {
            SlangType::User(user_type) => user_type.get_method(name),
            _ => None,
        }
    }
}

#[derive(Clone, PartialEq, Eq)]
pub struct ArrayType {
    pub element_type: Box<SlangType>,
    pub size: usize,
}
