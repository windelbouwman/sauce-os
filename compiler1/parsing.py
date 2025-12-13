"""Parser code."""

import logging
import os


# try lark as parser
from lark import Lark, Transformer as LarkTransformer
from lark.lexer import Lexer as LarkLexer, Token as LarkToken
from lark.exceptions import UnexpectedInput, VisitError

from . import ast
from .lexer import detect_indentations, tokenize
from .location import Location, Position
from .errors import ParseError, CompilationError

logger = logging.getLogger("slangc.parser")


def parse_file(id_context: ast.IdContext, filename: str) -> ast.Module:
    if isinstance(filename, tuple):
        filename, code = filename
    else:
        with open(filename, "r") as f:
            code = f.read()
    logger.info(f"Parsing {filename}")
    modname = os.path.splitext(os.path.basename(filename))[0]
    # TODO: clean modname of more special characters
    modname = modname.replace("-", "_")
    return parse_source(id_context, code, modname, filename)


def parse_source(
    id_context: ast.IdContext, code: str, modname: str, filename: str
) -> ast.Module:
    """Parse the given code."""
    logger.debug("Starting parse")
    try:
        module: ast.Module = lark_it(id_context, modname, code, "module")
    except ParseError as ex:
        raise CompilationError([(filename, ex.location, ex.message)])

    assert isinstance(module, ast.Module)

    module.filename = filename
    logger.debug("Parse complete!")
    return module


def lark_it(id_context: ast.IdContext, modname: str, code, start):
    """Invoke the lark parsing."""
    try:
        tree = lark_parser.parse(code, start=start)
    except UnexpectedInput as ex:
        raise ParseError(
            Location.from_row_column(ex.line, ex.column), f"Parsing choked: {ex}"
        )

    try:
        return CustomTransformer(id_context, modname).transform(tree)
    except VisitError as ex:
        if isinstance(ex.orig_exc, ParseError):
            raise ex.orig_exc
        else:
            raise


class CustomLarkLexer(LarkLexer):
    def __init__(self, lexer_conf):
        pass

    def lex(self, data):
        type_map = {
            "(": "LEFT_PARENTHESIS",
            ")": "RIGHT_PARENTHESIS",
            "[": "LEFT_BRACKET",
            "]": "RIGHT_BRACKET",
            "{": "LEFT_BRACE",
            "}": "RIGHT_BRACE",
            "<": "LESS_THAN",
            ">": "GREATER_THAN",
            ">=": "GREATER_EQUALS",
            "<=": "LESS_EQUALS",
            "=": "EQUALS",
            "==": "EQUALS_EQUALS",
            "!=": "NOT_EQUALS",
            "+=": "PLUS_EQUALS",
            "-=": "MINUS_EQUALS",
            "*=": "ASTERIX_EQUALS",
            "/=": "SLASH_EQUALS",
            "-": "MINUS",
            "+": "PLUS",
            "*": "ASTERIX",
            "/": "SLASH",
            "%": "PERCENT",
            ">>": "SHR",
            "<<": "SHL",
            "|": "BITOR",
            "^": "BITXOR",
            "&": "BITAND",
            ":": "COLON",
            ",": "COMMA",
            ".": "DOT",
            "->": "ARROW",
            "?": "QUESTION",
        }
        for token in detect_indentations(tokenize(data)):
            # print('token', token)
            ty2 = type_map.get(token.ty, token.ty)
            yield LarkToken(
                ty2,
                token.value,
                line=token.location.begin.row,
                column=token.location.begin.column,
                end_line=token.location.end.row,
                end_column=token.location.end.column,
            )


def get_loc(tok: LarkToken) -> Location:
    """Get Location from lark token."""
    return get_loc2(tok, tok)


def get_loc2(tok1: LarkToken, tok2: LarkToken) -> Location:
    """Get Location from two lark tokens."""
    assert isinstance(tok1, LarkToken)
    assert isinstance(tok2, LarkToken)
    return Location(
        Position(tok1.line, tok1.column), Position(tok2.end_line, tok2.end_column)
    )


def get_span(loc1: Location, loc2: Location):
    assert isinstance(loc1, Location)
    assert isinstance(loc2, Location)
    return Location(loc1.begin, loc2.end)


def binop(lhs: ast.Expression, op: str, rhs: ast.Expression) -> ast.Expression:
    assert isinstance(lhs, ast.Expression)
    assert isinstance(rhs, ast.Expression)
    return ast.binop(lhs, op, rhs, get_span(lhs.location, rhs.location))


