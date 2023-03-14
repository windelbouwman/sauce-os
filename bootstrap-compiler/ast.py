
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
        return f'{self.kind}[ty={self.ty}]'

    def clone(self):
        return Expression(self.kind, self.ty, self.location)

    def binop(self, op: str, rhs: 'Expression') -> 'Expression':
        return binop(self, op, rhs, self.location)

    def array_index(self, value: 'Expression') -> 'Expression':
        return array_index(self, value, self.location)


class Module(Node):
    def __init__(self, imports=(), definitions: list['Definition'] = ()):
        self.imports = list(imports)
        self.definitions = list(definitions)
        self.types = []
        self.scope = None


class Import(Node):
    def __init__(self, name: str, location: Location):
        super().__init__(location)
        self.name = name


class ImportFrom(Node):
    def __init__(self, modname: str, names: list[str], location: Location):
        super().__init__(location)
        assert isinstance(modname, str)
        assert isinstance(names, list)
        self.modname = modname
        self.names = names


class Definition(Node):
    pass


def class_def(name: str, members, location: Location):
    return ClassDef(name, members, location)


class ClassDef(Definition):
    def __init__(self, name: str, members, location: Location):
        super().__init__(location)
        self.name = name
        self.members = members


def var_def(name, ty, value, location: Location):
    assert isinstance(value, Expression)
    return VarDef(name, ty, value, location)


class VarDef(Definition):
    def __init__(self, name: str, ty: types.MyType, value: Expression, location: Location):
        super().__init__(location)
        self.name = name
        self.ty = ty
        self.value = value


def function_def(name: str, parameters: list['Parameter'], return_ty: types.MyType, statements: list['Statement'], location: Location):
    return FunctionDef(name, parameters, return_ty, statements, location)


class FunctionDef(Definition):
    def __init__(self, name: str, parameters: list['Parameter'], return_ty: types.MyType, statements: 'Statement', location: Location):
        super().__init__(location)
        assert isinstance(name, str)
        self.name = name
        self.parameters: list[Parameter] = parameters
        self.return_ty = return_ty
        self.statements = statements

    def get_type(self):
        return types.function_type([p.ty for p in self.parameters], self.return_ty)


class Parameter(Node):
    def __init__(self, name: str, ty: types.MyType, location: Location):
        super().__init__(location)
        assert isinstance(name, str)
        self.name = name
        assert isinstance(ty, types.MyType), str(ty)
        self.ty = ty

    def __repr__(self):
        return f"param({self.name})"


class StructDef(Definition):
    def __init__(self, name: str, fields: list['StructFieldDef'], location: Location):
        super().__init__(location)
        assert isinstance(name, str)
        self.name = name
        self.fields = fields
        self.scope = None

    def get_type(self):
        return types.struct_type(self)


class StructFieldDef(Node):
    def __init__(self, name: str, ty: types.MyType, location: Location):
        super().__init__(location)
        self.name = name
        self.ty = ty


class EnumDef(Definition):
    def __init__(self, name: str, type_parameters, variants: list['EnumVariant'], location: Location):
        super().__init__(location)
        self.name = name
        self.type_parameters = type_parameters
        self.variants = variants
        self.scope = None

    def get_type(self):
        return types.enum_type(self)


class EnumVariant(Node):
    def __init__(self, name: str, payload: list[types.MyType], location: Location):
        super().__init__(location)
        self.name = name
        self.payload = payload
    # def get_type(self):
    #     return types.StructType(self)


class Statement(Node):
    def __init__(self, kind: 'StatementKind', location: Location):
        super().__init__(location)
        self.kind = kind

    def __repr__(self):
        return f"stmt-{self.kind}"


class StatementKind:
    pass


def compound_statement(statements: list[Statement], location: Location):
    return Statement(CompoundStatement(statements), location)


class CompoundStatement(StatementKind):
    def __init__(self, statements: list['Statement']):
        super().__init__()
        self.statements = statements

    def __repr__(self):
        return f"CompoundStatement"


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


