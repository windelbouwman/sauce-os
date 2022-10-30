use crate::errors::CompilationError;
use crate::parsing::Location;

pub struct Diagnostics {
    errors: Vec<CompilationError>,
    path: std::path::PathBuf,
}

impl Diagnostics {
    pub fn new(path: &std::path::Path) -> Self {
        Self {
            errors: vec![],
            path: path.to_owned(),
        }
    }

    pub fn error(&mut self, location: Location, message: String) {
        log::error!("Error: row {}: {}", location.row, message);
        self.errors
            .push(CompilationError::new(self.path.clone(), location, message))
    }

    pub fn value_or_error<T>(self, value: T) -> Result<T, CompilationError> {
        if self.errors.is_empty() {
            Ok(value)
        } else {
            Err(CompilationError::multi(self.errors))
        }
    }
}
