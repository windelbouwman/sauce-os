// use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum MyType {
    Bool,
    Int,
    Float,
    String,

    /// A parameterized type, may contain subtypes which are type variables.
    Generic {
        base: Box<MyType>,
        type_parameters: Vec<String>,
    },

    TypeVar(String),

    /// A custom defined struct type!
    Struct(StructType),

    /// Type of a type (inception enable=1!)
    // Typ,
    Void,
    Function {
        argument_types: Vec<MyType>,
        return_type: Option<Box<MyType>>,
    },
}

/// A custom defined struct type!
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct StructType {
    pub name: Option<String>,
    pub fields: Vec<StructField>,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
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
