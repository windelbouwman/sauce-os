//! A typed version of the AST.
//!
//! Expressions are assigned types here.
//!
//! This intermediate form has most language
//! constructs, and types attached.

use super::{Definition, EnumVariant, Ref, Scope};
use std::sync::Arc;

pub struct Program {
    pub name: String,
    pub path: std::path::PathBuf,
    pub scope: Arc<Scope>,
    pub definitions: Vec<Definition>,
}

pub enum VariantRef {
    Name(String),
    Variant(Ref<EnumVariant>),
}
