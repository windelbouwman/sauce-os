""" Parser code.
"""

import logging
import os
import re

# try lark as parser
from lark import Lark, Transformer as LarkTransformer
from lark.lexer import Lexer as LarkLexer, Token as LarkToken
from lark.exceptions import UnexpectedInput, VisitError

from . import ast
from .lexer import detect_indentations, tokenize, Location, Position
from .errors import ParseError, CompilationError

logger = logging.getLogger("parser")


def parse_file(filename: str) -> ast.Module:
    if isinstance(filename, tuple):
        filename, code = filename
    else:
        with open(filename, "r") as f:
            code = f.read()
    logger.info(f"Parsing {filename}")
    modname = os.path.splitext(os.path.basename(filename))[0]
    # TODO: clean modname of more special characters
    modname = modname.replace("-", "_")
    return parse(code, modname, filename)


def parse(code: str, modname: str, filename: str) -> ast.Module:
    """Parse the given code."""
    logger.debug("Starting parse")
    try:
        module: ast.Module = lark_it(code, "module")
    except ParseError as ex:
        raise CompilationError([(filename, ex.location, ex.message)])

    assert isinstance(module, ast.Module)

    module.name = modname
    module.filename = filename
    logger.debug("Parse complete!")
    return module


def parse_expr(expr: str, start_loc: Location) -> ast.Expression:
    """Parse a single expression. Useful in f-strings."""

    node: ast.Expression = lark_it((start_loc, expr), start="eval_expr")
    assert isinstance(node, ast.Expression)
    # print(n)
    return node


def lark_it(code, start):
    """Invoke the lark parsing."""
    try:
        tree = lark_parser.parse(code, start=start)
    except UnexpectedInput as ex:
        raise ParseError(
            Location.from_row_column(ex.line, ex.column), f"Parsing choked: {ex}"
        )

    try:
        return CustomTransformer().transform(tree)
    except VisitError as ex:
        if isinstance(ex.orig_exc, ParseError):
            raise ex.orig_exc
        else:
            raise


def process_fstrings(literal: str, location: Location) -> ast.Expression:
    """Check if we have a string with f-strings in it."""

    # Check empty string:
    if not literal:
        return ast.string_constant(literal, location)

    # Split on braced expressions:
    parts = list(filter(None, re.split(r"({[^}]+})", literal)))
    # print('parts', parts, location)
    assert "".join(parts) == literal

    exprs = []
    row = location.begin.row
    col = location.begin.column + 1
    for part in parts:
        if part.startswith(r"{") and part.endswith("}"):
            p1 = Position(row, col + 1)
            p2 = Position(row, col + len(part) - 2)
            part_loc = Location(p1, p2)
            value = parse_expr(part[1:-1], part_loc)
            expr = value.to_string()
        else:
            p1 = Position(row, col)
            p2 = Position(row, col + len(part))
            part_loc = Location(p1, p2)
            expr = ast.string_constant(part, part_loc)
        col += len(part)
        exprs.append(expr)

    # Concatenate all parts:
    x = exprs.pop(0)
    while exprs:
        x = x.binop("+", exprs.pop(0))
    return x


