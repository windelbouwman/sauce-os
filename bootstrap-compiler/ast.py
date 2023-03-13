
from lark.load_grammar import Definition
from .location import Location
from . import types


class Node:
    def __init__(self, location: Location):
        self.location = location
        assert hasattr(location, 'row')


class Expression(Node):
    def __init__(self, kind: 'ExpressionKind', ty: types.MyType, location: Location):
        super().__init__(location)
        self.kind = kind
        self.ty = ty

    def __repr__(self):
        return f'kind={self.kind}, ty={self.ty}'

    def clone(self):
        return Expression(self.kind, self.ty, self.location)


class Module(Node):
    def __init__(self, imports: list['Import'] = (), definitions: list['Definition'] = ()):
        self.imports = list(imports)
        self.definitions = list(definitions)
        self.types = []
        self.scope = None


class Import(Node):
    def __init__(self, name: str, location: Location):
        super().__init__(location)
        self.name = name


class Definition(Node):
    pass


class FunctionDef(Definition):
    def __init__(self, name: str, parameters: list['Parameter'], return_ty: types.MyType, statements: list['Statement'], location: Location):
        super().__init__(location)
        self.name = name
        self.parameters: list[Parameter] = parameters
        self.return_ty = return_ty
        self.statements = statements

    def get_type(self):
        return types.FunctionType([p.ty for p in self.parameters], self.return_ty)


class Parameter(Node):
    def __init__(self, name: str, ty: types.MyType, location: Location):
        super().__init__(location)
        self.name = name
        assert isinstance(ty, types.MyType), str(ty)
        self.ty = ty


class StructDef(Definition):
    def __init__(self, name: str, fields: list['StructFieldDef'], location: Location):
        super().__init__(location)
        self.name = name
        self.fields = fields
        self.scope = None

    def get_type(self):
        return types.StructType(self)


class StructFieldDef(Node):
    def __init__(self, name: str, ty: types.MyType, location: Location):
        super().__init__(location)
        self.name = name
        self.ty = ty


class Statement(Node):
    def __init__(self, kind: 'StatementKind', location: Location):
        super().__init__(location)
        self.kind = kind


class StatementKind:
    pass


def expression_statement(value: Expression, location: Location) -> Statement:
    kind = ExpressionStatement(value)
    return Statement(kind, location)


class ExpressionStatement(StatementKind):
    def __init__(self, value: Expression):
        super().__init__()
        assert isinstance(value, Expression)
        self.value = value

    def __repr__(self):
        return f"ExpressionStatement"


def let_statement(target: str, ty: types.MyType | None, value: Expression, location: Location) -> Statement:
    kind = LetStatement(target, ty, value)
    return Statement(kind, location)


class LetStatement(StatementKind):
    def __init__(self, target: str, ty: types.MyType | None, value: Expression):
        super().__init__()
        self.target = target
        self.ty = ty
        self.variable = None
        self.value = value

    def __repr__(self):
        return f"Let({self.target})"


def loop_statement(inner: Statement, location: Location) -> Statement:
    kind = LoopStatement(inner)
    return Statement(kind, location)


class LoopStatement(StatementKind):
    def __init__(self, inner: Statement):
        super().__init__()
        self.inner = inner

    def __repr__(self):
        return "Loop"


def while_statement(condition: Expression, inner: Statement, location: Location):
    kind = WhileStatement(condition, inner)
    return Statement(kind, location)


class WhileStatement(StatementKind):
    def __init__(self, condition: Expression, inner: Statement):
        super().__init__()
        self.condition = condition
        self.inner = inner

    def __repr__(self):
        return "While"


def if_statement(condition: Expression, true_statement: Statement, false_statement: Statement, location: Location) -> Statement:
    kind = IfStatement(condition, true_statement, false_statement)
    return Statement(kind, location)


class IfStatement(StatementKind):
    def __init__(self, condition: Expression, true_statement: Statement, false_statement: Statement):
        super().__init__()
        self.condition = condition
        self.true_statement = true_statement
        self.false_statement = false_statement

    def __repr__(self):
        return "IfStatement"


def for_statement(target: str, values: Expression, inner: Statement, location: Location) -> Statement:
    kind = ForStatement(target, values, inner)
    return Statement(kind, location)


