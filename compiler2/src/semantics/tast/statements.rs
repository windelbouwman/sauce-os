//! Language statement representations.
//!

use super::Scope;
use super::{Block, EnumVariant, Expression, LocalVariable, Ref, SlangType, VariantRef};
use crate::parsing::Location;
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::Arc;

#[derive(Debug)]
pub struct Statement {
    pub location: Location,
    pub kind: StatementKind,
}

#[derive(Debug)]
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

#[derive(Debug)]
pub struct SwitchStatement {
    pub value: Expression,
    pub arms: Vec<SwitchArm>,
    pub default: Block,
}
#[derive(Debug)]
pub struct SwitchArm {
    pub value: Expression,

    /// The code of this case arm.
    pub body: Block,
}

#[derive(Debug)]
pub struct AssignmentStatement {
    pub target: Expression,
    pub value: Expression,
}

#[derive(Debug)]
pub struct IfStatement {
    pub condition: Expression,
    pub if_true: Block,
    pub if_false: Option<Block>,
}

#[derive(Debug)]
pub struct WhileStatement {
    pub condition: Expression,
    pub body: Block,
}

#[derive(Debug, Default)]
pub struct ForStatement {
    pub loop_var: Ref<LocalVariable>,
    pub iterable: Expression,
    pub body: Block,
}

#[derive(Debug, Default)]
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
            other => {
                panic!("Arm constructor contains no variant, but {:?}", other);
            }
        }
    }
}

impl std::fmt::Debug for CaseArm {
    fn fmt(&self, fmt: &mut std::fmt::Formatter) -> std::fmt::Result {
        fmt.debug_struct("CaseArm")
            .field("location", &self.location)
            .field("variant", &self.variant)
            .field("local_refs", &self.local_refs)
            .finish()
    }
}
