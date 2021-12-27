// use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum MyType {
    Bool,
    Int,
    Float,
    String,

    /// A custom defined struct type!
    Struct(StructType),

    /// Type of a type (inception enable=1!)
    // Typ,
    Void,
    Function {
        argument_types: Vec<MyType>,
        return_type: Option<Box<MyType>>,
    },

    Module,
}

impl MyType {
    pub fn new_struct(fields: Vec<(String, MyType)>) -> Self {
        MyType::Struct(StructType { name: None, fields })
    }
}

/// A custom defined struct type!
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct StructType {
    pub name: Option<String>,
    pub fields: Vec<(String, MyType)>,
}

impl StructType {
    pub fn get_field(&self, name: &str) -> Option<MyType> {
        for field in &self.fields {
            if field.0 == name {
                return Some(field.1.clone());
            }
        }
        None
    }

    pub fn index_of(&self, name: &str) -> Option<usize> {
        for (index, field) in self.fields.iter().enumerate() {
            if field.0 == name {
                return Some(index);
            }
        }
        None
    }
}
