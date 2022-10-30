use crate::parsing::Location;

#[derive(Debug)]
pub enum CompilationError {
    SingleError {
        path: std::path::PathBuf,
        location: Location,
        message: String,
    },
    MultiError(Vec<CompilationError>),
    Simple(String),
}

impl CompilationError {
    pub fn simple(message: String) -> Self {
        Self::Simple(message)
    }

    pub fn new(path: std::path::PathBuf, location: Location, message: String) -> Self {
        CompilationError::SingleError {
            path,
            location,
            message,
        }
    }

    pub fn multi(errors: Vec<CompilationError>) -> Self {
        CompilationError::MultiError(errors)
    }
}

/// Output error in somewhat user friendly way
pub fn print_error(error: CompilationError) {
    match error {
        CompilationError::SingleError {
            path,
            location,
            message,
        } => {
            // log::error!("{},{}: {}", location.row, location.column, message);
            println!(
                "********************* ERROR: [{}] *********************",
                path.display()
            );
            let source = std::fs::read_to_string(path).unwrap();
            let err_row = location.row as usize;
            let err_column = location.column as usize;
            let n_context = 5;
            for (row, line) in source.split('\n').enumerate() {
                let row = row + 1;
                if (row + n_context > err_row) && (row < err_row + n_context) {
                    println!("{:>5}: {}", row, line);
                }
                if row == err_row as usize {
                    let padding = " ".repeat(err_column + 6);
                    println!("{}^", padding);
                    println!("{}|", padding);
                    println!("{}+----  {}", padding, message);
                }
            }
        }
        CompilationError::MultiError(errors) => {
            for error in errors {
                print_error(error);
            }
        }
        CompilationError::Simple(message) => {
            println!("Error: {}", message);
        }
    }
}
