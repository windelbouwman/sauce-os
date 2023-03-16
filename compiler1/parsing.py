""" Parser code.
"""

import logging
import os

# try lark as parser
from lark import Lark, Transformer as LarkTransformer
from lark.lexer import Lexer as LarkLexer, Token as LarkToken
from lark.exceptions import UnexpectedInput

from . import ast, types
from .lexer import detect_indentations, tokenize, Location
from .errors import ParseError, print_error

logger = logging.getLogger('parser')


def parse_file(filename: str) -> ast.Module:
    logger.info(f"Parsing {filename}")
    modname = os.path.splitext(os.path.basename(filename))[0]
    with open(filename, 'r') as f:
        code = f.read()
    return parse(code, modname, filename)


def parse(code: str, modname: str, filename: str) -> ast.Module:
    logger.info("Starting parse")
    # parser = Parser(code)
    # new_ast = parser.parse_module()
    try:
        tree = lark_parser.parse(code)
    except UnexpectedInput as ex:
        raise ParseError(
            [(filename, Location(ex.line, ex.column), 'Parsing choked')])
    module: ast.Module = CustomTransformer().transform(tree)
    module.name = modname
    module.filename = filename
    logger.info("Parse complete!")
    return module


class CustomLarkLexer(LarkLexer):
    def __init__(self, lexer_conf):
        pass

    def lex(self, data):
        type_map = {
            '(': 'LEFT_BRACE',
            ')': 'RIGHT_BRACE',
            '[': 'LEFT_BRACKET',
            ']': 'RIGHT_BRACKET',
            '<': 'LESS_THAN',
            '>': 'GREATER_THAN',
            '>=': 'GREATER_EQUALS',
            '<=': 'LESS_EQUALS',
            '=': 'EQUALS',
            '==': 'EQUALS_EQUALS',
            '-': 'MINUS',
            '+': 'PLUS',
            '*': 'ASTERIX',
            '/': 'SLASH',
            ':': 'COLON',
            '::': 'DOUBLE_COLON',
            ',': 'COMMA',
            '.': 'DOT',
            '->': 'ARROW',
        }
        for token in detect_indentations(data, tokenize(data)):
            # print('token', token)
            ty2 = type_map.get(token.ty, token.ty)
            yield LarkToken(ty2, token.value, line=token.location.row, column=token.location.column)


def get_loc(tok: LarkToken):
    return Location(tok.line, tok.column)