class CustomTransformer(LarkTransformer):
    def __init__(self, id_context, modname):
        super().__init__()
        self.id_context = id_context
        self._modname = modname

    def new_id(self, name: str) -> ast.Id:
        return self.id_context.new_id(name)

    def module(self, x):
        id = self.id_context.new_id(self._modname)
        docstring, imports, definitions, eof = x
        span = get_span(Location.default(), get_loc(eof))
        return ast.Module(id, docstring, imports, definitions, span)

    def eval_expr(self, x):
        return x[0]

    def imports(self, x):
        return x

    def import1(self, x):
        modname = x[1].value
        return ast.Import(modname, get_loc(x[1]))

    def import2(self, x):
        modname = x[1].value
        names = x[3]
        return ast.ImportFrom(modname, names, get_loc(x[1]))

    def definitions(self, x):
        return x

    def definition(self, x):
        return x[0]

    def class_def(self, x):
        # class_def: is_pub KW_CLASS id_and_type_parameters COLON NEWLINE INDENT (func_def | var_def)+ DEDENT
        location, name, type_parameters = x[2]
        assert is_terminal(x[3], "COLON")
        assert is_terminal(x[4], "NEWLINE")
        assert is_terminal(x[5], "INDENT")
        docstring = x[6]
        members = x[7:-1]
        assert is_terminal(x[-1], "DEDENT")
        this_type = ast.void_type.clone()
        for member in members:
            if isinstance(member, ast.FunctionDef):
                this_parameter = ast.Parameter(
                    self.new_id("this"), False, this_type, member.location
                )
                member.this_parameter = this_parameter
        span = get_loc2(x[5], x[-1])
        class_def = ast.class_def(
            self.new_id(name), docstring, type_parameters, members, location, span
        )

        # Update the type of the 'this' parameter
        type_args = [t.get_ref().clone() for t in type_parameters]
        real_this_type = ast.class_type(class_def, type_args)
        this_type.change_to(real_this_type)

        return class_def

    def var_def(self, x):
        # var_def: is_pub KW_VAR ID COLON typ var_def_init
        location = get_loc(x[2])
        name = x[2].value
        ty = x[4]
        value = x[5]
        return ast.var_def(self.new_id(name), ty, value, location)

    def var_def_init(self, x):
        if is_terminal(x[0], "EQUALS"):
            value = x[1]
        else:
            value = None
            assert is_terminal(x[0], "NEWLINE")
        return value

    def is_pub(self, x):
        if len(x) == 1:
            assert is_terminal(x[0], "KW_PUB")
            return True
        else:
            return False

    def func_def(self, x):
        # is_pub KW_FN id_and_type_parameters function_signature COLON NEWLINE INDENT docstring statement+ DEDENT
        # x = x[1:]
        location, name, type_parameters = x[2]
        parameters, return_type, except_type = x[3]
        assert is_terminal(x[4], "COLON")
        assert is_terminal(x[5], "NEWLINE")
        assert is_terminal(x[6], "INDENT")
        docstring = x[7]
        statements = x[8:-1]
        span = get_loc2(x[4], x[-1])
        body = ast.compound_statement(statements, get_loc(x[6]))
        assert is_terminal(x[-1], "DEDENT")

        return ast.function_def(
            self.new_id(name),
            docstring,
            type_parameters,
            parameters,
            return_type,
            except_type,
            body,
            location,
            span,
        )

    def extern_func_def(self, x):
        # extern_func_def: KW_EXTERN STRING KW_FN id_and_type_parameters function_signature NEWLINE
        libname = x[1]
        assert isinstance(libname, str)
        location, name, type_parameters = x[3]
        parameters, return_type, except_type = x[4]
        ptypes = [p.ty for p in parameters]
        return ast.ExternFunction(self._modname, name, ptypes, return_type, location)

    def function_signature(self, x):
        # LEFT_PARENTHESIS parameters? RIGHT_PARENTHESIS (ARROW typ)?
        if is_terminal(x[1], "RIGHT_PARENTHESIS"):
            parameters = []
            x = x[2:]
        else:
            assert isinstance(x[1], list)
            parameters = x[1]
            x = x[3:]

        if x and is_terminal(x[0], "ARROW"):
            return_type = x[1]
            x = x[2:]
        else:
            return_type = ast.void_type

        if x and is_terminal(x[0], "KW_EXCEPT"):
            except_type = x[1]
            x = x[1:]
        else:
            except_type = ast.void_type

        return parameters, return_type, except_type

    def parameters(self, x):
        if len(x) == 1:
            return x
        else:
            return x[0] + [x[2]]

    def interface_def(self, x):
        # KW_INTERFACE id_and_type_parameters COLON NEWLINE INDENT func_decl+ DEDENT
        location, name, type_parameters = x[1]
        docstring = ""
        assert is_terminal(x[4], "INDENT")
        functions = x[5:-1]
        assert is_terminal(x[-1], "DEDENT")
        span = get_loc2(x[4], x[-1])
        return ast.InterfaceDef(
            self.new_id(name), docstring, type_parameters, functions, location, span
        )

    def func_decl(self, x):
        # KW_FN id_and_type_parameters function_signature NEWLINE
        location, name, type_parameters = x[1]
        parameters, return_type, except_type = x[2]
        return ast.FunctionDecl(
            self.new_id(name),
            type_parameters,
            parameters,
            return_type,
            except_type,
            location,
        )

    def impl_def(self, x):
        # aarg
        # KW_IMPL typ KW_FOR typ COLON NEWLINE INDENT func_def+ DEDENT
        assert is_terminal(x[0], "KW_IMPL")
        location = get_loc(x[0])
        interface = x[1]
        docstring = ""
        assert is_terminal(x[2], "KW_FOR")
        target = x[3]
        assert is_terminal(x[4], "COLON")
        assert is_terminal(x[5], "NEWLINE")
        assert is_terminal(x[6], "INDENT")
        assert is_terminal(x[-1], "DEDENT")
        span = get_loc2(x[6], x[-1])
        functions = x[7:-1]

        # Prepare 'this' implicit parameter
        this_type = target
        for function in functions:
            if isinstance(function, ast.FunctionDef):
                this_parameter = ast.Parameter(
                    self.new_id("this"), True, this_type, function.location
                )
                function.this_parameter = this_parameter

        id = self.new_id(f"impl_{self.id_context._counter}")
        return ast.ImplDef(id, docstring, interface, target, functions, location, span)

    def struct_def(self, x):
        # is_pub KW_STRUCT id_and_type_parameters COLON NEWLINE INDENT docstring struct_field+ DEDENT
        is_union = is_terminal(x[1], "KW_UNION")
        location, name, type_parameters = x[2]
        assert is_terminal(x[3], "COLON")
        assert is_terminal(x[4], "NEWLINE")
        assert is_terminal(x[5], "INDENT")
        docstring = x[6]
        fields = x[7:-1]
        assert is_terminal(x[-1], "DEDENT")
        span = get_loc2(x[5], x[-1])
        return ast.StructDef(
            self.new_id(name),
            docstring,
            type_parameters,
            is_union,
            fields,
            location,
            span,
        )

    def struct_field(self, x):
        return ast.StructFieldDef(x[0], x[2], get_loc(x[0]))

    def enum_def(self, x):
        # is_pub KW_ENUM id_and_type_parameters COLON NEWLINE INDENT docstring enum_variant+ DEDENT
        assert is_terminal(x[1], "KW_ENUM")
        location, name, type_parameters = x[2]
        assert is_terminal(x[3], "COLON")
        assert is_terminal(x[4], "NEWLINE")
        assert is_terminal(x[5], "INDENT")
        docstring = x[6]
        variants = x[7:-1]
        assert is_terminal(x[-1], "DEDENT")
        span = get_loc2(x[5], x[-1])
        return ast.EnumDef(
            self.new_id(name), docstring, type_parameters, variants, location, span
        )

    def enum_variant(self, x):
        name = x[0].value
        if len(x) == 2:
            payload = []
        else:
            assert len(x) == 5
            payload = [p.ty for p in x[2]]
        return ast.EnumVariant(name, payload, get_loc(x[0]))

    def type_def(self, x):
        """is_pub KW_TYPE ID EQUALS typ NEWLINE"""
        location = get_loc(x[1])
        name = self.new_id(x[2].value)
        typ = x[4]
        return ast.type_def(name, typ, location)

    def id_and_type_parameters(self, x):
        # id_and_type_parameters: ID type_parameters?
        name = x[0].value
        location = get_loc(x[0])
        if len(x) == 1:
            type_parameters = []
        else:
            type_parameters = x[1]
        return (location, name, type_parameters)

    def type_parameters(self, x):
        # type_parameters: LESS_THAN ids GREATER_THAN
        return [
            ast.type_parameter(self.new_id(name), location) for name, location in x[1]
        ]

    def typ(self, x):
        if is_terminal(x[0], "KW_FN"):
            # KW_FN LEFT_PARENTHESIS types? RIGHT_PARENTHESIS (ARROW typ)?
            if is_terminal(x[2], "RIGHT_PARENTHESIS"):
                parameter_types = []
            else:
                assert isinstance(x[2], list)
                parameter_types = x[2]
            parameter_names = [None] * len(parameter_types)

            if is_terminal(x[-2], "ARROW"):
                return_type = x[-1]
            else:
                return_type = ast.void_type

            except_type = ast.void_type

            return ast.function_type(
                parameter_names, parameter_types, return_type, except_type
            )
        elif is_terminal(x[0], "LEFT_BRACKET"):
            element_type = x[1]
            assert is_terminal(x[2], "RIGHT_BRACKET")
            return ast.array_type(0, element_type)
        elif is_terminal(x[0], "BITAND") or is_terminal(x[0], "ASTERIX"):
            element_type = x[1]
            return ast.pointer_type(element_type)
        elif isinstance(x[0], ast.QualName):
            if len(x) == 1:
                return ast.name_ref_type(x[0])
            else:
                tycon = x[0]
                assert is_terminal(x[1], "LEFT_BRACKET")
                type_arguments = x[2]
                assert is_terminal(x[3], "RIGHT_BRACKET")
                return ast.Type(ast.AbstractApp(tycon, type_arguments))
        else:
            raise ValueError("Invalid type")

    def types(self, x):
        if len(x) == 1:
            return x
        else:
            return x[0] + [x[2]]

    def qual_name(self, x):
        names = [(get_loc(n), n.value) for n in x[::2]]
        return ast.QualName(names)

    def parameter(self, x):
        # ID QUESTION? COLON typ
        name = x[0].value
        typ = x[-1]
        if len(x) == 4:
            needs_label = False
        else:
            needs_label = True
        return ast.Parameter(self.new_id(name), needs_label, typ, get_loc(x[0]))

    def docstring(self, x):
        if len(x) == 2:
            return x[0]

    def block(self, x):
        # COLON NEWLINE INDENT statement+ DEDENT
        # | COLON expression NEWLINE
        assert is_terminal(x[0], "COLON")
        if is_terminal(x[1], "NEWLINE"):
            assert is_terminal(x[1], "NEWLINE")
            assert is_terminal(x[2], "INDENT")
            statements = x[3:-1]
            assert is_terminal(x[-1], "DEDENT")
            span = get_loc2(x[0], x[-1])
            statement = ast.compound_statement(statements, get_loc(x[2]))
        else:
            expression = x[1]
            assert is_terminal(x[2], "NEWLINE")
            span = expression.location
            statement = ast.expression_statement(expression, expression.location)
        return ast.ScopedBlock(statement, span)

    def statement(self, x):
        if isinstance(x[0], ast.Expression):
            return ast.expression_statement(x[0], x[0].location)
        else:
            assert isinstance(x[0], ast.Statement)
            return x[0]

    def block_statement(self, x):
        return x[0]

    def simple_statement(self, x):
        return x[0]

    def pass_statement(self, x):
        return ast.pass_statement(get_loc(x[0]))

    def continue_statement(self, x):
        return ast.continue_statement(get_loc(x[0]))

    def break_statement(self, x):
        return ast.break_statement(get_loc(x[0]))

    def return_statement(self, x):
        # return_statement: KW_RETURN expression?
        value = x[1] if len(x) > 1 else None
        return ast.return_statement(value, get_loc(x[0]))

    def assignment_statement(self, x):
        # assignment_statement: expression EQUALS expression
        op = x[1].value
        return ast.assignment_statement(x[0], op, x[2], get_loc(x[1]))

    def delete_statement(self, x):
        return ast.delete_statement(x[1], get_loc(x[0]))

    def raise_statement(self, x):
        # raise_statement: KW_RAISE expression
        value = x[1]
        return ast.raise_statement(value, get_loc(x[0]))

    def try_statement(self, x):
        # try_statement: KW_TRY block KW_EXCEPT LEFT_PARENTHESIS parameter RIGHT_PARENTHESIS block
        try_code = x[1]
        parameter = x[4]
        except_code = x[6]
        return ast.try_statement(try_code, parameter, except_code, get_loc(x[0]))

    def if_statement(self, x):
        # KW_IF test block elif_clause* else_clause?
        condition = x[1]
        true_block = x[2]
        if_tail = x[3:]

        # Create else clause if not provided:
        if if_tail and isinstance(if_tail[-1], ast.ScopedBlock):
            false_block = if_tail.pop()
        else:
            false_block = ast.ScopedBlock(
                ast.pass_statement(get_loc(x[0])), true_block.scope.span
            )

        for test, block in reversed(if_tail):
            span = get_span(block.scope.span, false_block.scope.span)
            false_block = ast.ScopedBlock(
                ast.if_statement(test, block, false_block, block.body.location), span
            )

        return ast.if_statement(condition, true_block, false_block, get_loc(x[0]))

    def case_statement(self, x):
        # case_statement: KW_CASE expression COLON NEWLINE INDENT case_arm+ DEDENT else_clause?
        value = x[1]
        if is_terminal(x[-1], "DEDENT"):
            arms = x[5:-1]
            else_block = None
        else:
            assert is_terminal(x[-2], "DEDENT")
            else_block = x[-1]
            arms = x[5:-2]
        return ast.case_statement(value, arms, else_block, get_loc(x[0]))

    def case_arm(self, x):
        # case_arm: ID (LEFT_PARENTHESIS ids RIGHT_PARENTHESIS)? block
        name = x[0].value
        if is_terminal(x[1], "LEFT_PARENTHESIS"):
            variables = [
                self.new_variable(name, ast.void_type, location)
                for name, location in x[2]
            ]
        else:
            variables = []
        body = x[-1]
        return ast.CaseArm(name, variables, body, get_loc(x[0]))

    def switch_statement(self, x):
        # switch_statement: KW_SWITCH expression COLON NEWLINE INDENT switch_arm+ DEDENT else_clause
        value = x[1]
        arms = x[5:-2]
        default_body = x[-1]
        return ast.switch_statement(value, arms, default_body, get_loc(x[0]))

    def switch_arm(self, x):
        # switch_arm: expression block
        return ast.SwitchArm(x[0], x[1], x[0].location)

    def let_statement(self, x):
        """
        let_statement: KW_LET ID (COLON typ)? EQUALS big_expression
                     | KW_LET ID (COLON typ)? EQUALS block_statement
        """
        variable = self.new_variable(x[1].value, ast.void_type, get_loc(x[1]))
        if is_terminal(x[2], "COLON"):
            ty = x[3]
            x = x[2:]
        else:
            ty = None

        assert is_terminal(x[2], "EQUALS")
        value = x[3]
        if isinstance(value, ast.Statement):
            value = ast.statement_expression(value, value.location)
        return ast.let_statement(variable, ty, value, get_loc(x[0]))

    def while_statement(self, x):
        # KW_WHILE test block
        condition, inner = x[1], x[2]
        return ast.while_statement(condition, inner, get_loc(x[0]))

    def loop_statement(self, x):
        # KW_LOOP block
        inner = x[1]
        return ast.loop_statement(inner, get_loc(x[0]))

    def for_statement(self, x):
        # KW_FOR ID KW_IN expression block
        variable = self.new_variable(x[1].value, ast.void_type, get_loc(x[1]))
        values, inner = x[3], x[4]
        return ast.for_statement(variable, values, inner, get_loc(x[0]))

    def new_variable(self, name, ty, location) -> ast.Variable:
        return ast.Variable(self.new_id(name), ty, location)

    def elif_clause(self, x):
        # : KW_ELIF test block
        return (x[1], x[2])

    def else_clause(self, x):
        return x[-1]

    def test(self, x):
        return x[0]

    def disjunction(self, x):
        if len(x) == 1:
            return x[0]
        else:
            assert len(x) == 3
            lhs, op, rhs = x
            return binop(lhs, op, rhs)

    def conjunction(self, x):
        if len(x) == 1:
            return x[0]
        else:
            assert len(x) == 3
            lhs, op, rhs = x
            return binop(lhs, op, rhs)

    def inversion(self, x):
        if len(x) == 1:
            return x[0]
        else:
            assert len(x) == 2
            op, rhs = x
            return ast.unop(op.value, rhs, get_loc(x[0]))

    def comparison(self, x):
        if len(x) == 1:
            return x[0]
        else:
            lhs, op, rhs = x
            return binop(lhs, op.value, rhs)

    def cmpop(self, x):
        return x[0]

    def expression(self, x):
        if len(x) == 1:
            return x[0]
        elif len(x) == 3:
            lhs, op, rhs = x
            return binop(lhs, op.value, rhs)
        else:
            assert len(x) == 5
            true_value, kw_if, condition, kw_else, false_value = x
            return ast.if_expression(condition, true_value, false_value, get_loc(kw_if))

    def bitor(self, x):
        if len(x) == 1:
            return x[0]
        else:
            lhs, op, rhs = x
            return binop(lhs, op.value, rhs)

    def bitxor(self, x):
        if len(x) == 1:
            return x[0]
        else:
            lhs, op, rhs = x
            return binop(lhs, op.value, rhs)

    def bitand(self, x):
        if len(x) == 1:
            return x[0]
        else:
            lhs, op, rhs = x
            return binop(lhs, op.value, rhs)

    def bitshift(self, x):
        if len(x) == 1:
            return x[0]
        else:
            lhs, op, rhs = x
            return binop(lhs, op.value, rhs)

    def sum(self, x):
        if len(x) == 1:
            return x[0]
        else:
            lhs, op, rhs = x
            return binop(lhs, op.value, rhs)

    def addop(self, x):
        return x[0]

    def term(self, x):
        if len(x) == 1:
            return x[0]
        else:
            lhs, op, rhs = x
            return binop(lhs, op.value, rhs)

    def mulop(self, x):
        return x[0]

    def factor(self, x):
        if len(x) == 1:
            return x[0]
        else:
            op = x[0].value
            return ast.unop(op, x[1], get_loc(x[0]))

    def atom(self, x):
        if len(x) == 1:
            return x[0]
        elif len(x) > 2 and is_terminal(x[1], "LEFT_PARENTHESIS"):
            arguments = x[2] if len(x) == 4 else []
            callee = x[0]
            span = get_span(callee.location, get_loc(x[-1]))
            return ast.function_call(callee, arguments, span)
        elif len(x) > 2 and is_terminal(x[0], "LEFT_PARENTHESIS"):
            return x[1]
        elif len(x) > 2 and is_terminal(x[0], "KW_NEW"):
            raise NotImplementedError(str(x))
        elif len(x) > 2 and is_terminal(x[1], "LEFT_BRACKET"):
            base = x[0]
            index = x[2]
            ty = ast.void_type
            span = get_span(base.location, get_loc(x[-1]))
            return ast.array_index(base, index, ty, span)
        elif len(x) > 2 and is_terminal(x[1], "DOT"):
            base = x[0]
            field = x[2].value
            span = get_span(base.location, get_loc(x[2]))
            ty = ast.void_type
            return ast.dot_operator(base, field, ty, span)
        else:
            raise NotImplementedError(str(x))

    def tests(self, x):
        if len(x) == 1:
            return x
        else:
            return x[0] + [x[2]]

    def arguments(self, x):
        if len(x) == 1:
            return x
        else:
            return x[0] + [x[2]]

    def ids(self, x):
        if len(x) == 1:
            return [(x[0].value, get_loc(x[0]))]
        else:
            return x[0] + [(x[2].value, get_loc(x[2]))]

    def literal(self, x):
        if is_terminal(x[0], "NUMBER"):
            return ast.numeric_constant(x[0].value, get_loc(x[0]))
        elif is_terminal(x[0], "FNUMBER"):
            return ast.numeric_constant(x[0].value, get_loc(x[0]))
        elif is_terminal(x[0], "BOOL"):
            return ast.bool_constant(x[0].value, get_loc(x[0]))
        elif is_terminal(x[0], "CHAR"):
            return ast.char_constant(x[0].value, get_loc(x[0]))
        else:
            raise NotImplementedError(f"Literal: {x}")

    def rawstring(self, x):
        # rawstring: STRING_START STRING_LITERAL STRING_END
        return x[1].value

    def string(self, x):
        # string: STRING_START string_part* STRING_END
        parts = x[1:-1]
        if len(parts) == 0:  # empty string
            return ast.string_constant("", get_loc(x[0]))
        else:
            # Concatenate all parts:
            x = parts.pop(0)
            while parts:
                x = x.binop("+", parts.pop(0))
            return x

    def string_part(self, x):
        # string_part: STRING_LITERAL
        #         | LEFT_BRACE expression RIGHT_BRACE
        if len(x) == 1:
            return ast.string_constant(x[0].value, get_loc(x[0]))
        elif len(x) == 3:
            return x[1].to_string()
        else:
            raise RuntimeError("Invalid string_part rule")

    def array_literal(self, x):
        return ast.array_literal(x[1], get_loc2(x[0], x[-1]))

    def array_literal2(self, x):
        #  LEFT_BRACKET test COLON typ RIGHT_BRACKET
        size = x[1]
        typ = x[3]
        return ast.array_literal2(size, typ, get_loc2(x[0], x[-1]))

    def big_expression(self, x):
        if is_terminal(x[0], "KW_NEW"):
            return ast.new_operator(x[1], get_loc(x[0]))
        else:
            return x[0]

    def obj_init(self, x):
        "obj_init: expr COLON NEWLINE INDENT field_init+ DEDENT"
        assert is_terminal(x[1], "COLON")
        assert is_terminal(x[2], "NEWLINE")
        assert is_terminal(x[3], "INDENT")
        assert is_terminal(x[-1], "DEDENT")
        ty, fields = x[0], x[4:-1]
        return ast.function_call(ty, fields, get_loc(x[1]))

    def field_init(self, x):
        return x[0]

    def labeled_expression(self, x):
        if len(x) == 1:
            # value = ast.name_ref(name, get_loc(x[0]))
            location = x[0].location
            value = x[0]
            if isinstance(value.kind, ast.NameRef):
                name = value.kind.name
            else:
                name = None
        else:
            assert len(x) == 3
            location = get_loc(x[0])
            name = x[0].value
            value = x[2]
        return ast.LabeledExpression(name, value, location)

    def obj_ref(self, x):
        assert len(x) == 1
        return ast.name_ref(x[0].value, get_loc(x[0]))


