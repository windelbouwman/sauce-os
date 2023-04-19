# Idea: generate C code from bytecode.

from .vm import Program, Function


def gen_c_code(prog: Program):
    g = CGen()
    for func in prog.functions:
        g.gen_func(func)


class CGen:
    def __init__(self):
        self._uniq = 0
        self._indent = 0

    op_map = {"ADD": "+", "SUB": "-", "MUL": "*", "DIV": "/"}
    cmp_op = {"GT": ">", "LT": "<"}

    def gen_func(self, func: Function):
        self.emit(f"void {func.name}() {{")
        self.indent()
        stack = []
        local_vars = [f"local_{i}" for i in range(func.n_locals)]

        for opcode, operands in func.code:
            # For debugging:
            # print(opcode, operands, stack)
            if opcode == "CONST":
                (val,) = operands
                if isinstance(val, str):
                    var = self.new_var()
                    self.emit(f'const char* {var} = "{val}";')
                    stack.append(var)
                elif isinstance(val, int):
                    stack.append(str(int(val)))
                else:
                    raise NotImplementedError(opcode)
            elif opcode == "BUILTIN":
                stack.append(operands[0])
            elif opcode == "LOADFUNC":
                stack.append(operands[0])
            elif opcode == "CALL":
                callee = stack.pop()
                args = [stack.pop() for _ in range(operands[0])]
                args.reverse()
                args = ", ".join(str(a) for a in args)
                if operands[0] == 1:
                    var = self.new_var()
                    self.emit(f"{var} = {callee}({args});")
                    stack.append(var)
                else:
                    self.emit(f"{callee}({args});")
            elif opcode == "LOCAL_SET":
                val = stack.pop()
                var = local_vars[operands[0]]
                self.emit(f"{var} = {val};")
            elif opcode == "LOCAL_GET":
                var = local_vars[operands[0]]
                stack.append(var)
            elif opcode == "JUMP":
                self.emit(f"goto {operands};")
            elif opcode == "JUMP-IF":
                cond = stack.pop()
                self.emit(f"if ({cond})")
                self.indent()
                self.emit(f"goto {operands[0]};")
                self.dedent()
                self.emit("else")
                self.indent()
                self.emit(f"goto {operands[1]};")
                self.dedent()
            elif opcode in self.op_map:
                op = self.op_map[opcode]
                var = self.new_var()
                rhs = stack.pop()
                lhs = stack.pop()
                self.emit(f"{var} = {lhs} {op} {rhs};")
                stack.append(var)
            elif opcode in self.cmp_op:
                op = self.cmp_op[opcode]
                var = self.new_var()
                rhs = stack.pop()
                lhs = stack.pop()
                self.emit(f"int {var} = {lhs} {op} {rhs} ? 1 : 0;")
                stack.append(var)
            elif opcode == "RETURN":
                if operands[0] == 1:
                    val = stack.pop()
                    self.emit(f"return {val};")
                else:
                    self.emit(f"return;")
            else:
                raise NotImplementedError(opcode)
        self.dedent()
        self.emit("}")
        self.emit("")

    def indent(self):
        self._indent += 4

    def dedent(self):
        self._indent -= 4

    def emit(self, txt):
        print((" " * self._indent) + txt)

    def new_var(self):
        self._uniq += 1
        return f"val_{self._uniq}"
