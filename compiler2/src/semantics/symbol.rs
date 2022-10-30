//! Representation of a symbol.
//!
//! Symbols can refer to variables, parameters, functions etc..
//!

use super::type_system::SlangType;
use super::typed_ast;
use super::Ref;

use std::rc::Rc;

#[derive(Debug, Clone)]
pub enum Symbol {
    Typ(SlangType),
    Function {
        func_ref: Ref<typed_ast::FunctionDef>,
    },
    ExternFunction {
        name: String,
        typ: SlangType,
    },
    // Class {
    //     node_id: NodeId,
    // },
    Module {
        module_ref: Rc<typed_ast::Program>,
    },
    Parameter {
        param_ref: Ref<typed_ast::Parameter>,
    },
    LocalVariable {
        local_ref: Ref<typed_ast::LocalVariable>,
    },
    Field {
        field_ref: Ref<typed_ast::FieldDef>,
    },

    EnumVariant(Ref<typed_ast::EnumVariant>),
}
