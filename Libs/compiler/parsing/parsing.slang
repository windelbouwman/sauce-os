
import ast
import std
from lexer import Lexer
from token import token_to_string, Token
from location import Location, Position
from datatypes import List, Result, Option, list1, option_unwrap
from vectype import Vector, new_vector
from pathlib import basename
from basepass import IdGen
from utils import log_debug, log_trace, log_info
from errors import CompilationError, SingleCompilationError
import errors

pub fn parse_source(filename: str, id_gen: IdGen) -> ast.Module except CompilationError:
    let source = std.read_file(filename)
    let modname = basename(path: filename)
    let parser = Parser(id_gen)
    parser.feed(source)
    parser.parse_module(filename, name: modname)

fn parse_statement_from_text(source: str, id_gen: IdGen, p1: Position) -> ast.Statement except CompilationError:
    # Invoke parsing, purely on statement.
    let parser = Parser(id_gen)
    parser.feed(source)
    parser.lex.row = p1.row
    parser.lex.start_col = p1.column
    parser.parse_statement()

fn parse_expr_from_text(source: str, id_gen: IdGen, p1: Position) -> ast.Expression except CompilationError:
    # Invoke parsing, purely on expression.
    let parser = Parser(id_gen)
    parser.feed(source)
    parser.lex.row = p1.row
    parser.lex.start_col = p1.column
    parser.parse_expression()

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
        let docstring = parse_optional_docstring()

        loop:
            let tok = get_token()
            let is_pub = false
            case tok.kind:
                KwPub:
                    is_pub = true
                    tok = get_token()
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
                KwMacro:
                    let macro_def = parse_macro_def()
                    definitions.append(ast.Definition.Macro(macro_def))
                KwFn:
                    let func_def = parse_func_def(this_parameter: Option.None())
                    definitions.append(ast.Definition.Function(func_def))
                KwExtern:
                    let libname = parse_raw_string()

                    tok = get_token()
                    case tok.kind:
                        KwFn:
                            let func_def = parse_extern_func_def(libname)
                            definitions.append(ast.Definition.Function(func_def))
                    else:
                        raise unexpected_token(tok, expected: "'fn'")
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

        ast.new_module(name, filename: this.filename, imports, definitions)

    fn parse_import() -> ast.Import except CompilationError:
        let modname = parse_name()
        parse_newline()
        ast.import_self(modname: modname.name, location: modname.location)

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

        ast.import_names(modname: modname.name, location: modname.location, names)

    fn parse_pub() -> bool:
        let tok = get_token()
        case tok.kind:
            KwPub:
                true
        else:
            unget_token(tok)
            false
    
    fn parse_macro_def() -> ast.MacroDef except CompilationError:
        # unimplemented("macro-def")
        let name_at = parse_name()
        let name = name_at.name
        let location = name_at.location

        parse_colon()
        parse_newline()
        parse_indent()
        let statement = parse_statement()
        parse_dedent()

        ast.MacroDef(name, location)

    fn parse_enum_def(location: Location) -> ast.EnumDef except CompilationError:
        let name = parse_name().name
        let type_parameters: List[ast.TypeParameter] = parse_type_parameters()

        parse_colon()
        parse_newline()
        parse_indent()
        let docstring = parse_optional_docstring()

        let variants: List[ast.EnumVariant] = List()
        let tag_index = 0
        while not try_parse_dedent():
            let name_at = parse_name()
            let payload_types: List[ast.Type] = List()
            let tok3 = get_token()
            case tok3.kind:
                ParenthesisOpen:
                    loop:
                        payload_types.append(parse_parameter_def().ty)

                        let tok4 = get_token()
                        case tok4.kind:
                            ParenthesisClose:
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

        ast.enum_def(name, id: new_id(), location, type_parameters, variants)

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
        type_parameters

    fn parse_struct_def() -> ast.StructDef except CompilationError:
        let name_at = parse_name()
        let type_parameters: List[ast.TypeParameter] = parse_type_parameters()
        parse_colon()
        parse_newline()
        parse_indent()
        let docstring = parse_optional_docstring()

        let fields: List[ast.StructField] = List()
        while not try_parse_dedent():
            let field_name_at = parse_name()
            parse_colon()
            let ty = parse_type()
            parse_newline()
            fields.append(ast.StructField(name: field_name_at.name, ty, location: field_name_at.location))

        ast.struct_def(name: name_at.name, id: new_id(), type_parameters, fields, location: name_at.location)

    fn parse_class_def() -> ast.ClassDef except CompilationError:
        let name_at = parse_name()
        log_debug("Parsing class: {name_at.name}")
        let type_parameters: List[ast.TypeParameter] = parse_type_parameters()
        parse_colon()
        parse_newline()
        parse_indent()
        let docstring = parse_optional_docstring()

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
            is_extern: Option.None()
            type_parameters
            definitions: inner_defs
            scope: ast.Scope()

        class_def.scope.class_scope = true
        
        # Prepare 'this' parameter:
        let type_arguments: List[ast.Type] = List()
        for type_parameter in type_parameters:
            type_arguments.append(ast.type_parameter_ref(type_parameter))
        this_type.change_to(to_type: ast.apply_tycon(tycon: ast.TyCon.Class(class_def), type_arguments))
        class_def

    fn parse_func_def(this_parameter: Option[ast.ParameterDef]) -> ast.FunctionDef except CompilationError:
        let name_at = parse_name()
        log_debug("Parsing function: {name_at.name}")
        let type_parameters = parse_type_parameters()
        let parameters = parse_parameters()
        let info = parse_function_info()

        # Body
        parse_colon()
        parse_newline()
        parse_indent()
        let docstring = parse_optional_docstring()

        let inner: Vector[ast.Statement] = new_vector()
        while not try_parse_dedent():
            let statement = parse_statement()
            inner.append(statement)
        let location = inner.first().location
        let body = ast.compound(inner, location)

        ast.function_def(name: name_at.name, type_parameters, this_parameter, parameters, return_type: info.return_type, except_type: info.except_type, body, location: name_at.location)
    
    fn parse_extern_func_def(libname: str) -> ast.FunctionDef except CompilationError:
        let name_at = parse_name()
        let name: str = name_at.name
        let type_parameters = parse_type_parameters()
        let parameters = parse_parameters()
        let info = parse_function_info()
        parse_newline()
        ast.extern_function_def(libname, name, type_parameters, parameters, return_type: info.return_type, location: name_at.location)

    fn parse_parameters() -> List[ast.ParameterDef] except CompilationError:
        let parameters: List[ast.ParameterDef] = List()
        parse_parenthesis_open()
        # ')' or parameters and ')'
        let tok = get_token()
        case tok.kind:
            ParenthesisClose:
                pass
        else:
            unget_token(tok)
            loop:
                parameters.append(parse_parameter_def())
                let tok4 = get_token()
                case tok4.kind:
                    ParenthesisClose:
                        break
                    Comma:
                        pass
                else:
                    raise unexpected_token(tok: tok4, expected: "')' or ','")
        parameters

    fn parse_function_info() -> ast.FunctionInfo except CompilationError:
        let return_type = parse_optional_return_type()
        let except_type = parse_optional_except_type()

        if has_parsed_question():
            return_type = ast.unreachable_type()
        ast.FunctionInfo(return_type, except_type)

    fn parse_optional_return_type() -> ast.Type except CompilationError:
        # Optional return type
        let tok = get_token()
        case tok.kind:
            Arrow:
                parse_type()
        else:
            unget_token(tok)
            ast.void_type()

    fn parse_optional_except_type() -> ast.Type except CompilationError:
        # Optional except type
        let tok = get_token()
        case tok.kind:
            KwExcept:
                parse_type()
        else:
            unget_token(tok)
            ast.void_type()

    fn parse_parameter_def() -> ast.ParameterDef except CompilationError:
        let name_at = parse_name()
        # Parse optional '?' to indicate label is optional at call-site
        let label_is_optional = has_parsed_question()
        parse_colon()
        let ty = parse_type()
        ast.parameter_def(name: name_at.name, id: new_id(), label_is_optional, ty, location: name_at.location)
    
    fn parse_optional_docstring() -> Option[str]:
        let tok = get_token()
        case tok.kind:
            StringContent(value):
                let tok2 = get_token()
                case tok2.kind:
                    NewLine:
                        Option.Some(value)
                else:
                    unget_token(tok2)
                    unget_token(tok)
                    Option[str].None()
        else:
            unget_token(tok)
            Option[str].None()

    fn has_parsed_question() -> bool:
        let tok = get_token()
        case tok.kind:
            Question:
                true
        else:
            unget_token(tok)
            false

    fn parse_var_def() -> ast.VariableDef except CompilationError:
        let name_at = parse_name()
        let name = name_at.name
        parse_colon()
        let ty = parse_type()

        # Optional '=' <expr>
        let tok = get_token()
        let var_init: Option[ast.Expression] = case tok.kind:
            Equals:
                Option.Some(parse_expression())
        else:
            unget_token(tok)
            Option[ast.Expression].None()

        parse_newline()
        let variable = ast.variable(name, id: new_id(), ty, location: name_at.location)
        ast.VariableDef(variable, value: ast.VariableDefValue.Intern(value: var_init))

    fn parse_type() -> ast.Type except CompilationError:
        let tok0 = get_token()
        case tok0.kind:
            KwFn:
                parse_function_type()
        else:
            unget_token(tok0)
            let expr = parse_expression()
            ast.type_expression(expr)
    
    fn parse_function_type() -> ast.Type except CompilationError:
        """ Parse function signature. """

        # '('
        parse_parenthesis_open()

        let parameter_types: List[ast.ParameterType] = List()
        # ')' or parameters and ')'
        let tok2 = get_token()
        case tok2.kind:
            ParenthesisClose:
                pass
        else:
            unget_token(tok2)
            loop:
                let label: Option[str] = Option.None()
                let param_type = parse_type()
                parameter_types.append(ast.ParameterType(label, ty: param_type))

                let tok4 = get_token()
                case tok4.kind:
                    ParenthesisClose:
                        break
                    Comma:
                        continue
                else:
                    raise unexpected_token(tok: tok4, expected: "')' or ','")

        # Optional return type
        let return_type = parse_optional_return_type()
        let except_type = ast.void_type()

        let info = ast.FunctionInfo:
            return_type
            except_type

        ast.function_type(parameter_types, info)

    fn parse_block() -> ast.Statement except CompilationError:
        # parse block of statements.
        log_trace("parsing block")

        parse_colon()
        parse_newline()
        parse_indent()

        let inner: Vector[ast.Statement] = new_vector()
        while not try_parse_dedent():
            let statement = parse_statement()
            inner.append(statement)
        let location = inner.first().location
        ast.compound(inner, location)
    
    fn parse_statement() -> ast.Statement except CompilationError:
        log_trace("parsing statement")
        let tok = get_token()
        case tok.kind:
            KwPass:
                parse_newline()
                ast.pass_statement(location: tok.location)
            KwBreak:
                parse_newline()
                ast.break_statement(location: tok.location)
            KwContinue:
                parse_newline()
                ast.continue_statement(location: tok.location)
            KwLet:
                parse_let_statement(location: tok.location)
            KwIf:
                parse_if_statement(location: tok.location)
            KwLoop:
                let body = parse_block()
                ast.loop_statement(body, location: tok.location)
            KwWhile:
                parse_while_statement(location: tok.location)
            KwCase:
                parse_case_statement(location: tok.location)
            KwSwitch:
                parse_switch_statement(location: tok.location)
            KwFor:
                parse_for_statement(location: tok.location)
            KwTry:
                parse_try_statement(location: tok.location)
            KwReturn:
                parse_return_statement(location: tok.location)
            KwRaise:
                parse_raise_statement(location: tok.location)
        else:
            unget_token(tok)
            parse_expression_statement()

    fn parse_expression_statement() -> ast.Statement except CompilationError:
        let expr = parse_expression()

        # Maybe we have an assignment or object initializer
        let tok = get_token()
        case tok.kind:
            Equals:
                parse_assignement_expression(target: expr, op: Option.None(), location: tok.location)
            PlusEquals:
                parse_assignement_expression(target: expr, op: Option.Some(ast.BinaryOperator.Add()), location: tok.location)
            MinusEquals:
                parse_assignement_expression(target: expr, op: Option.Some(ast.BinaryOperator.Sub()), location: tok.location)
            NewLine:
                ast.expression_statement(expr)
            Colon:
                ast.expression_statement(expr: parse_obj_init(obj_ty: expr, location: tok.location))
        else:
            raise unexpected_token(tok, expected: "newline, ':', '=', '+=' or '-='")
    
    fn parse_assignement_expression(target: ast.Expression, op: Option[ast.BinaryOperator], location: Location) -> ast.Statement except CompilationError:
        let value = parse_expression()
        parse_newline()
        ast.assignment_statement(target, op, value, location)
    
    fn parse_let_statement(location: Location) -> ast.Statement except CompilationError:
        let name_at = parse_name()
        let var_name = name_at.name
        let var_type = ast.undefined_type()
        let variable = ast.variable(name: var_name, id: new_id(), ty: var_type, location: name_at.location)
        
        let tok2 = get_token()
        let type_hint: Option[ast.Type] = case tok2.kind:
            Colon:
                # Type hint!
                Option.Some(parse_type())
        else:
            unget_token(tok2)
            Option[ast.Type].None()

        parse_equals()

        tok2 = get_token()
        let value = case tok2.kind:
            KwIf:
                ast.statement_expression(statement: parse_if_statement(location: tok2.location))
            KwCase:
                ast.statement_expression(statement: parse_case_statement(location: tok2.location))
            KwSwitch:
                ast.statement_expression(statement: parse_switch_statement(location: tok2.location))
        else:
            unget_token(tok2)
            let value2 = parse_expression()

            let tok = get_token()
            case tok.kind:
                NewLine:
                    value2
                Colon:
                    parse_obj_init(obj_ty: value2, location: tok.location)
            else:
                raise unexpected_token(tok, expected: "newline or ':'")
        
        ast.let_statement(variable, type_hint, value, location)
    
    fn parse_obj_init(obj_ty: ast.Expression, location: Location) -> ast.Expression except CompilationError:
        # Obj initializer!
        parse_newline()
        parse_indent()
        
        let obj_fields: List[ast.LabeledExpression] = List()
        while not try_parse_dedent():
            obj_fields.append(parse_labeled_expression())
            parse_newline()
        ast.call(callee: obj_ty, arguments: obj_fields, ty: ast.undefined_type(), location)
    
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
        let name: Option[str] = case value.kind:
            NameRef(name2):
                Option.Some(name2)
        else:
            Option[str].None()
        ast.LabeledExpression(location: value.location, name, value)

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
        
        ast.if_statement(condition, body: true_block, false_body: false_block, location)
    
    fn parse_while_statement(location: Location) -> ast.Statement except CompilationError:
        let condition = parse_expression()
        let body = parse_block()
        ast.while_statement(condition, body, location)

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
        ast.for_statement(iter_var, iter_value, body, location)

    fn parse_try_statement(location: Location) -> ast.Statement except CompilationError:
        let try_body = parse_block()

        # 'except'
        let tok = get_token()
        case tok.kind:
            KwExcept:
                pass
        else:
            raise unexpected_token(tok, expected: "'except'")

        parse_parenthesis_open()
        let name_at = parse_name()
        parse_colon()
        let except_type = parse_type()
        parse_parenthesis_close()
        let except_var = ast.variable(name: name_at.name, id: new_id(), ty: ast.undefined_type(), location: name_at.location)

        let except_body = parse_block()
        ast.try_statement(try_body, except_var, except_type, except_body, location)

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
        let tok2 = get_token()
        let else_clause = case tok2.kind:
            KwElse:
                Option.Some(parse_block())
        else:
            unget_token(tok2)
            Option[ast.Statement].None()
        
        ast.case_statement(value: case_value, arms: case_arms, else_clause, location)
    
    fn parse_case_arm(name: str, location: Location) -> ast.CaseArm except CompilationError:
        let variables: List[ast.Variable] = List()
        # Eventual payload values to unpack:
        let tok4 = get_token()
        case tok4.kind:
            ParenthesisOpen:
                loop:
                    let name_at = parse_name()
                    let variable = ast.variable(name: name_at.name, id: new_id(), ty: ast.undefined_type(), location: name_at.location)
                    variables.append(variable)
                    
                    let tok5 = get_token()
                    case tok5.kind:
                        ParenthesisClose:
                            break
                        Comma:
                            continue
                    else:
                        raise unexpected_token(tok: tok5, expected: "',' or ')'")
        else:
            unget_token(tok4)

        # Arm body:
        let statement = parse_block()
        ast.CaseArm:
            location
            name
            variables: variables
            block: ast.scoped_block(body: statement)
    
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
        ast.switch_statement(value: switch_value, arms, default_body, location)

    fn parse_return_statement(location: Location) -> ast.Statement except CompilationError:
        # optionally parse expression (or newline)!
        let tok2 = get_token()
        let res_value: Option[ast.Expression] = case tok2.kind:
            NewLine:
                Option[ast.Expression].None()
        else:
            unget_token(tok2)
            let ret_val = parse_expression()
            parse_newline()
            Option.Some(ret_val)
        ast.return_statement(value: res_value, location)

    fn parse_raise_statement(location: Location) -> ast.Statement except CompilationError:
        let value = parse_expression()
        parse_newline()
        ast.raise_statement(value, location)

    fn parse_expression() -> ast.Expression except CompilationError:
        # log_trace("Parsing expression")
        parse_expression2(min_prec: 0)

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

        expr

    fn parse_unary() -> ast.Expression except CompilationError:
        let tok = get_token()
        case tok.kind:
            KwNot:
                let value = parse_unary()
                let op = ast.UnaryOperator.Not()
                ast.unop(op, value, ty: ast.undefined_type(), location: tok.location)
            Minus:
                let value = parse_unary()
                let op = ast.UnaryOperator.Minus()
                ast.unop(op, value, ty: ast.undefined_type(), location: tok.location)
        else:
            unget_token(tok)
            parse_atom()

    fn parse_atom() -> ast.Expression except CompilationError:
        let tok = get_token()
        let expr = case tok.kind:
            Integer(value):
                ast.integer_literal(value, location: tok.location)
            Float(value):
                ast.float_literal(value, location: tok.location)
            StringStart:
                parse_string(location: tok.location)
            Char(value):
                ast.char_literal(value, location: tok.location)
            Bool(value):
                ast.bool_literal(value, location: tok.location)
            Identifier(name):
                ast.name_ref(name, location: tok.location)
            ParenthesisOpen:
                let expr = parse_expression()
                parse_parenthesis_close()
                expr
            BracketOpen:
                parse_array_literal(location: tok.location)
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
                ParenthesisOpen:
                    expr = parse_call_suffix(callee: expr)
                BracketOpen:
                    expr = parse_index_suffix(base: expr)
            else:
                unget_token(tok)
                break
        expr

    fn parse_raw_string() -> str except CompilationError:
        """ Parse string without interpolation """
        let tok = get_token()
        case tok.kind:
            StringStart:
                pass
        else:
            raise unexpected_token(tok, expected: "string start")

        tok = get_token()
        let text = case tok.kind:
            StringContent(value):
                value
        else:
            raise unexpected_token(tok, expected: "string content")

        tok = get_token()
        case tok.kind:
            StringEnd:
                pass
        else:
            raise unexpected_token(tok, expected: "string end")

        text

    fn parse_string(location: Location) -> ast.Expression except CompilationError:
        """ Parse possibly interpolated string. """
        # Gather parts
        let parts: List[ast.Expression] = List()
        loop:
            let tok = get_token()
            case tok.kind:
                StringContent(value):
                    let raw_string_expr = ast.string_literal(value, location: tok.location)
                    parts.append(raw_string_expr)

                BraceOpen:
                    let to_string_expr = parse_expression()
                    to_string_expr = ast.to_string(value: to_string_expr, location: to_string_expr.location)
                    parts.append(to_string_expr)
                    parse_brace_close()

                StringEnd:
                    break
            else:
                raise unexpected_token(tok, expected: "String content, '\"' or '\{'")

        # Concatenate parts
        if parts.is_empty():
            ast.string_literal(value: "", location)
        else:
            let x = parts.pop_front()
            while not parts.is_empty():
                let rhs = parts.pop_front()
                let location = Location(begin: x.location.begin, end: rhs.location.end)
                x = ast.binop(lhs: x, op: ast.BinaryOperator.Add(), rhs, ty: ast.str_type(), location)
            x

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
        ast.subscript(base, indici, ty: ast.undefined_type(), location)
    
    fn parse_call_suffix(callee: ast.Expression) -> ast.Expression except CompilationError:
        # print("CALL")
        # Handle '(arg1,arg2)' suffix
        # Or '()' or '(arg1)'
        let arguments: List[ast.LabeledExpression] = List()
        let tok2 = get_token()
        let begin = callee.location.begin
        let end = tok2.location.end
        case tok2.kind:
            ParenthesisClose:
                # no args call
                pass
        else:
            unget_token(tok2)
            # call with parameters

            loop:
                arguments.append(parse_labeled_expression())
                let tok4 = get_token()
                case tok4.kind:
                    ParenthesisClose:
                        end = tok4.location.end
                        break
                    Comma:
                        continue
                else:
                    raise unexpected_token(tok: tok4, expected: "')' or ','")

        let location = Location(begin, end)
        ast.call(callee, arguments, ty: ast.undefined_type(), location)
    
    fn parse_array_literal(location: Location) -> ast.Expression except CompilationError:
        let values: List[ast.Expression] = List()
        loop:
            let value = parse_expression()
            values.append(value)
            
            let tok5 = get_token()
            case tok5.kind:
                BracketClose:
                    location = Location(begin: location.begin, end: tok5.location.end)
                    break
                Comma:
                    continue
                Colon:
                    return parse_array_literal2(size: value, location)
            else:
                raise unexpected_token(tok: tok5, expected: "',', ':' or ']'")
        ast.array_literal(values, location)
    
    fn parse_array_literal2(size: ast.Expression, location: Location) -> ast.Expression except CompilationError:
        let ty = parse_type()
        let tok5 = get_token()
        case tok5.kind:
            BracketClose:
                pass
        else:
            raise unexpected_token(tok: tok5, expected: "']'")

        location = Location(begin: location.begin, end: tok5.location.end)
        ast.array_literal2(size, ty, location)

    fn parse_name() -> NameAtLocation except CompilationError:
        let tok = get_token()
        case tok.kind:
            Identifier(name):
                NameAtLocation(name, location: tok.location)
        else:
            raise unexpected_token(tok, expected: "name")

    fn parse_parenthesis_open() except CompilationError:
        let tok = get_token()
        case tok.kind:
            ParenthesisOpen:
                pass
        else:
            raise unexpected_token(tok, expected: "'('")

    fn parse_parenthesis_close() except CompilationError:
        let tok = get_token()
        case tok.kind:
            ParenthesisClose:
                pass
        else:
            raise unexpected_token(tok, expected: "')'")

    fn parse_brace_close() except CompilationError:
        let tok = get_token()
        case tok.kind:
            BraceClose:
                pass
        else:
            raise unexpected_token(tok, expected: "'}'")

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

    fn parse_dedent() except CompilationError:
        let tok = get_token()
        case tok.kind:
            Dedent:
                pass
        else:
            raise unexpected_token(tok, expected: "dedent")

    fn try_parse_dedent() -> bool:
        # expect dedent (eventually)
        let tok = get_token()
        case tok.kind:
            Dedent:
                true
        else:
            unget_token(tok)
            false

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
        lex.next_token()

    fn unget_token(token?: Token):
        lex.pushback_token(token)

    fn new_id() -> int:
        id_gen.new_id()

    fn unexpected_token(tok: Token, expected: str) -> CompilationError:
        new_error(location: tok.location, message: "Expected {expected}, got {token_to_string(tok)}")

    fn new_error(location: Location, message: str) -> CompilationError:
        let err = errors.new_error(location, message)
        errors.new_errors(filename: filename, errors: list1(err))

struct NameAtLocation:
    name: str
    location: Location


