
import ast
import std
from lexer import Lexer
from token import token_to_string, Token
from location import Location, new_location
from datatypes import List, Result, Option, String, split_string
from utils import panic, log_debug, log_trace
from errors import CompilationError
import errors


fn new_error(tok: Token, message: str) -> CompilationError:
    return errors.new_error(tok.location, "{message}, got {token_to_string(tok)}")

fn basename(path: String) -> String:
    # retrieve 'bla' from 'for/bar/bla.txt'
    let base = split_string(path, "/").last()
    return split_string(base, ".").first()

fn parse_source(filename: String) -> Result[ast.Module,CompilationError]:
    let source = std.read_file(filename.value)
    let modname = basename(filename).value

    let parser = Parser()
    parser.feed(source)

    try:
        return Result.Ok(parser.parse_module(modname))
    except (err: CompilationError):
        return Result.Error(err)
    

class Parser:
    # An attempt at a recursive descent parser.
    var lex: Lexer = Lexer()
    var next_id: int = 1

    fn feed(source: str):
        this.lex.init(source)
    
    fn parse_module(modname: str) -> ast.Module except CompilationError:
        let definitions: List[ast.Definition] = List()
        let imports: List[ast.Import] = List()

        loop:
            let tok = this.lex.next_token()
            case tok.kind:
                Eof:
                    # We are done!
                    break
                KwImport:
                    imports.append(this.parse_import(tok.location))
                KwFrom:
                    imports.append(this.parse_from_import(tok.location))
                KwFn:
                    let func_def = this.parse_func_def(tok.location)
                    definitions.append(ast.Definition.Function(func_def))
                KwEnum:
                    let enum_def = this.parse_enum_def(tok.location)
                    definitions.append(ast.Definition.Enum(enum_def))
                KwStruct:
                    let struct_def = this.parse_struct_def(tok.location)
                    definitions.append(ast.Definition.Struct(struct_def))
                KwClass:
                    let class_def = this.parse_class_def(tok.location)
                    definitions.append(ast.Definition.Class(class_def))
            else:
                raise new_error(tok, "Unexpected token")

        let program = ast.new_module(modname, imports, definitions)
        return program

    fn parse_import(location: Location) -> ast.Import except CompilationError:
        let modname = "?"
        let tok = this.get_token()
        case tok.kind:
            Identifier(name):
                modname = name
        else:
            raise new_error(tok, "Expected name")

        this.parse_newline()
        return ast.import_self(modname, location)

    fn parse_from_import(location: Location) -> ast.Import except CompilationError:
        let modname = "?"
        let tok = this.get_token()
        case tok.kind:
            Identifier(name):
                modname = name
        else:
            raise new_error(tok, "Expected name")

        # 'import'
        tok = this.get_token()
        case tok.kind:
            KwImport:
                pass
        else:
            raise new_error(tok, "Expected 'import'")
        
        let names: List[str] = List()

        # list of names until newline:
        loop:
            let tok2 = this.get_token()
            case tok2.kind:
                Identifier(name):
                    names.append(name)
            else:
                raise new_error(tok2, "Expected name")

            tok2 = this.get_token()
            case tok2.kind:
                Comma:
                    continue
                NewLine:
                    break
            else:
                raise new_error(tok2, "Expected ',' or newline")

        return ast.import_names(modname, location, names)

    fn parse_enum_def(location: Location) -> ast.EnumDef except CompilationError:
        let name = "?"
        let tok = this.get_token()
        case tok.kind:
            Identifier(txt):
                name = txt
        else:
            raise new_error(tok, "Expected name")

        let type_parameters: List[ast.TypeParameter] = this.parse_type_parameters()

        this.parse_colon()
        this.parse_newline()
        this.parse_indent()

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
                                payload_types.append(this.parse_type())

                                let tok4 = this.get_token()
                                case tok4.kind:
                                    BraceClose:
                                        break
                                    Comma:
                                        continue
                                else:
                                    raise new_error(tok4, "Expected ',' or ')'")
                    else:
                        this.unget_token(tok3)
                    
                    let variant = ast.EnumVariant:
                        name: v
                        payload: payload_types
                        location: tok.location
                    variants.append(variant)

                    this.parse_newline()
                Dedent:
                    break
            else:
                raise new_error(tok, "Expected variant or dedent")

        return ast.enum_def(name, location, type_parameters, variants)

    fn parse_type_parameters() -> List[ast.TypeParameter] except CompilationError:
        let type_parameters: List[ast.TypeParameter] = List()
        let tok = this.get_token()
        case tok.kind:
            BracketOpen:
                # take in type parameters
                loop:
                    let tok2 = this.get_token()
                    case tok2.kind:
                        Identifier(name):
                            type_parameters.append(ast.type_parameter(name, this.new_id(), tok2.location))
                    else:
                        raise new_error(tok2, "Expected ID")

                    tok2 = this.get_token()
                    case tok2.kind:
                        BracketClose:
                            break
                        Comma:
                            continue
                    else:
                        raise new_error(tok2, "Expected , or ]")
        else:
            this.unget_token(tok)
        return type_parameters

    fn parse_struct_def(location: Location) -> ast.StructDef except CompilationError:
        let name = "?"
        let tok = this.get_token()
        case tok.kind:
            Identifier(txt):
                name = txt
        else:
            raise new_error(tok, "Expected name")

        let type_parameters: List[ast.TypeParameter] = this.parse_type_parameters()

        this.parse_colon()
        this.parse_newline()
        this.parse_indent()

        let fields: List[ast.StructField] = List()
        loop:
            # expect id or dedent (eventually)
            tok = this.get_token()
            case tok.kind:
                Identifier(field_name):
                    this.parse_colon()
                    let field_type = this.parse_type()
                    this.parse_newline()
                    fields.append(ast.new_struct_field(field_name, field_type, tok.location))
                Dedent:
                    break
            else:
                raise new_error(tok, "Expected field or dedent")

        return ast.struct_def(name, this.new_id(), type_parameters, fields, location)

    fn parse_class_def(location: Location) -> ast.ClassDef except CompilationError:
        let name = "?"
        let tok = this.get_token()
        case tok.kind:
            Identifier(txt):
                name = txt
        else:
            raise new_error(tok, "Expected name")

        let type_parameters: List[ast.TypeParameter] = this.parse_type_parameters()

        this.parse_colon()
        this.parse_newline()
        this.parse_indent()

        let inner_defs: List[ast.Definition] = List()
        loop:
            # expect var/fn def or dedent (eventually)
            tok = this.get_token()
            case tok.kind:
                KwVar:
                    let var_def = this.parse_var_def(tok.location)
                    inner_defs.append(ast.Definition.Var(var_def))
                KwFn:
                    let func_def = this.parse_func_def(tok.location)
                    inner_defs.append(ast.Definition.Function(func_def))
                Dedent:
                    break
            else:
                raise new_error(tok, "Expected field or dedent")

        let this_var = ast.variable("this", ast.undefined_type())
        let class_def = ast.ClassDef:
            node_id: ast.new_node_id(name, this.new_id())
            location: tok.location
            type_parameters: type_parameters
            this_var: this_var
            definitions: inner_defs
            scope: ast.Scope()
        
        # Prepare 'this' variable:
        let type_args: List[ast.MyType] = List()
        for tp in type_parameters:
            type_args.append(ast.type_parameter_ref(tp))
        class_def.this_var.ty = ast.apply_tycon(ast.TyCon.Class(class_def), type_args)
        return class_def

    fn parse_func_def(location: Location) -> ast.FunctionDef except CompilationError:
        
        # ID:
        let name = "?"
        let tok = this.get_token()
        case tok.kind:
            Identifier(txt):
                name = txt
        else:
            raise new_error(tok, "Expected name")

        log_debug("Parsing function: {name}")

        let type_parameters = this.parse_type_parameters()

        # '('
        tok = this.get_token()
        case tok.kind:
            BraceOpen:
                pass
        else:
            raise new_error(tok, "Expected '('")

        let parameters: List[ast.ParameterDef] = List()
        # ')' or parameters and ')'
        tok = this.get_token()
        case tok.kind:
            BraceClose:
                pass
        else:
            this.unget_token(tok)
            loop:
                parameters.append(this.parse_parameter_def())
                let tok4 = this.get_token()
                case tok4.kind:
                    BraceClose:
                        break
                    Comma:
                        pass
                else:
                    raise new_error(tok4, "Expected ')' or ','")

        # Optional return type
        let return_type: ast.MyType = ast.void_type()
        tok = this.get_token()
        case tok.kind:
            Arrow:
                return_type = this.parse_type()
        else:
            this.unget_token(tok)

        # Optional except type
        let except_type: ast.MyType = ast.void_type()
        tok = this.get_token()
        case tok.kind:
            KwExcept:
                except_type = this.parse_type()
        else:
            this.unget_token(tok)

        # Body
        let body = this.parse_block()
        return ast.function_def(name, type_parameters, parameters, return_type, except_type, body, location)
    
    fn parse_parameter_def() -> ast.ParameterDef except CompilationError:
        # Parameter name
        let param_name = "?"
        let tok2 = this.get_token()
        case tok2.kind:
            Identifier(txt):
                param_name = txt
        else:
            raise new_error(tok2, "Expected name")

        this.parse_colon()
        let param_type = this.parse_type()
        let param_def = ast.parameter_def(param_name, param_type, tok2.location)
        return param_def

    fn parse_var_def(location: Location) -> ast.VarDef except CompilationError:
        # ID:
        let var_name = "?"
        let tok = this.get_token()
        case tok.kind:
            Identifier(txt):
                var_name = txt
        else:
            raise new_error(tok, "Expected name")

        this.parse_colon()

        # Type        
        let var_type = this.parse_type()

        # '='
        tok = this.get_token()
        case tok.kind:
            Equals:
                pass
        else:
            raise new_error(tok, "Expected '='")
        
        # value
        let var_init = this.parse_expression()
        this.parse_newline()
        
        let variable = ast.variable(var_name, var_type)
        let var_def = ast.VarDef:
            variable: variable
        
        return var_def

    fn parse_type() -> ast.MyType except CompilationError:
        let tok0 = this.get_token()
        case tok0.kind:
            KwFn:
                # Parse function signature.

                # '('
                let tok2 = this.get_token()
                case tok2.kind:
                    BraceOpen:
                        pass
                else:
                    raise new_error(tok2, "Expected '('")

                let parameter_types: List[ast.MyType] = List()
                # ')' or parameters and ')'
                tok2 = this.get_token()
                case tok2.kind:
                    BraceClose:
                        pass
                else:
                    this.unget_token(tok2)
                    loop:
                        let param_type = this.parse_type()
                        parameter_types.append(param_type)

                        let tok4 = this.get_token()
                        case tok4.kind:
                            BraceClose:
                                break
                            Comma:
                                continue
                        else:
                            raise new_error(tok4, "Expected ')' or ','")

                # Optional return type
                tok2 = this.get_token()
                let return_type: ast.MyType = ast.void_type()
                case tok2.kind:
                    Arrow:
                        return_type = this.parse_type()
                else:
                    this.unget_token(tok2)
                
                return ast.function_type(parameter_types, return_type)
        else:
            this.unget_token(tok0)
            let expr = this.parse_expression()
            return ast.type_expression(expr)

    fn parse_block() -> ast.Statement except CompilationError:
        # parse block of statements.
        # expect indent
        log_trace("parsing block")
        let location = new_location(1, 1)

        this.parse_colon()
        this.parse_newline()
        this.parse_indent()

        let inner: List[ast.Statement] = List()

        loop:
            let statement = this.parse_statement()
            inner.append(statement)
            
            # expect dedent (eventually)
            let tok = this.get_token()
            case tok.kind:
                Dedent:
                    break
            else:
                this.unget_token(tok)

        return ast.compound(inner, location)
    
    fn parse_statement() -> ast.Statement except CompilationError:
        log_trace("parsing statement")
        let tok = this.get_token()
        case tok.kind:
            KwPass:
                this.parse_newline()
                return ast.pass_statement(tok.location)
            KwBreak:
                this.parse_newline()
                return ast.statement(ast.StatementKind.Break(), tok.location)
            KwContinue:
                this.parse_newline()
                return ast.statement(ast.StatementKind.Continue(), tok.location)
            KwLet:
                return this.parse_let_statement(tok.location)
            KwIf:
                return this.parse_if_statement(tok.location)
            KwLoop:
                let statement = this.parse_block()
                return ast.loop_statement(statement, tok.location)
            KwWhile:
                return this.parse_while_statement(tok.location)
            KwCase:
                return this.parse_case_statement(tok.location)
            KwFor:
                return this.parse_for_statement(tok.location)
            KwTry:
                return this.parse_try_statement(tok.location)
            KwReturn:
                return this.parse_return_statement(tok.location)
            KwRaise:
                return this.parse_raise_statement(tok.location)
        else:
            this.unget_token(tok)

            # Try to parse an expression!
            let expr = this.parse_expression()
            let s = ast.expression_statement(expr)

            # Maybe we have an assignment
            let is_assign = true
            let assign_op = Option.None()
            let tok2 = this.get_token()
            case tok2.kind:
                Equals:
                    pass
                PlusEquals:  # Assignment '+='
                    assign_op = Option.Some(ast.BinaryOperator.Add())
                MinusEquals:
                    assign_op = Option.Some(ast.BinaryOperator.Sub())
            else:
                is_assign = false
                this.unget_token(tok2)
            
            if is_assign:
                # Assignment!
                let value = this.parse_expression()
                s = ast.assignment_statement(expr, assign_op, value, tok2.location)
            else:
                s = ast.expression_statement(expr)

            this.parse_newline()
            return s
    
    fn parse_let_statement(location: Location) -> ast.Statement except CompilationError:
        let tok2 = this.get_token()
        let var_name = "?"
        case tok2.kind:
            Identifier(name):
                var_name = name
        else:
            raise new_error(tok2, "Expected name")
        
        let var_type = ast.undefined_type()
        let target_var = ast.variable(var_name, var_type)
        
        let type_hint: Option[ast.MyType] = Option.None()

        tok2 = this.get_token()
        case tok2.kind:
            Colon:
                # Type hint!
                type_hint = Option.Some(this.parse_type())
        else:
            this.unget_token(tok2)

        tok2 = this.get_token()
        case tok2.kind:
            Equals:
                pass
        else:
            raise new_error(tok2, "Expected '='")
        
        let value = this.parse_expression()

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
                    raise new_error(tok3, "Expected newline")
                
                this.parse_indent()
                
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
                        raise new_error(tok3, "Expected dedent")

                    this.parse_colon()
                    let field_value = this.parse_expression()
                    let field_init = ast.FieldInit:
                        location: field_loc
                        name: field_name
                        value: field_value
                    obj_fields.append(field_init)

                    this.parse_newline()
                value = ast.expression(ast.ExpressionKind.ObjInit(obj_ty, obj_fields), ast.undefined_type(), obj_location)

        else:
            raise new_error(tok2, "Expected newline or ':'")
        
        return ast.let_statement(target_var, type_hint, value, location)

    fn parse_if_statement(location: Location) -> ast.Statement except CompilationError:
        # Parse if-statement (if or elif keyword already parsed)

        let condition = this.parse_expression()
        let true_block = this.parse_block()
        
        # else-block or elif-block:
        let false_block = ast.pass_statement(location)
        let tok2 = this.get_token()
        case tok2.kind:
            KwElse:
                false_block = this.parse_block()
            KwElif:
                false_block = this.parse_if_statement(tok2.location)
        else:
            this.unget_token(tok2)
        
        return ast.if_statement(condition, true_block, false_block, location)
    
    fn parse_while_statement(location: Location) -> ast.Statement except CompilationError:
        let condition = this.parse_expression()
        let statement = this.parse_block()
        return ast.while_statement(condition, statement, location)

    fn parse_for_statement(location: Location) -> ast.Statement except CompilationError:
        let iter_var = "?"
        let tok2 = this.get_token()
        case tok2.kind:
            Identifier(name):
                iter_var = name
        else:
            raise new_error(tok2, "Expected name")

        # 'in'
        tok2 = this.get_token()
        case tok2.kind:
            KwIn:
                pass
        else:
            raise new_error(tok2, "Expected 'in'")

        let iter_value = this.parse_expression()

        # ':' + indented block:
        let statement = this.parse_block()
        return ast.for_statement(iter_var, iter_value, statement, location)

    fn parse_try_statement(location: Location) -> ast.Statement except CompilationError:
        let try_code = this.parse_block()

        # 'except'
        let tok = this.get_token()
        case tok.kind:
            KwExcept:
                pass
        else:
            raise new_error(tok, "Expected 'except'")

        # '('
        tok = this.get_token()
        case tok.kind:
            BraceOpen:
                pass
        else:
            raise new_error(tok, "Expected '('")

        let exc_param = this.parse_parameter_def()

        # ')'
        tok = this.get_token()
        case tok.kind:
            BraceClose:
                pass
        else:
            raise new_error(tok, "Expected ')'")

        let exc_code = this.parse_block()
        return ast.try_statement(try_code, exc_param, exc_code, location)

    fn parse_case_statement(location: Location) -> ast.Statement except CompilationError:
        # Value
        let case_value = this.parse_expression()
        this.parse_colon()
        this.parse_newline()
        this.parse_indent()
        
        let case_arms: List[ast.CaseArm] = List()
        loop:
            let tok3 = this.get_token()
            case tok3.kind:
                Identifier(name):
                    let variables: List[ast.Variable] = List()
                    # Eventual payload values to unpack:
                    let tok4 = this.get_token()
                    case tok4.kind:
                        BraceOpen:
                            loop:
                                let tok5 = this.get_token()
                                case tok5.kind:
                                    Identifier(n):
                                        variables.append(ast.variable(n, ast.undefined_type()))
                                else:
                                    raise new_error(tok5, "Expected name")
                                
                                tok5 = this.get_token()
                                case tok5.kind:
                                    BraceClose:
                                        break
                                    Comma:
                                        continue
                                else:
                                    raise new_error(tok5, "Expected ',' or ')'")
                    else:
                        this.unget_token(tok4)

                    # Arm body:
                    let statement = this.parse_block()
                    let arm = ast.CaseArm:
                        location: tok3.location
                        name: name
                        variables: variables
                        scope: ast.Scope()
                        body: statement
                    case_arms.append(arm)
                Dedent:
                    break
            else:
                raise new_error(tok3, "Expected variant or dedent")
        
        # Parse optional 'else' block
        let else_clause = Option.None()
        let tok2 = this.get_token()
        case tok2.kind:
            KwElse:
                else_clause = Option.Some(this.parse_block())
        else:
            this.unget_token(tok2)
        
        let c = ast.CaseStatement:
            value: case_value
            arms: case_arms
            else_clause: else_clause
        return ast.statement(ast.StatementKind.Case(c), location)

    fn parse_return_statement(location: Location) -> ast.Statement except CompilationError:
        # optionally parse expression (or newline)!
        let res_value: Option[ast.Expression] = Option.None()
        let tok2 = this.get_token()
        case tok2.kind:
            NewLine:
                pass
        else:
            this.unget_token(tok2)
            let ret_val = this.parse_expression()
            res_value = Option.Some(ret_val)
            this.parse_newline()
        return ast.return_statement(res_value, location)

    fn parse_raise_statement(location: Location) -> ast.Statement except CompilationError:
        let exc_val = this.parse_expression()
        this.parse_newline()
        return ast.raise_statement(exc_val, location)

    fn parse_expression() -> ast.Expression except CompilationError:
        log_trace("Parsing expression")
        return this.parse_expression2(0)

    fn parse_expression2(min_prec: int) -> ast.Expression except CompilationError:
        let expr = this.parse_unary()
        
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
                NotEquals:
                    op = ast.BinaryOperator.NotEquals()
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
            
            let rhs = this.parse_expression2(prec + 1)
            expr = ast.binop(expr, op, rhs, ast.undefined_type(), tok.location)

        return expr

    fn parse_unary() -> ast.Expression except CompilationError:
        let tok = this.get_token()
        case tok.kind:
            KwNot:
                let value = this.parse_unary()
                let op = ast.UnaryOperator.Not()
                return ast.unop(op, value, ast.undefined_type(), tok.location)
        else:
            this.unget_token(tok)
            return this.parse_atom()

    fn parse_atom() -> ast.Expression except CompilationError:
        let expr = ast.undefined_value()
        let tok = this.get_token()
        case tok.kind:
            Integer(v):
                expr = ast.integer_literal(v, tok.location)
            Float(v):
                expr = ast.float_literal(v, tok.location)
            String(v):
                expr = ast.string_literal(v, tok.location)
            Bool(v):
                expr = ast.bool_literal(v, tok.location)
            Identifier(v):
                expr = ast.name_ref(v, tok.location)
            BraceOpen:
                expr = this.parse_expression()
                let tok2 = this.get_token()
                case tok2.kind:
                    BraceClose:
                        pass
                else:
                    raise new_error(tok2, "Expected ')'")
        else:
            raise new_error(tok, "Unexpected token")

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
                        raise new_error(tok2, "Expected dedent")
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
                            let arg = this.parse_expression()
                            arguments.append(arg)
                            let tok4 = this.get_token()
                            case tok4.kind:
                                BraceClose:
                                    break
                                Comma:
                                    continue
                            else:
                                raise new_error(tok4, "Expected ')' or ','")

                    expr = ast.call(expr, arguments, ast.undefined_type(), tok.location)
                
                BracketOpen:
                    let arguments: List[ast.Expression] = List()
                    loop:
                        let arg = this.parse_expression()
                        arguments.append(arg)
                        let tok4 = this.get_token()
                        case tok4.kind:
                            BracketClose:
                                break
                            Comma:
                                continue
                        else:
                            raise new_error(tok4, "Expected ']' or ','")
                    expr = ast.subscript(expr, arguments, ast.undefined_type(), tok.location)
            else:
                this.unget_token(tok)
                break
        return expr
    
    fn parse_newline() except CompilationError:
        let tok = this.get_token()
        case tok.kind:
            NewLine:
                pass
        else:
            raise new_error(tok, "Expected newline")

    fn parse_indent() except CompilationError:
        let tok = this.get_token()
        case tok.kind:
            Indent:
                pass
        else:
            raise new_error(tok, "Expected indent")

    fn parse_colon() except CompilationError:
        let tok = this.get_token()
        case tok.kind:
            Colon:
                pass
        else:
            raise new_error(tok, "Expected ':'")

    fn get_token() -> Token:
        # Get token (EOF in case of end of file)
        return this.lex.next_token()

    fn unget_token(token: Token):
        this.lex.pushback_token(token)

    fn new_id() -> int:
        let x = this.next_id
        this.next_id += 1
        return x
