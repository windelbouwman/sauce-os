""" Idea: generate C code from bytecode.
"""
from .bc import OpCode, Program, Function, Typ
from . import bc


def gen_c_code(program: Program, f):
    g = CGen(f)
    g.gen_header()
    g.forward_decls(program)

    for func in program.functions:
        g.gen_func(func)


def is_void(ty: Typ) -> bool:
    return isinstance(ty, bc.BaseTyp) and ty.type_id == bc.SimpleTyp.VOID


# Memory implementation:
# Options:
# - pass by value
# - alloc on heap using malloc
method = "malloc"


class CGen:
    def __init__(self, f):
        self._f = f
        self._uniq = 0
        self._type_names = []
        self._indent = 0

    op_map = {
        OpCode.ADD: "+",
        OpCode.SUB: "-",
        OpCode.MUL: "*",
        OpCode.DIV: "/",
        OpCode.AND: "&",
        OpCode.OR: "|",
    }
    unop_map = {
        OpCode.NOT: "!",
    }
    cmp_op = {
        OpCode.GT: ">",
        OpCode.GTE: ">=",
        OpCode.LT: "<",
        OpCode.LTE: "<=",
        OpCode.EQ: "==",
    }

    def gen_header(self):
        # Hmm, bit lame, runtime protos here:
        self.emit("// runtime functions:")
        self.emit("const char* rt_str_concat(const char*, const char*);")
        self.emit("int rt_str_compare(const char *a, const char *b);")
        self.emit("void* rt_malloc(int size);")

        self.emit("void std_print(const char *message);")
        self.emit("void std_exit(int code);")
        self.emit("char *std_read_file(const char *filename);")

        self.emit("int std_str_len(const char *txt);")
        self.emit("char *std_str_slice(const char *txt, int begin, int end);")
        self.emit("char *std_str_get(const char *txt, int pos);")
        self.emit("int std_ord(const char *txt);")
        self.emit("char *std_int_to_str(int x);")
        self.emit("int std_str_to_int(const char *x);")

        self.emit("")

    def get_c_ty(self, ty: Typ, name: str) -> str:
        if isinstance(ty, bc.BaseTyp):
            if ty.type_id == bc.SimpleTyp.INT or ty.type_id == bc.SimpleTyp.BOOL:
                cty = "int"
            elif ty.type_id == bc.SimpleTyp.PTR:
                cty = "void*"
            elif ty.type_id == bc.SimpleTyp.STR:
                cty = "const char*"
            elif ty.type_id == bc.SimpleTyp.FLOAT:
                cty = "double"
            elif ty.type_id == bc.SimpleTyp.VOID:
                cty = "void"
            else:
                raise NotImplementedError(str(ty))
            return f"{cty} {name}" if name else cty
        elif isinstance(ty, bc.StructTyp):
            is_union, sname = self._type_names[ty.index]
            tag = "union" if is_union else "struct"
            cty = f"{tag} {sname}*"
            return f"{cty} {name}" if name else cty
        elif isinstance(ty, bc.FunctionType):
            assert name
            # return_type(*name)(param_types)"
            param_types = [self.get_c_ty(t, "") for t in ty.parameter_types]
            params = ",".join(param_types)
            ret_ty = self.get_c_ty(ty.return_type, "")
            return f"{ret_ty}(*{name})({params})"
        else:
            raise NotImplementedError(str(ty))

    def forward_decls(self, prog: Program):
        self.emit("// forward type declarations:")
        for name, is_union, fields in prog.types:
            tag = "union" if is_union else "struct"
            self.emit(f"{tag} {name};")
            self._type_names.append((is_union, name))
        self.emit("")

        for name, is_union, fields in prog.types:
            tag = "union" if is_union else "struct"
            self.emit(f"{tag} {name} {{")
            self.indent()
            for idx, field_type in enumerate(fields):
                field_name = f"f_{idx}"
                self.emit(f"{self.get_c_ty(field_type, field_name)};")
            self.dedent()
            self.emit(f"}};")
        self.emit("")

        self.emit("// forward declarations:")
        for func in prog.functions:
            self.gen_func_decl(func)
        self.emit("")

    def gen_func_decl(self, func: Function):
        # forward declaration
        _, signature = self.func_signature(func)
        self.emit(f"{signature};")

    def func_signature(self, func: Function):
        """Create function C signature."""
        ret_ty = self.get_c_ty(func.return_ty, "")
        params = [
            (self.get_c_ty(ty, f"param_{i}"), f"param_{i}")
            for i, ty in enumerate(func.params)
        ]
        param_txt = ", ".join(p_ty for p_ty, _ in params)
        return params, f"{ret_ty} {func.name}({param_txt})"

    def gen_func(self, func: Function):
        params, signature = self.func_signature(func)
        self.emit(f"{signature} {{")
        self.indent()
        self.indent()
        stack = []
        local_vars = [
            (self.get_c_ty(ty, f"local_{i}"), f"local_{i}")
            for i, ty in enumerate(func.local_vars)
        ]

        for v_ty, v in local_vars:
            self.emit(f"{v_ty};")
        local_vars = params + local_vars

        self._jump_targets = {}
        for tgt in get_jump_targets(func.code):
            if tgt not in self._jump_targets:
                self._jump_targets[tgt] = f"lab_{self.new_id()}"

        for idx, inst in enumerate(func.code):
            opcode, operands = inst

            if idx in self._jump_targets:
                self.dedent()
                self.emit(self._jump_targets[idx] + ":")
                self.indent()

            # For debugging:
            # print(opcode, operands, stack)
            if opcode == OpCode.CONST:
                (val,) = operands
                if isinstance(val, str):
                    var = self.new_var()
                    self.emit(f'const char* {var} = "{val}";')
                    stack.append(var)
                elif isinstance(val, bool):
                    stack.append("1" if val else "0")
                elif isinstance(val, int):
                    stack.append(str(val))
                elif isinstance(val, float):
                    stack.append(str(val))
                else:
                    raise NotImplementedError(f"{opcode} {val}")
            elif opcode == OpCode.BUILTIN:
                stack.append(operands[0])
            elif opcode == OpCode.LOADFUNC:
                stack.append(operands[0])
            elif opcode == OpCode.CALL:
                callee = stack.pop()
                args = pop_n(stack, operands[0])
                args = ", ".join(str(a) for a in args)
                ret_ty: Typ = operands[1]
                if is_void(ret_ty):
                    self.emit(f"{callee}({args});")
                else:
                    var = self.new_var()
                    dst = self.get_c_ty(ret_ty, var)
                    self.emit(f"{dst} = {callee}({args});")
                    stack.append(var)
            elif opcode == OpCode.LOCAL_SET:
                val = stack.pop()
                var = local_vars[operands[0]][1]
                self.emit(f"{var} = {val};")
            elif opcode == OpCode.LOCAL_GET:
                var = local_vars[operands[0]][1]
                stack.append(var)
            elif opcode == OpCode.SET_ATTR:
                value = stack.pop()
                base = stack.pop()
                index = operands[0]
                self.emit(f"{base}->f_{index} = {value};")
            elif opcode == OpCode.GET_ATTR:
                base = stack.pop()
                index = operands[0]
                var = self.new_var()
                dst = self.get_c_ty(operands[1], var)
                self.emit(f"{dst} = {base}->f_{index};")
                stack.append(var)
            elif opcode == OpCode.JUMP:
                self.emit(f"goto {self.get_label(operands[0])};")
            elif opcode == OpCode.JUMP_IF:
                cond = stack.pop()
                self.emit(f"if ({cond})")
                self.indent()
                self.emit(f"goto {self.get_label(operands[0])};")
                self.dedent()
                self.emit("else")
                self.indent()
                self.emit(f"goto {self.get_label(operands[1])};")
                self.dedent()
            elif opcode in self.op_map:
                op = self.op_map[opcode]
                ty: Typ = operands[0]
                var = self.new_var()
                rhs = stack.pop()
                lhs = stack.pop()
                dst = self.get_c_ty(ty, var)
                if isinstance(ty, bc.BaseTyp):
                    if ty.type_id == bc.SimpleTyp.STR:
                        assert opcode == OpCode.ADD
                        self.emit(f"const {dst} = rt_str_concat({lhs}, {rhs});")
                    elif (
                        (ty.type_id == bc.SimpleTyp.INT)
                        or (ty.type_id == bc.SimpleTyp.FLOAT)
                        or (ty.type_id == bc.SimpleTyp.BOOL)
                    ):
                        self.emit(f"const {dst} = {lhs} {op} {rhs};")
                    else:
                        raise ValueError(f"Cannot {op} {ty}")
                else:
                    raise ValueError(f"Cannot {op} {ty}")
                stack.append(var)
            elif opcode in self.cmp_op:
                op = self.cmp_op[opcode]
                ty: Typ = operands[0]
                var = self.new_var()
                rhs = stack.pop()
                lhs = stack.pop()
                if isinstance(ty, bc.BaseTyp):
                    if ty.type_id == bc.SimpleTyp.STR:
                        assert opcode == OpCode.EQ
                        self.emit(f"const int {var} = rt_str_compare({lhs}, {rhs});")
                    else:
                        self.emit(f"const int {var} = {lhs} {op} {rhs} ? 1 : 0;")
                else:
                    raise ValueError(f"Cannot '{op}' {ty}")
                stack.append(var)
            elif opcode == OpCode.CAST:
                val = stack.pop()
                to_ty: Typ = operands[0]
                var = self.new_var()
                dst = self.get_c_ty(to_ty, var)
                cty = self.get_c_ty(to_ty, "")
                if isinstance(to_ty, bc.BaseTyp):
                    if to_ty.type_id == bc.SimpleTyp.FLOAT:
                        self.emit(f"const {dst} = ({cty}){val};")
                    else:
                        raise NotImplementedError(str(to_ty.type_id))
                else:
                    raise NotImplementedError(str(to_ty))
                stack.append(var)
            elif opcode in self.unop_map:
                value = stack.pop()
                op = self.unop_map[opcode]
                var = self.new_var()
                self.emit(f"const int {var} = {op} {value};")
                stack.append(var)
            elif opcode == OpCode.UNION_LITERAL:
                value = stack.pop()
                var = self.new_var()
                f_index = operands[0]
                u_name = self._type_names[operands[1].index][1]
                field = f"f_{f_index}"
                if method == "by_val":
                    self.emit(f"union {u_name} {var} = {{ .{field} = {value} }};")
                elif method == "malloc":
                    self.emit(
                        f"union {u_name} *{var} = rt_malloc(sizeof(union {u_name}));"
                    )
                    self.emit(f"{var}->{field} = {value};")
                else:
                    raise NotImplementedError(method)
                stack.append(var)
            elif opcode == OpCode.STRUCT_LITERAL:
                var = self.new_var()
                # We have many options here!
                # We can store on stack, malloc, ref-count?
                values = pop_n(stack, operands[0])

                s_name = self._type_names[operands[1].index][1]
                if method == "by_val":
                    values = ", ".join(str(a) for a in values)
                    self.emit(f"struct {s_name} {var} = {{ {values} }};")
                elif method == "malloc":
                    self.emit(
                        f"struct {s_name} *{var} = rt_malloc(sizeof(struct {s_name}));"
                    )
                    for idx, value in enumerate(values):
                        self.emit(f"{var}->f_{idx} = {value};")
                else:
                    raise NotImplementedError(method)
                stack.append(var)
            elif opcode == OpCode.DUP:
                value = stack.pop()
                stack.append(value)
                stack.append(value)
            elif opcode == OpCode.RETURN:
                if operands[0] == 1:
                    val = stack.pop()
                    self.emit(f"return {val};")
                else:
                    self.emit(f"return;")
            else:
                raise NotImplementedError(str(opcode))
        self.dedent()
        self.dedent()
        self.emit("}")
        self.emit("")

    def get_label(self, target: int) -> str:
        assert isinstance(target, int)
        return self._jump_targets[target]

    def indent(self):
        self._indent += 4

    def dedent(self):
        self._indent -= 4

    def emit(self, txt: str):
        print((" " * self._indent) + txt, file=self._f)

    def new_var(self):
        return f"val_{self.new_id()}"

    def new_id(self):
        self._uniq += 1
        return self._uniq


def pop_n(stack, n: int):
    args = [stack.pop() for _ in range(n)]
    args.reverse()
    return args


def get_jump_targets(instructions):
    for opcode, operands in instructions:
        if opcode == OpCode.JUMP:
            yield operands[0]
        elif opcode == OpCode.JUMP_IF:
            yield operands[0]
            yield operands[1]
