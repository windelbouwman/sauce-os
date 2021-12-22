use super::ast;
use super::lexing::{Lexer, LexicalError};
use super::token;
use crate::errors::CompilationError;
use token::{Location, Token};

use lalrpop_util::lalrpop_mod;

lalrpop_mod!(
    #[allow(clippy::all)]
    funky,
    "/parsing/grammar.rs"
);

pub fn parse_src(source: &str) -> Result<ast::Program, CompilationError> {
    let lexer = Lexer::new(&source);

    let prog = funky::ProgramParser::new().parse(lexer)?;
    Ok(prog)
}

impl From<lalrpop_util::ParseError<Location, Token, LexicalError>> for CompilationError {
    fn from(err: lalrpop_util::ParseError<Location, Token, LexicalError>) -> Self {
        match err {
            lalrpop_util::ParseError::UnrecognizedEOF { location, expected } => {
                CompilationError::new(location, format!("Expected: {}", expected.join(", ")))
            }
            lalrpop_util::ParseError::InvalidToken { location } => {
                CompilationError::new(location, "Invalid token".to_string())
            }
            lalrpop_util::ParseError::ExtraToken { token } => {
                CompilationError::new(token.0, format!("Invalid token: {:?}", token.1))
            }
            lalrpop_util::ParseError::User { error } => {
                CompilationError::new(error.location, error.message)
            }
            lalrpop_util::ParseError::UnrecognizedToken { token, expected } => {
                CompilationError::new(
                    token.0,
                    format!("Got {:?}, expected: {}", token.1, expected.join(", ")),
                )
            }
        }
    }
}
