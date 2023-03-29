
from lark.load_grammar import Definition
from .location import Location


class Node:
    def __init__(self, location: Location):
        self.location = location
        assert hasattr(location, 'row')


class Definition(Node):
    def __init__(self, name: str, location: Location):
        super().__init__(location)
        assert isinstance(name, str)
        self.name = name
        self.scope = Scope()


class Scope:
    def __init__(self):
        self.symbols: dict[str, 'Definition'] = {}

    def is_defined(self, name: str) -> bool:
        return name in self.symbols

    def lookup(self, name: str) -> 'Definition':
        if name in self.symbols:
            return self.symbols[name]
        raise ValueError(f'Name {name} not found')

    def define(self, name: str, symbol: 'Definition'):
        self.symbols[name] = symbol


class TypeKind:
    pass


class MyType:
    """ Represents a type.

    Has many query functions to inspect what type we are.
    """

    def __init__(self, kind: TypeKind):
        # Use a member, to allow passing by 'reference'
        # AKA be able to mutate a type by passing the type object
        # and modifying is.
        self.kind = kind

    def clone(self) -> 'MyType':
        return MyType(self.kind)

    def is_reftype(self):
        return False

    def is_void(self):
        return isinstance(self.kind, VoidType)

    def is_struct(self):
        return isinstance(self.kind, App) and isinstance(self.kind.tycon, StructDef) and not self.kind.tycon.is_union

    def is_union(self):
        return isinstance(self.kind, App) and isinstance(self.kind.tycon, StructDef) and self.kind.tycon.is_union

    def is_enum(self):
        return isinstance(self.kind, App) and isinstance(self.kind.tycon, EnumDef)

    def is_class(self):
        return isinstance(self.kind, App) and isinstance(self.kind.tycon, ClassDef)

    def is_int(self) -> bool:
        return isinstance(self.kind, BaseType) and self.kind.is_int()

    def is_float(self) -> bool:
        return isinstance(self.kind, BaseType) and self.kind.is_float()

    def has_field(self, name: str) -> bool:
        if isinstance(self.kind, App):
            if isinstance(self.kind.tycon, StructDef):
                return self.kind.tycon.has_field(name)
            elif isinstance(self.kind.tycon, ClassDef):
                return self.kind.tycon.has_field(name)
            else:
                return False
        else:
            return False

    def get_field_name(self, i: int | str) -> str:
        """ Retrieve name of field. i can be index or name """
        if isinstance(self.kind, App):
            if isinstance(self.kind.tycon, StructDef):
                return self.kind.tycon.get_field(i).name
            elif isinstance(self.kind.tycon, ClassDef):
                return self.kind.tycon.get_field(i).name

        raise ValueError("Can only get field from struct/union")

    def get_field_names(self) -> list[str]:
        """ Retrieve names of all fields """
        if isinstance(self.kind, App) and isinstance(self.kind.tycon, StructDef):
            return self.kind.tycon.get_field_names()
        raise ValueError("Can only get field names from struct/union")

    def get_field_type(self, i: int | str) -> 'MyType':
        """ Retrieve type of field. i can be index or name """
        if isinstance(self.kind, App):
            # if isinstance(self.kind, (StructType, ClassType)):
            if isinstance(self.kind.tycon, StructDef):
                field = self.kind.tycon.get_field(i)
                return subst(field.ty, self.kind.m)
            elif isinstance(self.kind.tycon, ClassDef):
                return subst(self.kind.tycon.get_field_type(i), self.kind.m)
            else:
                raise NotImplementedError()
        else:
            raise ValueError("Can only get field from struct/union/class")

    def get_field_types(self) -> list['MyType']:
        """ Retrieve types of all fields """
        if isinstance(self.kind, App) and isinstance(self.kind.tycon, StructDef):
            return [subst(f.ty, self.kind.m) for f in self.kind.tycon.fields]
        else:
            raise ValueError("Can only get field names from struct/union")

    def has_variant(self, name: str) -> bool:
        if isinstance(self.kind, App) and isinstance(self.kind.tycon, EnumDef):
            return self.kind.tycon.scope.is_defined(name)
        else:
            return False

    def get_variant(self, name: str) -> 'EnumVariant':
        if isinstance(self.kind, App) and isinstance(self.kind.tycon, EnumDef):
            variant: EnumVariant = self.kind.tycon.scope.lookup(name)
            return variant
        else:
            raise ValueError(f'No variant enum type')

    def get_variant_types(self, name: str) -> list['MyType']:
        if isinstance(self.kind, App) and isinstance(self.kind.tycon, EnumDef):
            variant: EnumVariant = self.kind.tycon.scope.lookup(name)
            return [subst(p, self.kind.m) for p in variant.payload]
        else:
            raise ValueError(f'No variant enum type')

    # def equals(self, other: 'MyType'):
    #     assert isinstance(other, MyType)
    #     if self is other:
    #         return True
    #     elif isinstance(self.kind, BaseType) and isinstance(other.kind, BaseType):
    #         return self.kind.name == other.kind.name
    #     elif isinstance(self.kind, StructType) and isinstance(other.kind, StructType):
    #         # TODO: check for equal type_arguments
    #         return (self.kind.struct_def is other.kind.struct_def)
    #     elif isinstance(self.kind, EnumType) and isinstance(other.kind, EnumType):
    #         return self.kind.enum_def is other.kind.enum_def
    #     elif isinstance(self.kind, FunctionType) and isinstance(other.kind, FunctionType):
    #         return self.kind.equals(other.kind)
    #     elif isinstance(self.kind, ClassType) and isinstance(other.kind, ClassType):
    #         return self.kind.class_def is other.kind.class_def
    #     else:
    #         return False

    def __repr__(self):
        return f"{self.kind}"


