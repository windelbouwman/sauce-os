//! Various types to describe types in the SLANG lang.
//!

use super::generics::{replace_type_vars_top, GenericDef, TypeVar};
use super::typed_ast;
use super::typed_ast::Definition;
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

    /// Unresolved type
    Unresolved(ast::ObjRef),

    GenericInstance {
        generic: Generic,
        type_parameters: Vec<SlangType>,
    },
}

#[derive(Clone)]
pub struct TypeVarRef {
    pub ptr: Weak<TypeVar>,
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

    Generic(Weak<GenericDef>),
}

impl Generic {
    pub fn get_def(&self) -> Rc<GenericDef> {
        match self {
            Generic::Unresolved(_obj_ref) => {
                panic!("Unresolved generic!");
            }
            Generic::Generic(generic) => generic.upgrade().unwrap(),
        }
    }

    pub fn get_attr(&self, name: &str) -> Option<Symbol> {
        self.get_def().get_attr(name)
    }

    /// Apply types to this generic, creates a new type!
    ///
    /// This is a sort of template instantiation, in that a
    /// new type will be created!
    #[allow(dead_code)]
    pub fn apply(&self, types: &[SlangType]) -> Definition {
        let generic_def = self.get_def();
        generic_def.apply(types)
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
            SlangType::TypeConstructor(typ) => {
                write!(f, "type-con({})", typ)
            }
            SlangType::Opaque => {
                write!(f, "opaque")
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
            } => match generic {
                Generic::Generic(generic_def) => {
                    let generic_def = generic_def.upgrade().unwrap();
                    let bindings: String =
                        if generic_def.type_parameters.len() == type_parameters.len() {
                            let mut bounds: Vec<String> = vec![];
                            for (type_param, typ) in generic_def
                                .type_parameters
                                .iter()
                                .zip(type_parameters.iter())
                            {
                                bounds.push(format!("{}={}", type_param.name, typ));
                            }

                            bounds.join(", ")
                        } else {
                            "mismatched-type-parameters".to_owned()
                        };
                    write!(f, "generic-instance({} [{}])", generic_def.name, bindings)
                }
                Generic::Unresolved(obj_ref) => {
                    write!(f, "generic-instance(unresolved:{:?})", obj_ref)
                }
            },

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

    /// Retrieve attribute from user type.
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
    #[allow(dead_code)]
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

    #[allow(dead_code)]
    pub fn is_void(&self) -> bool {
        matches!(self, SlangType::Void)
    }

    #[allow(dead_code)]
    pub fn is_type_var(&self) -> bool {
        matches!(self, SlangType::TypeVar(_))
    }

    /// Check if this type is a bound generic
    pub fn is_generic_instance(&self) -> bool {
        matches!(self, SlangType::GenericInstance { .. })
    }

    pub fn is_int(&self) -> bool {
        matches!(self, SlangType::Int)
    }

    pub fn is_float(&self) -> bool {
        matches!(self, SlangType::Float)
    }

    /// Check if this type is a user defined type.
    pub fn is_user(&self) -> bool {
        matches!(self, SlangType::User(_))
    }

    pub fn is_heap_type(&self) -> bool {
        self.is_user() || self.is_generic_instance()
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

    #[allow(dead_code)]
    fn get_attr(&self, name: &str) -> Option<Symbol> {
        match self {
            SlangType::User(user_type) => user_type.get_attr(name),
            SlangType::TypeConstructor(type_con) => match type_con.as_ref() {
                SlangType::User(UserType::Enum(enum_def)) => {
                    enum_def.upgrade().unwrap().get_attr(name)
                }
                _ => None,
            },
            _ => None,
        }
    }

    /// Try to retrieve an attribute and get its type
    pub fn get_attr_type(&self, name: &str) -> Option<SlangType> {
        match self {
            SlangType::User(user_type) => user_type.get_attr(name).map(|f| f.get_type()),
            SlangType::GenericInstance {
                generic,
                type_parameters,
            } => {
                if let Some(attr) = generic.get_attr(name) {
                    Some(replace_type_vars_top(
                        &generic.get_def().type_parameters,
                        type_parameters,
                        attr.get_type(),
                    ))
                } else {
                    None
                }
                // Interesting idea: apply types to generic, to create a new typ
                // Use this new type to get the attr.
                // if let Some(field) = generic.get_def().get_attr(name) {
                //     // let def = generic.apply(type_parameters);
                //     // def.get_attr(name)
                //     // field.
                // } else {
                //     None
                // }
            }
            _ => None,
        }
    }

    pub fn get_method(&self, name: &str) -> Option<Rc<RefCell<typed_ast::FunctionDef>>> {
        match self {
            SlangType::User(user_type) => user_type.get_method(name),
            _ => None,
        }
    }

    /// Treat this type as a struct, and retrieve struct fields
    ///
    /// In case of a generic instance, this will replace type variables
    /// with concrete type values.
    pub fn get_struct_fields(&self) -> Option<Vec<(String, SlangType)>> {
        match self {
            SlangType::User(UserType::Struct(struct_ref)) => {
                // Get a firm hold to the struct type:
                let struct_ref = struct_ref.upgrade().unwrap();

                Some(struct_ref.get_struct_fields())
            }
            SlangType::GenericInstance {
                generic,
                type_parameters,
            } => {
                let generic = generic.get_def();

                match &generic.base {
                    typed_ast::Definition::Struct(struct_def) => {
                        let mut fields = vec![];
                        for field in &struct_def.fields {
                            let field_type: SlangType = replace_type_vars_top(
                                &generic.type_parameters,
                                type_parameters,
                                field.borrow().typ.clone(),
                            );
                            fields.push((field.borrow().name.clone(), field_type));
                        }

                        Some(fields)
                    }
                    _other => None,
                }
            }
            _other => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArrayType {
    pub element_type: Box<SlangType>,
    pub size: usize,
}
