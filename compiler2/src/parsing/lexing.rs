use super::token::{Location, Token};
use logos::Logos;

/// Remove leading and trailing double quotes from string
fn strip_quotes(txt: &str) -> String {
    let mut txt: String = txt.to_owned();
    txt.pop();
    txt.remove(0);
    txt
}

#[derive(Logos)]
enum LogosToken {
    #[regex("[a-zA-Z][a-zA-Z0-9_]*", |x| x.slice().to_string())]
    Identifier(String),

    #[regex("[0-9]+", |x| x.slice().to_string())]
    Number(String),

    #[regex(r"[0-9]+\.[0-9]+", |x| x.slice().to_string())]
    FloatingPoint(String),

    #[regex(r#""[^"]*""#, |x| strip_quotes(x.slice()))]
    String(String),

    #[token(":")]
    Colon,

    #[token(".")]
    Dot,

    #[token(",")]
    Comma,

    #[token("+")]
    Plus,

    #[token("-")]
    Minus,

    #[token("*")]
    Asterix,

    #[token("/")]
    Slash,

    #[token("<")]
    Less,

    #[token("<=")]
    LessEqual,

    #[token(">")]
    Greater,

    #[token(">=")]
    GreaterEqual,

    #[token("==")]
    DoubleEqual,

    #[token("=")]
    Equal,

    #[token("!=")]
    NotEqual,

    #[token("->")]
    Arrow,

    #[token("(")]
    OpeningParenthesis,

    #[token(")")]
    ClosingParenthesis,

    #[token(r"{")]
    OpeningBrace,

    #[token(r"}")]
    ClosingBrace,

    #[token("\n")]
    NewLine,

    #[regex(r#"#[^\n]*"#, |x| x.slice().to_owned())]
    Comment(String),

    #[regex(" +", |x| x.slice().len())]
    WhiteSpace(usize),

    #[error]
    Error,
}
type Spanned<Tok, Error> = Result<(Location, Tok, Location), Error>;

#[derive(Debug)]
pub struct LexicalError {
    pub location: Location,
    pub message: String,
}

pub struct Lexer<'t> {
    inner: logos::Lexer<'t, LogosToken>,
    pending: Vec<(Location, Token, Location)>,
    spaces: usize,
    row: usize,
    row_start: usize,
    at_end: bool,
    at_bol: bool,
    indentations: Vec<usize>,
}

impl<'t> Lexer<'t> {
    pub fn new(source: &'t str) -> Self {
        let inner = logos::Lexer::new(source);
        let pending = vec![];
        Lexer {
            inner,
            pending,
            row: 1,
            row_start: 0,
            spaces: 0,
            at_end: false,
            at_bol: true,
            indentations: vec![0],
        }
    }

    fn emit(&mut self, token: Token) {
        if self.at_bol {
            self.at_bol = false;
            self.update_indentation(self.spaces);
        }
        self.emit_spanned(token, self.inner.span());
    }

    fn emit_spanned(&mut self, token: Token, span: logos::Span) {
        let spanned = (
            self.get_location(span.start),
            token,
            self.get_location(span.end),
        );
        self.pending.push(spanned);
    }

    fn update_indentation(&mut self, new_level: usize) {
        let mut current_level: usize = *self.indentations.last().unwrap();
        let location = Location {
            row: self.row as i32,
            column: 1,
        };
        if new_level > current_level {
            // Indent
            self.indentations.push(new_level);
            self.pending
                .push((location.clone(), Token::Indent, location));
        } else if new_level < current_level {
            // Dedent (maybe more than once)
            while new_level < current_level {
                self.pending
                    .push((location.clone(), Token::Dedent, location.clone()));
                self.indentations.pop();
                current_level = *self.indentations.last().unwrap();
            }

            assert_eq!(new_level, current_level);
        }
    }

    fn get_location(&self, offset: usize) -> Location {
        let row = self.row as i32;
        let column = (offset + 1 - self.row_start) as i32;
        Location { row, column }
    }

    fn process(&mut self) -> Result<(), LexicalError> {
        let tok = self.inner.next();
        match tok {
            Some(tok) => self.process2(tok)?,
            None => {
                // Mark the end:
                self.at_end = true;

                let location = Location {
                    row: self.row as i32,
                    column: 1,
                };

                if !self.at_bol {
                    self.pending
                        .push((location.clone(), Token::Newline, location.clone()));
                }

                // Flush indentation levels
                while self.indentations.len() > 1 {
                    self.pending
                        .push((location.clone(), Token::Dedent, location.clone()));
                    self.indentations.pop();
                }
            }
        };
        Ok(())
    }

