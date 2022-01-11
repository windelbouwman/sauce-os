// use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MyType {
    Bool,
    Int,
    Float,
    String,

    Typ,

    /// A parameterized type, may contain subtypes which are type variables.
    Generic {
        base: Box<MyType>,
        type_parameters: Vec<String>,
    },

    TypeVar(String),

    /// A custom defined struct type!
    Struct(StructType),

    Class(ClassType),

    /// Type of a type (inception enable=1!)
    // Typ,
    Void,
    Function {
        argument_types: Vec<MyType>,
        return_type: Option<Box<MyType>>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClassType {
    pub name: String,
    pub fields: Vec<ClassField>,
    pub methods: Vec<ClassField>,
    // tbd?
    // scope: Scope,
}

#[derive(Debug, Clone, PartialEq, Eq)]
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
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StructType {
    pub name: Option<String>,
    pub fields: Vec<StructField>,
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
