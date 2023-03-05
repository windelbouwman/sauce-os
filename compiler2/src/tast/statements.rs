//! Language statement representations.
//!

use super::Scope;
use super::{EnumVariant, Expression, LocalVariable, Ref, SlangType, VariantRef};
use crate::parsing::Location;
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::Arc;

pub type Block = Vec<Statement>;

/// A single statement.
pub struct Statement {
    pub location: Location,
    pub kind: StatementKind,
}

pub enum StatementKind {
    Expression(Expression),
    Let {
        local_ref: Ref<LocalVariable>,
        type_hint: Option<SlangType>,
        value: Expression,
    },
    Assignment(AssignmentStatement),
    StoreLocal {
        local_ref: Ref<LocalVariable>,
        value: Expression,
    },

    SetAttr {
        base: Expression,
        attr: String,
        value: Expression,
    },

    SetIndex {
        base: Box<Expression>,
        index: Box<Expression>,
        value: Expression,
    },

    If(IfStatement),
    Loop {
        body: Block,
    },
    While(WhileStatement),
    For(ForStatement),
    Return {
        value: Option<Expression>,
    },
    Case(CaseStatement),
    Switch(SwitchStatement),
    Compound(Block),
    Pass,
    Break,
    Continue,

    /// Marker statement which cannot be reached!
    Unreachable,
}

impl StatementKind {
    pub fn into_statement(self) -> Statement {
        Statement {
            location: Default::default(),
            kind: self,
        }
    }
}

/// A switch statement
///
/// Switch chooses an arm based on an integer value
pub struct SwitchStatement {
    pub value: Expression,
    pub arms: Vec<SwitchArm>,
    pub default: Block,
}

pub struct SwitchArm {
    pub value: Expression,

    /// The code of this case arm.
    pub body: Block,
}

pub struct AssignmentStatement {
    pub target: Expression,
    pub value: Expression,
}

pub struct IfStatement {
    pub condition: Expression,
    pub if_true: Block,
    pub if_false: Option<Block>,
}

pub struct WhileStatement {
    pub condition: Expression,
    pub body: Block,
}

#[derive(Default)]
pub struct ForStatement {
    pub loop_var: Ref<LocalVariable>,
    pub iterable: Expression,
    pub body: Block,
}

#[derive(Default)]
pub struct CaseStatement {
    pub value: Expression,
    pub arms: Vec<CaseArm>,
}

pub struct CaseArm {
    pub location: Location,

    /// Index into the chosen enum variant:
    pub variant: VariantRef,

    /// Id's of local variables used for this arms unpacked values
    pub local_refs: Vec<Ref<LocalVariable>>,

    pub scope: Arc<Scope>,

    /// The code of this case arm.
    pub body: Block,
}

impl CaseArm {
    pub fn get_variant(&self) -> Rc<RefCell<EnumVariant>> {
        match &self.variant {
            // ExpressionKind::TypeConstructor(TypeConstructor::EnumVariant(variant))
            // |
            VariantRef::Variant(variant) => variant.upgrade().unwrap(),
            VariantRef::Name(name) => {
                panic!("Arm constructor contains no variant, but {}", name);
            }
        }
    }
}
