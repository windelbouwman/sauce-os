
class Node:
    def __init__(self, location):
        self.location = location
        assert hasattr(location, 'row')


class Module(Node):
    def __init__(self):
        self.imports = []
        self.functions = []
        self.types = []


class Import(Node):
    def __init__(self, name, location):
        super().__init__(location)
        self.name = name


class FunctionDef(Node):
    def __init__(self, name, parameters, return_ty, statements, location):
        super().__init__(location)
        self.name = name
        self.parameters = parameters
        self.return_ty = return_ty
        self.statements = statements


class Parameter(Node):
    def __init__(self, name, ty, location):
        super().__init__(location)
        self.name = name
        self.ty = ty


class StructDef(Node):
    def __init__(self, name, fields, location):
        super().__init__(location)
        self.name = name
        self.fields = fields


class StructFieldDef(Node):
    def __init__(self, name, ty, location):
        super().__init__(location)
        self.name = name
        self.ty = ty


class Statement(Node):
    def __init__(self, location):
        super().__init__(location)


class Let(Statement):
    def __init__(self, target, value, location):
        super().__init__(location)
        self.target = target
        self.value = value

    def __repr__(self):
        return f"Let({self.target})"


class Loop(Statement):
    def __init__(self, inner, location):
        super().__init__(location)
        self.inner = inner


class While(Statement):
    def __init__(self, condition, inner, location):
        super().__init__(location)
        self.condition = condition
        self.inner = inner

    def __repr__(self):
        return "While"


class IfStatement(Statement):
    def __init__(self, condition, true_statement, false_statement, location):
        super().__init__(location)
        self.condition = condition
        self.true_statement = true_statement
        self.false_statement = false_statement

    def __repr__(self):
        return "IfStatement"


class Break(Statement):
    def __init__(self, location):
        super().__init__(location)

    def __repr__(self):
        return "Break"


class Continue(Statement):
    def __init__(self, location):
        super().__init__(location)

    def __repr__(self):
        return "Continue"


class Return(Statement):
    def __init__(self, value, location):
        super().__init__(location)
        self.value = value


class Expression(Node):
    def __init__(self, location):
        super().__init__(location)
        self.ty = None


class NewOp(Expression):
    def __init__(self, ty, fields, location):
        super().__init__(location)
        self.new_ty = ty
        self.fields = fields


class NewOpField(Node):
    def __init__(self, name, value, location):
        super().__init__(location)
        self.name = name
        self.value = value


class FunctionCall(Expression):
    def __init__(self, target, args, location):
        super().__init__(location)
        self.target = target
        self.args = args

    def __repr__(self):
        return f'FunctionCall({self.target})'


class Binop(Expression):
    def __init__(self, lhs, op, rhs, location):
        super().__init__(location)
        self.lhs = lhs
        self.op = op
        self.rhs = rhs

    def __repr__(self):
        return f'Binop({self.op})'


class StringConstant(Expression):
    def __init__(self, text, location):
        super().__init__(location)
        self.text = text

    def __repr__(self):
        return f'StringConstant("{self.text}")'


class NumericConstant(Expression):
    def __init__(self, value, location):
        super().__init__(location)
        self.value = value

    def __repr__(self):
        return f'NumericConstant({self.value})'


class NameRef(Node):
    def __init__(self, name, location):
        super().__init__(location)
        self.name = name

    def __repr__(self):
        return f'name-ref({self.name})'


class DotOperator(Expression):
    """ variable.field operation.
    """

    def __init__(self, base, field, location):
        super().__init__(location)
        self.base = base
        self.field = field


def print_ast(mod):
    AstPrinter().print_module(mod)


class AstPrinter:
    def __init__(self):
        self._indent = 0

    def indent(self):
        self._indent += 2

    def dedent(self):
        self._indent -= 2

    def emit(self, txt):
        indent = ' ' * self._indent
        print(indent + txt)

    def print_module(self, mod):
        self.emit('Imports:')
        for imp in mod.imports:
            self.emit(f'- {imp.name}')

        self.emit('Functions:')
        for func in mod.functions:
            self.emit(f'- {func.name}')
            self.indent()
            self.print_block(func.statements)
            self.dedent()

    def print_block(self, block):
        if isinstance(block, list):
            for statement in block:
                self.print_statement(statement)
        else:
            self.print_statement(block)

    def print_statement(self, statement):
        self.emit(f'{statement}')
        self.indent()
        if isinstance(statement, IfStatement):
            self.print_expression(statement.condition)
            self.print_block(statement.true_statement)
            self.print_block(statement.false_statement)
        elif isinstance(statement, Let):
            self.print_expression(statement.value)
        elif isinstance(statement, Return):
            self.print_expression(statement.value)
        elif isinstance(statement, FunctionCall):
            self.print_function_call(statement)
        elif isinstance(statement, While):
            self.print_expression(statement.condition)
        self.dedent()

    def print_expression(self, expression):
        self.emit(f'{expression}')
        self.indent()
        if isinstance(expression, Binop):
            self.print_expression(expression.lhs)
            self.print_expression(expression.rhs)
        elif isinstance(expression, FunctionCall):
            self.print_function_call(expression)
        self.dedent()

    def print_function_call(self, call):
        for arg in call.args:
            self.print_expression(arg)