class CustomLarkLexer(LarkLexer):
    def __init__(self, lexer_conf):
        pass

    def lex(self, data):
        type_map = {
            "(": "LEFT_BRACE",
            ")": "RIGHT_BRACE",
            "[": "LEFT_BRACKET",
            "]": "RIGHT_BRACKET",
            "<": "LESS_THAN",
            ">": "GREATER_THAN",
            ">=": "GREATER_EQUALS",
            "<=": "LESS_EQUALS",
            "=": "EQUALS",
            "==": "EQUALS_EQUALS",
            "!=": "NOT_EQUALS",
            "+=": "PLUS_EQUALS",
            "-=": "MINUS_EQUALS",
            "-": "MINUS",
            "+": "PLUS",
            "*": "ASTERIX",
            "/": "SLASH",
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
    return Location(
        Position(tok.line, tok.column), Position(tok.end_line, tok.end_column)
    )


def get_span(loc1: Location, loc2: Location):
    return Location(loc1.begin, loc2.end)


class CustomTransformer(LarkTransformer):
    def module(self, x):
        name = "?"
        imports, definitions = x
        return ast.Module(name, imports, definitions)

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
        # class_def: KW_CLASS id_and_type_parameters COLON NEWLINE INDENT (func_def | var_def)+ DEDENT
        assert x[2].type == "COLON"
        location, name, type_parameters = x[1]
        assert x[4].type == "INDENT"
        assert x[-1].type == "DEDENT"
        members = x[5:-1]
        return ast.class_def(name, type_parameters, members, location)

    def var_def(self, x):
        # var_def: KW_VAR ID COLON typ (EQUALS expression)? NEWLINE
        location = get_loc(x[0])
        name = x[1].value
        ty = x[3]
        if isinstance(x[4], LarkToken) and x[4].type == "EQUALS":
            value = x[5]
        else:
            value = None
        return ast.var_def(name, ty, value, location)

    def func_def(self, x):
        # KW_FN id_and_type_parameters function_signature block
        location, name, type_parameters = x[1]
        parameters, return_type, except_type = x[2]
        body = x[-1]
        return ast.function_def(
            name,
            type_parameters,
            parameters,
            return_type,
            except_type,
            body,
            get_loc(x[0]),
        )

    def function_signature(self, x):
        # LEFT_BRACE parameters? RIGHT_BRACE (ARROW typ)?
        if isinstance(x[1], LarkToken) and x[1].type == "RIGHT_BRACE":
            parameters = []
            idx = 2
        else:
            assert isinstance(x[1], list)
            parameters = x[1]
            idx = 3

        if idx < len(x) and isinstance(x[idx], LarkToken) and x[idx].type == "ARROW":
            return_type = x[idx + 1]
            idx += 2
        else:
            return_type = ast.void_type

        if (
            idx < len(x)
            and isinstance(x[idx], LarkToken)
            and x[idx].type == "KW_EXCEPT"
        ):
            except_type = x[idx + 1]
            idx += 2
        else:
            except_type = ast.void_type

        return parameters, return_type, except_type

    def parameters(self, x):
        if len(x) == 1:
            return x
        else:
            return x[0] + [x[2]]

    def struct_def(self, x):
        # struct_def: KW_STRUCT id_and_type_parameters COLON NEWLINE INDENT struct_field+ DEDENT
        assert isinstance(x[2], LarkToken) and x[2].type == "COLON"
        location, name, type_parameters = x[1]
        fields = x[5:-1]
        is_union = False
        return ast.StructDef(name, type_parameters, is_union, fields, location)

    def struct_field(self, x):
        return ast.StructFieldDef(x[0], x[2], get_loc(x[0]))

    def enum_def(self, x):
        # enum_def: KW_ENUM id_and_type_parameters COLON NEWLINE INDENT enum_variant+ DEDENT
        assert isinstance(x[2], LarkToken) and x[2].type == "COLON"
        location, name, type_parameters = x[1]
        variants = x[5:-1]
        return ast.EnumDef(name, type_parameters, variants, location)

    def enum_variant(self, x):
        name = x[0].value
        if len(x) == 2:
            payload = []
        else:
            assert len(x) == 5
            payload = [p.ty for p in x[2]]
        return ast.EnumVariant(name, payload, get_loc(x[0]))

    def type_def(self, x):
        name, typ = x[1].value, x[3]
        return ast.type_def(name, typ, get_loc(x[0]))

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
        return [ast.type_parameter(name, location) for name, location in x[1]]

    def typ(self, x):
        if isinstance(x[0], LarkToken) and x[0].type == "KW_FN":
            # KW_FN LEFT_BRACE types? RIGHT_BRACE (ARROW typ)?
            if isinstance(x[2], LarkToken) and x[2].type == "RIGHT_BRACE":
                parameter_types = []
            else:
                assert isinstance(x[2], list)
                parameter_types = x[2]
            parameter_names = [None] * len(parameter_types)

            if isinstance(x[-2], LarkToken) and x[-2].type == "ARROW":
                return_type = x[-1]
            else:
                return_type = ast.void_type

            except_type = ast.void_type

            return ast.function_type(
                parameter_names, parameter_types, return_type, except_type
            )
        else:
            assert isinstance(x[0], ast.Expression)
            return ast.type_expression(x[0])

    def types(self, x):
        if len(x) == 1:
            return x
        else:
            return x[0] + [x[2]]

    def parameter(self, x):
        # ID QUESTION? COLON typ
        name = x[0].value
        typ = x[-1]
        if len(x) == 4:
            needs_label = False
        else:
            needs_label = True
        return ast.Parameter(name, needs_label, typ, get_loc(x[0]))

    def block(self, x):
        # COLON NEWLINE INDENT statement+ DEDENT
        statements = x[3:-1]
        if len(statements) == 1:
            return statements[0]
        else:
            return ast.compound_statement(statements, get_loc(x[2]))

    def statement(self, x):
        return x[0]

    def simple_statement(self, x):
        if isinstance(x[0], ast.Expression):
            return ast.expression_statement(x[0], x[0].location)
        else:
            assert isinstance(x[0], ast.Statement)
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

    def raise_statement(self, x):
        # raise_statement: KW_RAISE expression
        value = x[1]
        return ast.raise_statement(value, get_loc(x[0]))

    def try_statement(self, x):
        # try_statement: KW_TRY block KW_EXCEPT LEFT_BRACE parameter RIGHT_BRACE block
        try_code = x[1]
        parameter = x[4]
        except_code = x[6]
        return ast.try_statement(try_code, parameter, except_code, get_loc(x[0]))

    def if_statement(self, x):
        # KW_IF test block elif_clause* else_clause?
        condition = x[1]
        true_statement = x[2]
        elif_tail = x[3:]

        # Assume no else clause:
        false_statement = ast.pass_statement(get_loc(x[0]))

        for tail in reversed(elif_tail):
            if isinstance(tail, ast.Statement):
                false_statement = tail
            else:
                test, body = tail
                false_statement = ast.if_statement(
                    test, body, false_statement, body.location
                )

        return ast.if_statement(
            condition, true_statement, false_statement, get_loc(x[0])
        )

    def case_statement(self, x):
        # case_statement: KW_CASE expression COLON NEWLINE INDENT case_arm+ DEDENT else_clause?
        value = x[1]
        if isinstance(x[-1], LarkToken) and x[-1].type == "DEDENT":
            arms = x[5:-1]
            else_clause = None
        else:
            assert x[-2].type == "DEDENT"
            else_clause = x[-1]
            arms = x[5:-2]
        return ast.case_statement(value, arms, else_clause, get_loc(x[0]))

    def case_arm(self, x):
        # case_arm: ID (LEFT_BRACE ids RIGHT_BRACE)? block
        name = x[0].value
        if isinstance(x[1], LarkToken) and x[1].type == "LEFT_BRACE":
            variables = [
                ast.Variable(name, ast.void_type, location) for name, location in x[2]
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
        """KW_LET ID (COLON typ)? EQUALS expression NEWLINE"""
        variable = ast.Variable(x[1].value, ast.void_type, get_loc(x[1]))
        if isinstance(x[2], LarkToken) and x[2].type == "COLON":
            assert isinstance(x[4], LarkToken) and x[4].type == "EQUALS"
            ty, value = x[3], x[5]
        else:
            assert isinstance(x[2], LarkToken) and x[2].type == "EQUALS"
            ty, value = None, x[3]
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
        variable = ast.Variable(x[1].value, ast.void_type, get_loc(x[1]))
        values, inner = x[3], x[4]
        return ast.for_statement(variable, values, inner, get_loc(x[0]))

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
            return ast.binop(lhs, op, rhs, get_loc(x[1]))

    def conjunction(self, x):
        if len(x) == 1:
            return x[0]
        else:
            assert len(x) == 3
            lhs, op, rhs = x
            return ast.binop(lhs, op, rhs, get_loc(x[1]))

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
            return ast.binop(lhs, op.value, rhs, get_loc(x[1]))

    def cmpop(self, x):
        return x[0]

    def expression(self, x):
        if len(x) == 1:
            return x[0]
        else:
            lhs, op, rhs = x
            return ast.binop(lhs, op.value, rhs, get_loc(x[1]))

    def sum(self, x):
        if len(x) == 1:
            return x[0]
        else:
            lhs, op, rhs = x
            return ast.binop(lhs, op.value, rhs, get_loc(x[1]))

    def addop(self, x):
        return x[0]

    def term(self, x):
        if len(x) == 1:
            return x[0]
        else:
            lhs, op, rhs = x
            return ast.binop(lhs, op.value, rhs, get_loc(x[1]))

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
        elif len(x) > 2 and isinstance(x[1], LarkToken) and x[1].type == "LEFT_BRACE":
            arguments = x[2] if len(x) == 4 else []
            callee = x[0]
            span = get_span(callee.location, get_loc(x[-1]))
            return ast.function_call(callee, arguments, span)
        elif len(x) > 2 and isinstance(x[0], LarkToken) and x[0].type == "LEFT_BRACE":
            return x[1]
        elif len(x) > 2 and isinstance(x[1], LarkToken) and x[1].type == "LEFT_BRACKET":
            base = x[0]
            index = x[2]
            ty = ast.void_type
            span = get_span(base.location, get_loc(x[-1]))
            return ast.array_index(base, index, ty, span)
        elif len(x) > 2 and isinstance(x[1], LarkToken) and x[1].type == "DOT":
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
        if x[0].type == "NUMBER":
            return ast.numeric_constant(x[0].value, get_loc(x[0]))
        elif x[0].type == "STRING":
            text = x[0].value
            return process_fstrings(text, get_loc(x[0]))
        elif x[0].type == "FNUMBER":
            return ast.numeric_constant(x[0].value, get_loc(x[0]))
        elif x[0].type == "BOOL":
            return ast.bool_constant(x[0].value, get_loc(x[0]))
        elif x[0].type == "CHAR":
            return ast.char_constant(x[0].value, get_loc(x[0]))
        else:
            raise NotImplementedError(f"Literal: {x}")

    def array_literal(self, x):
        return ast.array_literal(x[1], get_loc(x[0]))

    def obj_init(self, x):
        "obj_init: expr COLON NEWLINE INDENT field_init+ DEDENT"
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


grammar = r"""
module: imports definitions
eval_expr: expression NEWLINE

imports: (import1|import2)*
import1: KW_IMPORT ID NEWLINE
import2: KW_FROM ID KW_IMPORT ids NEWLINE

definitions: definition*
definition: func_def
          | struct_def
          | enum_def
          | class_def
          | type_def

class_def: KW_CLASS id_and_type_parameters COLON NEWLINE INDENT (func_def | var_def)+ DEDENT
var_def: KW_VAR ID COLON typ (EQUALS expression)? NEWLINE
func_def: KW_FN id_and_type_parameters function_signature block
function_signature: LEFT_BRACE parameters? RIGHT_BRACE (ARROW typ)? (KW_EXCEPT typ)?
parameters: parameter
          | parameters COMMA parameter
parameter: ID QUESTION? COLON typ
struct_def: KW_STRUCT id_and_type_parameters COLON NEWLINE INDENT struct_field+ DEDENT
struct_field: ID COLON typ NEWLINE
enum_def: KW_ENUM id_and_type_parameters COLON NEWLINE INDENT enum_variant+ DEDENT
enum_variant: ID NEWLINE
            | ID LEFT_BRACE parameters RIGHT_BRACE NEWLINE
type_def: KW_TYPE ID EQUALS typ NEWLINE
id_and_type_parameters: ID type_parameters?
type_parameters: LEFT_BRACKET ids RIGHT_BRACKET
types: typ
     | types COMMA typ
typ: expression
   | KW_FN LEFT_BRACE types? RIGHT_BRACE (ARROW typ)?
ids: ID
   | ids COMMA ID

block: COLON NEWLINE INDENT statement+ DEDENT

statement: simple_statement NEWLINE
         | if_statement
         | while_statement
         | loop_statement
         | let_statement
         | for_statement
         | case_statement
         | switch_statement
         | try_statement

simple_statement: expression
                | break_statement
                | continue_statement
                | pass_statement
                | assignment_statement
                | return_statement
                | raise_statement

break_statement: KW_BREAK
continue_statement: KW_CONTINUE
pass_statement: KW_PASS
return_statement: KW_RETURN test?
assignment_statement: expression (EQUALS | PLUS_EQUALS | MINUS_EQUALS) expression

raise_statement: KW_RAISE expression
try_statement: KW_TRY block KW_EXCEPT LEFT_BRACE parameter RIGHT_BRACE block
if_statement: KW_IF test block elif_clause* else_clause?
elif_clause: KW_ELIF test block
else_clause: KW_ELSE block
let_statement: KW_LET ID (COLON typ)? EQUALS expression NEWLINE
             | KW_LET ID (COLON typ)? EQUALS obj_init
while_statement: KW_WHILE test block
loop_statement: KW_LOOP block
for_statement: KW_FOR ID KW_IN expression block
case_statement: KW_CASE expression COLON NEWLINE INDENT case_arm+ DEDENT else_clause?
case_arm: ID (LEFT_BRACE ids RIGHT_BRACE)? block
switch_statement: KW_SWITCH expression COLON NEWLINE INDENT switch_arm+ DEDENT else_clause
switch_arm: expression block

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

expression: sum
sum: sum addop term
   | term
addop: PLUS | MINUS
term: term mulop factor
    | factor
mulop: ASTERIX | SLASH
factor: atom
      | MINUS factor

atom: obj_ref
    | literal
    | array_literal
    | atom LEFT_BRACE arguments? RIGHT_BRACE
    | LEFT_BRACE test RIGHT_BRACE
    | atom LEFT_BRACKET tests RIGHT_BRACKET
    | atom DOT ID

tests: test
     | tests COMMA test

arguments: labeled_expression
         | arguments COMMA labeled_expression

literal: STRING | NUMBER | FNUMBER | BOOL | CHAR
array_literal: LEFT_BRACKET tests RIGHT_BRACKET
obj_ref: ID

obj_init: expression COLON NEWLINE INDENT field_init+ DEDENT
field_init: labeled_expression NEWLINE
labeled_expression: test
                  | ID COLON test

%declare KW_AND KW_BREAK KW_CASE KW_CLASS KW_CONTINUE
%declare KW_ELIF KW_ELSE KW_ENUM
%declare KW_FN KW_FOR KW_FROM KW_IF KW_IMPORT KW_IN
%declare KW_LET KW_LOOP KW_NOT KW_OR KW_PASS
%declare KW_RETURN KW_STRUCT KW_SWITCH KW_TYPE KW_VAR KW_WHILE
%declare KW_RAISE KW_TRY KW_EXCEPT

%declare LEFT_BRACE RIGHT_BRACE LEFT_BRACKET RIGHT_BRACKET
%declare COLON COMMA DOT ARROW QUESTION
%declare MINUS PLUS ASTERIX SLASH
%declare LESS_THAN GREATER_THAN EQUALS_EQUALS LESS_EQUALS GREATER_EQUALS NOT_EQUALS
%declare EQUALS PLUS_EQUALS MINUS_EQUALS

%declare INDENT DEDENT NEWLINE
%declare NUMBER STRING FNUMBER BOOL CHAR ID

"""
lark_parser = Lark(
    grammar, parser="lalr", lexer=CustomLarkLexer, start=["module", "eval_expr"]
)