def let_statement(variable: 'Variable', ty: types.MyType | None, value: Expression, location: Location) -> Statement:
    kind = LetStatement(variable, ty, value)
    return Statement(kind, location)


class LetStatement(StatementKind):
    def __init__(self, variable: 'Variable', ty: types.MyType | None, value: Expression):
        super().__init__()
        assert isinstance(variable, Variable)
        self.ty = ty
        self.variable = variable
        self.value = value

    def __repr__(self):
        return f"Let({self.variable})"


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


def case_statement(value: Expression, arms: list['CaseArm'], location: Location):
    kind = CaseStatement(value, arms)
    return Statement(kind, location)


class CaseStatement(StatementKind):
    def __init__(self, value: Expression, arms: list['CaseArm']):
        self.value = value
        self.arms = arms


class CaseArm(Node):
    def __init__(self, name: str, variables: list['Variable'], body: Statement, location: Location):
        super().__init__(location)
        assert isinstance(name, str)
        self.name = name
        self.variables = variables
        self.body = body
        self.scope = None


def for_statement(variable: 'Variable', values: Expression, inner: Statement, location: Location) -> Statement:
    kind = ForStatement(variable, values, inner)
    return Statement(kind, location)


class ForStatement(StatementKind):
    def __init__(self, variable: 'Variable', values: Expression, inner: Statement):
        super().__init__()
        assert isinstance(variable, Variable)
        self.variable = variable
        self.values = values
        self.inner = inner

    def __repr__(self):
        return f"ForStatement({self.variable})"


def break_statement(location: Location) -> Statement:
    kind = BreakStatement()
    return Statement(kind, location)


class BreakStatement(StatementKind):
    def __repr__(self):
        return "Break"


def continue_statement(location: Location) -> Statement:
    return Statement(ContinueStatement(), location)


class ContinueStatement(StatementKind):
    def __repr__(self):
        return "Continue"


def pass_statement(location: Location) -> Statement:
    return Statement(PassStatement(), location)


class PassStatement(StatementKind):
    def __repr__(self):
        return "Pass"


def assignment_statement(target: Expression, value: Expression, location: Location):
    kind = AssignmentStatement(target, value)
    return Statement(kind, location)


class AssignmentStatement(StatementKind):
    def __init__(self, target: Expression, value: Expression):
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


def bool_constant(value: bool, location: Location):
    return Expression(BoolLiteral(value), types.bool_type, location)


class BoolLiteral(ExpressionKind):
    def __init__(self, value: bool):
        super().__init__()
        self.value = value

    def __repr__(self):
        return f'BoolLiteral({self.value})'


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


class SemiEnumLiteral(ExpressionKind):
    """ Variant, selected from enum, but not called yet.

    For example:
    >>> Option.Some

    To use the enum, call this expression:
    >>> Option.Some(1337)
    """

    def __init__(self, enum_def: EnumDef, variant: EnumVariant):
        super().__init__()
        self.enum_def = enum_def
        self.variant = variant


class EnumLiteral(ExpressionKind):
    def __init__(self, enum_def: EnumDef, variant: EnumVariant, values: list[Expression]):
        super().__init__()
        self.enum_def = enum_def
        self.variant = variant
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
        assert isinstance(base, Expression)
        assert isinstance(index, Expression)
        self.base = base
        self.index = index

    def __repr__(self):
        return f"ArrayIndex"


class Variable:
    def __init__(self, name: str, ty: types.MyType):
        super().__init__()
        assert isinstance(name, str)
        assert isinstance(ty, types.MyType)
        self.name = name
        self.ty = ty

    def __repr__(self):
        return f'var({self.name})'

    def ref_expr(self, location: Location) -> Expression:
        """ Retrieve an expression referring to this variable! """
        kind = ObjRef(self)
        return Expression(kind, self.ty, location)