class CustomTransformer(LarkTransformer):
    def start(self, x):
        name = '?'
        imports, definitions = x
        return ast.Module(name, imports, definitions)

    def imports(self, x):
        return x

    def import1(self, x):
        modname = x[1].value
        return ast.Import(modname, get_loc(x[0]))

    def import2(self, x):
        modname = x[1].value
        names = x[3]
        return ast.ImportFrom(modname, names, get_loc(x[0]))

    def definitions(self, x):
        return x

    def definition(self, x):
        return x[0]

    def class_def(self, x):
        # class_def: KW_CLASS ID COLON NEWLINE INDENT (func_def | var_def)+ DEDENT
        name = x[1].value
        members = x[5:-1]
        # print(members)
        return ast.class_def(name, members, get_loc(x[0]))

    def var_def(self, x):
        # var_def: KW_VAR ID COLON typ EQUALS expression NEWLINE
        name = x[1].value
        ty, value = x[3], x[5]
        return ast.var_def(name, ty, value, get_loc(x[0]))

    def func_def(self, x):
        # KW_FN ID type_parameters? function_signature COLON NEWLINE block
        name = x[1].value
        if isinstance(x[4], LarkToken) and x[4].type == 'COLON':
            type_parameters = x[2]
        else:
            assert isinstance(x[3], LarkToken) and x[3].type == 'COLON'
            type_parameters = []
        parameters, return_type = x[-4]
        body = x[-1]
        return ast.function_def(name, type_parameters, parameters, return_type, body, get_loc(x[0]))

    def function_signature(self, x):
        # LEFT_BRACE parameters? RIGHT_BRACE (ARROW typ)?
        if isinstance(x[1], LarkToken) and x[1].type == 'RIGHT_BRACE':
            parameters = []
        else:
            assert isinstance(x[1], list)
            parameters = x[1]

        if isinstance(x[-2], LarkToken) and x[-2].type == 'ARROW':
            return_type = x[-1]
        else:
            return_type = types.void_type
        return parameters, return_type

    def parameters(self, x):
        if len(x) == 1:
            return x
        else:
            return x[0] + [x[2]]

    def struct_def(self, x):
        # KW_STRUCT type_parameters? ID COLON NEWLINE INDENT struct_field+ DEDENT
        if isinstance(x[3], LarkToken) and x[3].type == 'COLON':
            type_parameters = x[1]
            name = x[2].value
            fields = x[6:-1]
        else:
            assert isinstance(x[2], LarkToken) and x[2].type == 'COLON'
            type_parameters = []
            name = x[1].value
            fields = x[5:-1]
        is_union = False
        return ast.StructDef(name, type_parameters, is_union, fields, get_loc(x[0]))

    def struct_field(self, x):
        return ast.StructFieldDef(x[0], x[2], get_loc(x[0]))

    def enum_def(self, x):
        # KW_ENUM type_parameters? ID COLON NEWLINE INDENT enum_variant+ DEDENT
        if isinstance(x[3], LarkToken) and x[3].type == 'COLON':
            type_parameters = x[1]
            name = x[2].value
            variants = x[6:-1]
        else:
            assert isinstance(x[2], LarkToken) and x[2].type == 'COLON'
            type_parameters = []
            name = x[1].value
            variants = x[5:-1]
        return ast.EnumDef(name, type_parameters, variants, get_loc(x[0]))

    def enum_variant(self, x):
        name = x[0].value
        if len(x) == 2:
            payload = []
        else:
            assert len(x) == 5
            payload = x[2]
        return ast.EnumVariant(name, payload, get_loc(x[0]))

    def type_def(self, x):
        name, typ = x[1].value, x[3]
        return ast.type_def(name, typ, get_loc(x[0]))

    def type_parameters(self, x):
        # type_parameters: LESS_THAN ids GREATER_THAN
        return [ast.type_var(name, location) for name, location in x[1]]

    def typ(self, x):
        if isinstance(x[0], LarkToken) and x[0].type == 'KW_FN':
            # raise NotImplementedError('?')
            parameters, return_type = x[1]
            return types.function_type(parameters, return_type)
        else:
            assert isinstance(x[0], ast.Expression)
            return types.type_expression(x[0])

    def types(self, x):
        if len(x) == 1:
            return x
        else:
            return x[0] + [x[2]]

    def parameter(self, x):
        return ast.Parameter(x[0].value, x[2], get_loc(x[0]))

    def block(self, x):
        statements = x[1:-1]
        if len(statements) == 1:
            return statements[0]
        else:
            return ast.compound_statement(statements, get_loc(x[0]))

    def statement(self, x):
        return x[0]

    def simple_statement(self, x):
        if len(x) == 3:
            return ast.assignment_statement(x[0], x[2], get_loc(x[1]))
        elif isinstance(x[0], LarkToken) and x[0].type == 'KW_RETURN':
            value = x[1] if len(x) > 1 else None
            return ast.return_statement(value, get_loc(x[0]))
        elif isinstance(x[0], LarkToken) and x[0].type == 'KW_BREAK':
            return ast.break_statement(get_loc(x[0]))
        elif isinstance(x[0], LarkToken) and x[0].type == 'KW_CONTINUE':
            return ast.continue_statement(get_loc(x[0]))
        elif isinstance(x[0], LarkToken) and x[0].type == 'KW_PASS':
            return ast.pass_statement(get_loc(x[0]))
        assert isinstance(x[0], ast.Expression)
        return ast.expression_statement(x[0], x[0].location)

    def if_statement(self, x):
        # KW_IF test COLON NEWLINE block else_clause?
        condition = x[1]
        true_statement = x[4]
        if len(x) > 5:
            false_statement = x[5]
        else:
            false_statement = None
        return ast.if_statement(condition, true_statement, false_statement, get_loc(x[0]))

    def case_statement(self, x):
        # case_statement: KW_CASE expression COLON NEWLINE INDENT case_arm+ DEDENT else_clause?
        value = x[1]
        if isinstance(x[-1], LarkToken) and x[-1].type == 'DEDENT':
            arms = x[5:-1]
        else:
            assert x[-2].type == 'DEDENT'
            print("TODO: else clause in case statement")
            else_clause = x[-1]
            arms = x[5:-2]
        return ast.case_statement(value, arms, get_loc(x[0]))

    def case_arm(self, x):
        # case_arm: ID (LEFT_BRACE ids RIGHT_BRACE)? COLON NEWLINE block
        name = x[0].value
        if isinstance(x[1], LarkToken) and x[1].type == 'LEFT_BRACE':
            variables = [ast.Variable(name, types.void_type, location)
                         for name, location in x[2]]
        else:
            variables = []
        body = x[-1]
        return ast.CaseArm(name, variables, body, get_loc(x[0]))

    def switch_statement(self, x):
        # switch_statement: KW_SWITCH expression COLON NEWLINE INDENT switch_arm+ DEDENT KW_ELSE COLON NEWLINE block
        value = x[1]
        arms = x[5:-5]
        default_body = x[-1]
        return ast.switch_statement(value, arms, default_body, get_loc(x[0]))

    def switch_arm(self, x):
        # switch_arm: expression COLON NEWLINE block
        print(x)
        return ast.SwitchArm(x[0], x[3], get_loc(x[1]))

    def let_statement(self, x):
        """ KW_LET ID (COLON typ)? EQUALS expression NEWLINE """
        variable = ast.Variable(x[1].value, types.void_type, get_loc(x[1]))
        if isinstance(x[2], LarkToken) and x[2].type == 'COLON':
            assert isinstance(x[4], LarkToken) and x[4].type == 'EQUALS'
            ty, value = x[3], x[5]
        else:
            assert isinstance(x[2], LarkToken) and x[2].type == 'EQUALS'
            ty, value = None, x[3]
        return ast.let_statement(variable, ty, value, get_loc(x[0]))

    def while_statement(self, x):
        condition, inner = x[1], x[4]
        return ast.while_statement(condition, inner, get_loc(x[0]))

    def loop_statement(self, x):
        inner = x[3]
        return ast.loop_statement(inner, get_loc(x[0]))

    def for_statement(self, x):
        # KW_FOR ID KW_IN expression COLON NEWLINE block
        variable = ast.Variable(x[1].value, types.void_type, get_loc(x[1]))
        values, inner = x[3], x[6]
        return ast.for_statement(variable, values, inner, get_loc(x[0]))

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
            return ast.Unop(op, rhs, get_loc(x[0]))

    def comparison(self, x):
        lhs, op, rhs = x
        return ast.binop(lhs, op, rhs, get_loc(x[1]))

    def cmpop(self, x):
        return x[0]

    def expression(self, x):
        if len(x) == 1:
            return x[0]
        else:
            lhs, op, rhs = x
            return ast.binop(lhs, op, rhs, get_loc(x[1]))

    def sum(self, x):
        if len(x) == 1:
            return x[0]
        else:
            lhs, op, rhs = x
            return ast.binop(lhs, op, rhs, get_loc(x[1]))

    def addop(self, x):
        return x[0]

    def term(self, x):
        if len(x) == 1:
            return x[0]
        else:
            lhs, op, rhs = x
            return ast.binop(lhs, op, rhs, get_loc(x[1]))

    def mulop(self, x):
        return x[0]

    def factor(self, x):
        return x[0]

    def atom(self, x):
        if len(x) == 1:
            return x[0]
        elif len(x) > 2 and isinstance(x[1], LarkToken) and x[1].type == 'LEFT_BRACE':
            arguments = x[2] if len(x) == 4 else []
            return ast.function_call(x[0], arguments, get_loc(x[1]))
        elif len(x) > 2 and isinstance(x[0], LarkToken) and x[0].type == 'LEFT_BRACE':
            return x[1]
        elif len(x) > 2 and isinstance(x[1], LarkToken) and x[1].type == 'LEFT_BRACKET':
            base, index = x[0], x[2]
            ty = types.void_type
            return ast.array_index(base, index, ty, get_loc(x[1]))
        elif len(x) > 2 and isinstance(x[1], LarkToken) and x[1].type == 'DOT':
            base, field = x[0], x[2]
            ty = types.void_type
            return ast.dot_operator(base, field, ty, get_loc(x[1]))
        else:
            raise NotImplementedError(str(x))

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
        if x[0].type == 'NUMBER':
            return ast.numeric_constant(x[0].value, get_loc(x[0]))
        elif x[0].type == 'STRING':
            return ast.string_constant(x[0].value, get_loc(x[0]))
        elif x[0].type == 'FNUMBER':
            return ast.numeric_constant(x[0].value, get_loc(x[0]))
        elif x[0].type == 'BOOL':
            return ast.bool_constant(x[0].value, get_loc(x[0]))
        else:
            print('Literal!', x)

    def array_literal(self, x):
        return ast.array_literal(x[1], get_loc(x[0]))

    def obj_init(self, x):
        "obj_init: ID COLON NEWLINE INDENT field_init+ DEDENT"
        ty, fields = x[0], x[4: -1]
        return ast.new_op(ty, fields, get_loc(x[1]))

    def field_init(self, x):
        name, value = x[0], x[2]
        return ast.NewOpField(name, value, get_loc(x[1]))

    def obj_ref(self, x):
        if len(x) == 1:
            return ast.name_ref(x[0].value, get_loc(x[0]))
        else:
            ty = types.void_type
            return ast.dot_operator(x[0], x[2].value, ty, get_loc(x[1]))


