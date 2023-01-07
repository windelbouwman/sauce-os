//! Semantic phase.
//!
//! Phase 1: fillscrope.rs
//! - Translate ast into typed_ast.
//! - Fill scopes with symbols.
//!
//! Phase 2: namebinding.rs
//! - Resolve symbols
//!
//! Phase 3: pass2.rs
//! - Evaluate type expressions
//!
//! Phase 4: typechecker.rs
//! - Type check

mod analysis;
mod context;
mod diagnostics;
mod fillscope;
mod id_generator;
mod namebinding;
mod pass2;
mod phase5_desugar;
mod typechecker;

pub use context::Context;

pub use diagnostics::Diagnostics;

// phased type checker:
pub use analysis::analyze;
pub use typechecker::check_types;