class BuiltinModule:
    def __init__(self, name: str, symbols):
        super().__init__()
        self.name = name
        self.ty = types.ModuleType()
        self.symbols = symbols


class BuiltinFunction:
    def __init__(self, name: str, parameter_types: list[types.MyType], return_type: types.MyType):
        self.name = name
        self.ty = types.function_type(parameter_types, return_type)


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
            if definition.return_ty:
                self.visit_type(definition.return_ty)
            self.visit_statement(definition.statements)
        elif isinstance(definition, StructDef):
            for field in definition.fields:
                self.visit_type(field.ty)
        elif isinstance(definition, EnumDef):
            for variant in definition.variants:
                for ty in variant.payload:
                    self.visit_type(ty)
        elif isinstance(definition, ClassDef):
            for member in definition.members:
                self.visit_definition(member)
        elif isinstance(definition, VarDef):
            self.visit_type(definition.ty)
            self.visit_expression(definition.value)

    def visit_node(self, node: Node):
        if isinstance(node, CaseArm):
            self.visit_statement(node.body)
        else:
            raise NotImplementedError(str(node))

    def visit_type(self, ty: types.MyType):
        if isinstance(ty.kind, types.TypeExpression):
            self.visit_expression(ty.kind.expr)

    def visit_statement(self, statement: Statement):
        kind = statement.kind
        if isinstance(kind, IfStatement):
            self.visit_expression(kind.condition)
            self.visit_statement(kind.true_statement)
            if kind.false_statement:
                self.visit_statement(kind.false_statement)
        elif isinstance(kind, CaseStatement):
            self.visit_expression(kind.value)
            self.mid_statement(statement)
            for arm in kind.arms:
                self.visit_node(arm)
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
            self.visit_statement(kind.inner)
        elif isinstance(kind, LoopStatement):
            self.visit_statement(kind.inner)
        elif isinstance(kind, ForStatement):
            self.visit_expression(kind.values)
            self.mid_statement(statement)
            self.visit_statement(kind.inner)
        elif isinstance(kind, AssignmentStatement):
            self.visit_expression(kind.target)
            self.visit_expression(kind.value)
        elif isinstance(kind, CompoundStatement):
            for statement2 in kind.statements:
                self.visit_statement(statement2)
        elif isinstance(kind, (BreakStatement, ContinueStatement, PassStatement)):
            pass
        else:
            raise NotImplementedError(str(kind))

    def mid_statement(self, statement: Statement):
        """ Extra hook to allow mid-statement handlers """
        pass

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
        elif isinstance(kind, StructLiteral):
            for value in kind.values:
                self.visit_expression(value)
        elif isinstance(kind, EnumLiteral):
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

    def print_module(self, module: Module):
        self.emit('Imports:')
        for imp in module.imports:
            self.emit(f'- {imp}')

        self.visit_module(module)

    def visit_definition(self, definition: Definition):
        if isinstance(definition, FunctionDef):
            self.emit(f'- fn {definition.name}')
            self.indent()
        elif isinstance(definition, StructDef):
            self.emit(f'- struct {definition.name}')
            self.indent()
            for field in definition.fields:
                self.emit(f'- {field.name} : {field.ty}')
        elif isinstance(definition, EnumDef):
            self.emit(f'- enum {definition.name}')
            self.indent()
        elif isinstance(definition, ClassDef):
            self.emit(f'- class {definition.name}')
            self.indent()
        elif isinstance(definition, VarDef):
            self.emit(f'- var {definition.name}')
            self.indent()
        else:
            self.emit(f'- ? {definition}')
            self.indent()

        super().visit_definition(definition)
        self.dedent()

    def visit_statement(self, statement: Statement):
        self.emit(f'{statement.kind}')
        self.indent()
        super().visit_statement(statement)
        self.dedent()

    def visit_expression(self, expression: Expression):
        self.emit(f'{expression}')
        self.indent()
        super().visit_expression(expression)
        self.dedent()
