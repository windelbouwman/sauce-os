
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
        let imports: List[ast.Import] = List()

        loop:
            let tok = this.lex.next_token()
            case tok.kind:
                Eof:
                    # We are done!
                    break
                KwImport:
                    case this.parse_import(tok.location):
                        Ok(i):
                            pass
                        Error(error):
                            return Result.Error(error)
                KwFrom:
                    case this.parse_from_import(tok.location):
                        Ok(i):
                            pass
                        Error(error):
                            return Result.Error(error)
                KwFn:
                    case this.parse_func_def(tok.location):
                        Ok(func_def):
                            definitions.append(ast.Definition.Function(func_def))
                        Error(error):
                            return Result.Error(error)
                KwEnum:
                    case this.parse_enum_def(tok.location):
                        Ok(enum_def):
                            definitions.append(ast.Definition.Enum(enum_def))
                        Error(error):
                            return Result.Error(error)
                KwStruct:
                    case this.parse_struct_def(tok.location):
                        Ok(struct_def):
                            definitions.append(ast.Definition.Struct(struct_def))
                        Error(error):
                            return Result.Error(error)
                KwClass:
                    case this.parse_class_def(tok.location):
                        Ok(class_def):
                            definitions.append(ast.Definition.Class(class_def))
                        Error(error):
                            return Result.Error(error)
            else:
                return Result.Error(new_error(tok, "Unexpected token"))

        let program = ast.new_module("FUU", imports, definitions)
        return Result::Ok(program)

    fn parse_import(location: Location) -> Result[ast.Import,CompilationError]:
        let modname = "?"
        let tok = this.get_token()
        case tok.kind:
            Identifier(name):
                modname = name
        else:
            return Result.Error(new_error(tok, "Expected name"))

        # Newline
        tok = this.get_token()
        case tok.kind:
            NewLine:
                pass
        else:
            return Result.Error(new_error(tok, "Expected newline"))
        
        let i = ast.Import:
            modname: modname
            location: location
        
        return Result.Ok(i)

    fn parse_from_import(location: Location) -> Result[ast.FromImport, CompilationError]:
        let modname = "?"
        let tok = this.get_token()
        case tok.kind:
            Identifier(name):
                modname = name
        else:
            return Result.Error(new_error(tok, "Expected name"))

        # 'import'
        tok = this.get_token()
        case tok.kind:
            KwImport:
                pass
        else:
            return Result.Error(new_error(tok, "Expected 'import'"))
        
        let names: List[str] = List()

        # list of names until newline:
        loop:
            let tok2 = this.get_token()
            case tok2.kind:
                Identifier(name):
                    names.append(name)
                NewLine:
                    break
            else:
                return Result.Error(new_error(tok2, "Expected name"))

            tok2 = this.get_token()
            case tok2.kind:
                Comma:
                    continue
                NewLine:
                    break
            else:
                return Result.Error(new_error(tok2, "Expected ',' or newline"))

        let i = ast.FromImport:
            modname: modname
            location: location
            names: names

        return Result.Ok(i)

    fn parse_enum_def(location: Location) -> Result[ast.EnumDef, CompilationError]:
        let name = "?"
        let tok = this.get_token()
        case tok.kind:
            Identifier(txt):
                name = txt
        else:
            return Result::Error(new_error(tok, "Expected name"))

        case this.parse_type_parameters():
            Ok(type_parameters):
                # TODO: use type params
                pass
            Error(error):
                return Result.Error(error)

        # Colon
        tok = this.get_token()
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
            return Result.Error(new_error(tok, "Expected newline"))

        # indent:
        tok = this.get_token()
        case tok.kind:
            Indent:
                pass
        else:
            return Result.Error(new_error(tok, "Expected indent"))

        let variants: List[ast.EnumVariant] = List()
        loop:
            # expect id or dedent (eventually)
            tok = this.get_token()
            case tok.kind:
                Identifier(v):
                    let payload_types: List[ast.MyType] = List()
                    let tok3 = this.get_token()
                    case tok3.kind:
                        BraceOpen:
                            loop:
                                case this.parse_type():
                                    Ok(t):
                                        payload_types.append(t)
                                    Error(error):
                                        return Result.Error(error)

                                let tok4 = this.get_token()
                                case tok4.kind:
                                    BraceClose:
                                        break
                                    Comma:
                                        continue
                                else:
                                    return Result.Error(new_error(tok4, "Expected ',' or ')'"))
                    else:
                        this.unget_token(tok3)

                    # Newline
                    tok3 = this.get_token()
                    case tok3.kind:
                        NewLine:
                            pass
                    else:
                        return Result.Error(new_error(tok3, "Expected newline"))

                Dedent:
                    break
            else:
                return Result.Error(new_error(tok, "Expected variant or dedent"))


        let e = ast.enum_def(name, location, variants)
        return Result.Ok(e)

    fn parse_type_parameters() -> Result[List[ast.TypeParameter], CompilationError]:
        let type_parameters: List[ast.TypeParameter] = List()
        let tok = this.get_token()
        case tok.kind:
            BracketOpen:
                # take in type parameters
                loop:
                    let tok2 = this.get_token()
                    case tok2.kind:
                        Identifier(i):
                            type_parameters.append(ast.type_parameter(i, tok2.location))
                    else:
                        return Result.Error(new_error(tok2, "Expected ID"))

                    tok2 = this.get_token()
                    case tok2.kind:
                        BracketClose:
                            break
                        Comma:
                            continue
                    else:
                        return Result.Error(new_error(tok2, "Expected , or ]"))
        else:
            this.unget_token(tok)
        return Result.Ok(type_parameters)

    fn parse_struct_def(location: Location) -> Result[ast.StructDef, CompilationError]:
        let name = "?"
        let tok = this.get_token()
        case tok.kind:
            Identifier(txt):
                name = txt
        else:
            return Result::Error(new_error(tok, "Expected name"))

        case this.parse_type_parameters():
            Ok(type_parameters):
                # TODO: use type params
                pass
            Error(error):
                return Result.Error(error)

        # Colon
        tok = this.get_token()
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
            return Result.Error(new_error(tok, "Expected newline"))

        # indent:
        tok = this.get_token()
        case tok.kind:
            Indent:
                pass
        else:
            return Result.Error(new_error(tok, "Expected indent"))

        let fields: List[ast.StructField] = List()
        loop:
            # expect id or dedent (eventually)
            tok = this.get_token()
            case tok.kind:
                Identifier(field_name):
                    let field_type = ast.undefined_type()

                    # ':'
                    let tok3 = this.get_token()
                    case tok3.kind:
                        Colon:
                            pass
                    else:
                        return Result.Error(new_error(tok3, "Expected ':'"))

                    # Field type
                    case this.parse_type():
                        Ok(t):
                            field_type = t
                        Error(error):
                            return Result.Error(error)

                    # Newline
                    tok3 = this.get_token()
                    case tok3.kind:
                        NewLine:
                            pass
                    else:
                        return Result.Error(new_error(tok3, "Expected newline"))
                    fields.append(ast.new_struct_field(field_name, field_type, tok.location))
                Dedent:
                    break
            else:
                return Result.Error(new_error(tok, "Expected field or dedent"))

        let s = ast.struct_def(name, fields, location)
        return Result.Ok(s)

    fn parse_class_def(location: Location) -> Result[ast.ClassDef, CompilationError]:
        let name = "?"
        let tok = this.get_token()
        case tok.kind:
            Identifier(txt):
                name = txt
        else:
            return Result::Error(new_error(tok, "Expected name"))

        case this.parse_type_parameters():
            Ok(type_parameters):
                # TODO: use type params
                pass
            Error(error):
                return Result.Error(error)

        # Colon
        tok = this.get_token()
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
            return Result.Error(new_error(tok, "Expected newline"))

        # indent:
        tok = this.get_token()
        case tok.kind:
            Indent:
                pass
        else:
            return Result.Error(new_error(tok, "Expected indent"))

        # let inner_defs = List()
        loop:
            # expect var/fn def or dedent (eventually)
            tok = this.get_token()
            case tok.kind:
                KwVar:
                    case this.parse_var_def(tok.location):
                        Ok(var_def):
                            pass
                        Error(error):
                            return Result.Error(error)
                KwFn:
                    case this.parse_func_def(tok.location):
                        Ok(func_def):
                            pass
                        Error(error):
                            return Result.Error(error)
                Dedent:
                    break
            else:
                return Result.Error(new_error(tok, "Expected field or dedent"))

        let c = ast.ClassDef:
            name: name
            location: tok.location
            scope: ast.Scope()
        return Result.Ok(c)

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
            return Result.Error(new_error(tok, "Expected '('"))

        let parameters: List[ast.ParameterDef] = List()
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
                let tok3 = this.get_token()
                case tok3.kind:
                    Colon:
                        pass
                else:
                    return Result::Error(new_error(tok3, "Expected ':'"))

                let param_type = ast.undefined_type()
                case this.parse_type():
                    Ok(t):
                        param_type = t
                    Error(error):
                        return Result.Error(error)

                let param_def = ast.parameter_def(param_name, param_type, tok2.location)
                parameters.append(param_def)

                let tok4 = this.get_token()
                case tok4.kind:
                    BraceClose:
                        break
                    Comma:
                        pass
                else:
                    return Result::Error(new_error(tok4, "Expected ')' or ','"))

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
                return Result.Ok(ast.function_def(name, parameters, body, location))
            Error(error):
                return Result.Error(error)
    
    fn parse_var_def(location: Location) -> Result[ast.VarDef, CompilationError]:
        # ID:
        let var_name = "?"
        let tok = this.get_token()
        case tok.kind:
            Identifier(txt):
                var_name = txt
        else:
            return Result.Error(new_error(tok, "Expected name"))

        # ':'
        tok = this.get_token()
        case tok.kind:
            Colon:
                pass
        else:
            return Result::Error(new_error(tok, "Expected ':'"))

        # Type        
        let var_type = ast.undefined_type()
        case this.parse_type():
            Ok(t):
                var_type = t
            Error(error):
                return Result.Error(error)

        # '='
        tok = this.get_token()
        case tok.kind:
            Equals:
                pass
        else:
            return Result::Error(new_error(tok, "Expected '='"))
        
        # value
        let var_init = ast.undefined_value()
        case this.parse_expression():
            Ok(expr):
                var_init = expr
            Error(error):
                return Result.Error(error)

        # Newline
        tok = this.get_token()
        case tok.kind:
            NewLine:
                pass
        else:
            return Result.Error(new_error(tok, "Expected newline"))
        
        let variable = ast.variable(var_name, var_type)
        let var_def = ast.VarDef:
            variable: variable
        
        return Result.Ok(var_def)

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
                    Colon:
                        # Obj initializer!
                        let obj_ty = ast.new_type(ast.TypeKind.TypeExpression(value))
                        let tok3 = this.get_token()
                        let obj_location = tok3.location
                        case tok3.kind:
                            NewLine:
                                pass
                        else:
                            return Result::Error(new_error(tok3, "Expected newline"))
                        
                        # indent:
                        tok3 = this.get_token()
                        case tok3.kind:
                            Indent:
                                pass
                        else:
                            return Result.Error(new_error(tok3, "Expected indent"))
                        
                        let obj_fields: List[ast.FieldInit] = List()
                        loop:
                            # ID
                            let field_name = "?"
                            tok3 = this.get_token()
                            let field_loc = tok3.location
                            case tok3.kind:
                                Identifier(x):
                                    field_name = x
                                Dedent:
                                    break
                            else:
                                return Result.Error(new_error(tok3, "Expected dedent"))

                            # ':'
                            tok3 = this.get_token()
                            case tok3.kind:
                                Colon:
                                    pass
                            else:
                                return Result.Error(new_error(tok3, "Expected ':'"))
                            
                            case this.parse_expression():
                                Ok(value):
                                    let field_init = ast.FieldInit:
                                        location: field_loc
                                        name: field_name
                                        value: value
                                    obj_fields.append(field_init)
                                Error(error):
                                    return Result.Error(error)

                            # newline
                            tok3 = this.get_token()
                            case tok3.kind:
                                NewLine:
                                    pass
                            else:
                                return Result::Error(new_error(tok3, "Expected ':'"))
                        value = ast.expression(ast.ExpressionKind.ObjInit(obj_ty, obj_fields), ast.undefined_type(), obj_location)

                else:
                    return Result::Error(new_error(tok2, "Expected newline or ':'"))
                
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
            KwCase:
                # Value
                let case_value = ast.undefined_value()
                case this.parse_expression():
                    Ok(expr):
                        case_value = expr
                    Error(error):
                        return Result.Error(error)

                # Colon
                let tok2 = this.get_token()
                case tok2.kind:
                    Colon:
                        pass
                else:
                    return Result.Error(new_error(tok2, "Expected ':'"))

                # Newline
                tok2 = this.get_token()
                case tok2.kind:
                    NewLine:
                        pass
                else:
                    return Result.Error(new_error(tok2, "Expected newline"))

                # indent:
                tok2 = this.get_token()
                case tok2.kind:
                    Indent:
                        pass
                else:
                    return Result.Error(new_error(tok2, "Expected indent"))
                
                let case_arms: List[ast.CaseArm] = List()
                loop:
                    let tok3 = this.get_token()
                    case tok3.kind:
                        Identifier(name):
                            # Eventual payload values to unpack:
                            let tok4 = this.get_token()
                            case tok4.kind:
                                BraceOpen:
                                    loop:
                                        let tok5 = this.get_token()
                                        case tok5.kind:
                                            Identifier(n):
                                                pass
                                        else:
                                            return Result.Error(new_error(tok5, "Expected name"))
                                        
                                        tok5 = this.get_token()
                                        case tok5.kind:
                                            BraceClose:
                                                break
                                            Comma:
                                                continue
                                        else:
                                            return Result.Error(new_error(tok5, "Expected ',' or ')'"))
                            else:
                                this.unget_token(tok4)

                            # Arm body:
                            case this.parse_block():
                                Ok(statement):
                                    let arm = ast.CaseArm:
                                        body: statement
                                    case_arms.append(arm)
                                Error(error):
                                    return Result.Error(error)
                        Dedent:
                            break
                    else:
                        return Result.Error(new_error(tok2, "Expected variant or dedent"))
                
                # Parse optional 'else' block
                let else_clause = Option.None()
                tok2 = this.get_token()
                case tok2.kind:
                    KwElse:
                        case this.parse_block():
                            Ok(statement):
                                else_clause = Option.Some(statement)
                            Error(error):
                                return Result.Error(error)
                else:
                    this.unget_token(tok2)
                
                let c = ast.CaseStatement:
                    value: case_value
                    arms: case_arms
                    else_clause: else_clause
                return Result.Ok(ast.statement(ast.StatementKind.Case(c), tok.location))
                    
            KwFor:
                let iter_var = "?"
                let tok2 = this.get_token()
                case tok2.kind:
                    Identifier(name):
                        iter_var = name
                else:
                    return Result::Error(new_error(tok2, "Expected name"))

                # 'in'
                tok2 = this.get_token()
                case tok2.kind:
                    KwIn:
                        pass
                else:
                    return Result.Error(new_error(tok2, "Expected 'in'"))

                let iter_value = ast.undefined_value()
                case this.parse_expression():
                    Ok(expr):
                        iter_value = expr
                    Error(error):
                        return Result.Error(error)

                # ':' + indented block:
                case this.parse_block():
                    Ok(statement):
                        return Result.Ok(ast.for_statement(iter_var, iter_value, statement, tok.location))
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
                
                BracketOpen:
                    let arguments: List[ast.Expression] = List()
                    loop:
                        case this.parse_expression():
                            Ok(arg):
                                arguments.append(arg)
                            Error(error):
                                return Result.Error(error)
                        # TODO: support multiple arguments

                        let tok4 = this.get_token()
                        case tok4.kind:
                            BracketClose:
                                break
                            Comma:
                                continue
                        else:
                            return Result::Error(new_error(tok4, "Expected ']' or ','"))
                    expr = ast.subscript(expr, arguments, ast.undefined_type(), tok.location)
            else:
                this.unget_token(tok)
                break
        return Result.Ok(expr)

    fn get_token() -> Token:
        # Get token (EOF in case of end of file)
        return this.lex.next_token()

    fn unget_token(token: Token):
        this.lex.pushback_token(token)
