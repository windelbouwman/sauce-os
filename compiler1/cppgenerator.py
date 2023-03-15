"""
Idea: Use C++ as intermediate code for bootstrapping.

Idea2: Use python code as bootstrapping target?

"""

from . import ast, types


def gencode(modules: list[ast.Module], f=None):
    g = Generator(f)
    g.gen_prelude()
    g.gen_type_decls(modules)
    g.gen_func_decls(modules)

    for module in modules:
        g.gen_module(module)


class Generator:
    def __init__(self, f):
        self.level = 0
        self.f = f

    def gen_module(self, module: ast.Module):
        for definition in module.definitions:
            if isinstance(definition, ast.FunctionDef):
                self.gen_func_def(definition)

    def gen_prelude(self):
        self.print("")
        self.print("// Auto-generated C++ code!")
        self.print("")
        self.print("#include <string>")
        # contents from: runtime/runtime.hpp
        self.print("void std_print(std::string msg);")
        self.print("std::string std_int_to_str(int value);")
        self.print("std::string std_float_to_str(double value);")
        self.print("")

    def gen_type_decls(self, modules: list[ast.Module]):
        for module in modules:
            for definition in module.definitions:
                if isinstance(definition, ast.StructDef):
                    self.gen_struct_def(definition)
        self.print("")

    def gen_func_decls(self, modules: list[ast.Module]):
        """ Do some forward declarations """
        for module in modules:
            for definition in module.definitions:
                if isinstance(definition, ast.FunctionDef):
                    self.gen_func_decl(definition)
        self.print("")

    def gen_func_decl(self, func_def: ast.FunctionDef):
        decl = self.func_proto(func_def)
        self.print(f"{decl};")

    def gen_func_def(self, func_def: ast.FunctionDef):
        decl = self.func_proto(func_def)
        self.print(f"{decl} {{")
        self.gen_block(func_def.statements)
        self.print(f"}}")
        self.print(f"")

    def func_proto(self, func_def: ast.FunctionDef):
        parameters = ', '.join(
            f'{self.gen_type(p.ty, p.name)}' for p in func_def.parameters)
        return f"{self.gen_type(func_def.return_ty, func_def.name)}({parameters})"

    def gen_struct_def(self, struct_def: ast.StructDef):
        t = 'union' if struct_def.is_union else 'struct'
        self.print(f"{t} {struct_def.name} {{")
        self.indent()
        for field in struct_def.fields:
            self.print(f"{self.gen_type(field.ty, field.name)};")
        self.dedent()
        self.print(f"}};")
        self.print(f"")

    def gen_type(self, ty: types.MyType, name: str) -> str:
        kind = ty.kind
        if isinstance(kind, types.BaseType):
            ctypes = {
                'str': 'std::string',
                'float': 'double',
            }
            cty = ctypes.get(kind.name, kind.name)
            return f"{cty} {name}" if name else cty
        elif isinstance(kind, types.ArrayType):
            assert name
            return f"{self.gen_type(kind.element_type, name)}[{kind.size}]"
        elif isinstance(kind, types.StructType):
            assert name
            t = 'union' if kind.struct_def.is_union else 'struct'
            return f"{t} {kind.struct_def.name} {name}"
        elif isinstance(kind, types.EnumType):
            raise ValueError("C++ backend does not support enum types.")
        else:
            return f"{ty} {name}" if name else str(ty)

    def gen_block(self, block: ast.Statement):
        self.indent()
        self.gen_statement(block)
        self.dedent()

    def gen_statement(self, statement: ast.Statement):
        kind = statement.kind
        if isinstance(kind, ast.ExpressionStatement):
            self.print(f"{self.gen_expr(kind.value)};")
        elif isinstance(kind, ast.LetStatement):
            # ty = 'int'  # TODO
            dst = self.gen_type(kind.variable.ty, kind.variable.name)
            value = self.gen_expr(kind.value, parens=False)
            self.print(
                f"{dst} = {value};")
        elif isinstance(kind, ast.AssignmentStatement):
            self.print(
                f"{self.gen_expr(kind.target)} = {self.gen_expr(kind.value, parens=False)};")
        elif isinstance(kind, ast.IfStatement):
            self.print(
                f"if ({self.gen_expr(kind.condition, parens=False)}) {{")
            self.gen_block(kind.true_statement)
            if kind.false_statement:
                self.print(f"}} else {{")
                self.gen_block(kind.false_statement)
            self.print(f"}}")
        elif isinstance(kind, ast.CaseStatement):
            raise ValueError("C++ backend does not support case statements.")
        elif isinstance(kind, ast.SwitchStatement):
            self.print(
                f"switch ({self.gen_expr(kind.value, parens=False)}) {{")
            self.indent()
            for arm in kind.arms:
                self.print(f"case {self.gen_expr(arm.value)}: {{")
                self.indent()
                self.gen_statement(arm.body)
                self.print(f"break;")
                self.dedent()
                self.print(f"}}")

            self.print(f"default:")
            self.indent()
            self.gen_statement(kind.default_body)
            self.print(f"break;")
            self.dedent()

            self.dedent()
            self.print(f"}}")
        elif isinstance(kind, ast.WhileStatement):
            self.print(
                f"while ({self.gen_expr(kind.condition, parens=False)}) {{")
            self.gen_block(kind.inner)
            self.print(f"}}")
        elif isinstance(kind, ast.ForStatement):
            raise ValueError("Rewrite for-loops into while")
        elif isinstance(kind, ast.LoopStatement):
            raise ValueError("Rewrite loops into while")
        elif isinstance(kind, ast.BreakStatement):
            self.print(f"break;")
        elif isinstance(kind, ast.ContinueStatement):
            self.print(f"continue;")
        elif isinstance(kind, ast.PassStatement):
            pass
        elif isinstance(kind, ast.ReturnStatement):
            if kind.value:
                self.print(f"return {self.gen_expr(kind.value)};")
            else:
                self.print(f"return;")
        elif isinstance(kind, ast.CompoundStatement):
            for statement2 in kind.statements:
                self.gen_statement(statement2)
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
            ops = {'and': '&&', 'or': '||'}
            op: str = ops.get(kind.op, kind.op)
            x = f"{self.gen_expr(kind.lhs)} {op} {self.gen_expr(kind.rhs)}"
            return f"({x})" if parens else x
        elif isinstance(kind, ast.TypeCast):
            return f"static_cast<{self.gen_type(kind.ty, '')}>({self.gen_expr(kind.value)})"
        elif isinstance(kind, ast.NumericConstant):
            return f"{kind.value}"
        elif isinstance(kind, ast.StringConstant):
            return f"{kind.text}"
        elif isinstance(kind, ast.BoolLiteral):
            txt = {True: 'true', False: 'false'}
            return txt[kind.value]
        elif isinstance(kind, ast.ArrayLiteral):
            values = [self.gen_expr(e) for e in kind.values]
            return f"{{ {', '.join(values)} }}"
        elif isinstance(kind, ast.StructLiteral):
            values = [self.gen_expr(e) for e in kind.values]
            return f"{{ {', '.join(values)} }}"
        elif isinstance(kind, ast.UnionLiteral):
            # TODO: select field?
            field = kind.field
            value = self.gen_expr(kind.value)
            return f"{{ .{field}={value} }}"
        elif isinstance(kind, ast.EnumLiteral):
            raise ValueError("C++ backend does not handle enum literals")
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
        elif isinstance(kind, ast.NameRef):
            raise ValueError("Names must be resolved")
        else:
            raise NotImplementedError(str(expr))

    def indent(self):
        self.level += 1

    def dedent(self):
        self.level -= 1

    def print(self, txt: str):
        if self.f:
            print("    " * self.level + txt, file=self.f)
        else:
            print("    " * self.level + txt)