    fn process2(&mut self, tok: LogosToken) -> Result<(), LexicalError> {
        match tok {
            LogosToken::Identifier(name) => match name.as_str() {
                "and" => self.emit(Token::KeywordAnd),
                "break" => self.emit(Token::KeywordBreak),
                "continue" => self.emit(Token::KeywordContinue),
                "else" => self.emit(Token::KeywordElse),
                "false" => self.emit(Token::KeywordFalse),
                "fn" => self.emit(Token::KeywordFn),
                "for" => self.emit(Token::KeywordFor),
                "if" => self.emit(Token::KeywordIf),
                "import" => self.emit(Token::KeywordImport),
                "loop" => self.emit(Token::KeywordLoop),
                "let" => self.emit(Token::KeywordLet),
                "mut" => self.emit(Token::KeywordMut),
                "or" => self.emit(Token::KeywordOr),
                "pass" => self.emit(Token::KeywordPass),
                "pub" => self.emit(Token::KeywordPub),
                "return" => self.emit(Token::KeywordReturn),
                "struct" => self.emit(Token::KeywordStruct),
                "true" => self.emit(Token::KeywordTrue),
                "while" => self.emit(Token::KeywordWhile),
                other => {
                    self.emit(Token::Identifier {
                        value: other.to_owned(),
                    });
                }
            },
            LogosToken::Number(value) => {
                use std::str::FromStr;
                let value: i64 = i64::from_str(&value).unwrap();
                self.emit(Token::Number { value });
            }
            LogosToken::FloatingPoint(value) => {
                use std::str::FromStr;
                let value: f64 = f64::from_str(&value).unwrap();
                self.emit(Token::FloatingPoint { value });
            }
            LogosToken::String(value) => {
                self.emit(Token::String { value });
            }
            LogosToken::Arrow => {
                self.emit(Token::Arrow);
            }
            LogosToken::Colon => {
                self.emit(Token::Colon);
            }
            LogosToken::Dot => {
                self.emit(Token::Dot);
            }
            LogosToken::Comma => {
                self.emit(Token::Comma);
            }
            LogosToken::Plus => {
                self.emit(Token::Plus);
            }
            LogosToken::Minus => {
                self.emit(Token::Minus);
            }
            LogosToken::Asterix => {
                self.emit(Token::Asterix);
            }
            LogosToken::Slash => {
                self.emit(Token::Slash);
            }
            LogosToken::Less => {
                self.emit(Token::Less);
            }
            LogosToken::LessEqual => {
                self.emit(Token::LessEqual);
            }
            LogosToken::Greater => {
                self.emit(Token::Greater);
            }
            LogosToken::GreaterEqual => {
                self.emit(Token::GreaterEqual);
            }
            LogosToken::Equal => {
                self.emit(Token::Equal);
            }
            LogosToken::NotEqual => {
                self.emit(Token::NotEqual);
            }
            LogosToken::DoubleEqual => {
                self.emit(Token::DoubleEqual);
            }
            LogosToken::OpeningParenthesis => {
                self.emit(Token::OpeningParenthesis);
            }
            LogosToken::ClosingParenthesis => {
                self.emit(Token::ClosingParenthesis);
            }
            LogosToken::OpeningBrace => {
                self.emit(Token::OpeningBrace);
            }
            LogosToken::ClosingBrace => {
                self.emit(Token::ClosingBrace);
            }
            LogosToken::NewLine => self.newline(),
            LogosToken::Comment(value) => {
                log::debug!("Comment: '{}'", value);
            }
            LogosToken::WhiteSpace(amount) => {
                if self.at_bol {
                    self.spaces += amount;
                }
            }
            LogosToken::Error => {
                return Err(self.error("Oh no, unknown character!".to_owned()));
            }
        }

        Ok(())
    }

    fn error(&self, message: String) -> LexicalError {
        let span = self.inner.span();
        let location = self.get_location(span.start);
        LexicalError { location, message }
    }

    fn newline(&mut self) {
        if !self.at_bol {
            self.emit(Token::Newline);
        }
        self.spaces = 0;
        self.at_bol = true;
        self.row_start = self.inner.span().end;
        self.row += 1;
    }
}

impl<'t> std::iter::Iterator for Lexer<'t> {
    type Item = Spanned<Token, LexicalError>;

    fn next(&mut self) -> Option<Self::Item> {
        while self.pending.is_empty() && !self.at_end {
            if let Err(err) = self.process() {
                return Some(Err(err));
            }
        }

        if self.pending.is_empty() {
            None
        } else {
            Some(Ok(self.pending.remove(0)))
        }
    }
}
