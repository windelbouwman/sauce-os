mod generics;
mod scope;
mod symbol;
pub mod type_system;
mod typecheck;
pub mod typed_ast;
mod typed_ast_printer;
// mod visitor;

pub use scope::Scope;
pub use symbol::Symbol;
pub use typecheck::type_check;
pub use typed_ast_printer::print_ast;

use crate::errors::CompilationError;
use crate::parsing::Location;

#[derive(Default)]
pub struct Diagnostics {
    errors: Vec<CompilationError>,
}

impl Diagnostics {
    fn error(&mut self, location: Location, message: String) {
        log::error!("Error: row {}: {}", location.row, message);
        self.errors.push(CompilationError::new(location, message))
    }
}
