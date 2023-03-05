
from .location import Location
from . import types


class Node:
    def __init__(self, location: Location):
        self.location = location
        assert hasattr(location, 'row')


class Expression(Node):
    def __init__(self, location: Location):
        super().__init__(location)
        self.ty = None


class Module(Node):
    def __init__(self, imports: list['Import'] = (), definitions=()):
        self.imports = list(imports)
        self.definitions = list(definitions)
        self.types = []


class Import(Node):
    def __init__(self, name: str, location: Location):
        super().__init__(location)
        self.name = name


class FunctionDef(Node):
    def __init__(self, name: str, parameters: list['Parameter'], return_ty, statements: list['Statement'], location: Location):
        super().__init__(location)
        self.name = name
        self.parameters: list[Parameter] = parameters
        self.return_ty = return_ty
        self.statements = statements


class Parameter(Node):
    def __init__(self, name: str, ty, location: Location):
        super().__init__(location)
        self.name = name
        self.ty = ty


class StructDef(Node):
    def __init__(self, name: str, fields: list['StructFieldDef'], location: Location):
        super().__init__(location)
        self.name = name
        self.fields = fields


class StructFieldDef(Node):
    def __init__(self, name: str, ty, location: Location):
        super().__init__(location)
        self.name = name
        self.ty = ty


class Statement(Node):
    def __init__(self, location: Location):
        super().__init__(location)


class Let(Statement):
    def __init__(self, target, ty, value: Expression, location: Location):
        super().__init__(location)
        self.target = target
        self.ty = ty
        self.value = value

    def __repr__(self):
        return f"Let({self.target})"


class Loop(Statement):
    def __init__(self, inner: Statement, location: Location):
        super().__init__(location)
        self.inner = inner


class While(Statement):
    def __init__(self, condition: Expression, inner: Statement, location: Location):
        super().__init__(location)
        self.condition = condition
        self.inner = inner

    def __repr__(self):
        return "While"


class IfStatement(Statement):
    def __init__(self, condition: Expression, true_statement: Statement, false_statement: Statement, location: Location):
        super().__init__(location)
        self.condition = condition
        self.true_statement = true_statement
        self.false_statement = false_statement

    def __repr__(self):
        return "IfStatement"


class ForStatement(Statement):
    def __init__(self, target: str, values: Expression, inner: Statement, location: Location):
        super().__init__(location)
        self.target = target
        self.values = values
        self.inner = inner

    def __repr__(self):
        return f"ForStatement({self.target})"


class Break(Statement):
    def __init__(self, location: Location):
        super().__init__(location)

    def __repr__(self):
        return "Break"


class Continue(Statement):
    def __init__(self, location: Location):
        super().__init__(location)

    def __repr__(self):
        return "Continue"


class Assignment(Statement):
    def __init__(self, target, value: Expression, location: Location):
        super().__init__(location)
        self.target = target
        self.value = value

    def __repr__(self):
        return "Assignment"


class Return(Statement):
    def __init__(self, value, location: Location):
        super().__init__(location)
        self.value = value

    def __repr__(self):
        return 'Return'


class NewOp(Expression):
    def __init__(self, ty, fields: list['NewOpField'], location: Location):
        super().__init__(location)
        self.new_ty = ty
        self.fields = fields

    def __repr__(self):
        return f'NewOP'


class NewOpField(Node):
    def __init__(self, name: str, value: Expression, location: Location):
        super().__init__(location)
        self.name = name
        self.value = value

    def __repr__(self):
        return f'NewOpField({self.name})'


class FunctionCall(Expression):
    def __init__(self, target: Expression, args: list['Expression'], location: Location):
        super().__init__(location)
        self.target = target
        self.args = args

    def __repr__(self):
        return f'FunctionCall'


class Binop(Expression):
    def __init__(self, lhs: Expression, op: str, rhs: Expression, location: Location):
        super().__init__(location)
        self.lhs = lhs
        self.op = op
        self.rhs = rhs

    def __repr__(self):
        return f'Binop({self.op})'


class StringConstant(Expression):
    def __init__(self, text: str, location: Location):
        super().__init__(location)
        self.text = text

    def __repr__(self):
        return f'StringConstant("{self.text}")'


class NumericConstant(Expression):
    """ Float or int """

    def __init__(self, value, location: Location):
        super().__init__(location)
        self.value = value

    def __repr__(self):
        return f'NumericConstant({self.value})'


