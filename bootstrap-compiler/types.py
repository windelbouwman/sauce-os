
class MyType:
    def is_reftype(self):
        return False

    def is_void(self):
        return isinstance(self, VoidType)

    def is_struct(self):
        return isinstance(self, StructType)

    def is_int(self):
        return isinstance(self, BaseType) and self.name == 'int'

    def is_float(self):
        return isinstance(self, BaseType) and self.name == 'float'


class BaseType(MyType):
    def __init__(self, name: str):
        super().__init__()
        self.name = name

    def __repr__(self):
        return f'base-type<{self.name}>'


class TypeExpression(MyType):
    def __init__(self, expr):
        super().__init__()
        self.expr = expr

    def __repr__(self):
        return f'type-expr<{self.expr}>'


class VoidType(MyType):
    def __repr__(self):
        return 'void'


class FunctionType(MyType):
    def __init__(self, parameter_types: list[MyType], return_type: MyType):
        super().__init__()
        self.parameter_types = parameter_types
        self.return_type = return_type


class StructType(MyType):
    def __init__(self, struct_def):
        self.struct_def = struct_def

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


class ArrayType(MyType):
    def __init__(self, size: int, element_type: MyType):
        self.size = size
        self.element_type = element_type


class ModuleType(MyType):
    pass


str_type = BaseType("str")
int_type = BaseType("int")
float_type = BaseType("float")
bool_type = BaseType('bool')
void_type = VoidType()