grammar = r"""
start: imports definitions

imports: (import1|import2)*
import1: KW_IMPORT ID NEWLINE
import2: KW_FROM ID KW_IMPORT ids NEWLINE

definitions: definition*
definition: func_def
          | struct_def
          | enum_def
          | class_def
          | type_def

class_def: KW_CLASS ID COLON NEWLINE INDENT (func_def | var_def)+ DEDENT
var_def: KW_VAR ID COLON typ EQUALS expression NEWLINE
func_def: KW_FN ID type_parameters? function_signature COLON NEWLINE block
function_signature: LEFT_BRACE parameters? RIGHT_BRACE (ARROW typ)?
parameters: parameter
          | parameters COMMA parameter
parameter: ID COLON typ
struct_def: KW_STRUCT type_parameters? ID COLON NEWLINE INDENT struct_field+ DEDENT
struct_field: ID COLON typ NEWLINE
enum_def: KW_ENUM type_parameters? ID COLON NEWLINE INDENT enum_variant+ DEDENT
enum_variant: ID NEWLINE
            | ID LEFT_BRACE types RIGHT_BRACE NEWLINE
type_def: KW_TYPE ID EQUALS typ NEWLINE
type_parameters: LESS_THAN ids GREATER_THAN
types: typ
     | types COMMA typ
typ: expression
   | KW_FN function_signature
ids: ID
   | ids COMMA ID

block: INDENT statement+ DEDENT

statement: simple_statement NEWLINE
         | if_statement
         | while_statement
         | loop_statement
         | let_statement
         | for_statement
         | case_statement
         | switch_statement

simple_statement: expression
                | KW_BREAK
                | KW_CONTINUE
                | KW_PASS
                | expression EQUALS expression
                | KW_RETURN expression?
if_statement: KW_IF test COLON NEWLINE block else_clause?
else_clause: KW_ELSE COLON NEWLINE block
let_statement: KW_LET ID (COLON typ)? EQUALS expression NEWLINE
             | KW_LET ID (COLON typ)? EQUALS obj_init
while_statement: KW_WHILE test COLON NEWLINE block
loop_statement: KW_LOOP COLON NEWLINE block
for_statement: KW_FOR ID KW_IN expression COLON NEWLINE block
case_statement: KW_CASE expression COLON NEWLINE INDENT case_arm+ DEDENT else_clause?
case_arm: ID (LEFT_BRACE ids RIGHT_BRACE)? COLON NEWLINE block
switch_statement: KW_SWITCH expression COLON NEWLINE INDENT switch_arm+ DEDENT KW_ELSE COLON NEWLINE block
switch_arm: expression COLON NEWLINE block

test: disjunction
disjunction: disjunction KW_OR conjunction
           | conjunction
conjunction: conjunction KW_AND inversion
           | inversion
inversion: KW_NOT inversion
         | comparison
comparison: expression cmpop expression
cmpop: LESS_THAN | GREATER_THAN | EQUALS_EQUALS | LESS_EQUALS | GREATER_EQUALS

expression: sum
sum: sum addop term
   | term
addop: PLUS | MINUS
term: term mulop factor
    | factor
mulop: ASTERIX | SLASH
factor: atom

atom: obj_ref
    | literal
    | array_literal
    | atom LEFT_BRACE arguments? RIGHT_BRACE
    | LEFT_BRACE expression RIGHT_BRACE
    | atom LEFT_BRACKET expression RIGHT_BRACKET
    | atom DOT ID

arguments: expression
         | arguments COMMA expression

literal: STRING | NUMBER | FNUMBER | BOOL
array_literal: LEFT_BRACKET arguments RIGHT_BRACKET
obj_ref: ID
       | obj_ref DOUBLE_COLON ID

obj_init: typ COLON NEWLINE INDENT field_init+ DEDENT
field_init: ID COLON expression NEWLINE

%declare KW_AND KW_BREAK KW_CASE KW_CLASS KW_CONTINUE
%declare KW_ELSE KW_ENUM
%declare KW_FN KW_FOR KW_FROM KW_IF KW_IMPORT KW_IN
%declare KW_LET KW_LOOP KW_NOT KW_OR KW_PASS
%declare KW_RETURN KW_STRUCT KW_SWITCH KW_TYPE KW_VAR KW_WHILE

%declare LEFT_BRACE RIGHT_BRACE LEFT_BRACKET RIGHT_BRACKET
%declare COLON DOUBLE_COLON COMMA DOT ARROW
%declare MINUS PLUS ASTERIX SLASH
%declare LESS_THAN GREATER_THAN EQUALS_EQUALS LESS_EQUALS GREATER_EQUALS EQUALS

%declare INDENT DEDENT NEWLINE
%declare NUMBER STRING FNUMBER BOOL ID

"""
lark_parser = Lark(grammar, parser='lalr', lexer=CustomLarkLexer)
