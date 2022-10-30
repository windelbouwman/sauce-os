use super::ast;
use super::lexing::{Lexer, LexicalError};
use super::location::Location;
use super::token;
use crate::errors::CompilationError;
use token::Token;

use lalrpop_util::lalrpop_mod;

lalrpop_mod!(
    #[allow(clippy::all)]
    funky,
    "/parsing/grammar.rs"
);

pub fn parse_file(path: &std::path::Path) -> Result<ast::Program, CompilationError> {
    log::info!("Parsing {}", path.display());
    let source = std::fs::read_to_string(path).map_err(|err| {
        CompilationError::simple(format!("Error opening {}: {}", path.display(), err))
    })?;

    let lexer = Lexer::new(&source);

    let mut prog = funky::ProgramParser::new()
        .parse(lexer)
        .map_err(|e| create_error(path, e))?;

    // Determine module name by base filename.
    let modname: String = path.file_stem().unwrap().to_str().unwrap().to_owned();
    prog.name = modname;
    prog.path = path.to_owned();

    log::debug!("Parsing done&done");
    Ok(prog)
}

fn create_error(
    path: &std::path::Path,
    err: lalrpop_util::ParseError<Location, Token, LexicalError>,
) -> CompilationError {
    let path = path.to_owned();
    match err {
        lalrpop_util::ParseError::UnrecognizedEOF { location, expected } => {
            CompilationError::new(path, location, format!("Expected: {}", expected.join(", ")))
        }
        lalrpop_util::ParseError::InvalidToken { location } => {
            CompilationError::new(path, location, "Invalid token".to_string())
        }
        lalrpop_util::ParseError::ExtraToken { token } => {
            CompilationError::new(path, token.0, format!("Invalid token: {:?}", token.1))
        }
        lalrpop_util::ParseError::User { error } => {
            CompilationError::new(path, error.location, error.message)
        }
        lalrpop_util::ParseError::UnrecognizedToken { token, expected } => CompilationError::new(
            path,
            token.0,
            format!("Got {:?}, expected: {}", token.1, expected.join(", ")),
        ),
    }
}
