
import ast
import std
from lexer import Lexer
from token import token_to_string, Token
from location import Location, location_default
from datatypes import List, Result, Option, vec1
from strlib import split_string
from basepass import IdGen
from utils import panic, log_debug, log_trace, log_info
from errors import CompilationError, SingleCompilationError
import errors


fn basename(path: str) -> str:
    # retrieve 'bla' from 'for/bar/bla.txt'
    let base = split_string(value: path, sep: '/').last()
    return split_string(value: base, sep: '.').first()

fn parse_source(filename: str, id_gen: IdGen) -> ast.Module except CompilationError:
    let source = std.read_file(filename)
    let modname = basename(path: filename)
    let parser = Parser(id_gen)
    parser.feed(source)
    return parser.parse_module(filename, name: modname)

fn parse_expr_from_text(source: str, id_gen: IdGen) -> ast.Expression except CompilationError:
    # Invoke parsing, purely on expression.
    let parser = Parser(id_gen)
    parser.feed(source)
    return parser.parse_expression()

class Parser:
    # An attempt at a recursive descent parser.
    var lex: Lexer = Lexer()
    var filename: Option[str] = Option.None()
    var id_gen: IdGen

    fn feed(source: str):
        this.lex.init(source)
    
    fn parse_module(filename: str, name: str) -> ast.Module except CompilationError:
        let definitions: List[ast.Definition] = List()
        let imports: List[ast.Import] = List()
        this.filename = Option.Some(filename)

        loop:
            let tok = this.lex.next_token()
            case tok.kind:
                Eof:
                    # We are done!
                    break
                KwImport:
                    imports.append(this.parse_import())
                KwFrom:
                    imports.append(this.parse_from_import())
                KwFn:
                    let func_def = this.parse_func_def(location: tok.location, this_parameter: Option.None())
                    definitions.append(ast.Definition.Function(func_def))
                KwEnum:
                    let enum_def = this.parse_enum_def(location: tok.location)
                    definitions.append(ast.Definition.Enum(enum_def))
                KwStruct:
                    let struct_def = this.parse_struct_def(location: tok.location)
                    definitions.append(ast.Definition.Struct(struct_def))
                KwClass:
                    let class_def = this.parse_class_def(location: tok.location)
                    definitions.append(ast.Definition.Class(class_def))
            else:
                raise this.new_error(tok, message: "Unexpected token")

        let program = ast.new_module(name, filename: this.filename, imports, definitions)
        return program

    fn parse_import() -> ast.Import except CompilationError:
        let modname = this.parse_name()
        this.parse_newline()
        return ast.import_self(modname: modname.name, location: modname.location)

    fn parse_from_import() -> ast.Import except CompilationError:
        let modname = this.parse_name()

        # 'import'
        let tok = this.get_token()
        case tok.kind:
            KwImport:
                pass
        else:
            raise this.new_error(tok, message: "Expected 'import'")
        
        let names: List[str] = List()

        # list of names until newline:
        loop:
            names.append(this.parse_name().name)
            let tok2 = this.get_token()
            case tok2.kind:
                Comma:
                    continue
                NewLine:
                    break
            else:
                raise this.new_error(tok: tok2, message: "Expected ',' or newline")

        return ast.import_names(modname: modname.name, location: modname.location, names)

    fn parse_enum_def(location: Location) -> ast.EnumDef except CompilationError:
        let name = this.parse_name().name
        let type_parameters: List[ast.TypeParameter] = this.parse_type_parameters()

        this.parse_colon()
        this.parse_newline()
        this.parse_indent()

        let variants: List[ast.EnumVariant] = List()
        let tag_index = 0
        while not this.try_parse_dedent():
            let name_at = this.parse_name()
            let payload_types: List[ast.Type] = List()
            let tok3 = this.get_token()
            case tok3.kind:
                BraceOpen:
                    loop:
                        payload_types.append(this.parse_parameter_def().ty)

                        let tok4 = this.get_token()
                        case tok4.kind:
                            BraceClose:
                                break
                            Comma:
                                continue
                        else:
                            raise this.new_error(tok: tok4, message: "Expected ',' or ')'")
            else:
                this.unget_token(tok3)
            
            let variant = ast.EnumVariant:
                name: name_at.name
                tag_value: tag_index
                payload: payload_types
                location: name_at.location
            variants.append(variant)
            tag_index += 1

            this.parse_newline()

        return ast.enum_def(name, id: this.new_id(), location, type_parameters, variants)

    fn parse_type_parameters() -> List[ast.TypeParameter] except CompilationError:
        let type_parameters: List[ast.TypeParameter] = List()
        let tok = this.get_token()
        case tok.kind:
            BracketOpen:
                # take in type parameters
                loop:
                    let name_at = this.parse_name()
                    type_parameters.append(ast.new_type_parameter(name: name_at.name, id: this.new_id(), location: name_at.location))

                    let tok2 = this.get_token()
                    case tok2.kind:
                        BracketClose:
                            break
                        Comma:
                            continue
                    else:
                        raise this.new_error(tok: tok2, message: "Expected , or ]")
        else:
            this.unget_token(tok)
        return type_parameters

    fn parse_struct_def(location: Location) -> ast.StructDef except CompilationError:
        let name = this.parse_name().name
        let type_parameters: List[ast.TypeParameter] = this.parse_type_parameters()
        this.parse_colon()
        this.parse_newline()
        this.parse_indent()

        let fields: List[ast.StructField] = List()
        while not this.try_parse_dedent():
            let name_at = this.parse_name()
            this.parse_colon()
            let ty = this.parse_type()
            this.parse_newline()
            fields.append(ast.StructField(name: name_at.name, ty, location: name_at.location))

        return ast.struct_def(name, id: this.new_id(), type_parameters, fields, location)

    fn parse_class_def(location: Location) -> ast.ClassDef except CompilationError:
        let name_at = this.parse_name()
        let type_parameters: List[ast.TypeParameter] = this.parse_type_parameters()
        this.parse_colon()
        this.parse_newline()
        this.parse_indent()

        let inner_defs: List[ast.Definition] = List()
        # TODO: create type instance per 'this' parameter
        let this_type = ast.undefined_type()
        loop:
            # expect var/fn def or dedent (eventually)
            let tok = this.get_token()
            case tok.kind:
                KwVar:
                    let var_def = this.parse_var_def(location: tok.location)
                    inner_defs.append(ast.Definition.Var(var_def))
                KwFn:
                    let this_parameter = ast.parameter_def(name: "this", id: this.new_id(), label_is_optional: true, ty: this_type, location: tok.location)
                    let func_def = this.parse_func_def(location: tok.location, this_parameter: Option.Some(this_parameter))
                    inner_defs.append(ast.Definition.Function(func_def))
                Dedent:
                    break
            else:
                raise this.new_error(tok, message: "Expected field or dedent")

        let class_def = ast.ClassDef:
            id: ast.NodeId(name: name_at.name, id: this.new_id())
            location: name_at.location
            type_parameters
            definitions: inner_defs
            scope: ast.Scope()
        
        # Prepare 'this' parameter:
        let type_arguments: List[ast.Type] = List()
        for type_parameter in type_parameters:
            type_arguments.append(ast.type_parameter_ref(type_parameter))
        ast.change_type_to(ty: this_type, ty2: ast.apply_tycon(tycon: ast.TyCon.Class(class_def), type_arguments))
        return class_def

    fn parse_func_def(location: Location, this_parameter: Option[ast.ParameterDef]) -> ast.FunctionDef except CompilationError:
        let name: str = this.parse_name().name
        log_debug("Parsing function: {name}")
        let type_parameters = this.parse_type_parameters()
        this.parse_brace_open()

        let parameters: List[ast.ParameterDef] = List()
        # ')' or parameters and ')'
        let tok = this.get_token()
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
                    raise this.new_error(tok: tok4, message: "Expected ')' or ','")

        # Optional return type
        let return_type: ast.Type = ast.void_type()
        tok = this.get_token()
        case tok.kind:
            Arrow:
                return_type = this.parse_type()
        else:
            this.unget_token(tok)

        # Optional except type
        let except_type: ast.Type = ast.void_type()
        tok = this.get_token()
        case tok.kind:
            KwExcept:
                except_type = this.parse_type()
        else:
            this.unget_token(tok)

        # Body
        let body = this.parse_block()
        return ast.function_def(name, id: this.new_id(), type_parameters, this_parameter, parameters, return_type, except_type, body, location)
    
    fn parse_parameter_def() -> ast.ParameterDef except CompilationError:
        let name_at = this.parse_name()
        # Parse optional '?' to indicate label is optional at call-site
        let label_is_optional = false
        let tok = this.get_token()
        case tok.kind:
            Question:
                label_is_optional = true
        else:
            this.unget_token(tok)
        this.parse_colon()
        let ty = this.parse_type()
        return ast.parameter_def(name: name_at.name, id: this.new_id(), label_is_optional, ty, location: name_at.location)

    fn parse_var_def(location: Location) -> ast.VariableDef except CompilationError:
        let name_at = this.parse_name()
        let name = name_at.name
        this.parse_colon()
        let ty = this.parse_type()

        # Optional '=' <expr>
        let var_init: Option[ast.Expression] = Option.None()
        let tok = this.get_token()
        case tok.kind:
            Equals:
                # TODO/TBD: using let var_init here should be a programming error?
                var_init = Option.Some(this.parse_expression())
        else:
            this.unget_token(tok)

        this.parse_newline()
        let variable = ast.variable(name, id: this.new_id(), ty)
        let var_def = ast.VariableDef(location: name_at.location, variable, value: var_init)
        return var_def

    fn parse_type() -> ast.Type except CompilationError:
        let tok0 = this.get_token()
        case tok0.kind:
            KwFn:
                # Parse function signature.

                # '('
                this.parse_brace_open()

                let parameter_types: List[ast.Type] = List()
                # ')' or parameters and ')'
                let tok2 = this.get_token()
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
                            raise this.new_error(tok: tok4, message: "Expected ')' or ','")

                # Optional return type
                tok2 = this.get_token()
                let return_type: ast.Type = ast.void_type()
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
        log_trace("parsing block")
        let location = location_default()

        this.parse_colon()
        this.parse_newline()
        this.parse_indent()

        let inner: List[ast.Statement] = List()
        while not this.try_parse_dedent():
            let statement = this.parse_statement()
            inner.append(statement)

        return ast.compound(inner, location)
    
    fn parse_statement() -> ast.Statement except CompilationError:
        log_trace("parsing statement")
        let tok = this.get_token()
        case tok.kind:
            KwPass:
                this.parse_newline()
                return ast.pass_statement(location: tok.location)
            KwBreak:
                this.parse_newline()
                return ast.break_statement(location: tok.location)
            KwContinue:
                this.parse_newline()
                return ast.continue_statement(location: tok.location)
            KwLet:
                return this.parse_let_statement(location: tok.location)
            KwIf:
                return this.parse_if_statement(location: tok.location)
            KwLoop:
                let body = this.parse_block()
                return ast.loop_statement(body, location: tok.location)
            KwWhile:
                return this.parse_while_statement(location: tok.location)
            KwCase:
                return this.parse_case_statement(location: tok.location)
            KwSwitch:
                return this.parse_switch_statement(location: tok.location)
            KwFor:
                return this.parse_for_statement(location: tok.location)
            KwTry:
                return this.parse_try_statement(location: tok.location)
            KwReturn:
                return this.parse_return_statement(location: tok.location)
            KwRaise:
                return this.parse_raise_statement(location: tok.location)
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
                s = ast.assignment_statement(target: expr, op: assign_op, value, location: tok2.location)
            else:
                s = ast.expression_statement(expr)

            this.parse_newline()
            return s
    
    fn parse_let_statement(location: Location) -> ast.Statement except CompilationError:
        let name_at = this.parse_name()
        let var_name = name_at.name
        let var_type = ast.undefined_type()
        let variable = ast.variable(name: var_name, id: this.new_id(), ty: var_type)
        
        let type_hint: Option[ast.Type] = Option.None()

        let tok2 = this.get_token()
        case tok2.kind:
            Colon:
                # Type hint!
                type_hint = Option.Some(this.parse_type())
        else:
            this.unget_token(tok2)

        this.parse_equals()
        let value = this.parse_expression()

        tok2 = this.get_token()
        case tok2.kind:
            NewLine:
                pass
            Colon:
                value = this.parse_obj_init(obj_ty: value, location: tok2.location)
        else:
            raise this.new_error(tok: tok2, message: "Expected newline or ':'")
        
        return ast.let_statement(variable, type_hint, value, location)
    
    fn parse_obj_init(obj_ty: ast.Expression, location: Location) -> ast.Expression except CompilationError:
        # Obj initializer!
        this.parse_newline()
        this.parse_indent()
        
        let obj_fields: List[ast.LabeledExpression] = List()
        while not this.try_parse_dedent():
            obj_fields.append(this.parse_labeled_expression())
            this.parse_newline()
        return ast.call(callee: obj_ty, arguments: obj_fields, ty: ast.undefined_type(), location)
    
    fn parse_labeled_expression() -> ast.LabeledExpression except CompilationError:
        # Parse ID ':' expression | expression
        let tok = this.get_token()
        case tok.kind:
            Identifier(name):
                let tok2 = this.get_token()
                case tok2.kind:
                    Colon:
                        # Parse ID ':' expression
                        let value = this.parse_expression()
                        return ast.LabeledExpression(location: tok.location, name: Option.Some(name), value)
                else:
                    this.unget_token(tok2)
                    this.unget_token(tok)
        else:
            this.unget_token(tok)

        # Parse expression
        let value = this.parse_expression()
        let name: Option[str] = Option.None()
        case value.kind:
            NameRef(name2):
                name = Option.Some(name2)
        else:
            pass
        return ast.LabeledExpression(location: value.location, name, value)

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
                false_block = this.parse_if_statement(location: tok2.location)
        else:
            this.unget_token(tok2)
        
        return ast.if_statement(condition, body: true_block, false_body: false_block, location)
    
    fn parse_while_statement(location: Location) -> ast.Statement except CompilationError:
        let condition = this.parse_expression()
        let body = this.parse_block()
        return ast.while_statement(condition, body, location)

    fn parse_for_statement(location: Location) -> ast.Statement except CompilationError:
        let iter_var = this.parse_name().name

        # 'in'
        let tok2 = this.get_token()
        case tok2.kind:
            KwIn:
                pass
        else:
            raise this.new_error(tok: tok2, message: "Expected 'in'")

        let iter_value = this.parse_expression()

        # ':' + indented block:
        let body = this.parse_block()
        return ast.for_statement(iter_var, iter_var_id: this.new_id(), iter_value, body, location)

    fn parse_try_statement(location: Location) -> ast.Statement except CompilationError:
        let try_body = this.parse_block()

        # 'except'
        let tok = this.get_token()
        case tok.kind:
            KwExcept:
                pass
        else:
            raise this.new_error(tok, message: "Expected 'except'")

        this.parse_brace_open()
        let except_param = this.parse_parameter_def()
        this.parse_brace_close()

        let except_body = this.parse_block()
        return ast.try_statement(try_body, except_param, except_body, location)

    fn parse_case_statement(location: Location) -> ast.Statement except CompilationError:
        # Value
        let case_value = this.parse_expression()
        this.parse_colon()
        this.parse_newline()
        this.parse_indent()
        
        let case_arms: List[ast.CaseArm] = List()
        while not this.try_parse_dedent():
            let name_at = this.parse_name()
            case_arms.append(this.parse_case_arm(name: name_at.name, location: name_at.location))
        
        # Parse optional 'else' block
        let else_clause = Option.None()
        let tok2 = this.get_token()
        case tok2.kind:
            KwElse:
                else_clause = Option.Some(this.parse_block())
        else:
            this.unget_token(tok2)
        
        return ast.case_statement(value: case_value, arms: case_arms, else_clause, location)
    
    fn parse_case_arm(name: str, location: Location) -> ast.CaseArm except CompilationError:
        let variables: List[ast.Variable] = List()
        # Eventual payload values to unpack:
        let tok4 = this.get_token()
        case tok4.kind:
            BraceOpen:
                loop:
                    let name_at = this.parse_name()
                    variables.append(ast.variable(name: name_at.name, id: this.new_id(), ty: ast.undefined_type()))
                    
                    let tok5 = this.get_token()
                    case tok5.kind:
                        BraceClose:
                            break
                        Comma:
                            continue
                    else:
                        raise this.new_error(tok: tok5, message: "Expected ',' or ')'")
        else:
            this.unget_token(tok4)

        # Arm body:
        let statement = this.parse_block()
        let arm = ast.CaseArm:
            location
            name
            variables: variables
            block: ast.scoped_block(body: statement)
        return arm
    
    fn parse_switch_statement(location: Location) -> ast.Statement except CompilationError:
        let switch_value = this.parse_expression()
        this.parse_colon()
        this.parse_newline()
        this.parse_indent()
        let arms: List[ast.SwitchArm] = List()
        while not this.try_parse_dedent():
            let value = this.parse_expression()
            let block = ast.scoped_block(body: this.parse_block())
            arms.append(ast.SwitchArm(location: value.location, value, block))
        
        this.parse_kw_else()
        let default_body = this.parse_block()
        return ast.switch_statement(value: switch_value, arms, default_body, location)

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
        return ast.return_statement(value: res_value, location)

    fn parse_raise_statement(location: Location) -> ast.Statement except CompilationError:
        let value = this.parse_expression()
        this.parse_newline()
        return ast.raise_statement(value, location)

    fn parse_expression() -> ast.Expression except CompilationError:
        log_trace("Parsing expression")
        return this.parse_expression2(min_prec: 0)

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
            
            let rhs = this.parse_expression2(min_prec: prec + 1)
            let location = Location(begin: expr.location.begin, end: rhs.location.end)
            expr = ast.binop(lhs: expr, op, rhs, ty: ast.undefined_type(), location)

        return expr

    fn parse_unary() -> ast.Expression except CompilationError:
        let tok = this.get_token()
        case tok.kind:
            KwNot:
                let value = this.parse_unary()
                let op = ast.UnaryOperator.Not()
                return ast.unop(op, value, ty: ast.undefined_type(), location: tok.location)
            Minus:
                let value = this.parse_unary()
                let op = ast.UnaryOperator.Minus()
                return ast.unop(op, value, ty: ast.undefined_type(), location: tok.location)
        else:
            this.unget_token(tok)
            return this.parse_atom()

    fn parse_atom() -> ast.Expression except CompilationError:
        let expr = ast.undefined_value()
        let tok = this.get_token()
        case tok.kind:
            Integer(value):
                expr = ast.integer_literal(value, location: tok.location)
            Float(value):
                expr = ast.float_literal(value, location: tok.location)
            String(value):
                expr = this.process_fstring(literal: value, location: tok.location)
            Char(value):
                expr = ast.char_literal(value, location: tok.location)
            Bool(value):
                expr = ast.bool_literal(value, location: tok.location)
            Identifier(name):
                expr = ast.name_ref(name, location: tok.location)
            BraceOpen:
                expr = this.parse_expression()
                this.parse_brace_close()
            BracketOpen:
                expr = this.parse_array_literal(location: tok.location)
        else:
            raise this.new_error(tok, message: "Unexpected token")

        # Attempt suffixes
        loop:
            tok = this.get_token()
            case tok.kind:
                Dot:
                    # handle '.attribute' suffix
                    let attr_at = this.parse_name()
                    let location = Location(begin: expr.location.begin, end: attr_at.location.end)
                    expr = ast.get_attr(base: expr, field: attr_at.name, ty: ast.undefined_type(), location)
                BraceOpen:
                    expr = this.parse_call_suffix(callee: expr)
                BracketOpen:
                    let indici: List[ast.Expression] = List()
                    loop:
                        indici.append(this.parse_expression())
                        let tok4 = this.get_token()
                        case tok4.kind:
                            BracketClose:
                                break
                            Comma:
                                continue
                        else:
                            raise this.new_error(tok: tok4, message: "Expected ']' or ','")
                    expr = ast.subscript(base: expr, indici, ty: ast.undefined_type(), location: tok.location)
            else:
                this.unget_token(tok)
                break
        return expr
    
    fn parse_call_suffix(callee: ast.Expression) -> ast.Expression except CompilationError:
        # print("CALL")
        # Handle '(arg1,arg2)' suffix
        # Or '()' or '(arg1)'
        let arguments: List[ast.LabeledExpression] = List()
        let tok2 = this.get_token()
        let begin = callee.location.begin
        let end = tok2.location.end
        case tok2.kind:
            BraceClose:
                # no args call
                pass
        else:
            this.unget_token(tok2)
            # call with parameters

            loop:
                arguments.append(this.parse_labeled_expression())
                let tok4 = this.get_token()
                case tok4.kind:
                    BraceClose:
                        end = tok4.location.end
                        break
                    Comma:
                        continue
                else:
                    raise this.new_error(tok: tok4, message: "Expected ')' or ','")

        let location = Location(begin, end)
        return ast.call(callee, arguments, ty: ast.undefined_type(), location)
    
    fn parse_array_literal(location: Location) -> ast.Expression except CompilationError:
        let values: List[ast.Expression] = List()
        loop:
            values.append(this.parse_expression())
            
            let tok5 = this.get_token()
            case tok5.kind:
                BracketClose:
                    break
                Comma:
                    continue
            else:
                raise this.new_error(tok: tok5, message: "Expected ',' or ']'")
        return ast.array_literal(values, location)

    fn parse_name() -> NameAtLocation except CompilationError:
        let tok = this.get_token()
        case tok.kind:
            Identifier(name):
                return NameAtLocation(name, location: tok.location)
        else:
            raise this.new_error(tok, message: "Expected name")

    fn parse_brace_open() except CompilationError:
        let tok = this.get_token()
        case tok.kind:
            BraceOpen:
                pass
        else:
            raise this.new_error(tok, message: "Expected '('")

    fn parse_brace_close() except CompilationError:
        let tok = this.get_token()
        case tok.kind:
            BraceClose:
                pass
        else:
            raise this.new_error(tok, message: "Expected ')'")

    fn parse_newline() except CompilationError:
        let tok = this.get_token()
        case tok.kind:
            NewLine:
                pass
        else:
            raise this.new_error(tok, message: "Expected newline")

    fn parse_indent() except CompilationError:
        let tok = this.get_token()
        case tok.kind:
            Indent:
                pass
        else:
            raise this.new_error(tok, message: "Expected indent")

    fn try_parse_dedent() -> bool:
        # expect dedent (eventually)
        let tok = this.get_token()
        case tok.kind:
            Dedent:
                return true
        else:
            this.unget_token(tok)
            return false

    fn parse_kw_else() except CompilationError:
        let tok = this.get_token()
        case tok.kind:
            KwElse:
                pass
        else:
            raise this.new_error(tok, message: "Expected 'else'")

    fn parse_colon() except CompilationError:
        let tok = this.get_token()
        case tok.kind:
            Colon:
                pass
        else:
            raise this.new_error(tok, message: "Expected ':'")

    fn parse_equals() except CompilationError:
        let tok = this.get_token()
        case tok.kind:
            Equals:
                pass
        else:
            raise this.new_error(tok, message: "Expected '='")

    fn get_token() -> Token:
        # Get token (EOF in case of end of file)
        return this.lex.next_token()

    fn unget_token(token?: Token):
        this.lex.pushback_token(token)

    fn new_id() -> int:
        return this.id_gen.new_id()

    fn new_error(tok: Token, message: str) -> CompilationError:
        let err = errors.new_error(location: tok.location, message: "{message}, got {token_to_string(tok)}")
        return errors.new_errors(filename: this.filename, errors: vec1(err))

    fn process_fstring(literal: str, location: Location) -> ast.Expression except CompilationError:
        # Check strings for parts surrounded by '{' and '}'
        let txt_length = std.str_len(literal)
        if txt_length == 0:
            return ast.string_literal(value: "", location)

        let parts: List[ast.Expression] = List()

        let index = 0
        let begin = index
        let end = index
        let in_braces = false

        while index < txt_length:
            let c = std.str_get(literal, index)
            if not in_braces and std.ord(c) == 123:  # { -> 123
                in_braces = true

                # Raw string part
                end = index
                if begin < end:
                    let raw_string_value = std.str_slice(value: literal, begin, end)
                    let raw_string_expr = ast.string_literal(value: raw_string_value, location)
                    parts.append(raw_string_expr)
                begin = index + 1
            elif in_braces and std.ord(c) == 125:  # } -> 125
                in_braces = false

                # Expression which must be turned into string
                end = index
                if begin < end:
                    let expr_text = std.str_slice(value: literal, begin, end)
                    let to_string_expr: ast.Expression = parse_expr_from_text(source: expr_text, id_gen: this.id_gen)
                    to_string_expr = ast.to_string(value: to_string_expr, location)
                    parts.append(to_string_expr)
                begin = index + 1

            index += 1
        
        if in_braces:
            # TODO: raise proper error
            panic("invalid f-string!")

        # Last part:
        end = index
        if begin < end:
            let raw_string_value2 = std.str_slice(value: literal, begin, end)
            let raw_string_expr2 = ast.string_literal(value: raw_string_value2, location)
            parts.append(raw_string_expr2)
        
        let x = parts.pop_front()
        while not parts.is_empty():
            x = ast.binop(lhs: x, op: ast.BinaryOperator.Add(), rhs: parts.pop_front(), ty: ast.str_type(), location)
        return x

struct NameAtLocation:
    name: str
    location: Location


