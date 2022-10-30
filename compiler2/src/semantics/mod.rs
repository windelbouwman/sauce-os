/* Ideas:

Phase 1:
- Translate ast into typed_ast.
- Fill scopes with symbols.

Phase 2:
- Resolve symbols

Phase 3:
- Type check

*/

// mod generics;
mod analysis;
mod context;
mod diagnostics;
mod enum_type;
mod fillscope;
mod id_generator;
mod namebinding;
mod phase5_desugar;
mod scope;
mod symbol;
pub mod type_system;
mod typechecker;
pub mod typed_ast;
mod typed_ast_printer;
use std::cell::RefCell;
use std::rc::Rc;
mod visitor;

pub use context::Context;
pub use typed_ast::NodeId;
use typed_ast::Ref;

/// Refer to the given reference
pub fn refer<'t, T>(r: &'t Ref<T>) -> Rc<RefCell<T>> {
    r.upgrade().unwrap()
}

pub use diagnostics::Diagnostics;
pub use scope::Scope;
pub use symbol::Symbol;
pub use typed_ast_printer::print_ast;

// phased type checker:
pub use analysis::analyze;
