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
        self.emit("#include <string.h>")

        self.emit("// runtime functions:")
        self.emit("char* rt_str_concat(char*, char*);")
        self.emit("int rt_str_compare(char *a, char *b);")
        self.emit("void* rt_malloc(int size);")
        self.emit("void rt_incref(void *ptr);")
        self.emit("void rt_decref(void *ptr);")

        self.emit("void std_print(char *message);")
        self.emit("void std_exit(int code);")
        self.emit("char* std_read_file(char *filename);")

        self.emit("int std_str_len(char* txt);")
        self.emit("char* std_str_slice(char* txt, int begin, int end);")
        self.emit("char* std_str_get(char* txt, int pos);")
        self.emit("int std_ord(char *txt);")
        self.emit("char *std_int_to_str(int x);")
        self.emit("int std_str_to_int(char *x);")

        self.emit("")

    def get_c_ty(self, ty: Typ, name: str) -> str:
        if isinstance(ty, bc.BaseTyp):
            if ty.type_id == bc.SimpleTyp.INT or ty.type_id == bc.SimpleTyp.BOOL:
                cty = "int"
            elif ty.type_id == bc.SimpleTyp.PTR:
                cty = "void*"
            elif ty.type_id == bc.SimpleTyp.STR:
                cty = "char*"
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
            (self.get_c_ty(ty, f"param_{i}"), f"param_{i}", is_ptr(ty))
            for i, ty in enumerate(func.params)
        ]
        param_txt = ", ".join(p[0] for p in params)
        return params, f"{ret_ty} {func.name}({param_txt})"

    def gen_func(self, func: Function):
        params, signature = self.func_signature(func)
        self.emit(f"{signature} {{")
        self.indent()
        self.indent()
        stack = []
        local_vars = [
            (self.get_c_ty(ty, f"local_{i}"), f"local_{i}", is_ptr(ty))
            for i, ty in enumerate(func.local_vars)
        ]

        for v_ty, v, _ in local_vars:
            self.emit(f"{v_ty} = 0;")
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
                val = operands[0]
                if isinstance(val, str):
                    var = self.new_var()
                    self.emit(f"char* {var} = rt_malloc({len(val) + 1});")
                    self.emit(f'memcpy({var}, "{val}", {len(val)+1});')
                    stack.append((var, True))
                elif isinstance(val, bool):
                    val = "1" if val else "0"
                    stack.append((val, False))
                elif isinstance(val, int):
                    stack.append((str(val), False))
                elif isinstance(val, float):
                    stack.append((str(val), False))
                else:
                    raise NotImplementedError(f"{opcode} {val}")
            elif opcode == OpCode.BUILTIN:
                stack.append((operands[0], False))
            elif opcode == OpCode.LOADFUNC:
                stack.append((operands[0], False))
            elif opcode == OpCode.CALL:
                callee, _ = stack.pop()
                args = pop_n(stack, operands[0])
                args = ", ".join(str(a) for a in args)
                ret_ty: Typ = operands[1]
                if is_void(ret_ty):
                    self.emit(f"{callee}({args});")
                else:
                    var = self.new_var()
                    dst = self.get_c_ty(ret_ty, var)
                    self.emit(f"{dst} = {callee}({args});")
                    stack.append((var, is_ptr(ret_ty)))
            elif opcode == OpCode.LOCAL_SET:
                val, _ = stack.pop()
                var = local_vars[operands[0]][1]
                # TODO: dec-ref old value?
                self.emit(f"{var} = {val};")
            elif opcode == OpCode.LOCAL_GET:
                var = local_vars[operands[0]][1]
                is_ptr2 = local_vars[operands[0]][2]
                self.inc_ref(var, is_ptr2)
                stack.append((var, is_ptr2))
            elif opcode == OpCode.SET_ATTR:
                value, _ = stack.pop()
                base, base_ptr = stack.pop()
                index = operands[0]
                # TODO: dec-ref old field value?
                self.emit(f"{base}->f_{index} = {value};")
                assert base_ptr
                self.emit(f"rt_decref({base});")
            elif opcode == OpCode.GET_ATTR:
                base, base_ptr = stack.pop()
                assert base_ptr
                index = operands[0]
                var = self.new_var()
                ty: Typ = operands[1]
                dst = self.get_c_ty(ty, var)
                self.emit(f"{dst} = {base}->f_{index};")
                self.inc_ref(var, is_ptr(ty))
                self.dec_ref(base, base_ptr)
                stack.append((var, is_ptr(ty)))
            elif opcode == OpCode.JUMP:
                self.emit(f"goto {self.get_label(operands[0])};")
            elif opcode == OpCode.JUMP_IF:
                cond, _ = stack.pop()
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
                rhs, _ = stack.pop()
                lhs, _ = stack.pop()
                dst = self.get_c_ty(ty, var)
                if isinstance(ty, bc.BaseTyp):
                    if ty.type_id == bc.SimpleTyp.STR:
                        assert opcode == OpCode.ADD
                        self.emit(f"{dst} = rt_str_concat({lhs}, {rhs});")
                    elif (
                        (ty.type_id == bc.SimpleTyp.INT)
                        or (ty.type_id == bc.SimpleTyp.FLOAT)
                        or (ty.type_id == bc.SimpleTyp.BOOL)
                    ):
                        self.emit(f"const {dst} = {lhs} {op} {rhs};")
                    else:
                        raise ValueError(f"Cannot '{op}' {ty}")
                else:
                    raise ValueError(f"Cannot '{op}' {ty}")
                stack.append((var, is_ptr(ty)))
            elif opcode in self.cmp_op:
                op = self.cmp_op[opcode]
                ty: Typ = operands[0]
                var = self.new_var()
                rhs, _ = stack.pop()
                lhs, _ = stack.pop()
                if isinstance(ty, bc.BaseTyp):
                    if ty.type_id == bc.SimpleTyp.STR:
                        assert opcode == OpCode.EQ
                        self.emit(f"const int {var} = rt_str_compare({lhs}, {rhs});")
                    else:
                        self.emit(f"const int {var} = {lhs} {op} {rhs} ? 1 : 0;")
                else:
                    raise ValueError(f"Cannot '{op}' {ty}")
                stack.append((var, False))
            elif opcode == OpCode.CAST:
                val, p = stack.pop()
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
                stack.append((var, is_ptr(to_ty)))
            elif opcode in self.unop_map:
                value, _ = stack.pop()
                op = self.unop_map[opcode]
                var = self.new_var()
                self.emit(f"const int {var} = {op} {value};")
                stack.append((var, False))
            elif opcode == OpCode.UNION_LITERAL:
                value, _ = stack.pop()
                var = self.new_var()
                f_index = operands[0]
                u_name = self._type_names[operands[1].index][1]
                field = f"f_{f_index}"
                cty = f"union {u_name}"
                self.emit(f"{cty} *{var} = rt_malloc(sizeof({cty}));")
                self.emit(f"{var}->{field} = {value};")
                stack.append((var, True))
            elif opcode == OpCode.STRUCT_LITERAL:
                var = self.new_var()
                values = pop_n(stack, operands[0])
                s_name = self._type_names[operands[1].index][1]
                cty = f"struct {s_name}"
                self.emit(f"{cty} *{var} = rt_malloc(sizeof({cty}));")
                for idx, value in enumerate(values):
                    self.emit(f"{var}->f_{idx} = {value};")
                stack.append((var, True))
            elif opcode == OpCode.DUP:
                value, p = stack.pop()
                self.inc_ref(value, p)
                stack.append((value, p))
                stack.append((value, p))
            elif opcode == OpCode.RETURN:
                # Cleanup stack!
                for _, v, is_ptr2 in local_vars:
                    if is_ptr2:
                        self.emit(f"rt_decref({v});")

                if operands[0] == 1:
                    val, _ = stack.pop()
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

    def inc_ref(self, var: str, ptr: bool):
        if ptr:
            self.emit(f"rt_incref({var});")

    def dec_ref(self, var: str, ptr: bool):
        if ptr:
            self.emit(f"rt_decref({var});")

    def new_var(self):
        return f"val_{self.new_id()}"

    def new_id(self):
        self._uniq += 1
        return self._uniq


def pop_n(stack, n: int):
    args = [stack.pop()[0] for _ in range(n)]
    args.reverse()
    return args


def get_jump_targets(instructions):
    for opcode, operands in instructions:
        if opcode == OpCode.JUMP:
            yield operands[0]
        elif opcode == OpCode.JUMP_IF:
            yield operands[0]
            yield operands[1]


def is_ptr(ty: Typ) -> bool:
    """Check if this is a ref-counted pointer"""
    if isinstance(ty, bc.BaseTyp):
        if ty.type_id == bc.SimpleTyp.PTR:
            return True
        elif ty.type_id == bc.SimpleTyp.STR:
            return True
    elif isinstance(ty, bc.StructTyp):
        return True

    return False