def subst(t: MyType, m: dict['TypeVar', MyType]) -> MyType:
    """ Substitute type variables.
    """
    if isinstance(t.kind, TypeVarKind):
        if t.kind.type_variable in m:
            return m[t.kind.type_variable]
        else:
            return t
    elif isinstance(t.kind, App):
        return tycon_apply(t.kind.tycon, [subst(u, m) for u in t.kind.type_args])
    elif isinstance(t.kind, (BaseType, VoidType)):
        return t
    elif isinstance(t.kind, FunctionType):
        new_args = [subst(a, m) for a in t.kind.parameter_types]
        new_ret = subst(t.kind.return_type, m)
        return function_type(new_args, new_ret)
    else:
        raise NotImplementedError(str(t))


class TypeConstructor(Definition):
    """ A type constructor.

    Apply actual types to create a type.

    Basetype for struct/enum/class defs!
    """

    def __init__(self, name: str, location: Location, type_parameters: list['TypeVar']):
        super().__init__(name, location)
        self.type_parameters = type_parameters

    def apply(self, type_arguments: list['MyType']):
        return tycon_apply(self, type_arguments)

    def equals(self, other: 'TypeConstructor') -> bool:
        raise NotImplementedError()


class App(TypeKind):
    """ Type application.

    Apply type arguments to given type constructor.
    """

    def __init__(self, tycon: TypeConstructor, type_args: list['MyType']):
        assert isinstance(tycon, TypeConstructor)
        assert len(tycon.type_parameters) == len(type_args)
        self.m = dict(zip(tycon.type_parameters, type_args))
        self.tycon = tycon
        self.type_args = type_args

    def __repr__(self):
        if self.type_args:
            return f"App({self.tycon},{self.type_args})"
        else:
            return f"A({self.tycon})"


class TypeFunc(TypeConstructor):
    """ Type function!

    This represents a generic type. Create actual types
    by applying type arguments.
    """

    def __init__(self, type_parameters: list['TypeVar'], ty: MyType):
        super().__init__()
        self.type_parameters = type_parameters
        self.ty = ty


def base_type(name: str):
    return MyType(BaseType(name))


class BaseType(TypeKind):
    def __init__(self, name: str):
        super().__init__()
        self.name = name

    def __repr__(self):
        return f'base-type<{self.name}>'

    def equals(self, other: 'TypeKind'):
        if isinstance(other, BaseType):
            return self.name == other.name
        else:
            return False

    def is_int(self) -> bool:
        return self.name == 'int'

    def is_float(self) -> bool:
        return self.name == 'float'


