use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq)]
pub enum MyType {
    Int,
    Float,
    String,

    /// Type of a type (inception enable=1!)
    // Typ,
    Void,
    Function {
        argument_types: Vec<MyType>,
        return_type: Option<Box<MyType>>,
    },
    Module {
        exposed: HashMap<String, MyType>,
    },
}

// impl MyType {
//     /// Type equality checking!
//     pub fn equals(&self, other: &Self) -> bool {
//         match self {
//             MyType::Int => {
//                 if let MyType::Int = other {
//                     true
//                 } else {
//                     false
//                 }
//             }
//             MyType::Float => {
//                 if let MyType::Float = other {
//                     true
//                 } else {
//                     false
//                 }
//             }
//             MyType::String => {
//                 if let MyType::String = other {
//                     true
//                 } else {
//                     false
//                 }
//             }
//             MyType::Module => {
//                 // TODO?
//                 true
//             }
//             MyType::Function {
//                 argument_types,
//                 return_type,
//             } => {
//                 if let MyType::Function {
//                     argument_types: argument_types2,
//                     return_type: return_type2,
//                 } = other
//                 {
//                     if (argument_types.len() == argument_types2.len())
//                         && return_type.equals(return_type2)
//                     {
//                         for (a1, a2) in argument_types.iter().zip(argument_types2.iter()) {
//                             if !a1.equals(a2) {
//                                 return false;
//                             }
//                         }
//                         true
//                     } else {
//                         false
//                     }
//                 } else {
//                     false
//                 }
//             }
//         }
//     }
// }
