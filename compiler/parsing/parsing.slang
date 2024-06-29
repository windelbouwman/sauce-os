
import ast
import std
from lexer import Lexer
from token import token_to_string, Token
from location import Location, Position
from datatypes import List, Result, Option, vec1, option_unwrap
from strlib import split_string
from basepass import IdGen
from utils import panic, log_debug, log_trace, log_info
from errors import CompilationError, SingleCompilationError
import errors


fn basename(path: str) -> str:
    # retrieve 'bla' from 'for/bar/bla.txt'
    let base = split_string(text: path, sep: '/').last()
    return split_string(text: base, sep: '.').first()

pub fn parse_source(filename: str, id_gen: IdGen) -> ast.Module except CompilationError:
    let source = std.read_file(filename)
    let modname = basename(path: filename)
    let parser = Parser(id_gen)
    parser.feed(source)
    return parser.parse_module(filename, name: modname)

fn parse_expr_from_text(source: str, id_gen: IdGen, p1: Position) -> ast.Expression except CompilationError:
    # Invoke parsing, purely on expression.
    let parser = Parser(id_gen)
    parser.feed(source)
    parser.lex.row = p1.row
    parser.lex.start_col = p1.column
    return parser.parse_expression()

class Parser:
    # An attempt at a recursive descent parser.
    var lex: Lexer = Lexer()
    var filename: Option[str] = Option.None()
    var id_gen: IdGen
    var modname: Option[str] = Option.None()

    fn feed(source: str):
        lex.init(source)
    
    fn parse_module(filename: str, name: str) -> ast.Module except CompilationError:
        let definitions: List[ast.Definition] = List()
        let imports: List[ast.Import] = List()
        this.filename = Option.Some(filename)
        this.modname = Option.Some(name)

        loop:
            let tok = lex.next_token()
            let is_pub = false
            case tok.kind:
                KwPub:
                    is_pub = true
                    tok = lex.next_token()
            else:
                pass
            
            case tok.kind:
                Eof:
                    # We are done!
                    break
                KwImport:
                    imports.append(parse_import())
                KwFrom:
                    imports.append(parse_from_import())
                KwFn:
                    let func_def = parse_func_def(this_parameter: Option.None())
                    definitions.append(ast.Definition.Function(func_def))
                KwExtern:
                    let extern_func_def = parse_extern_func_def()
                    definitions.append(ast.Definition.ExternFunction(extern_func_def))
                KwEnum:
                    let enum_def = parse_enum_def(location: tok.location)
                    definitions.append(ast.Definition.Enum(enum_def))
                KwStruct:
                    let struct_def = parse_struct_def()
                    definitions.append(ast.Definition.Struct(struct_def))
                KwClass:
                    let class_def = parse_class_def()
                    definitions.append(ast.Definition.Class(class_def))
                KwVar:
                    let var_def = parse_var_def()
                    definitions.append(ast.Definition.Var(var_def))
            else:
                raise unexpected_token(tok, expected: "import, fn, enum, struct, class, extern")

        let program = ast.new_module(name, filename: this.filename, imports, definitions)
        return program

    fn parse_import() -> ast.Import except CompilationError:
        let modname = parse_name()
        parse_newline()
        return ast.import_self(modname: modname.name, location: modname.location)

    fn parse_from_import() -> ast.Import except CompilationError:
        let modname = parse_name()

        # 'import'
        let tok = get_token()
        case tok.kind:
            KwImport:
                pass
        else:
            raise unexpected_token(tok, expected: "'import'")
        
        let names: List[str] = List()

        # list of names until newline:
        loop:
            names.append(parse_name().name)
            let tok2 = get_token()
            case tok2.kind:
                Comma:
                    continue
                NewLine:
                    break
            else:
                raise unexpected_token(tok: tok2, expected: "',' or newline")

        return ast.import_names(modname: modname.name, location: modname.location, names)

    fn parse_pub() -> bool:
        let is_pub = false
        let tok = get_token()
        case tok.kind:
            KwPub:
                is_pub = true
        else:
            unget_token(tok)
        return is_pub

    fn parse_enum_def(location: Location) -> ast.EnumDef except CompilationError:
        let name = parse_name().name
        let type_parameters: List[ast.TypeParameter] = parse_type_parameters()

        parse_colon()
        parse_newline()
        parse_indent()

        let variants: List[ast.EnumVariant] = List()
        let tag_index = 0
        while not try_parse_dedent():
            let name_at = parse_name()
            let payload_types: List[ast.Type] = List()
            let tok3 = get_token()
            case tok3.kind:
                BraceOpen:
                    loop:
                        payload_types.append(parse_parameter_def().ty)

                        let tok4 = get_token()
                        case tok4.kind:
                            BraceClose:
                                break
                            Comma:
                                continue
                        else:
                            raise unexpected_token(tok: tok4, expected: "',' or ')'")
            else:
                unget_token(tok3)
            
            let variant = ast.EnumVariant:
                name: name_at.name
                tag_value: tag_index
                payload: payload_types
                location: name_at.location
            variants.append(variant)
            tag_index += 1

            parse_newline()

        return ast.enum_def(name, id: new_id(), location, type_parameters, variants)

    fn parse_type_parameters() -> List[ast.TypeParameter] except CompilationError:
        let type_parameters: List[ast.TypeParameter] = List()
        let tok = get_token()
        case tok.kind:
            BracketOpen:
                # take in type parameters
                loop:
                    let name_at = parse_name()
                    type_parameters.append(ast.new_type_parameter(name: name_at.name, id: new_id(), location: name_at.location))

                    let tok2 = get_token()
                    case tok2.kind:
                        BracketClose:
                            break
                        Comma:
                            continue
                    else:
                        raise unexpected_token(tok: tok2, expected: "',' or ']'")
        else:
            unget_token(tok)
        return type_parameters

    fn parse_struct_def() -> ast.StructDef except CompilationError:
        let name_at = parse_name()
        let type_parameters: List[ast.TypeParameter] = parse_type_parameters()
        parse_colon()
        parse_newline()
        parse_indent()

        let fields: List[ast.StructField] = List()
        while not try_parse_dedent():
            let field_name_at = parse_name()
            parse_colon()
            let ty = parse_type()
            parse_newline()
            fields.append(ast.StructField(name: field_name_at.name, ty, location: field_name_at.location))

        return ast.struct_def(name: name_at.name, id: new_id(), type_parameters, fields, location: name_at.location)

    fn parse_class_def() -> ast.ClassDef except CompilationError:
        let name_at = parse_name()
        let type_parameters: List[ast.TypeParameter] = parse_type_parameters()
        parse_colon()
        parse_newline()
        parse_indent()

        let inner_defs: List[ast.Definition] = List()
        # TODO: create type instance per 'this' parameter
        let this_type = ast.undefined_type()
        loop:
            # expect var/fn def or dedent (eventually)
            let tok = get_token()
            case tok.kind:
                KwVar:
                    let var_def = parse_var_def()
                    inner_defs.append(ast.Definition.Var(var_def))
                KwFn:
                    let this_parameter = ast.parameter_def(name: "this", id: new_id(), label_is_optional: true, ty: this_type, location: tok.location)
                    let func_def = parse_func_def(this_parameter: Option.Some(this_parameter))
                    inner_defs.append(ast.Definition.Function(func_def))
                Dedent:
                    break
            else:
                raise unexpected_token(tok, expected: "field or dedent")

        let class_def = ast.ClassDef:
            id: ast.NodeId(name: name_at.name, id: new_id())
            location: name_at.location
            is_extern: false
            type_parameters
            definitions: inner_defs
            scope: ast.Scope()

        class_def.scope.class_scope = true
        
        # Prepare 'this' parameter:
        let type_arguments: List[ast.Type] = List()
        for type_parameter in type_parameters:
            type_arguments.append(ast.type_parameter_ref(type_parameter))
        ast.change_type_to(ty: this_type, ty2: ast.apply_tycon(tycon: ast.TyCon.Class(class_def), type_arguments))
        return class_def

    fn parse_func_def(this_parameter: Option[ast.ParameterDef]) -> ast.FunctionDef except CompilationError:
        let name_at = parse_name()
        log_debug("Parsing function: {name_at.name}")
        let type_parameters = parse_type_parameters()
        let parameters = parse_parameters()
        let info = parse_function_info()

        # Body
        let body = parse_block()

        let function_def = ast.function_def(name: name_at.name, id: new_id(), type_parameters, this_parameter, parameters, return_type: info.return_type, except_type: info.except_type, body, location: name_at.location)
        function_def.info.no_return = info.no_return
        return function_def
    
    fn parse_extern_func_def() -> ast.ExternFunctionDef except CompilationError:
        let tok = get_token()
        case tok.kind:
            KwFn:
                pass
        else:
            raise unexpected_token(tok, expected: "'fn'")
        let name_at = parse_name()
        let name: str = name_at.name
        let type_parameters = parse_type_parameters()
        let parameters = parse_parameters()
        let info = parse_function_info()
        parse_newline()

        let parameter_types = ast.get_parameter_types_from_parameters(parameters)

        let extern_function_def = ast.extern_function_def(modname: option_unwrap(modname), name, type_parameters, parameter_types, return_type: info.return_type, location: name_at.location)
        extern_function_def.info.no_return = info.no_return
        return extern_function_def

    fn parse_parameters() -> List[ast.ParameterDef] except CompilationError:
        let parameters: List[ast.ParameterDef] = List()
        parse_brace_open()
        # ')' or parameters and ')'
        let tok = get_token()
        case tok.kind:
            BraceClose:
                pass
        else:
            unget_token(tok)
            loop:
                parameters.append(parse_parameter_def())
                let tok4 = get_token()
                case tok4.kind:
                    BraceClose:
                        break
                    Comma:
                        pass
                else:
                    raise unexpected_token(tok: tok4, expected: "')' or ','")
        return parameters

    fn parse_function_info() -> ast.FunctionInfo except CompilationError:
        let return_type = parse_optional_return_type()

        # Optional except type
        let except_type: ast.Type = ast.void_type()
        let tok = get_token()
        case tok.kind:
            KwExcept:
                except_type = parse_type()
        else:
            unget_token(tok)
        let no_return = has_parsed_question()
        return ast.FunctionInfo(no_return, return_type, except_type)

    fn parse_optional_return_type() -> ast.Type except CompilationError:
        # Optional return type
        let return_type: ast.Type = ast.void_type()
        let tok = get_token()
        case tok.kind:
            Arrow:
                return_type = parse_type()
        else:
            unget_token(tok)
        return return_type

    fn parse_parameter_def() -> ast.ParameterDef except CompilationError:
        let name_at = parse_name()
        # Parse optional '?' to indicate label is optional at call-site
        let label_is_optional = has_parsed_question()
        parse_colon()
        let ty = parse_type()
        return ast.parameter_def(name: name_at.name, id: new_id(), label_is_optional, ty, location: name_at.location)
    
    fn has_parsed_question() -> bool:
        let q = false
        let tok = get_token()
        case tok.kind:
            Question:
                q = true
        else:
            unget_token(tok)
        return q

    fn parse_var_def() -> ast.VariableDef except CompilationError:
        let name_at = parse_name()
        let name = name_at.name
        parse_colon()
        let ty = parse_type()

        # Optional '=' <expr>
        let var_init: Option[ast.Expression] = Option.None()
        let tok = get_token()
        case tok.kind:
            Equals:
                var_init = Option.Some(parse_expression())
        else:
            unget_token(tok)

        parse_newline()
        let variable = ast.variable(name, id: new_id(), ty, location: name_at.location)
        let var_def = ast.VariableDef(variable, value: var_init)
        return var_def

    fn parse_type() -> ast.Type except CompilationError:
        let tok0 = get_token()
        case tok0.kind:
            KwFn:
                # Parse function signature.

                # '('
                parse_brace_open()

                let parameter_types: List[ast.ParameterType] = List()
                # ')' or parameters and ')'
                let tok2 = get_token()
                case tok2.kind:
                    BraceClose:
                        pass
                else:
                    unget_token(tok2)
                    loop:
                        let label: Option[str] = Option.None()
                        let param_type = parse_type()
                        parameter_types.append(ast.ParameterType(label, ty: param_type))

                        let tok4 = get_token()
                        case tok4.kind:
                            BraceClose:
                                break
                            Comma:
                                continue
                        else:
                            raise unexpected_token(tok: tok4, expected: "')' or ','")

                # Optional return type
                let return_type = parse_optional_return_type()
                let except_type = ast.void_type()

                let info = ast.FunctionInfo:
                    no_return: false
                    return_type
                    except_type

                return ast.function_type(parameter_types, info)
        else:
            unget_token(tok0)
            let expr = parse_expression()
            return ast.type_expression(expr)

    fn parse_block() -> ast.Statement except CompilationError:
        # parse block of statements.
        log_trace("parsing block")

        parse_colon()
        parse_newline()
        parse_indent()

        let inner: List[ast.Statement] = List()
        while not try_parse_dedent():
            let statement = parse_statement()
            inner.append(statement)
        let location = inner.first().location
        return ast.compound(inner, location)
    
    fn parse_statement() -> ast.Statement except CompilationError:
        log_trace("parsing statement")
        let tok = get_token()
        case tok.kind:
            KwPass:
                parse_newline()
                return ast.pass_statement(location: tok.location)
            KwBreak:
                parse_newline()
                return ast.break_statement(location: tok.location)
            KwContinue:
                parse_newline()
                return ast.continue_statement(location: tok.location)
            KwLet:
                return parse_let_statement(location: tok.location)
            KwIf:
                return parse_if_statement(location: tok.location)
            KwLoop:
                let body = parse_block()
                return ast.loop_statement(body, location: tok.location)
            KwWhile:
                return parse_while_statement(location: tok.location)
            KwCase:
                return parse_case_statement(location: tok.location)
            KwSwitch:
                return parse_switch_statement(location: tok.location)
            KwFor:
                return parse_for_statement(location: tok.location)
            KwTry:
                return parse_try_statement(location: tok.location)
            KwReturn:
                return parse_return_statement(location: tok.location)
            KwRaise:
                return parse_raise_statement(location: tok.location)
        else:
            unget_token(tok)
            return parse_expression_statement()

    fn parse_expression_statement() -> ast.Statement except CompilationError:
        let expr = parse_expression()
        let stmt = ast.expression_statement(expr)

        # Maybe we have an assignment
        let is_assign = true
        let assign_op = Option.None()
        let tok2 = get_token()
        case tok2.kind:
            Equals:
                pass
            PlusEquals:  # Assignment '+='
                assign_op = Option.Some(ast.BinaryOperator.Add())
            MinusEquals:
                assign_op = Option.Some(ast.BinaryOperator.Sub())
        else:
            is_assign = false
            unget_token(tok2)
        
        if is_assign:
            # Assignment!
            let value = parse_expression()
            stmt = ast.assignment_statement(target: expr, op: assign_op, value, location: tok2.location)

        parse_newline()
        return stmt
    
    fn parse_let_statement(location: Location) -> ast.Statement except CompilationError:
        let name_at = parse_name()
        let var_name = name_at.name
        let var_type = ast.undefined_type()
        let variable = ast.variable(name: var_name, id: new_id(), ty: var_type, location: name_at.location)
        
        let type_hint: Option[ast.Type] = Option.None()

        let tok2 = get_token()
        case tok2.kind:
            Colon:
                # Type hint!
                type_hint = Option.Some(parse_type())
        else:
            unget_token(tok2)

        parse_equals()
        let value = parse_expression()

        tok2 = get_token()
        case tok2.kind:
            NewLine:
                pass
            Colon:
                value = parse_obj_init(obj_ty: value, location: tok2.location)
        else:
            raise unexpected_token(tok: tok2, expected: "newline or ':'")
        
        return ast.let_statement(variable, type_hint, value, location)
    
    fn parse_obj_init(obj_ty: ast.Expression, location: Location) -> ast.Expression except CompilationError:
        # Obj initializer!
        parse_newline()
        parse_indent()
        
        let obj_fields: List[ast.LabeledExpression] = List()
        while not try_parse_dedent():
            obj_fields.append(parse_labeled_expression())
            parse_newline()
        return ast.call(callee: obj_ty, arguments: obj_fields, ty: ast.undefined_type(), location)
    
    fn parse_labeled_expression() -> ast.LabeledExpression except CompilationError:
        # Parse ID ':' expression | expression
        let tok = get_token()
        case tok.kind:
            Identifier(name):
                let tok2 = get_token()
                case tok2.kind:
                    Colon:
                        # Parse ID ':' expression
                        let value = parse_expression()
                        return ast.LabeledExpression(location: tok.location, name: Option.Some(name), value)
                else:
                    unget_token(tok2)
                    unget_token(tok)
        else:
            unget_token(tok)

        # Parse expression
        let value = parse_expression()
        let name: Option[str] = Option.None()
        case value.kind:
            NameRef(name2):
                name = Option.Some(name2)
        else:
            pass
        return ast.LabeledExpression(location: value.location, name, value)

    fn parse_if_statement(location: Location) -> ast.Statement except CompilationError:
        # Parse if-statement (if or elif keyword already parsed)

        let condition = parse_expression()
        let true_block = parse_block()
        
        # else-block or elif-block:
        let false_block = ast.pass_statement(location)
        let tok2 = get_token()
        case tok2.kind:
            KwElse:
                false_block = parse_block()
            KwElif:
                false_block = parse_if_statement(location: tok2.location)
        else:
            unget_token(tok2)
        
        return ast.if_statement(condition, body: true_block, false_body: false_block, location)
    
    fn parse_while_statement(location: Location) -> ast.Statement except CompilationError:
        let condition = parse_expression()
        let body = parse_block()
        return ast.while_statement(condition, body, location)

    fn parse_for_statement(location: Location) -> ast.Statement except CompilationError:
        let name_at = parse_name()

        # 'in'
        let tok2 = get_token()
        case tok2.kind:
            KwIn:
                pass
        else:
            raise unexpected_token(tok: tok2, expected: "'in'")

        let iter_value = parse_expression()

        # ':' + indented block:
        let body = parse_block()
        let iter_var = ast.variable(name: name_at.name, id: new_id(), ty: ast.undefined_type(), location: name_at.location)
        return ast.for_statement(iter_var, iter_value, body, location)

    fn parse_try_statement(location: Location) -> ast.Statement except CompilationError:
        let try_body = parse_block()

        # 'except'
        let tok = get_token()
        case tok.kind:
            KwExcept:
                pass
        else:
            raise unexpected_token(tok, expected: "'except'")

        parse_brace_open()
        let name_at = parse_name()
        parse_colon()
        let except_type = parse_type()
        parse_brace_close()
        let except_var = ast.variable(name: name_at.name, id: new_id(), ty: ast.undefined_type(), location: name_at.location)

        let except_body = parse_block()
        return ast.try_statement(try_body, except_var, except_type, except_body, location)

    fn parse_case_statement(location: Location) -> ast.Statement except CompilationError:
        # Value
        let case_value = parse_expression()
        parse_colon()
        parse_newline()
        parse_indent()
        
        let case_arms: List[ast.CaseArm] = List()
        while not try_parse_dedent():
            let name_at = parse_name()
            case_arms.append(parse_case_arm(name: name_at.name, location: name_at.location))
        
        # Parse optional 'else' block
        let else_clause = Option.None()
        let tok2 = get_token()
        case tok2.kind:
            KwElse:
                else_clause = Option.Some(parse_block())
        else:
            unget_token(tok2)
        
        return ast.case_statement(value: case_value, arms: case_arms, else_clause, location)
    
    fn parse_case_arm(name: str, location: Location) -> ast.CaseArm except CompilationError:
        let variables: List[ast.Variable] = List()
        # Eventual payload values to unpack:
        let tok4 = get_token()
        case tok4.kind:
            BraceOpen:
                loop:
                    let name_at = parse_name()
                    let variable = ast.variable(name: name_at.name, id: new_id(), ty: ast.undefined_type(), location: name_at.location)
                    variables.append(variable)
                    
                    let tok5 = get_token()
                    case tok5.kind:
                        BraceClose:
                            break
                        Comma:
                            continue
                    else:
                        raise unexpected_token(tok: tok5, expected: "',' or ')'")
        else:
            unget_token(tok4)

        # Arm body:
        let statement = parse_block()
        let arm = ast.CaseArm:
            location
            name
            variables: variables
            block: ast.scoped_block(body: statement)
        return arm
    
    fn parse_switch_statement(location: Location) -> ast.Statement except CompilationError:
        let switch_value = parse_expression()
        parse_colon()
        parse_newline()
        parse_indent()
        let arms: List[ast.SwitchArm] = List()
        while not try_parse_dedent():
            let value = parse_expression()
            let block = ast.scoped_block(body: parse_block())
            arms.append(ast.SwitchArm(location: value.location, value, block))
        
        parse_kw_else()
        let default_body = parse_block()
        return ast.switch_statement(value: switch_value, arms, default_body, location)

    fn parse_return_statement(location: Location) -> ast.Statement except CompilationError:
        # optionally parse expression (or newline)!
        let res_value: Option[ast.Expression] = Option.None()
        let tok2 = get_token()
        case tok2.kind:
            NewLine:
                pass
        else:
            unget_token(tok2)
            let ret_val = parse_expression()
            res_value = Option.Some(ret_val)
            parse_newline()
        return ast.return_statement(value: res_value, location)

    fn parse_raise_statement(location: Location) -> ast.Statement except CompilationError:
        let value = parse_expression()
        parse_newline()
        return ast.raise_statement(value, location)

    fn parse_expression() -> ast.Expression except CompilationError:
        log_trace("Parsing expression")
        return parse_expression2(min_prec: 0)

    fn parse_expression2(min_prec: int) -> ast.Expression except CompilationError:
        let expr = parse_unary()
        
        loop:
            # Determine next token and new precedence
            let tok = get_token()
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
                BitOr:
                    op = ast.BinaryOperator.BitOr()
                    prec = 51
                BitXor:
                    op = ast.BinaryOperator.BitXor()
                    prec = 52
                BitAnd:
                    op = ast.BinaryOperator.BitAnd()
                    prec = 53
                ShiftLeft:
                    op = ast.BinaryOperator.ShiftLeft()
                    prec = 55
                ShiftRight:
                    op = ast.BinaryOperator.ShiftRight()
                    prec = 55
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
                unget_token(tok)
                break
            
            if prec < min_prec:
                unget_token(tok)
                break
            
            let rhs = parse_expression2(min_prec: prec + 1)
            let location = Location(begin: expr.location.begin, end: rhs.location.end)
            expr = ast.binop(lhs: expr, op, rhs, ty: ast.undefined_type(), location)

        return expr

    fn parse_unary() -> ast.Expression except CompilationError:
        let tok = get_token()
        case tok.kind:
            KwNot:
                let value = parse_unary()
                let op = ast.UnaryOperator.Not()
                return ast.unop(op, value, ty: ast.undefined_type(), location: tok.location)
            Minus:
                let value = parse_unary()
                let op = ast.UnaryOperator.Minus()
                return ast.unop(op, value, ty: ast.undefined_type(), location: tok.location)
        else:
            unget_token(tok)
            return parse_atom()

    fn parse_atom() -> ast.Expression except CompilationError:
        let expr = ast.undefined_value()
        let tok = get_token()
        case tok.kind:
            Integer(value):
                expr = ast.integer_literal(value, location: tok.location)
            Float(value):
                expr = ast.float_literal(value, location: tok.location)
            String(value):
                expr = process_fstring(literal: value, location: tok.location)
            Char(value):
                expr = ast.char_literal(value, location: tok.location)
            Bool(value):
                expr = ast.bool_literal(value, location: tok.location)
            Identifier(name):
                expr = ast.name_ref(name, location: tok.location)
            BraceOpen:
                expr = parse_expression()
                parse_brace_close()
            BracketOpen:
                expr = parse_array_literal(location: tok.location)
        else:
            raise unexpected_token(tok, expected: "integer, string, identifier, '('")

        # Attempt suffixes
        loop:
            tok = get_token()
            case tok.kind:
                Dot:
                    # handle '.attribute' suffix
                    let attr_at = parse_name()
                    let location = Location(begin: expr.location.begin, end: attr_at.location.end)
                    expr = ast.get_attr(base: expr, field: attr_at.name, ty: ast.undefined_type(), location)
                BraceOpen:
                    expr = parse_call_suffix(callee: expr)
                BracketOpen:
                    expr = parse_index_suffix(base: expr)
            else:
                unget_token(tok)
                break
        return expr
    
    fn parse_index_suffix(base: ast.Expression) -> ast.Expression except CompilationError:
        let begin = base.location.begin
        let end = base.location.end
        let indici: List[ast.Expression] = List()
        loop:
            indici.append(parse_expression())
            let tok4 = get_token()
            case tok4.kind:
                BracketClose:
                    end = tok4.location.end
                    break
                Comma:
                    continue
            else:
                raise unexpected_token(tok: tok4, expected: "']' or ','")
        let location = Location(begin, end)
        return ast.subscript(base, indici, ty: ast.undefined_type(), location)
    
    fn parse_call_suffix(callee: ast.Expression) -> ast.Expression except CompilationError:
        # print("CALL")
        # Handle '(arg1,arg2)' suffix
        # Or '()' or '(arg1)'
        let arguments: List[ast.LabeledExpression] = List()
        let tok2 = get_token()
        let begin = callee.location.begin
        let end = tok2.location.end
        case tok2.kind:
            BraceClose:
                # no args call
                pass
        else:
            unget_token(tok2)
            # call with parameters

            loop:
                arguments.append(parse_labeled_expression())
                let tok4 = get_token()
                case tok4.kind:
                    BraceClose:
                        end = tok4.location.end
                        break
                    Comma:
                        continue
                else:
                    raise unexpected_token(tok: tok4, expected: "')' or ','")

        let location = Location(begin, end)
        return ast.call(callee, arguments, ty: ast.undefined_type(), location)
    
    fn parse_array_literal(location: Location) -> ast.Expression except CompilationError:
        let values: List[ast.Expression] = List()
        loop:
            let value = parse_expression()
            values.append(value)
            
            let tok5 = get_token()
            case tok5.kind:
                BracketClose:
                    break
                Comma:
                    continue
                Colon:
                    return parse_array_literal2(value, location)
            else:
                raise unexpected_token(tok: tok5, expected: "',', ':' or ']'")
        return ast.array_literal(values, location)
    
    fn parse_array_literal2(value: ast.Expression, location: Location) -> ast.Expression except CompilationError:
        let size = parse_expression()
        let tok5 = get_token()
        case tok5.kind:
            BracketClose:
                pass
        else:
            raise unexpected_token(tok: tok5, expected: "']'")

        return ast.array_literal2(value, size, location)

    fn parse_name() -> NameAtLocation except CompilationError:
        let tok = get_token()
        case tok.kind:
            Identifier(name):
                return NameAtLocation(name, location: tok.location)
        else:
            raise unexpected_token(tok, expected: "name")

    fn parse_brace_open() except CompilationError:
        let tok = get_token()
        case tok.kind:
            BraceOpen:
                pass
        else:
            raise unexpected_token(tok, expected: "'('")

    fn parse_brace_close() except CompilationError:
        let tok = get_token()
        case tok.kind:
            BraceClose:
                pass
        else:
            raise unexpected_token(tok, expected: "')'")

    fn parse_newline() except CompilationError:
        let tok = get_token()
        case tok.kind:
            NewLine:
                pass
        else:
            raise unexpected_token(tok, expected: "newline")

    fn parse_indent() except CompilationError:
        let tok = get_token()
        case tok.kind:
            Indent:
                pass
        else:
            raise unexpected_token(tok, expected: "indent")

    fn try_parse_dedent() -> bool:
        # expect dedent (eventually)
        let tok = get_token()
        case tok.kind:
            Dedent:
                return true
        else:
            unget_token(tok)
            return false

    fn parse_kw_else() except CompilationError:
        let tok = get_token()
        case tok.kind:
            KwElse:
                pass
        else:
            raise unexpected_token(tok, expected: "'else'")

    fn parse_colon() except CompilationError:
        let tok = get_token()
        case tok.kind:
            Colon:
                pass
        else:
            raise unexpected_token(tok, expected: "':'")

    fn parse_equals() except CompilationError:
        let tok = get_token()
        case tok.kind:
            Equals:
                pass
        else:
            raise unexpected_token(tok, expected: "'='")

    fn get_token() -> Token:
        # Get token (EOF in case of end of file)
        return lex.next_token()

    fn unget_token(token?: Token):
        lex.pushback_token(token)

    fn new_id() -> int:
        return id_gen.new_id()

    fn unexpected_token(tok: Token, expected: str) -> CompilationError:
        return new_error(location: tok.location, message: "Expected {expected}, got {token_to_string(tok)}")

    fn new_error(location: Location, message: str) -> CompilationError:
        let err = errors.new_error(location, message)
        return errors.new_errors(filename: filename, errors: vec1(err))

    fn process_fstring(literal: str, location: Location) -> ast.Expression except CompilationError:
        # Check strings for parts surrounded by '{' and '}'
        let txt_length = std.str_len(text: literal)
        if txt_length == 0:
            return ast.string_literal(value: "", location)

        let parts: List[ast.Expression] = List()

        let index = 0
        let begin = index
        let end = index
        let in_braces = false

        while index < txt_length:
            let c = std.str_get(text: literal, index)
            if not in_braces and std.ord(c) == 123:  # { -> 123
                in_braces = true

                # Raw string part
                end = index
                if begin < end:
                    let raw_string_value = std.str_slice(text: literal, begin, end)
                    let raw_string_expr = ast.string_literal(value: raw_string_value, location)
                    parts.append(raw_string_expr)
                begin = index + 1
            elif in_braces and std.ord(c) == 125:  # } -> 125
                in_braces = false

                # Expression which must be turned into string
                end = index
                if begin < end:
                    # Skip past first " of string:
                    let p1 = Position(row: location.begin.row, column: location.begin.column + begin + 1)
                    let expr_text = std.str_slice(text: literal, begin, end)
                    let to_string_expr: ast.Expression = parse_expr_from_text(source: expr_text, id_gen: id_gen, p1)
                    to_string_expr = ast.to_string(value: to_string_expr, location: to_string_expr.location)
                    parts.append(to_string_expr)
                begin = index + 1

            index += 1
        
        if in_braces:
            raise new_error(location, message: "invalid f-string!")

        # Last part:
        end = index
        if begin < end:
            let raw_string_value2 = std.str_slice(text: literal, begin, end)
            let raw_string_expr2 = ast.string_literal(value: raw_string_value2, location)
            parts.append(raw_string_expr2)
        
        let x = parts.pop_front()
        while not parts.is_empty():
            x = ast.binop(lhs: x, op: ast.BinaryOperator.Add(), rhs: parts.pop_front(), ty: ast.str_type(), location)
        return x

struct NameAtLocation:
    name: str
    location: Location