def type_expression(expr: 'Expression'):
    return MyType(TypeExpression(expr))


class TypeExpression(TypeKind):
    def __init__(self, expr: 'Expression'):
        super().__init__()
        self.expr = expr

    def __repr__(self):
        return f'type-expr<{self.expr}>'


class VoidType(TypeKind):
    def __init__(self):
        super().__init__()

    def __repr__(self):
        return 'void'

    def equals(self, other: 'TypeKind'):
        return isinstance(other, VoidType)


def function_type(parameter_types: list[MyType], return_type: MyType) -> MyType:
    """ Create function type with no type parameters. """
    return MyType(FunctionType(parameter_types, return_type))


# class FunctionType(TypeConstructor):
#     """ Function/Arrow operator. """

#     def __repr__(self):
#         return 'Arrow'


class FunctionType(TypeKind):
    def __init__(self, parameter_types: list[MyType], return_type: MyType):
        super().__init__()
        self.parameter_types = parameter_types
        self.return_type = return_type

    def __repr__(self):
        return f'Function({self.parameter_types}, {self.return_type})'

    # def equals(self, other: 'FunctionType') -> bool:
    #     if not self.return_type.equals(other.return_type):
    #         return False
    #     if len(self.parameter_types) != len(other.parameter_types):
    #         return False
    #     return all(a.equals(b) for a, b in zip(self.parameter_types, other.parameter_types))


def struct_type(struct_def: 'StructDef', type_arguments: list[MyType]) -> MyType:
    return tycon_apply(struct_def, type_arguments)


def enum_type(enum_def: 'EnumDef', type_arguments: list[MyType]) -> MyType:
    return tycon_apply(enum_def, type_arguments)


def class_type(class_def: 'ClassDef', type_arguments: list[MyType]) -> MyType:
    return tycon_apply(class_def, type_arguments)


def array_type(size: int, element_type: MyType) -> MyType:
    return MyType(ArrayType(size, element_type))


class ArrayType(TypeKind):
    def __init__(self, size: int, element_type: MyType):
        super().__init__()
        self.size = size
        self.element_type = element_type


def tycon_apply(tycon: TypeConstructor, type_args: list[MyType]) -> MyType:
    """ Apply type arguments to type constructor. """
    if isinstance(tycon, TypeFunc):
        pass
    return MyType(App(tycon, type_args))


def meta_type(name: str) -> MyType:
    return MyType(Meta(name))


class Meta(TypeKind):
    """ An unknown, to be inferred type. """

    def __init__(self, name: str):
        super().__init__()
        self.name = name
        self.assigned: MyType = None

    def __repr__(self):
        return f"Meta({self.name})"


def type_var_ref(type_variable: 'TypeVar') -> MyType:
    return MyType(TypeVarKind(type_variable))


class TypeVarKind(TypeKind):
    def __init__(self, type_variable: 'TypeVar'):
        super().__init__()
        self.type_variable = type_variable

    def __repr__(self):
        return f"var({self.type_variable})"


str_type = base_type("str")
int_type = base_type("int")
float_type = base_type("float")
bool_type = base_type('bool')
void_type = MyType(VoidType())


class Expression(Node):
    def __init__(self, kind: 'ExpressionKind', ty: MyType, location: Location):
        super().__init__(location)
        self.kind = kind
        assert isinstance(ty, MyType)
        self.ty = ty

        # Ideas for attributes:
        self.is_constant = False
        self.is_lvalue = False

    def __repr__(self):
        return f'{self.kind}[ty={self.ty}]'

    def clone(self):
        return Expression(self.kind, self.ty, self.location)

    def binop(self, op: str, rhs: 'Expression') -> 'Expression':
        return binop(self, op, rhs, self.location)

    def get_attr(self, field: str | int) -> 'Expression':
        if self.ty.is_struct():
            ty = self.ty.get_field_type(field)
            field = self.ty.get_field_name(field)
        else:
            ty = void_type
        return dot_operator(self, field, ty, self.location)

    def array_index(self, value: 'Expression') -> 'Expression':
        assert isinstance(self.ty.kind, ArrayType)
        ty = self.ty.kind.element_type
        return array_index(self, value, ty, self.location)

    def call(self, arguments: list['Expression']) -> 'Expression':
        return function_call(self, arguments, self.location)


