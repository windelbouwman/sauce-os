//! Program transformation.
//!
//! This module contain logic to transform complex TAST into simpler TAST.
//!
//! Example transformations:
//! - Rewrite enums into tagged unions
//! - Rewrite classes into structs and functions
//! - Turn for-loops into while loops.

mod rewriting;
mod rewriting_classes;
mod rewriting_enums;
mod rewriting_for_loop;
mod rewriting_generics;

pub use rewriting::transform;
