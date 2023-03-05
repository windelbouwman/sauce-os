use super::{get_substitution_map, refer, replace_type_vars_sub, NameNodeId, NodeId, TypeVar};
use super::{Block, Ref, Scope, SlangType, UserType};
use crate::parsing::Location;
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::Arc;

/// A function definition.
///
/// Function definition, including:
/// - name
/// - type parameters
/// - parameters
/// - local variables
/// - actual code.
pub struct FunctionDef {
    pub name: NameNodeId,
    pub location: Location,
    pub type_parameters: Vec<Rc<TypeVar>>,
    pub signature: Rc<RefCell<FunctionSignature>>,
    pub this_param: Option<Rc<RefCell<Parameter>>>,
    pub scope: Arc<Scope>,
    pub locals: Vec<Rc<RefCell<LocalVariable>>>,
    pub body: Block,
}

impl FunctionDef {
    pub fn get_type(&self) -> SlangType {
        SlangType::User(UserType::Function(self.signature.clone()))
    }
}

/// A function signature.
pub struct FunctionSignature {
    pub parameters: Vec<Rc<RefCell<Parameter>>>,
    pub return_type: Option<SlangType>,
}

impl FunctionSignature {
    /// Check if the types of signatures are equal
    pub fn compatible_signature(&self, other: &Self) -> bool {
        if self.parameters.len() != other.parameters.len() {
            return false;
        }

        for (p1, p2) in self.parameters.iter().zip(other.parameters.iter()) {
            if p1.borrow().typ != p2.borrow().typ {
                return false;
            }
        }
        self.return_type == other.return_type
    }
}

/// Reference to a function, including type arguments.
pub enum Function {
    InternFunction {
        function_ref: Ref<FunctionDef>,
        type_arguments: Vec<SlangType>,
    },
    ExternFunction {
        name: String,
        typ: SlangType,
    },
}

impl Function {
    /// Get function signature
    pub fn get_type(&self) -> SlangType {
        match self {
            Function::InternFunction {
                function_ref,
                type_arguments,
            } => {
                // The below code should be reduced...

                let function_def = refer(function_ref);
                let function_def2 = function_def.borrow();

                // apply type arguments!
                let subs_map = get_substitution_map(&function_def2.type_parameters, type_arguments);

                let signature = function_def2.signature.borrow();
                // let signature = signature2.borrow();
                let mut new_parameters = vec![];
                for parameter in &signature.parameters {
                    let parameter = parameter.borrow();
                    let p2 = Parameter {
                        location: parameter.location.clone(),
                        name: parameter.name.clone(),
                        typ: replace_type_vars_sub(parameter.typ.clone(), &subs_map),
                    };
                    new_parameters.push(Rc::new(RefCell::new(p2)));
                }

                let return_type = signature
                    .return_type
                    .as_ref()
                    .map(|t| replace_type_vars_sub(t.clone(), &subs_map));

                let new_signature = Rc::new(RefCell::new(FunctionSignature {
                    parameters: new_parameters,
                    return_type: return_type,
                }));

                SlangType::User(UserType::Function(new_signature))
            }
            Function::ExternFunction { name: _, typ } => typ.clone(),
        }
    }

    pub fn get_original_signature(&self) -> Rc<RefCell<FunctionSignature>> {
        match self {
            Function::InternFunction {
                function_ref,
                type_arguments: _,
            } => {
                let ref1 = refer(function_ref);
                let ref2 = ref1.borrow();
                ref2.signature.clone()
            }
            Function::ExternFunction { name: _, typ } => {
                let signature = typ.clone().into_function_type();
                signature
            }
        }
    }
}

pub struct LocalVariable {
    pub location: Location,
    pub mutable: bool,
    pub name: NameNodeId,
    pub typ: SlangType,
}

impl LocalVariable {
    pub fn new(location: Location, mutable: bool, name: String, id: NodeId) -> Self {
        Self {
            location,
            mutable,
            name: NameNodeId { name, id },
            typ: SlangType::Undefined,
        }
    }
}

pub struct Parameter {
    /// The place where this parameter was defined.
    pub location: Location,

    /// The name of the parameter
    pub name: NameNodeId,
    pub typ: SlangType,
}