class Module(Node):
    def __init__(self, name: str, imports: list['BaseImport'], definitions: list['Definition']):
        super().__init__(Location(1, 1))
        assert isinstance(name, str)
        self.name = name
        self.filename = ''
        self.imports = list(imports)
        self.definitions = list(definitions)
        self.types = []
        self.scope: Scope = Scope()

    def __repr__(self):
        return f"Module({self.name})"

    def get_deps(self) -> list[str]:
        return [imp.modname for imp in self.imports]

    def has_field(self, name: str) -> bool:
        return self.scope.is_defined(name)

    def get_field(self, name: str) -> 'Definition':
        return self.scope.lookup(name)

    def add_definition(self, name: str, definition: 'Definition'):
        assert not self.scope.is_defined(name)
        self.scope.define(name, definition)
        self.definitions.append(definition)


class BaseImport(Node):
    def __init__(self, modname: str, location: Location):
        super().__init__(location)
        assert isinstance(modname, str)
        self.modname = modname


class Import(BaseImport):
    def __repr__(self):
        return f"import({self.modname})"


class ImportFrom(BaseImport):
    def __init__(self, modname: str, names: list[tuple[str, Location]], location: Location):
        super().__init__(modname, location)
        assert isinstance(names, list)
        self.modname = modname
        self.names = names

    def __repr__(self):
        return f"import({self.names})from({self.modname})"


def type_var(name: str, location: Location):
    return TypeVar(name, location)


class TypeVar(Definition):
    """ Type variable, used when dealing with generics.
    """

    def __init__(self, name: str, location: Location):
        super().__init__(name, location)

    def __repr__(self):
        return f'type-var({self.name})'


def type_def(name: str, ty: MyType, location: Location):
    return TypeDef(name, ty, location)


class TypeDef(Definition):
    def __init__(self, name: str, ty: MyType, location: Location):
        super().__init__(name, location)
        assert isinstance(ty, MyType)
        self.ty = ty


def class_def(name: str, type_parameters: list[TypeVar], members: list['Definition'], location: Location):
    return ClassDef(name, type_parameters, members, location)


class ClassDef(TypeConstructor):
    def __init__(self, name: str, type_parameters: list[TypeVar], members: list['Definition'], location: Location):
        super().__init__(name, location, type_parameters)
        self.members = members

    def __repr__(self):
        return f"class-{self.name}"

    def get_type(self, type_arguments: list[MyType]):
        return class_type(self, type_arguments)

    def has_field(self, name: str) -> bool:
        return self.scope.is_defined(name)

    def get_field(self, name: str | int) -> 'Definition':
        if isinstance(name, int):
            raise NotImplementedError('Get field by int')
        else:
            return self.scope.lookup(name)

    def get_field_type(self, i: int | str) -> MyType:
        field = self.get_field(i)
        if isinstance(field, FunctionDef):
            return field.get_type()
        else:
            assert isinstance(field, VarDef)
            return field.ty

    def equals(self, other: 'TypeConstructor') -> bool:
        return self is other


def var_def(name: str, ty: MyType, value: Expression, location: Location):
    assert isinstance(value, Expression)
    return VarDef(name, ty, value, location)


class VarDef(Definition):
    def __init__(self, name: str, ty: MyType, value: Expression, location: Location):
        super().__init__(name, location)
        self.ty = ty
        self.value = value


def function_def(name: str, type_parameters: list[TypeVar], parameters: list['Parameter'], return_ty: MyType, statements: 'Statement', location: Location):
    return FunctionDef(name, type_parameters, parameters, return_ty, statements, location)


class FunctionDef(Definition):
    def __init__(self, name: str, type_parameters: list[TypeVar], parameters: list['Parameter'], return_ty: MyType, statements: 'Statement', location: Location):
        super().__init__(name, location)
        self.name = name
        self.type_parameters = type_parameters
        self.parameters: list[Parameter] = parameters
        self.return_ty = return_ty
        self.statements = statements

    def __repr__(self):
        return f"func-def-{self.name}"


