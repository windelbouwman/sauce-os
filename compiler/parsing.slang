
import ast
import std
from lexer import Lexer
from token import to_string
from location import Location, new_location
from datatypes import List, Result


struct CompilationError:
    location: Location
    message: str

fn new_error(location: Location, message: str) -> CompilationError:
    let e = CompilationError:
        location: location
        message: message
    return e

fn parse_source(filename: str) -> Result[ast.Module,CompilationError]:
    let source = std::read_file(filename)

    if false:
        std::print("Source-code")
        std::print("===============")
        std.print(source)
        std::print("===============")

    let parser = Parser()
    parser.feed(source)

    return parser.parse_module()
    

class Parser:
    # An attempt at a recursive descent parser.
    var lex: Lexer = Lexer()

    fn feed(source: str):
        this.lex.init(source)
    
    fn parse_module() -> Result[ast.Module,CompilationError]:
        let definitions = List()
        # let imports = List()

        loop:
            case this.lex.next_token():
                None:
                    # We are done!
                    break
                Some(tok):
                    case tok.kind:
                        KwImport:
                            this.parse_import(tok.location)
                        KwFn:
                            let func_def = this.parse_func_def(tok.location)
                        String(txt):
                            let n = ast.string_literal(txt, tok.location)
                            ast.print_expr(n)
                    else:
                        return Result.Error(new_error(tok.location, "Unexpected token: {to_string(tok)}"))
                        # std::print(to_string(tok))

        let program = ast::Module:
            name: "FUU"
            definitions: definitions
        
        return Result::Ok(program)

    fn parse_import(location: Location):
        let name = this.lex.next_token() # id
        # TODO: how to check?
        let x = this.lex.next_token() # newline

    fn parse_func_def(location: Location) -> Result[ast.FunctionDef, CompilationError]:
        
        # ID:
        let name = "?"
        case this.lex.next_token():
            None:
                return Result::Error(new_error(new_location(9999, 1), "Expected name"))
            Some(tok):
                case tok.kind:
                    Identifier(txt):
                        name = txt
                else:
                    return Result::Error(new_error(tok.location, "Expected name"))

        # TODO: parameters!
        # Body
        case this.parse_block():
            Ok(body):
                return Result.Ok(ast.function_def(name, body, location))
            Error(error):
                return Result.Error(error)

    fn parse_block() -> Result[ast.Statement, CompilationError]:
        # parse block of statements.
        # expect indent
        let location = new_location(1, 1)
        # indent:
        case this.lex.next_token():
            None:
                return Result::Error(new_error(new_location(9999, 1), "Expected indent"))
            Some(tok):
                case tok.kind:
                    Indent:
                        location = tok.location
                else:
                    return Result::Error(new_error(tok.location, "Expected indent"))


        let inner: List[ast.Statement] = List()

        loop:
            case this.parse_statement():
                Ok(statement):
                    inner.append(statement)
                Error(error):
                    return Result.Error(error)
            break

        # expect dedent
        case this.lex.next_token():
            None:
                return Result::Error(new_error(new_location(9999, 1), "Expected dedent"))
            Some(tok):
                case tok.kind:
                    Dedent:
                        pass
                else:
                    return Result::Error(new_error(tok.location, "Expected dedent"))

        return Result.Ok(ast.compound(inner, location))
    
    fn parse_statement() -> Result[ast.Statement, CompilationError]:
        case this.lex.next_token():
            None:
                return Result::Error(new_error(new_location(9999, 1), "Expected some statement"))
            Some(tok):
                case tok.kind:
                    KwPass:
                        return Result.Ok(ast.statement(ast::StatementKind::Pass(), tok.location))
                else:
                    return Result::Error(new_error(tok.location, "Unexpected token"))
    
    fn parse_expression() -> Result[ast.Expression, CompilationError]:
        pass