def is_terminal(x, term_type: str) -> bool:
    return isinstance(x, LarkToken) and x.type == term_type


grammar = r"""
module: docstring imports definitions EOF
eval_expr: expression NEWLINE EOF

imports: (import1|import2)*
import1: KW_IMPORT ID NEWLINE
import2: KW_FROM ID KW_IMPORT ids NEWLINE

definitions: definition*
definition: func_def
          | var_def
          | struct_def
          | enum_def
          | class_def
          | type_def
          | extern_func_def
          | interface_def
          | impl_def

is_pub: KW_PUB?
class_def: is_pub KW_CLASS id_and_type_parameters COLON NEWLINE INDENT docstring (func_def | var_def)+ DEDENT
var_def: is_pub (KW_VAR | KW_LET) ID COLON typ var_def_init
var_def_init: NEWLINE
            | EQUALS big_expression
func_def: is_pub KW_FN id_and_type_parameters function_signature COLON NEWLINE INDENT docstring statement+ DEDENT
extern_func_def: KW_EXTERN rawstring KW_FN id_and_type_parameters function_signature NEWLINE
func_decl: KW_FN id_and_type_parameters function_signature NEWLINE
interface_def: KW_INTERFACE id_and_type_parameters COLON NEWLINE INDENT func_decl+ DEDENT
impl_def: KW_IMPL typ KW_FOR typ COLON NEWLINE INDENT func_def+ DEDENT
docstring: (DOCSTRING NEWLINE)?
function_signature: LEFT_PARENTHESIS parameters? RIGHT_PARENTHESIS (ARROW typ)? (KW_EXCEPT typ)?
parameters: parameter
          | parameters COMMA parameter
parameter: ID QUESTION? COLON typ
struct_def: is_pub (KW_STRUCT | KW_UNION) id_and_type_parameters COLON NEWLINE INDENT docstring struct_field+ DEDENT
struct_field: ID COLON typ NEWLINE
enum_def: is_pub KW_ENUM id_and_type_parameters COLON NEWLINE INDENT docstring enum_variant+ DEDENT
enum_variant: ID NEWLINE
            | ID LEFT_PARENTHESIS parameters RIGHT_PARENTHESIS NEWLINE
type_def: is_pub KW_TYPE ID EQUALS typ NEWLINE
id_and_type_parameters: ID type_parameters?
type_parameters: LEFT_BRACKET ids RIGHT_BRACKET
types: typ
     | types COMMA typ
typ: LEFT_BRACKET typ RIGHT_BRACKET
   | KW_FN LEFT_PARENTHESIS types? RIGHT_PARENTHESIS (ARROW typ)?
   | BITAND typ
   | ASTERIX typ
   | qual_name
   | qual_name LEFT_BRACKET types RIGHT_BRACKET
qual_name: ID (DOT ID)*
ids: ID
   | ids COMMA ID

block: COLON NEWLINE INDENT statement+ DEDENT
     | COLON test NEWLINE

statement: simple_statement NEWLINE
         | block_statement
         | big_expression
simple_statement: break_statement
                | continue_statement
                | pass_statement
                | assignment_statement
                | return_statement
                | raise_statement
                | delete_statement
block_statement: if_statement
               | while_statement
               | loop_statement
               | let_statement
               | for_statement
               | case_statement
               | switch_statement
               | try_statement

break_statement: KW_BREAK
continue_statement: KW_CONTINUE
pass_statement: KW_PASS
return_statement: KW_RETURN test?
assignment_statement: test (EQUALS | PLUS_EQUALS | MINUS_EQUALS | ASTERIX_EQUALS | SLASH_EQUALS) test

raise_statement: KW_RAISE expression
delete_statement: KW_DELETE ID

try_statement: KW_TRY block KW_EXCEPT LEFT_PARENTHESIS parameter RIGHT_PARENTHESIS block
if_statement: KW_IF test block elif_clause* else_clause?
elif_clause: KW_ELIF test block
else_clause: KW_ELSE block
let_statement: (KW_LET | KW_VAR) ID (COLON typ)? EQUALS big_expression
             | (KW_LET | KW_VAR) ID (COLON typ)? EQUALS block_statement
while_statement: KW_WHILE test block
loop_statement: KW_LOOP block
for_statement: KW_FOR ID KW_IN expression block
case_statement: KW_CASE expression COLON NEWLINE INDENT case_arm+ DEDENT else_clause?
case_arm: ID (LEFT_PARENTHESIS ids RIGHT_PARENTHESIS)? block
switch_statement: KW_SWITCH expression COLON NEWLINE INDENT switch_arm+ DEDENT else_clause
switch_arm: expression block

big_expression: test NEWLINE
              | obj_init
              | KW_NEW obj_init
test: disjunction
disjunction: disjunction KW_OR conjunction
           | conjunction
conjunction: conjunction KW_AND inversion
           | inversion
inversion: KW_NOT inversion
         | comparison
comparison: expression cmpop expression
          | expression
cmpop: LESS_THAN | GREATER_THAN | EQUALS_EQUALS | LESS_EQUALS | GREATER_EQUALS | NOT_EQUALS

expression: bitor
          | expression KW_IF test KW_ELSE expression
bitor: bitor BITOR bitxor
     | bitxor
bitxor: bitxor BITXOR bitand
      | bitand
bitand: bitand BITAND bitshift
      | bitshift
bitshift: bitshift SHR sum
        | bitshift SHL sum
        | sum
sum: sum addop term
   | term
addop: PLUS | MINUS
term: term mulop factor
    | factor
mulop: ASTERIX | SLASH | PERCENT
factor: atom
      | MINUS factor
      | PLUS factor
      | BITAND factor

atom: obj_ref
    | literal
    | string
    | array_literal
    | array_literal2
    | atom LEFT_PARENTHESIS arguments? RIGHT_PARENTHESIS
    | LEFT_PARENTHESIS test RIGHT_PARENTHESIS
    | atom LEFT_BRACKET tests RIGHT_BRACKET
    | atom DOT ID

tests: test
     | tests COMMA test

arguments: labeled_expression
         | arguments COMMA labeled_expression

literal: NUMBER | FNUMBER | BOOL | CHAR
rawstring: STRING_START STRING_LITERAL STRING_END
string: STRING_START string_part* STRING_END
string_part: STRING_LITERAL
           | LEFT_BRACE expression RIGHT_BRACE
array_literal: LEFT_BRACKET tests RIGHT_BRACKET
array_literal2: LEFT_BRACKET test COLON typ RIGHT_BRACKET
obj_ref: ID

obj_init: expression COLON NEWLINE INDENT field_init+ DEDENT
field_init: labeled_expression NEWLINE
labeled_expression: test
                  | ID COLON test

%declare KW_AND KW_BREAK KW_CASE KW_CLASS KW_CONTINUE
%declare KW_ELIF KW_ELSE KW_ENUM KW_PUB
%declare KW_FN KW_FOR KW_FROM KW_IF KW_IMPORT KW_IN
%declare KW_LET KW_LOOP KW_NOT KW_OR KW_PASS
%declare KW_RETURN KW_STRUCT KW_UNION KW_SWITCH KW_TYPE KW_VAR KW_WHILE
%declare KW_RAISE KW_TRY KW_EXCEPT KW_EXTERN
%declare KW_INTERFACE KW_IMPL KW_NEW KW_DELETE

%declare LEFT_PARENTHESIS RIGHT_PARENTHESIS LEFT_BRACE RIGHT_BRACE LEFT_BRACKET RIGHT_BRACKET
%declare COLON COMMA DOT ARROW QUESTION
%declare MINUS PLUS ASTERIX SLASH PERCENT
%declare LESS_THAN GREATER_THAN EQUALS_EQUALS LESS_EQUALS GREATER_EQUALS NOT_EQUALS
%declare EQUALS PLUS_EQUALS MINUS_EQUALS ASTERIX_EQUALS SLASH_EQUALS
%declare BITAND BITOR BITXOR SHR SHL

%declare INDENT DEDENT NEWLINE EOF
%declare NUMBER FNUMBER BOOL CHAR ID
%declare DOCSTRING

%declare STRING_START STRING_LITERAL STRING_END

"""
lark_parser = Lark(
    grammar, parser="lalr", lexer=CustomLarkLexer, start=["module", "eval_expr"]
)