class Parameter(Definition):
    def __init__(self, name: str, ty: MyType, location: Location):
        super().__init__(name, location)
        assert isinstance(ty, MyType), str(ty)
        self.ty = ty

    def __repr__(self):
        return f"param({self.name})"


class StructDef(TypeConstructor):
    def __init__(self, name: str, type_parameters: list[TypeVar], is_union: bool, fields: list['StructFieldDef'], location: Location):
        super().__init__(name, location, type_parameters)
        assert isinstance(name, str)
        self.is_union = is_union
        for index, field in enumerate(fields):
            field.index = index
        self.fields = fields

    def __repr__(self):
        t = 'union' if self.is_union else 'struct'
        return f"{t}-{self.name}"

    def has_field(self, name: str) -> bool:
        return self.scope.is_defined(name)

    def get_field(self, name: str | int) -> 'StructFieldDef':
        if isinstance(name, int):
            return self.fields[name]
        else:
            return self.scope.lookup(name)

    def get_field_names(self) -> list[str]:
        return [field.name for field in self.fields]

    def equals(self, other: 'TypeConstructor') -> bool:
        return self is other


class StructFieldDef(Definition):
    def __init__(self, name: str, ty: MyType, location: Location):
        super().__init__(name, location)
        assert isinstance(ty, MyType)
        self.index = 0
        self.ty = ty


class StructBuilder:
    """ Builder for structs.
    """

    def __init__(self, name: str, is_union: bool, location: Location):
        self.name = name
        self.type_parameters = []
        self.is_union = is_union
        self.fields = []
        self.location = location

    def set_is_union(self, value: bool):
        self.is_union = value

    def add_type_parameter(self, name: str, location: Location) -> MyType:
        type_var = TypeVar(name, location)
        self.type_parameters.append(type_var)
        return type_var_ref(type_var)

    def add_field(self, name: str, ty: MyType, location: Location):
        self.fields.append(StructFieldDef(name, ty, location))

    def finish(self) -> StructDef:
        return StructDef(self.name, self.type_parameters, self.is_union, self.fields, self.location)


class EnumDef(TypeConstructor):
    def __init__(self, name: str, type_parameters: list[TypeVar], variants: list['EnumVariant'], location: Location):
        super().__init__(name, location, type_parameters)

        # Assign index to variants:
        for idx, variant in enumerate(variants):
            variant.index = idx

        self.variants = variants

    def __repr__(self):
        return f"Enum-{self.name}"

    def get_type(self, type_arguments: list[MyType]) -> MyType:
        return enum_type(self, type_arguments)

    def equals(self, other: TypeConstructor) -> bool:
        return self is other


class EnumVariant(Definition):
    def __init__(self, name: str, payload: list[MyType], location: Location):
        super().__init__(name, location)
        self.payload = payload
        self.index = 0

    def __repr__(self):
        return f'EnumVariant({self.name})'


class Statement(Node):
    def __init__(self, kind: 'StatementKind', location: Location):
        super().__init__(location)
        self.kind = kind

    def __repr__(self):
        return f"stmt-{self.kind}"


class StatementKind:
    pass


def compound_statement(statements: list[Statement], location: Location):
    if len(statements) == 1:
        return statements[0]
    else:
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


def let_statement(variable: 'Variable', ty: MyType | None, value: Expression, location: Location) -> Statement:
    kind = LetStatement(variable, ty, value)
    return Statement(kind, location)


class LetStatement(StatementKind):
    def __init__(self, variable: 'Variable', ty: MyType | None, value: Expression):
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


def case_statement(value: Expression, arms: list['CaseArm'], location: Location) -> Statement:
    kind = CaseStatement(value, arms)
    return Statement(kind, location)


class CaseStatement(StatementKind):
    def __init__(self, value: Expression, arms: list['CaseArm']):
        assert isinstance(value, Expression)
        self.value = value
        self.arms = arms

    def __repr__(self):
        return f"CaseStatement"


