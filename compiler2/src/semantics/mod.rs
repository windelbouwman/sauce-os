mod scope;
pub mod type_system;
mod typecheck;
pub mod typed_ast;
mod typed_ast_printer;

pub use scope::{Scope, Symbol};
pub use typecheck::type_check;
pub use typed_ast_printer::print_ast;
