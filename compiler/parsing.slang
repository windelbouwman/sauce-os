
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

        # '('
        tok = this.get_token()
        case tok.kind:
            BraceOpen:
                pass
        else:
            return Result::Error(new_error(tok, "Expected '('"))

        # ')' or parameters and ')'
        tok = this.get_token()
        case tok.kind:
            BraceClose:
                pass
        else:
            this.unget_token(tok)
            loop:
                # Parameter name
                let param_name = "?"
                let tok2 = this.get_token()
                case tok2.kind:
                    Identifier(txt):
                        param_name = txt
                else:
                    return Result::Error(new_error(tok2, "Expected name"))

                # ':'
                tok2 = this.get_token()
                case tok2.kind:
                    Colon:
                        pass
                else:
                    return Result::Error(new_error(tok2, "Expected ':'"))

                let param_type = ast.undefined_type()
                case this.parse_type():
                    Ok(t):
                        param_type = t
                    Error(error):
                        return Result.Error(error)

                tok2 = this.get_token()
                case tok2.kind:
                    BraceClose:
                        break
                    Comma:
                        pass
                else:
                    return Result::Error(new_error(tok, "Expected ')' or ','"))

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
    
    fn parse_type() -> Result[ast.MyType, CompilationError]:
        case this.parse_expression():
            Ok(e):
                # TODO: type expression!
                let t = ast.undefined_type()
                return Result.Ok(t)
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
                # Trailing newline
                let tok2 = this.get_token()
                case tok2.kind:
                    NewLine:
                        pass
                else:
                    return Result::Error(new_error(tok2, "Expected newline"))

                return Result.Ok(ast.pass_statement(tok.location))
            KwBreak:
                # Trailing newline
                let tok2 = this.get_token()
                case tok2.kind:
                    NewLine:
                        pass
                else:
                    return Result::Error(new_error(tok2, "Expected newline"))

                return Result.Ok(ast.statement(ast::StatementKind::Break(), tok.location))
            KwContinue:
                # Trailing newline
                let tok2 = this.get_token()
                case tok2.kind:
                    NewLine:
                        pass
                else:
                    return Result::Error(new_error(tok2, "Expected newline"))

                return Result.Ok(ast.statement(ast::StatementKind::Continue(), tok.location))
            KwLet:
                let tok2 = this.get_token()
                let var_name = "?"
                case tok2.kind:
                    Identifier(name):
                        var_name = name
                else:
                    return Result::Error(new_error(tok2, "Expected name"))
                
                let var_type = ast.undefined_type()
                let target_var = ast.variable(var_name, var_type)
                
                let type_hint = ast.undefined_type()

                tok2 = this.get_token()
                case tok2.kind:
                    Colon:
                        # Type hint!
                        case this.parse_type():
                            Ok(t):
                                type_hint = t
                            Error(error):
                                return Result.Error(error)
                else:
                    this.unget_token(tok2)

                tok2 = this.get_token()
                case tok2.kind:
                    Equals:
                        pass
                else:
                    return Result.Error(new_error(tok2, "Expected '='"))

                let value = ast.undefined_value()
                case this.parse_expression():
                    Ok(expr):
                        value = expr
                    Error(error):
                        return Result.Error(error)

                tok2 = this.get_token()
                case tok2.kind:
                    NewLine:
                        pass
                else:
                    return Result::Error(new_error(tok2, "Expected newline"))

                return Result.Ok(ast.let_statement(target_var, value, tok.location))
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
                let tok2 = this.get_token()
                case tok2.kind:
                    KwElse:
                        case this.parse_block():
                            Ok(statement):
                                false_block = statement
                            Error(error):
                                return Result.Error(error)
                else:
                    this.unget_token(tok2)
                
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
            this.unget_token(tok)

            # Try to parse an expression!
            case this.parse_expression():
                Ok(expr):
                    let s = ast.expression_statement(expr)

                    # Maybe we have an assignment
                    let tok2 = this.get_token()
                    case tok2.kind:
                        Equals:
                            # Assignment!
                            case this.parse_expression():
                                Ok(value):
                                    s = ast.assignment_statement(expr, value, tok2.location)
                                Error(error):
                                    return Result.Error(error)
                        PlusEquals:
                            # Assignment! '+='
                            print("ATTENTION: += badly parsed")
                            # TODO!
                            case this.parse_expression():
                                Ok(value):
                                    s = ast.assignment_statement(expr, value, tok2.location)
                                Error(error):
                                    return Result.Error(error)
                    else:
                        this.unget_token(tok2)
                    
                    # Now consume final newline!
                    tok2 = this.get_token()
                    case tok2.kind:
                        NewLine:
                            pass
                    else:
                        return Result::Error(new_error(tok2, "Expected newline"))
                    return Result.Ok(s)
                Error(error):
                    return Result.Error(error)
    
    fn parse_expression() -> Result[ast.Expression, CompilationError]:
        # print("Parsing expression")
        return this.parse_expression2(0)

    fn parse_expression2(min_prec: int) -> Result[ast.Expression, CompilationError]:
        # print("Parsing expression")
        let expr = ast.undefined_value()
        case this.parse_atom():
            Ok(atom):
                expr = atom
            Error(error):
                return Result.Error(error)
        
        loop:
            # Determine next token and new precedence
            let tok = this.get_token()
            let prec = 0
            let op: ast.BinaryOperator = ast.BinaryOperator.Add()
            case tok.kind:
                KwOr:
                    op = ast.BinaryOperator.Or()
                    prec = 20
                KwAnd:
                    op = ast.BinaryOperator.And()
                    prec = 25
                Less:
                    op = ast.BinaryOperator.Less()
                    prec = 30
                LessEquals:
                    op = ast.BinaryOperator.LessEquals()
                    prec = 30
                Greater:
                    op = ast.BinaryOperator.Greater()
                    prec = 30
                GreaterEquals:
                    op = ast.BinaryOperator.GreaterEquals()
                    prec = 30
                EqualsEquals:
                    op = ast.BinaryOperator.Equals()
                    prec = 30
                Plus:
                    op = ast.BinaryOperator.Add()
                    prec = 60
                Minus:
                    op = ast.BinaryOperator.Sub()
                    prec = 60
                Slash:
                    op = ast.BinaryOperator.Div()
                    prec = 80
                Asterix:
                    op = ast.BinaryOperator.Mul()
                    prec = 80
            else:
                this.unget_token(tok)
                break
            
            if prec < min_prec:
                this.unget_token(tok)
                break
            
            let rhs = ast.undefined_value()
            case this.parse_expression2(prec + 1):
                Ok(e):
                    rhs = e
                Error(error):
                    return Result.Error(error)

            expr = ast.binop(expr, op, rhs, ast.undefined_type(), tok.location)

        return Result.Ok(expr)

    fn parse_atom() -> Result[ast.Expression, CompilationError]:
        let expr = ast.undefined_value()
        let tok = this.get_token()
        case tok.kind:
            Integer(v):
                expr = ast.integer_literal(v, tok.location)
            Float(v):
                expr = ast.float_literal(v, tok.location)
            String(v):
                expr = ast.string_literal(v, tok.location)
            Identifier(v):
                expr = ast.name_ref(v, tok.location)
            BraceOpen:
                case this.parse_expression():
                    Ok(e):
                        expr = e
                    Error(error):
                        return Result.Error(error)

                let tok2 = this.get_token()
                case tok2.kind:
                    BraceClose:
                        pass
                else:
                    return Result::Error(new_error(tok2, "Expected ')'"))
        else:
            return Result.Error(new_error(tok, "Unexpected token"))

        # Attempt suffixes
        loop:
            tok = this.get_token()
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

                            let tok4 = this.get_token()
                            case tok4.kind:
                                BraceClose:
                                    break
                                Comma:
                                    continue
                            else:
                                return Result::Error(new_error(tok4, "Expected ')' or ','"))

                    expr = ast.call(expr, arguments, ast.undefined_type(), tok.location)

            else:
                this.unget_token(tok)
                break
        return Result.Ok(expr)

    fn get_token() -> Token:
        # Get token (EOF in case of end of file)
        return this.lex.next_token()

    fn unget_token(token: Token):
        this.lex.pushback_token(token)