class ForStatement(StatementKind):
    def __init__(self, target: str, values: Expression, inner: Statement):
        super().__init__()
        self.target = target
        self.values = values
        self.inner = inner

    def __repr__(self):
        return f"ForStatement({self.target})"


def break_statement(location: Location) -> Statement:
    kind = BreakStatement()
    return Statement(kind, location)


class BreakStatement(StatementKind):
    def __init__(self):
        super().__init__()

    def __repr__(self):
        return "Break"


def continue_statement(location: Location) -> Statement:
    kind = ContinueStatement()
    return Statement(kind, location)


class ContinueStatement(StatementKind):
    def __init__(self):
        super().__init__()

    def __repr__(self):
        return "Continue"


def assignment_statement(target, value: Expression, location: Location):
    kind = AssignmentStatement(target, value)
    return Statement(kind, location)


class AssignmentStatement(StatementKind):
    def __init__(self, target, value: Expression):
        super().__init__()
        self.target = target
        self.value = value

    def __repr__(self):
        return "Assignment"


def return_statement(value: Expression | None, location: Location):
    kind = ReturnStatement(value)
    return Statement(kind, location)


class ReturnStatement(StatementKind):
    def __init__(self, value: Expression | None):
        super().__init__()
        self.value = value

    def __repr__(self):
        return 'Return'


class ExpressionKind:
    pass


def new_op(ty: types.MyType, fields: list['NewOpField'], location: Location):
    kind = NewOp(ty, fields)
    ty = types.void_type
    return Expression(kind, ty, location)


class NewOp(ExpressionKind):
    def __init__(self, ty: types.MyType, fields: list['NewOpField']):
        super().__init__()
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


def function_call(target: Expression, args: list['Expression'], location: Location):
    kind = FunctionCall(target, args)
    ty = types.void_type
    return Expression(kind, ty, location)


class FunctionCall(ExpressionKind):
    def __init__(self, target: Expression, args: list['Expression']):
        super().__init__()
        self.target = target
        self.args = args

    def __repr__(self):
        return f'FunctionCall'


def binop(lhs: Expression, op: str, rhs: Expression, location: Location):
    kind = Binop(lhs, op, rhs)
    ty = types.void_type
    return Expression(kind, ty, location)


class Binop(ExpressionKind):
    def __init__(self, lhs: Expression, op: str, rhs: Expression):
        super().__init__()
        self.lhs = lhs
        self.op = op
        self.rhs = rhs

    def __repr__(self):
        return f'Binop({self.op})'


def string_constant(text: str, location: Location):
    kind = StringConstant(text)
    ty = types.str_type
    return Expression(kind, ty, location)


class TypeCast(ExpressionKind):
    def __init__(self, ty: types.MyType, value: Expression):
        super().__init__()
        self.ty = ty
        self.value = value

    def __repr__(self):
        return f'TypeCast'


class StringConstant(ExpressionKind):
    def __init__(self, text: str):
        super().__init__()
        self.text = text

    def __repr__(self):
        return f'StringConstant("{self.text}")'


def numeric_constant(value: int | float, location: Location):
    kind = NumericConstant(value)
    if isinstance(value, int):
        ty = types.int_type
    else:
        assert isinstance(value, float)
        ty = types.float_type
    return Expression(kind, ty, location)


class NumericConstant(ExpressionKind):
    """ Float or int """

    def __init__(self, value: int | float):
        super().__init__()
        self.value = value

    def __repr__(self):
        return f'NumericConstant({self.value})'


def array_literal(values: list[Expression], location: Location):
    kind = ArrayLiteral(values)
    ty = types.void_type
    return Expression(kind, ty, location)


class ArrayLiteral(ExpressionKind):
    def __init__(self, values: list[Expression]):
        super().__init__()
        self.values = values

    def __repr__(self):
        return f'ArrayLiteral({len(self.values)})'


class StructLiteral(ExpressionKind):
    def __init__(self, ty: types.MyType, values: list[Expression]):
        self.ty = ty
        self.values = values


def name_ref(name: str, location: Location):
    kind = NameRef(name)
    ty = types.void_type
    return Expression(kind, ty, location)


