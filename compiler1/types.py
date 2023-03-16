
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
        return isinstance(self.kind, StructType) and self.kind.is_struct()

    def is_union(self):
        return isinstance(self.kind, StructType) and self.kind.is_union()

    def is_enum(self):
        return isinstance(self.kind, EnumType)

    def is_int(self) -> bool:
        return isinstance(self.kind, BaseType) and self.kind.name == 'int'

    def is_float(self) -> bool:
        return isinstance(self.kind, BaseType) and self.kind.name == 'float'

    def has_field(self, name: str) -> bool:
        if isinstance(self.kind, (StructType, ClassType)):
            return self.kind.has_field(name)
        else:
            return False

    def get_field_name(self, i: int | str) -> str:
        """ Retrieve name of field. i can be index or name """
        if isinstance(self.kind, StructType):
            return self.kind.get_field_name(i)
        else:
            raise ValueError("Can only get field from struct/union")

    def get_field_type(self, i: int | str) -> 'MyType':
        """ Retrieve type of field. i can be index or name """
        if isinstance(self.kind, (StructType, ClassType)):
            return self.kind.get_field_type(i)
        else:
            raise ValueError("Can only get field from struct/union/class")

    def equals(self, other: 'MyType'):
        assert isinstance(other, MyType)
        if self is other:
            return True
        elif isinstance(self.kind, BaseType) and isinstance(other.kind, BaseType):
            return self.kind.name == other.kind.name
        elif isinstance(self.kind, StructType) and isinstance(other.kind, StructType):
            # TODO: check for equal type_arguments
            return (self.kind.struct_def is other.kind.struct_def)
        elif isinstance(self.kind, EnumType) and isinstance(other.kind, EnumType):
            return self.kind.enum_def is other.kind.enum_def
        elif isinstance(self.kind, FunctionType) and isinstance(other.kind, FunctionType):
            return self.kind.equals(other.kind)
        elif isinstance(self.kind, ClassType) and isinstance(other.kind, ClassType):
            return self.kind.class_def is other.kind.class_def
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

    def equals(self, other: 'FunctionType') -> bool:
        if not self.return_type.equals(other.return_type):
            return False
        if len(self.parameter_types) != len(other.parameter_types):
            return False
        return all(a.equals(b) for a, b in zip(self.parameter_types, other.parameter_types))


def struct_type(struct_def, type_arguments: list[MyType]):
    return MyType(StructType(struct_def, type_arguments))


class StructType(TypeKind):
    def __init__(self, struct_def, type_arguments: list[MyType]):
        self.struct_def = struct_def
        self.type_arguments = type_arguments

    def __repr__(self):
        t = 'union' if self.struct_def.is_union else 'struct'
        return f"{t}-{self.struct_def.name}"

    def is_struct(self) -> bool:
        return not self.is_union()

    def is_union(self) -> bool:
        return self.struct_def.is_union

    def is_reftype(self):
        return True

    def has_field(self, name: str) -> bool:
        return self.struct_def.has_field(name)

    def get_field_type(self, i: int | str) -> MyType:
        field = self.struct_def.get_field(i)
        # TODO: use type_arguments
        return field.ty

    def get_field_name(self, i: int | str) -> str:
        field = self.struct_def.get_field(i)
        return field.name

    def index_of(self, name):
        names = [name for name, _ in self.fields]
        return names.index(name)


def enum_type(enum_def, type_arguments: list[MyType]) -> MyType:
    return MyType(EnumType(enum_def, type_arguments))


class EnumType(TypeKind):
    def __init__(self, enum_def, type_arguments: list[MyType]):
        self.enum_def = enum_def
        self.type_arguments = type_arguments

    def __repr__(self):
        return f"enum-{self.enum_def.name}"


def class_type(class_def, type_arguments: list[MyType]) -> MyType:
    return MyType(ClassType(class_def, type_arguments))


class ClassType(TypeKind):
    def __init__(self, class_def, type_arguments: list[MyType]):
        self.class_def = class_def
        self.type_arguments = type_arguments

    def __repr__(self):
        return f"class-{self.class_def.name}"

    def has_field(self, name: str) -> bool:
        return self.class_def.has_field(name)

    def get_field_type(self, i: int | str) -> MyType:
        return self.class_def.get_field_type(i)


def array_type(size: int, element_type: MyType) -> MyType:
    return MyType(ArrayType(size, element_type))


class ArrayType(TypeKind):
    def __init__(self, size: int, element_type: MyType):
        super().__init__()
        self.size = size
        self.element_type = element_type


class ModuleType(TypeKind):
    pass


def type_var_ref(type_variable) -> MyType:
    return MyType(TypeVarKind(type_variable))


class TypeVarKind(TypeKind):
    def __init__(self, type_variable):
        super().__init__()
        self.type_variable = type_variable


str_type = base_type("str")
int_type = base_type("int")
float_type = base_type("float")
bool_type = base_type('bool')
void_type = MyType(VoidType())
