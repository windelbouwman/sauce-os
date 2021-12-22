""" Parser code.
"""

import logging
import re

from .ast import Module, FunctionCall
from .ast import Import, FunctionDef, StructDef, Parameter
from .ast import StructFieldDef
from .ast import FunctionCall, IfStatement, Let
from .ast import NameRef, DotOperator, NewOp, NewOpField
from .ast import NumericConstant, StringConstant, Binop
from .ast import Continue, Break, Return
from .symboltable import Scope
from .lexer import detect_indentations, tokenize
from .errors import print_error, ParseError
logger = logging.getLogger('parser')


def parse(code):
    logger.info("Starting parse")
    parser = Parser(code)
    new_ast = parser.parse_module()
    return new_ast


class Parser:
    def __init__(self, code):
        self.code = code
        self._tokens = detect_indentations(code, tokenize(code))
        self.peek = next(self._tokens)
        self._scopes = [Scope(None)]

    def parse_module(self):
        mod = Module()
        while self.peek:
            if self.peek.ty == 'fn':
                func = self.parse_function_def()
                mod.functions.append(func)
            elif self.peek.ty == 'import':
                location = self.consume('import').location
                name = self.consume('ID').value
                imp = Import(name, location)
                mod.imports.append(imp)
            elif self.peek.ty == 'struct':
                s = self.parse_struct_def()
                mod.types.append(s)
            else:
                self.error(self.peek.location, f'What now: {self.peek.ty}')
        return mod

    def parse_struct_def(self):
        location = self.consume('struct').location
        name = self.consume('ID').value
        self.consume(':')
        self.consume('INDENT')
        fields = []
        var, ty = self.parse_typed_var()
        fields.append(StructFieldDef(var.value, ty, var.location))
        while self.peek.ty != 'DEDENT':
            var, ty = self.parse_typed_var()
            fields.append(StructFieldDef(var.value, ty, var.location))
        self.consume('DEDENT')
        return StructDef(name, fields, location)

    def parse_typed_var(self):
        name = self.consume('ID')
        self.consume(':')
        ty = self.parse_type()
        return name, ty

    def parse_type(self):
        name = self.consume('ID')
        ty = NameRef(name.value, name.location)
        return ty

    def parse_function_def(self):
        location = self.consume('fn').location
        name = self.consume('ID').value
        self.consume('(')
        if self.peek.ty == ')':
            args = []
        else:
            args = self.parse_one_or_more(self.parse_function_parameter, ',')
        self.consume(')')
        if self.peek.ty == '->':
            self.consume('->')
            return_ty = self.parse_type()
        else:
            return_ty = None
        self.consume(':')
        statements = self.parse_block()
        func = FunctionDef(name, args, return_ty, statements, location)
        logger.debug(f'Parsed function {func.name}')
        return func

    def parse_function_parameter(self):
        name, ty = self.parse_typed_var()
        return Parameter(name.value, ty, name.location)

    def parse_statement(self):
        if self.peek.ty == 'ID':
            statement = self.parse_expression()
        elif self.peek.ty == 'if':
            statement = self.parse_if_statement()
        elif self.peek.ty == 'let':
            statement = self.parse_let_statement()
        elif self.peek.ty == 'loop':
            statement = self.parse_loop_statement()
        elif self.peek.ty == 'while':
            statement = self.parse_while_statement()
        elif self.peek.ty == 'pass':
            self.consume('pass')
            statement = None
        elif self.peek.ty == 'break':
            location = self.consume('break').location
            statement = Break(location)
        elif self.peek.ty == 'continue':
            location = self.consume('continue').location
            statement = Continue(location)
        elif self.peek.ty == 'return':
            location = self.consume('return').location
            value = self.parse_expression()
            statement = Return(value, location)
        else:
            self.error(self.peek.location,
                       f'Unknown statement: {self.peek.ty}')
        # logger.debug(f'Parsed statement: {statement}')
        return statement

    def parse_function_call(self, target):
        location = self.consume('(').location
        if self.peek.ty == ')':
            args = []
        else:
            args = self.parse_one_or_more(self.parse_expression, ',')
        self.consume(')')
        return FunctionCall(target, args, location)

    def parse_one_or_more(self, func, seperator):
        items = [func()]
        while self.has_consumed(seperator):
            items.append(func())
        return items

    def parse_if_statement(self):
        location = self.consume('if').location
        condition = self.parse_expression()
        self.consume(':')
        true_block = self.parse_block()
        if self.peek.ty == 'else':
            self.consume('else')
            self.consume(':')
            false_block = self.parse_block()
        else:
            false_block = None
        statement = IfStatement(condition, true_block, false_block, location)
        return statement

    def parse_let_statement(self):
        location = self.consume('let').location
        target = self.consume('ID')
        self.consume('=')
        value = self.parse_expression()
        return Let(target.value, value, location)

    def parse_loop_statement(self):
        location = self.consume('loop').location
        self.consume(':')
        inner = self.parse_block()
        return Loop(inner, location)

    def parse_while_statement(self):
        location = self.consume('while').location
        self.consume(':')
        inner = self.parse_block()
        return While(inner, location)

    def parse_block(self):
        statements = []
        self.consume('INDENT')
        statement = self.parse_statement()
        statements.append(statement)
        while self.peek.ty != 'DEDENT':
            statement = self.parse_statement()
            statements.append(statement)
        self.consume('DEDENT')
        return statements

    PRIO = {
        'or': 10,
        'and': 20,
        '<': 30,
        '<=': 30,
        '!=': 30,
        '==': 30,
        '>=': 30,
        '>': 30,
        '+': 50,
        '-': 50,
        '*': 60,
        '/': 60,
    }

    def parse_expression(self, binding=0):
        value = self.parse_primary()
        while (
                self.peek.ty in self.PRIO and
                self.PRIO[self.peek.ty] >= binding):
            prio = self.PRIO[self.peek.ty] + 1
            op = self.consume()
            rhs = self.parse_expression(prio)
            value = Binop(value, op.value, rhs, op.location)
        return value

    def parse_primary(self):
        """ Parse a primary expression! """
        if self.peek.ty == 'STRING':
            text = self.consume('STRING')
            value = StringConstant(text.value[1:-1], text.location)
        elif self.peek.ty == 'ID':
            value = self.parse_designator()
        elif self.peek.ty == 'NUMBER':
            val = self.consume('NUMBER')
            value = NumericConstant(val.value, val.location)
        elif self.peek.ty == '(':
            self.consume('(')
            value = self.parse_expression()
            self.consume(')')
        else:
            self.error(self.peek.location,
                       f'Unknown expression: {self.peek.ty}')

        # post fixes!
        while self.peek.ty in ['(', '.', '{', '[']:
            if self.peek.ty == '(':
                value = self.parse_function_call(value)
            elif self.peek.ty == '.':
                location = self.consume('.').location
                field = self.consume('ID').value
                value = DotOperator(value, field, location)
            elif self.peek.ty == '{':
                location = self.consume('{').location
                fields = self.parse_one_or_more(
                    self.parse_new_struct_field_initializer, ',')
                value = NewOp(value, fields, location)
                self.consume('}')
            elif self.peek.ty == '[':
                raise NotImplementedError('Array indexing?')
            else:
                raise NotImplementedError(str(self.peek.ty))

        return value

    def parse_new_struct_field_initializer(self):
        name = self.consume('ID')
        self.consume(':')
        field_value = self.parse_expression()
        return NewOpField(name.value, field_value, name.location)

    def parse_designator(self):
        name = self.consume('ID')
        location = name.location
        name = name.value
        return NameRef(name, location)

    def consume(self, ty=None):
        tok = self.next_token()
        if ty:
            if tok.ty != ty:
                self.error(
                    tok.location, f'Expected {ty}, but got {tok.ty}')
        return tok

    def has_consumed(self, ty):
        if self.peek.ty == ty:
            self.consume(ty)
            return True
        else:
            return False

    def error(self, location, message):
        print_error(self.code, location, message)
        raise ParseError(message)

    def next_token(self):
        token = self.peek
        self.peek = next(self._tokens, None)
        # logger.debug(f'Parsing {token} (next={self.peek})')
        return token
