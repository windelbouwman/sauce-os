"""
Idea: Use C++ as intermediate code for bootstrapping.

Idea2: Use python code as bootstrapping target?

"""

from . import ast, types


def gencode(module: ast.Module, f=None):
    g = Generator(f)
    g.gen_module(module)


class Generator:
    def __init__(self, f):
        self.level = 0
        self.f = f

    def gen_module(self, module: ast.Module):
        self.print("")
        self.print("// Auto-generated C++ code!")
        self.print("")
        self.print("#include <string>")
        # contents from: runtime/runtime.hpp
        self.print("void std_print(std::string msg);")
        self.print("std::string std_int_to_str(int value);")
        self.print("")
        for definition in module.definitions:
            if isinstance(definition, ast.FunctionDef):
                self.gen_func_def(definition)
            elif isinstance(definition, ast.StructDef):
                self.gen_struct_def(definition)
            else:
                pass

    def gen_func_def(self, func_def: ast.FunctionDef):
        # TODO: return type
        parameters = [
            f'{self.gen_type(p.ty, p.name)}' for p in func_def.parameters]
        self.print(f"void {func_def.name}({', '.join(parameters)}) {{")
        self.gen_block(func_def.statements)
        self.print(f"}}")
        self.print(f"")

    def gen_struct_def(self, struct_def: ast.StructDef):
        self.print(f"struct {struct_def.name} {{")
        self.indent()
        for field in struct_def.fields:
            self.print(f"{self.gen_type(field.ty, field.name)};")
        self.dedent()
        self.print(f"}};")
        self.print(f"")

    def gen_type(self, ty: types.MyType, name: str) -> str:
        if isinstance(ty, types.BaseType):
            ctypes = {
                'str': 'std::string',
                'float': 'double',
            }
            cty = ctypes.get(ty.name, ty.name)
            return f"{cty} {name}"
        elif isinstance(ty, types.ArrayType):
            return f"{self.gen_type(ty.element_type, name)}[{ty.size}]"
        elif isinstance(ty, types.StructType):
            return f"struct {ty.struct_def.name} {name}"
        else:
            return str(ty)

    def gen_block(self, block: list[ast.Statement]):
        self.indent()
        for statement in block:
            self.gen_statement(statement)
        self.dedent()

    def gen_statement(self, statement: ast.Statement):
        kind = statement.kind
        if isinstance(kind, ast.ExpressionStatement):
            self.print(f"{self.gen_expr(kind.value)};")
        elif isinstance(kind, ast.LetStatement):
            # ty = 'int'  # TODO
            dst = self.gen_type(kind.variable.ty, kind.target)
            value = self.gen_expr(kind.value, parens=False)
            self.print(
                f"{dst} = {value};")
        elif isinstance(kind, ast.AssignmentStatement):
            self.print(
                f"{self.gen_expr(kind.target)} = {self.gen_expr(kind.value, parens=False)};")
        elif isinstance(kind, ast.IfStatement):
            self.print(
                f"if ({self.gen_expr(kind.condition, parens=False)}) {{")
            # if statement.true_statement:
            self.gen_block(kind.true_statement)
            if kind.false_statement:
                self.print(f"}} else {{")
                self.gen_block(kind.false_statement)
            self.print(f"}}")
        elif isinstance(kind, ast.WhileStatement):
            self.print(
                f"while ({self.gen_expr(kind.condition, parens=False)}) {{")
            self.gen_block(kind.inner)
            self.print(f"}}")
        elif isinstance(kind, ast.ForStatement):
            # TODO!
            self.print(
                f"for (int {kind.target} = 1;111) {{")
            self.gen_block(kind.inner)
            self.print(f"}}")
        elif isinstance(kind, ast.LoopStatement):
            self.print(f"while (true) {{")
            self.gen_block(kind.inner)
            self.print(f"}}")
        elif isinstance(kind, ast.BreakStatement):
            self.print(f"break;")
        elif isinstance(kind, ast.ContinueStatement):
            self.print(f"continue;")
        elif isinstance(kind, ast.ReturnStatement):
            if kind.value:
                self.print(f"return {self.gen_expr(kind.value)};")
            else:
                self.print(f"return;")
        else:
            self.print(f"{statement}")

    def gen_expr(self, expr: ast.Expression, parens: bool = True):
        kind = expr.kind
        if isinstance(kind, ast.FunctionCall):
            args = ", ".join([self.gen_expr(arg, parens=False)
                             for arg in kind.args])
            return f"{self.gen_expr(kind.target)}({args})"
        elif isinstance(kind, ast.ArrayIndex):
            return f"{self.gen_expr(kind.base)}[{self.gen_expr(kind.index)}]"
        elif isinstance(kind, ast.DotOperator):
            return f"{self.gen_expr(kind.base)}.{kind.field}"
        elif isinstance(kind, ast.Binop):
            ops = {
                'and': '&&', 'or': '||'
            }
            op: str = ops.get(kind.op, kind.op)
            x = f"{self.gen_expr(kind.lhs)} {op} {self.gen_expr(kind.rhs)}"
            return f"({x})" if parens else x
        elif isinstance(kind, ast.TypeCast):
            return f"static_cast<{self.gen_type(kind.ty, '')}> ({self.gen_expr(kind.value)})"
        elif isinstance(kind, ast.NumericConstant):
            return f"{kind.value}"
        elif isinstance(kind, ast.StringConstant):
            return f"{kind.text}"
        elif isinstance(kind, ast.ArrayLiteral):
            values = [self.gen_expr(e) for e in kind.values]
            return f"{{ {', '.join(values)} }}"
        elif isinstance(kind, ast.StructLiteral):
            values = [self.gen_expr(e) for e in kind.values]
            return f"{{ {', '.join(values)} }}"
        elif isinstance(kind, ast.ObjRef):
            if isinstance(kind.obj, ast.Variable):
                return f"{kind.obj.name}"
            elif isinstance(kind.obj, ast.BuiltinFunction):
                return f"{kind.obj.name}"
            elif isinstance(kind.obj, ast.FunctionDef):
                return f"{kind.obj.name}"
            elif isinstance(kind.obj, ast.Parameter):
                return f"{kind.obj.name}"
            else:
                raise NotImplementedError(str(kind.obj))

        elif isinstance(expr, ast.Parameter):
            return f"{expr.name}"
        elif isinstance(expr, ast.FunctionDef):
            return f"{expr.name}"
        elif isinstance(expr, ast.NameRef):
            return f"{expr.name}"
        else:
            return str(expr)

    def indent(self):
        self.level += 1

    def dedent(self):
        self.level -= 1

    def print(self, txt: str):
        if self.f:
            print("    " * self.level + txt, file=self.f)
        else:
            print("    " * self.level + txt)
