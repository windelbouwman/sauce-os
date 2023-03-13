""" Parser code.
"""

import logging

# try lark as parser
from lark import Lark, Transformer as LarkTransformer
from lark.lexer import Lexer as LarkLexer, Token as LarkToken

from . import ast, types
from .lexer import detect_indentations, tokenize, Location

logger = logging.getLogger('parser')


def parse(code: str) -> ast.Module:
    logger.info("Starting parse")
    # parser = Parser(code)
    # new_ast = parser.parse_module()
    tree = lark_parser.parse(code)
    logger.info("Parse complete!")
    new_ast = CustomTransformer().transform(tree)
    return new_ast


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
        }
        for token in detect_indentations(data, tokenize(data)):
            # print('token', token)
            ty2 = type_map.get(token.ty, token.ty)
            yield LarkToken(ty2, token.value, line=token.location.row, column=token.location.column)


def get_loc(tok: LarkToken):
    return Location(tok.line, tok.column)


class CustomTransformer(LarkTransformer):
    def start(self, x):
        return ast.Module(x[0], x[1])

    def imports(self, x):
        return x

    def import_(self, x):
        # print('import ', x)
        return ast.Import(x[1], get_loc(x[0]))

    def definitions(self, x):
        return x

    def definition(self, x):
        return x[0]

    def func_def(self, x):
        name = x[1]
        if isinstance(x[3], list):
            parameters = x[3]
        else:
            parameters = []
        body = x[-1]
        return_type = types.void_type
        return ast.FunctionDef(name, parameters, return_type, body, get_loc(x[0]))

    def parameters(self, x):
        if len(x) == 1:
            return x
        else:
            return x[0] + [x[2]]

    def struct_def(self, x):
        name = x[1]
        fields = x[5:-1]
        return ast.StructDef(name, fields, get_loc(x[0]))

    def struct_field(self, x):
        return ast.StructFieldDef(x[0], x[2], get_loc(x[0]))

    def typ(self, x):
        # print('typ', x)
        return types.TypeExpression(ast.name_ref(x[0], get_loc(x[0])))

    def parameter(self, x):
        return ast.Parameter(x[0].value, x[2], get_loc(x[0]))

    def block(self, x):
        return x[1:-1]

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
        return ast.expression_statement(x[0], x[0].location)

    def if_statement(self, x):
        condition = x[1]
        true_statement = x[4]
        if len(x) > 5:
            false_statement = x[5]
        else:
            false_statement = None
        return ast.if_statement(condition, true_statement, false_statement, get_loc(x[0]))

    def let_statement(self, x):
        """ KW_LET ID (COLON typ)? EQUALS expression NEWLINE """
        target = x[1]
        if isinstance(x[2], LarkToken) and x[2].type == 'COLON':
            assert isinstance(x[4], LarkToken) and x[4].type == 'EQUALS'
            ty, value = x[3], x[5]
        else:
            assert isinstance(x[2], LarkToken) and x[2].type == 'EQUALS'
            ty, value = None, x[3]
        return ast.let_statement(target, ty, value, get_loc(x[0]))

    def while_statement(self, x):
        condition, inner = x[1], x[4]
        return ast.while_statement(condition, inner, get_loc(x[0]))

    def loop_statement(self, x):
        inner = x[3]
        return ast.loop_statement(inner, get_loc(x[0]))

    def for_statement(self, x):
        target, values, inner = x[1], x[3], x[6]
        return ast.for_statement(target, values, inner, get_loc(x[0]))

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
            return ast.array_index(base, index, get_loc(x[1]))
        elif len(x) > 2 and isinstance(x[1], LarkToken) and x[1].type == 'DOT':
            base, field = x[0], x[2]
            return ast.dot_operator(base, field, get_loc(x[1]))
        else:
            raise NotImplementedError(str(x))

    def arguments(self, x):
        if len(x) == 1:
            return x
        else:
            return x[0] + [x[2]]

    def literal(self, x):
        if x[0].type == 'NUMBER':
            return ast.numeric_constant(x[0].value, get_loc(x[0]))
        elif x[0].type == 'STRING':
            return ast.string_constant(x[0].value, get_loc(x[0]))
        elif x[0].type == 'FNUMBER':
            return ast.numeric_constant(x[0].value, get_loc(x[0]))
        else:
            print('Literal!', x)

    def array_literal(self, x):
        return ast.array_literal(x[1], get_loc(x[0]))

    def obj_init(self, x):
        "obj_init: ID COLON NEWLINE INDENT field_init+ DEDENT"
        ty, fields = x[0], x[4:-1]
        return ast.new_op(ty, fields, get_loc(x[1]))

    def field_init(self, x):
        name, value = x[0], x[2]
        return ast.NewOpField(name, value, get_loc(x[1]))

    def obj_ref(self, x):
        if len(x) == 1:
            return ast.name_ref(x[0].value, get_loc(x[0]))
        else:
            return ast.dot_operator(x[0], x[2].value, get_loc(x[1]))


grammar = r"""
start: imports definitions

imports: import_*
import_: KW_IMPORT ID NEWLINE

definitions: definition*
definition: func_def
          | struct_def

func_def: KW_FN ID LEFT_BRACE parameters? RIGHT_BRACE COLON NEWLINE block
parameters: parameter
          | parameters COMMA parameter
parameter: ID COLON typ
struct_def: KW_STRUCT ID COLON NEWLINE INDENT struct_field+ DEDENT
struct_field: ID COLON typ NEWLINE
typ: ID
block: INDENT statement+ DEDENT

statement: simple_statement NEWLINE
         | if_statement
         | while_statement
         | loop_statement
         | let_statement
         | for_statement

simple_statement: expression
                | KW_BREAK
                | KW_CONTINUE
                | expression EQUALS expression
                | KW_RETURN expression?
if_statement: KW_IF test COLON NEWLINE block else_clause?
else_clause: KW_ELSE COLON NEWLINE block
let_statement: KW_LET ID (COLON typ)? EQUALS expression NEWLINE
             | KW_LET ID (COLON typ)? EQUALS obj_init
while_statement: KW_WHILE test COLON NEWLINE block
loop_statement: KW_LOOP COLON NEWLINE block
for_statement: KW_FOR ID KW_IN expression COLON NEWLINE block

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

literal: STRING | NUMBER | FNUMBER
array_literal: LEFT_BRACKET arguments RIGHT_BRACKET
obj_ref: ID
       | obj_ref DOUBLE_COLON ID

obj_init: typ COLON NEWLINE INDENT field_init+ DEDENT
field_init: ID COLON expression NEWLINE

%declare KW_AND KW_BREAK KW_CONTINUE KW_ELSE
%declare KW_FN KW_FOR KW_IF KW_IMPORT KW_IN
%declare KW_LET KW_LOOP KW_NOT KW_OR
%declare KW_RETURN KW_STRUCT KW_WHILE

%declare LEFT_BRACE RIGHT_BRACE LEFT_BRACKET RIGHT_BRACKET
%declare COLON DOUBLE_COLON COMMA DOT
%declare MINUS PLUS ASTERIX SLASH
%declare LESS_THAN GREATER_THAN EQUALS_EQUALS LESS_EQUALS GREATER_EQUALS EQUALS

%declare INDENT DEDENT NEWLINE
%declare NUMBER STRING FNUMBER ID

"""
lark_parser = Lark(grammar, parser='lalr', lexer=CustomLarkLexer)
