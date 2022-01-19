// use std::collections::HashMap;
use std::sync::Arc;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MyType {
    Bool,
    Int,
    Float,
    String,

    /// Type of a type (inception enable=1!)
    Typ,

    /// A parameterized type, may contain subtypes which are type variables.
    Generic {
        base: Box<MyType>,
        type_parameters: Vec<String>,
    },

    TypeVar(String),

    /// A custom defined struct type!
    Struct(StructType),

    Enum(EnumType),

    EnumWithData(EnumType),

    Class(ClassTypeRef),

    Void,

    Function(FunctionType),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FunctionType {
    pub argument_types: Vec<MyType>,
    pub return_type: Option<Box<MyType>>,
}

#[derive(Debug, Clone)]
pub struct ClassTypeRef {
    pub inner: Arc<ClassType>,
}

impl ClassTypeRef {
    pub fn new(inner: ClassType) -> Self {
        Self {
            inner: Arc::new(inner),
        }
    }

    pub fn name(&self) -> &str {
        &self.inner.name
    }

    pub fn lookup(&self, name: &str) -> Option<MyType> {
        self.inner.lookup(name)
    }
}

impl PartialEq for ClassTypeRef {
    fn eq(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.inner, &other.inner)
    }
}

impl Eq for ClassTypeRef {}

// #[derive(Clone)]
pub struct ClassType {
    pub name: String,
    pub fields: Vec<ClassField>,
    pub methods: Vec<ClassField>,
    // tbd?
    // scope: Scope,
}

impl std::fmt::Debug for ClassType {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        f.debug_struct("Class").field("name", &self.name).finish()
    }
}

#[derive(Debug, Clone)]
pub struct ClassField {
    pub name: String,
    pub typ: MyType,
}

impl ClassType {
    pub fn lookup(&self, name: &str) -> Option<MyType> {
        // TBD: linear search is a bad idea.
        for field in &self.fields {
            if field.name == name {
                return Some(field.typ.clone());
            }
        }
        for field in &self.methods {
            if field.name == name {
                return Some(field.typ.clone());
            }
        }
        None
    }

    pub fn index_of(&self, name: &str) -> Option<usize> {
        for (index, field) in self.fields.iter().enumerate() {
            if field.name == name {
                return Some(index);
            }
        }
        None
    }

    /// Create a funky constructor name
    pub fn ctor_func_name(&self) -> String {
        format!("{}_ctor", self.name)
    }
}

/// A custom defined struct type!
#[derive(Clone, PartialEq, Eq)]
pub struct StructType {
    pub name: Option<String>,
    pub fields: Vec<StructField>,
}

impl std::fmt::Debug for StructType {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        f.debug_struct("Struct").field("name", &self.name).finish()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StructField {
    pub name: String,
    pub typ: MyType,
}

impl StructType {
    pub fn get_field(&self, name: &str) -> Option<MyType> {
        for field in &self.fields {
            if field.name == name {
                return Some(field.typ.clone());
            }
        }
        None
    }

    pub fn index_of(&self, name: &str) -> Option<usize> {
        for (index, field) in self.fields.iter().enumerate() {
            if field.name == name {
                return Some(index);
            }
        }
        None
    }
}

#[derive(Clone, PartialEq, Eq)]
pub struct EnumType {
    pub name: String,
    pub options: Vec<EnumOption>,
}

impl EnumType {
    pub fn lookup(&self, name: &str) -> Option<&EnumOption> {
        for option in &self.options {
            if option.name == name {
                return Some(option);
            }
        }
        None
    }
}

impl std::fmt::Debug for EnumType {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        f.debug_struct("EnumType")
            .field("name", &self.name)
            .finish()
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EnumOption {
    pub name: String,
    pub data: Vec<MyType>,
}