class CaseArm(Node):
    def __init__(self, name: str, variables: list['Variable'], body: Statement, location: Location):
        super().__init__(location)
        assert isinstance(name, str)
        self.name = name
        self.variables = variables
        assert isinstance(body, Statement)
        self.body = body
        self.scope = Scope()


def switch_statement(value: Expression, arms: list['SwitchArm'], default_body: Statement, location: Location) -> Statement:
    kind = SwitchStatement(value, arms, default_body)
    return Statement(kind, location)


class SwitchStatement(StatementKind):
    def __init__(self, value: Expression, arms: list['SwitchArm'], default_body: Statement):
        assert isinstance(value, Expression)
        self.value = value
        self.arms = arms
        self.default_body = default_body

    def __repr__(self):
        return f"SwitchStatement"


class SwitchArm(Node):
    def __init__(self, value: Expression, body: Statement, location: Location):
        super().__init__(location)
        assert isinstance(value, Expression)
        self.value = value
        assert isinstance(body, Statement)
        self.body = body


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


def assignment_statement(target: Expression, value: Expression, location: Location) -> Statement:
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


def new_op(ty: MyType, fields: list['NewOpField'], location: Location):
    kind = NewOp(ty, fields)
    ty = void_type
    return Expression(kind, ty, location)


class NewOp(ExpressionKind):
    def __init__(self, ty: MyType, fields: list['NewOpField']):
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
    ty = void_type
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
    ty = void_type
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
    ty = str_type
    return Expression(kind, ty, location)


class TypeCast(ExpressionKind):
    def __init__(self, ty: MyType, value: Expression):
        super().__init__()
        self.ty = ty
        self.value = value

    def __repr__(self):
        return f'TypeCast'


class StringConstant(ExpressionKind):
    def __init__(self, text: str):
        super().__init__()
        assert isinstance(text, str)
        self.text = text

    def __repr__(self):
        return f'StringConstant("{self.text}")'


def numeric_constant(value: int | float, location: Location):
    kind = NumericConstant(value)
    if isinstance(value, int):
        ty = int_type
    else:
        assert isinstance(value, float)
        ty = float_type
    return Expression(kind, ty, location)


class NumericConstant(ExpressionKind):
    """ Float or int """

    def __init__(self, value: int | float):
        super().__init__()
        self.value = value

    def __repr__(self):
        return f'NumericConstant({self.value})'


def bool_constant(value: bool, location: Location):
    return Expression(BoolLiteral(value), bool_type, location)


class BoolLiteral(ExpressionKind):
    def __init__(self, value: bool):
        super().__init__()
        assert isinstance(value, bool)
        self.value = value

    def __repr__(self):
        return f'BoolLiteral({self.value})'


def array_literal(values: list[Expression], location: Location):
    kind = ArrayLiteral(values)
    ty = void_type
    return Expression(kind, ty, location)


class ArrayLiteral(ExpressionKind):
    def __init__(self, values: list[Expression]):
        super().__init__()
        self.values = values

    def __repr__(self):
        return f'ArrayLiteral({len(self.values)})'


def struct_literal(ty: MyType, values: list[Expression], location: Location) -> Expression:
    assert ty.is_struct()
    kind = StructLiteral(ty, values)
    return Expression(kind, ty, location)


class StructLiteral(ExpressionKind):
    def __init__(self, ty: MyType, values: list[Expression]):
        super().__init__()
        self.ty = ty
        self.values = values

    def __repr__(self):
        return f'StructLiteral'


def union_literal(ty: MyType, field: str | int, value: Expression, location: Location) -> Expression:
    assert ty.is_union()
    if isinstance(field, int):
        field = ty.get_field_name(field)
    kind = UnionLiteral(ty, field, value)
    return Expression(kind, ty, location)


class UnionLiteral(ExpressionKind):
    def __init__(self, ty: MyType, field: str | int, value: Expression):
        super().__init__()
        self.ty = ty
        self.field = field
        self.value = value

    def __repr__(self):
        return f'UnionLiteral({self.field})'


class GenericLiteral(ExpressionKind):
    def __init__(self, tycon: TypeConstructor):
        super().__init__()
        self.tycon = tycon

    def __repr__(self):
        return f"generic-literal({self.tycon})"


