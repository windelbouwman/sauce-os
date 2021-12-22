
class MyType:
    def is_reftype(self):
        return False

    def is_void(self):
        return isinstance(self, VoidType)

    def is_struct(self):
        return isinstance(self, StructType)


class BaseType(MyType):
    def __init__(self, name):
        super().__init__()
        self.name = name

    def __repr__(self):
        return f'base-type<{self.name}>'


class VoidType(MyType):
    def __repr__(self):
        return 'void'


class FunctionType(MyType):
    def __init__(self, parameter_types, return_type):
        super().__init__()
        self.parameter_types = parameter_types
        self.return_type = return_type


class StructType(MyType):
    def __init__(self, fields):
        self.fields = fields

    def is_reftype(self):
        return True

    def has_field(self, name):
        # print(self.fields)
        for n, t in self.fields:
            if n == name:
                return True
        return False

    def get_field(self, name):
        for n, t in self.fields:
            if n == name:
                return n, t

    def index_of(self, name):
        names = [name for name, _ in self.fields]
        return names.index(name)


class ModuleType(MyType):
    pass


str_type = BaseType("str")
int_type = BaseType("int")
bool_type = BaseType('bool')
void_type = VoidType()
