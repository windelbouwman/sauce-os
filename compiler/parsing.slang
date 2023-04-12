
import ast
import std
from std import print
from lexer import Lexer
from token import token_to_string, Token
from location import Location, new_location
from datatypes import List, Result, Option
from utils import panic


struct CompilationError:
    location: Location
    message: str

fn new_error(tok: Token, message: str) -> CompilationError:
    let e = CompilationError:
        location: tok.location
        message: "{message}, got {token_to_string(tok)}"
    return e

fn parse_source(filename: str) -> Result[ast.Module,CompilationError]:
    let source = std::read_file(filename)

    if false:
        print("Source-code")
        std::print("===============")
        print(source)
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
        let definitions: List[ast.Definition] = List()
        # let imports = List()

        loop:
            let tok = this.lex.next_token()
            case tok.kind:
                Eof:
                    # We are done!
                    break
                KwImport:
                    this.parse_import(tok.location)
                KwFn:
                    case this.parse_func_def(tok.location):
                        Ok(func_def):
                            definitions.append(ast.Definition.Function(func_def))
                        Error(error):
                            return Result.Error(error)
            else:
                return Result.Error(new_error(tok, "Unexpected token"))

        let program = ast::Module:
            name: "FUU"
            definitions: definitions
        
        return Result::Ok(program)

    fn parse_import(location: Location):
        let name = this.get_token() # id
        # TODO: how to check?
        let x = this.get_token() # newline

    fn parse_func_def(location: Location) -> Result[ast.FunctionDef, CompilationError]:
        
        # ID:
        let name = "?"
        let tok = this.get_token()
        case tok.kind:
            Identifier(txt):
                name = txt
        else:
            return Result::Error(new_error(tok, "Expected name"))

        print("Parsing function: {name}")

        # parameters!
        # '('
        tok = this.get_token()
        case tok.kind:
            BraceOpen:
                pass
        else:
            return Result::Error(new_error(tok, "Expected '('"))

        # ')'
        tok = this.get_token()
        case tok.kind:
            BraceClose:
                pass
        else:
            return Result::Error(new_error(tok, "Expected ')'"))

        # Optional arrow + type
        tok = this.get_token()
        case tok.kind:
            Arrow:
                # 'int' parse expression!
                let t = this.parse_expression()
            Colon:
                this.unget_token(tok)
        else:
            return Result::Error(new_error(tok, "Expected '->' or ':'"))

        # Body
        case this.parse_block():
            Ok(body):
                return Result.Ok(ast.function_def(name, body, location))
            Error(error):
                return Result.Error(error)

    fn parse_block() -> Result[ast.Statement, CompilationError]:
        # parse block of statements.
        # expect indent
        # print("parsing block")
        let location = new_location(1, 1)

        # Colon
        let tok = this.get_token()
        case tok.kind:
            Colon:
                pass
        else:
            return Result::Error(new_error(tok, "Expected ':'"))

        # Newline
        tok = this.get_token()
        case tok.kind:
            NewLine:
                pass
        else:
            return Result::Error(new_error(tok, "Expected newline"))

        # indent:
        tok = this.get_token()
        case tok.kind:
            Indent:
                location = tok.location
        else:
            return Result::Error(new_error(tok, "Expected indent"))

        let inner: List[ast.Statement] = List()

        loop:
            case this.parse_statement():
                Ok(statement):
                    inner.append(statement)
                Error(error):
                    return Result.Error(error)
            
            # expect dedent (eventually)
            tok = this.get_token()
            case tok.kind:
                Dedent:
                    break
            else:
                this.unget_token(tok)

        return Result.Ok(ast.compound(inner, location))
    
    fn parse_statement() -> Result[ast.Statement, CompilationError]:
        # print("parsing statement")
        let tok = this.get_token()
        case tok.kind:
            KwPass:
                return Result.Ok(ast.pass_statement(tok.location))
            KwBreak:
                return Result.Ok(ast.statement(ast::StatementKind::Break(), tok.location))
            KwContinue:
                return Result.Ok(ast.statement(ast::StatementKind::Continue(), tok.location))
            KwIf:
                # panic("TODO: IF")
                # condition:
                let condition = ast.undefined_value()
                case this.parse_expression():
                    Ok(expr):
                        condition = expr
                    Error(error):
                        return Result.Error(error)

                # true-block:
                let true_block = ast.pass_statement(tok.location)
                case this.parse_block():
                    Ok(statement):
                        true_block = statement
                    Error(error):
                        return Result.Error(error)
                
                # else-block:
                let false_block = ast.pass_statement(tok.location)
                
                return Result.Ok(ast.if_statement(condition, true_block, false_block, tok.location))
            KwLoop:
                case this.parse_block():
                    Ok(statement):
                        return Result.Ok(ast.loop_statement(statement, tok.location))
                    Error(error):
                        return Result.Error(error)
            KwWhile:
                let condition = ast.undefined_value()
                case this.parse_expression():
                    Ok(expr):
                        condition = expr
                    Error(error):
                        return Result.Error(error)

                case this.parse_block():
                    Ok(statement):
                        return Result.Ok(ast.while_statement(condition, statement, tok.location))
                    Error(error):
                        return Result.Error(error)
            KwReturn:
                # optionally parse expression (or newline)!
                let res_value: Option[ast.Expression] = Option.None()
                let tok2 = this.get_token()
                case tok2.kind:
                    NewLine:
                        pass
                else:
                    this.unget_token(tok2)
                    case this.parse_expression():
                        Ok(ret_val):
                            res_value = Option.Some(ret_val)

                            # Final newline:

                            let tok3 = this.get_token()
                            case tok3.kind:
                                NewLine:
                                    pass
                            else:
                                return Result::Error(new_error(tok3, "Expected newline"))

                        Error(error):
                            return Result.Error(error)

                return Result.Ok(ast.return_statement(res_value, tok.location))
        else:
            # Try to parse an expression!
            this.unget_token(tok)
            case this.parse_expression():
                Ok(expr):
                    # Now consume final newline!
                    let tok2 = this.get_token()
                    case tok2.kind:
                        NewLine:
                            pass
                    else:
                        return Result::Error(new_error(tok2, "Expected newline"))
                    return Result.Ok(ast.expression_statement(expr))
                Error(error):
                    return Result.Error(error)
    
    fn parse_expression() -> Result[ast.Expression, CompilationError]:
        # print("Parsing expression")

        let expr = ast.undefined_value()
        case this.parse_atom():
            Ok(atom):
                expr = atom
            Error(error):
                return Result.Error(error)

        # Attempt suffixes
        loop:
            let tok = this.get_token()
            case tok.kind:
                Dot:
                    # handle '.attribute' suffix
                    let tok2 = this.get_token()
                    case tok2.kind:
                        Identifier(attr):
                            expr = ast.get_attr(expr, attr, ast.undefined_type(), tok2.location)
                    else:
                        return Result::Error(new_error(tok2, "Expected dedent"))
                BraceOpen:
                    # print("CALL")
                    # Handle '(arg1,arg2)' suffix
                    # Or '()' or '(arg1)'
                    let arguments: List[ast.Expression] = List()
                    let tok2 = this.get_token()
                    case tok2.kind:
                        BraceClose:
                            # no args call
                            pass
                    else:
                        this.unget_token(tok2)
                        # call with parameters

                        loop:
                            case this.parse_expression():
                                Ok(arg):
                                    arguments.append(arg)
                                Error(error):
                                    return Result.Error(error)
                            # TODO: support multiple arguments
                            break
                        
                        # Capture closing brace
                        let tok3 = this.get_token()
                        case tok3.kind:
                            BraceClose:
                                pass
                        else:
                            return Result::Error(new_error(tok2, "Expected ')'"))

                    expr = ast.call(expr, arguments, ast.undefined_type(), tok.location)

            else:
                this.unget_token(tok)
                break
        return Result.Ok(expr)

    fn parse_atom() -> Result[ast.Expression, CompilationError]:
        let tok = this.get_token()
        case tok.kind:
            Integer(v):
                return Result.Ok(ast.integer_literal(v, tok.location))
            String(v):
                return Result.Ok(ast.string_literal(v, tok.location))
            Identifier(v):
                return Result.Ok(ast.name_ref(v, tok.location))
            BraceOpen:
                panic("TODO: braced expressions!")
        else:
            return Result.Error(new_error(tok, "Unexpected token"))

    fn get_token() -> Token:
        # Get token (EOF in case of end of file)
        return this.lex.next_token()

    fn unget_token(token: Token):
        this.lex.pushback_token(token)