class TypeLiteral(ExpressionKind):
    def __init__(self, ty: MyType):
        super().__init__()
        self.ty = ty

    def __repr__(self):
        return f"type-literal({self.ty})"


class SemiEnumLiteral(ExpressionKind):
    """ Variant, selected from enum, but not called yet.

    For example:
    >>> Option.Some

    To use the enum, call this expression:
    >>> Option.Some(1337)
    """

    def __init__(self, enum_ty: MyType, variant: EnumVariant):
        super().__init__()
        self.enum_ty = enum_ty
        self.variant = variant


class EnumLiteral(ExpressionKind):
    def __init__(self, enum_ty: MyType, variant: EnumVariant, values: list[Expression]):
        super().__init__()
        self.enum_ty = enum_ty
        self.variant = variant
        self.values = values

    def __repr__(self):
        return f'EnumLiteral({self.variant})'


def name_ref(name: str, location: Location):
    kind = NameRef(name)
    ty = void_type
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


def dot_operator(base: Expression, field: str, ty: MyType, location: Location):
    kind = DotOperator(base, field)
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


def array_index(base: Expression, index: Expression, ty: MyType, location: Location):
    kind = ArrayIndex(base, index)
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


class Variable(Definition):
    def __init__(self, name: str, ty: MyType, location: Location):
        super().__init__(name, location)
        assert isinstance(ty, MyType)
        self.ty = ty

    def __repr__(self):
        return f'var({self.name})'

    def ref_expr(self, location: Location) -> Expression:
        """ Retrieve an expression referring to this variable! """
        return Expression(ObjRef(self), self.ty, location)


class BuiltinFunction(Definition):
    def __init__(self, name: str, parameter_types: list[MyType], return_type: MyType):
        super().__init__(name, Location(1, 1))
        self.ty = function_type(parameter_types, return_type)

    def __repr__(self):
        return f'builtin({self.name})'


class Undefined:
    def __init__(self):
        self.ty = void_type


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
        elif isinstance(definition, TypeDef):
            self.visit_type(definition.ty)

    def visit_node(self, node: Node):
        if isinstance(node, CaseArm):
            self.visit_statement(node.body)
        elif isinstance(node, SwitchArm):
            self.visit_expression(node.value)
            self.visit_statement(node.body)
        else:
            raise NotImplementedError(str(node))

    def visit_type(self, ty: MyType):
        if isinstance(ty.kind, TypeExpression):
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
            for arm in kind.arms:
                self.visit_node(arm)
        elif isinstance(kind, SwitchStatement):
            self.visit_expression(kind.value)
            for arm in kind.arms:
                self.visit_node(arm)
            self.visit_statement(kind.default_body)
        elif isinstance(kind, LetStatement):
            if kind.ty:
                self.visit_type(kind.ty)
            self.visit_type(kind.variable.ty)
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
            self.visit_type(kind.ty)
            for value in kind.values:
                self.visit_expression(value)
        elif isinstance(kind, UnionLiteral):
            self.visit_type(kind.ty)
            self.visit_expression(kind.value)
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
            t = 'union' if definition.is_union else 'struct'
            self.emit(f'- {t} {definition.name}')
            self.indent()
            for field in definition.fields:
                self.emit(f'- {field.name} : {field.ty}')
        elif isinstance(definition, EnumDef):
            self.emit(f'- enum {definition.name}')
            self.indent()
            for variant in definition.variants:
                self.emit(f"- {variant.name} : {variant.payload}")
        elif isinstance(definition, ClassDef):
            self.emit(f'- class {definition.name}')
            self.indent()
        elif isinstance(definition, VarDef):
            self.emit(f'- var {definition.name}')
            self.indent()
        elif isinstance(definition, TypeDef):
            self.emit(f'- type-def {definition.name}')
            self.indent()
        else:
            self.emit(f'- ? {definition}')
            self.indent()

        super().visit_definition(definition)
        self.dedent()

    # def visit_type(self, ty: MyType):
    #     self.emit(f"ty > {ty}")
    #     self.indent()
    #     super().visit_type(ty)
    #     self.dedent()

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
