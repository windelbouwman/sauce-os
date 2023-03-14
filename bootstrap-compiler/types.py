
class TypeKind:
    pass


class MyType:
    def __init__(self, kind: TypeKind):
        # Use a member, to allow passing by 'reference'
        # AKA be able to mutate a type by passing the type object
        # and modifying is.
        self.kind = kind

    def is_reftype(self):
        return False

    def is_void(self):
        return isinstance(self.kind, VoidType)

    def is_struct(self):
        return isinstance(self.kind, StructType)

    def is_enum(self):
        return isinstance(self.kind, EnumType)

    def is_int(self) -> bool:
        return isinstance(self.kind, BaseType) and self.kind.name == 'int'

    def is_float(self) -> bool:
        return isinstance(self.kind, BaseType) and self.kind.name == 'float'

    def equals(self, other: 'MyType'):
        if self is other:
            return True
        elif isinstance(self.kind, BaseType) and isinstance(other.kind, BaseType):
            return self.kind.name == other.kind.name
        elif isinstance(self.kind, StructType) and isinstance(other.kind, StructType):
            return self.kind.struct_def is other.kind.struct_def
        elif isinstance(self.kind, EnumType) and isinstance(other.kind, EnumType):
            return self.kind.enum_def is other.kind.enum_def
        else:
            return False

    def __repr__(self):
        return f"{self.kind}"


def base_type(name: str):
    return MyType(BaseType(name))


class BaseType(TypeKind):
    def __init__(self, name: str):
        super().__init__()
        self.name = name

    def __repr__(self):
        return f'base-type<{self.name}>'


def type_expression(expr):
    return MyType(TypeExpression(expr))


class TypeExpression(TypeKind):
    def __init__(self, expr):
        super().__init__()
        self.expr = expr

    def __repr__(self):
        return f'type-expr<{self.expr}>'


class VoidType(TypeKind):
    def __repr__(self):
        return 'void'


def function_type(parameter_types: list[MyType], return_type: MyType) -> MyType:
    return MyType(FunctionType(parameter_types, return_type))


class FunctionType(TypeKind):
    def __init__(self, parameter_types: list[MyType], return_type: MyType):
        super().__init__()
        self.parameter_types = parameter_types
        self.return_type = return_type


def struct_type(struct_def):
    return MyType(StructType(struct_def))


class StructType(TypeKind):
    def __init__(self, struct_def):
        self.struct_def = struct_def

    def __repr__(self):
        return f"enum-{self.struct_def.name}"

    def is_reftype(self):
        return True

    def has_field(self, name: str) -> bool:
        return self.struct_def.scope.is_defined(name)

    def get_field(self, name: str) -> MyType:
        field = self.struct_def.scope.lookup(name)
        return field.ty

    def index_of(self, name):
        names = [name for name, _ in self.fields]
        return names.index(name)


def enum_type(enum_def) -> MyType:
    return MyType(EnumType(enum_def))


class EnumType(TypeKind):
    def __init__(self, enum_def):
        self.enum_def = enum_def

    def __repr__(self):
        return f"enum-{self.enum_def.name}"


def array_type(size: int, element_type: MyType) -> MyType:
    return MyType(ArrayType(size, element_type))


class ArrayType(TypeKind):
    def __init__(self, size: int, element_type: MyType):
        self.size = size
        self.element_type = element_type


class ModuleType(TypeKind):
    pass


str_type = base_type("str")
int_type = base_type("int")
float_type = base_type("float")
bool_type = base_type('bool')
void_type = MyType(VoidType())