class NameRef(ExpressionKind):
    def __init__(self, name: str):
        super().__init__()
        self.name = name

    def __repr__(self):
        return f'name-ref({self.name})'


class ObjRef(ExpressionKind):
    def __init__(self, obj):
        super().__init__()
        self.obj = obj

    def __repr__(self):
        return f'obj-ref({self.obj})'


def dot_operator(base: Expression, field: str, location: Location):
    kind = DotOperator(base, field)
    ty = types.void_type
    return Expression(kind, ty, location)


class DotOperator(ExpressionKind):
    """ variable.field operation.
    """

    def __init__(self, base: Expression, field: str):
        super().__init__()
        self.base = base
        self.field = field

    def __repr__(self):
        return f"dot-operator({self.field})"


def array_index(base: Expression, index: Expression, location: Location):
    kind = ArrayIndex(base, index)
    ty = types.void_type
    return Expression(kind, ty, location)


class ArrayIndex(ExpressionKind):
    """ variable[index] operation.
    """

    def __init__(self, base: Expression, index: Expression):
        super().__init__()
        self.base = base
        self.index = index

    def __repr__(self):
        return f"ArrayIndex"


class Variable:
    def __init__(self, name: str, ty: types.MyType):
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
    def visit_module(self, module: Module):
        for definition in module.definitions:
            self.visit_definition(definition)

    def visit_definition(self, definition: Definition):
        if isinstance(definition, FunctionDef):
            for parameter in definition.parameters:
                self.visit_type(parameter.ty)
            self.visit_block(definition.statements)
        elif isinstance(definition, StructDef):
            for field in definition.fields:
                self.visit_type(field.ty)

    def visit_type(self, ty: types.MyType):
        if isinstance(ty, types.TypeExpression):
            self.visit_expression(ty.expr)

    def visit_block(self, block: list['Statement']):
        if isinstance(block, list):
            for statement in block:
                self.visit_statement(statement)
        else:
            self.visit_statement(block)

    def visit_statement(self, statement: Statement):
        kind = statement.kind
        if isinstance(kind, IfStatement):
            self.visit_expression(kind.condition)
            self.visit_block(kind.true_statement)
            if kind.false_statement:
                self.visit_block(kind.false_statement)
        elif isinstance(kind, LetStatement):
            if kind.ty:
                self.visit_type(kind.ty)
            self.visit_expression(kind.value)
        elif isinstance(kind, ReturnStatement):
            if kind.value:
                self.visit_expression(kind.value)
        elif isinstance(kind, ExpressionStatement):
            self.visit_expression(kind.value)
        elif isinstance(kind, WhileStatement):
            self.visit_expression(kind.condition)
            self.visit_block(kind.inner)
        elif isinstance(kind, ForStatement):
            self.visit_expression(kind.values)
            self.visit_block(kind.inner)
        elif isinstance(kind, AssignmentStatement):
            self.visit_expression(kind.target)
            self.visit_expression(kind.value)

    def visit_expression(self, expression: Expression):
        kind = expression.kind
        if isinstance(kind, Binop):
            self.visit_expression(kind.lhs)
            self.visit_expression(kind.rhs)
        elif isinstance(kind, FunctionCall):
            self.visit_expression(kind.target)
            for arg in kind.args:
                self.visit_expression(arg)
        elif isinstance(kind, DotOperator):
            self.visit_expression(kind.base)
        elif isinstance(kind, ArrayLiteral):
            for value in kind.values:
                self.visit_expression(value)
        elif isinstance(kind, NewOp):
            self.visit_type(kind.new_ty)
            for field in kind.fields:
                self.visit_expression(field.value)
        elif isinstance(kind, ArrayIndex):
            self.visit_expression(kind.base)
            self.visit_expression(kind.index)
        elif isinstance(kind, TypeCast):
            self.visit_type(kind.ty)
            self.visit_expression(kind.value)


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
        self.emit(f'{statement.kind}')
        self.indent()
        super().visit_statement(statement)
        self.dedent()

    def visit_expression(self, expression: Expression):
        self.emit(f'{expression.kind}')
        self.indent()
        super().visit_expression(expression)
        self.dedent()