class ArrayLiteral(Expression):
    def __init__(self, values: list[Expression], location: Location):
        super().__init__(location)
        self.values = values

    def __repr__(self):
        return f'ArrayLiteral({len(self.values)})'


class NameRef(Node):
    def __init__(self, name: str, location: Location):
        super().__init__(location)
        self.name = name

    def __repr__(self):
        return f'name-ref({self.name})'


class DotOperator(Expression):
    """ variable.field operation.
    """

    def __init__(self, base: Expression, field: str, location: Location):
        super().__init__(location)
        self.base = base
        self.field = field

    def __repr__(self):
        return f"dot-operator({self.field})"


class ArrayIndex(Expression):
    """ variable[index] operation.
    """

    def __init__(self, base: Expression, index: Expression, location: Location):
        super().__init__(location)
        self.base = base
        self.index = index

    def __repr__(self):
        return f"ArrayIndex"


class Variable:
    def __init__(self, name: str, ty):
        super().__init__()
        self.name = name
        self.ty = ty

    def __repr__(self):
        return f'var({self.name})'


class BuiltinModule:
    def __init__(self, name: str, symbols):
        super().__init__()
        self.name = name
        self.ty = types.ModuleType()
        self.symbols = symbols


class BuiltinFunction:
    def __init__(self, name: str, parameter_types, return_type):
        self.name = name
        self.ty = types.FunctionType(parameter_types, return_type)


class Undefined:
    def __init__(self):
        self.ty = types.void_type


class AstVisitor:
    def visit_block(self, block: list['Statement']):
        if isinstance(block, list):
            for statement in block:
                self.visit_statement(statement)
        else:
            self.visit_statement(block)

    def visit_statement(self, statement: Statement):
        if isinstance(statement, IfStatement):
            self.visit_expression(statement.condition)
            self.visit_block(statement.true_statement)
            self.visit_block(statement.false_statement)
        elif isinstance(statement, Let):
            self.visit_expression(statement.value)
        elif isinstance(statement, Return):
            self.visit_expression(statement.value)
        elif isinstance(statement, FunctionCall):
            self.visit_expression(statement)
        elif isinstance(statement, While):
            self.visit_expression(statement.condition)
            self.visit_block(statement.inner)
        elif isinstance(statement, ForStatement):
            self.visit_expression(statement.values)
            self.visit_block(statement.inner)
        elif isinstance(statement, Assignment):
            self.visit_expression(statement.target)
            self.visit_expression(statement.value)

    def visit_expression(self, expression: Expression):
        if isinstance(expression, Binop):
            self.visit_expression(expression.lhs)
            self.visit_expression(expression.rhs)
        elif isinstance(expression, FunctionCall):
            self.visit_expression(expression.target)
            for arg in expression.args:
                self.visit_expression(arg)
        elif isinstance(expression, DotOperator):
            self.visit_expression(expression.base)
        elif isinstance(expression, ArrayLiteral):
            for value in expression.values:
                self.visit_expression(value)
        elif isinstance(expression, NewOp):
            for field in expression.fields:
                self.visit_expression(field.value)
        elif isinstance(expression, ArrayIndex):
            self.visit_expression(expression.base)
            self.visit_expression(expression.index)


def print_ast(mod: Module):
    AstPrinter().print_module(mod)


class AstPrinter(AstVisitor):
    def __init__(self):
        self._indent = 0

    def indent(self):
        self._indent += 4

    def dedent(self):
        self._indent -= 4

    def emit(self, txt: str):
        indent = ' ' * self._indent
        print(indent + txt)

    def print_module(self, mod: Module):
        self.emit('Imports:')
        for imp in mod.imports:
            self.emit(f'- {imp.name}')

        self.emit('Functions:')
        for definition in mod.definitions:
            if isinstance(definition, FunctionDef):
                self.emit(f'- fn {definition.name}')
                self.indent()
                self.visit_block(definition.statements)
                self.dedent()
            elif isinstance(definition, StructDef):
                self.emit(f'- struct {definition.name}')
                self.indent()
                for field in definition.fields:
                    self.emit(f'- {field.name} : {field.ty}')
                self.dedent()

    def visit_statement(self, statement: Statement):
        self.emit(f'{statement}')
        self.indent()
        super().visit_statement(statement)
        self.dedent()

    def visit_expression(self, expression: Expression):
        self.emit(f'{expression}')
        self.indent()
        super().visit_expression(expression)
        self.dedent()
