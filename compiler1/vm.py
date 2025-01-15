"""Virtual machine to run byte-code.

Having a virtual machine is a way for bootstrapping
a compiler.

"""

import logging
from .builtins import get_builtins
from .bc import Program, Function, OpCode, Typ
from . import bc

logger = logging.getLogger("slangc.vm")


def run_bytecode(prog: Program, f):
    """Take bytecode and invoke 'main' function."""
    logger.info("Running byte-code!")
    m = VirtualMachine(f)
    m.load(prog)
    m.invoke("main")


def check_value_type(value, ty: Typ):
    """Assert that the given value is of the given type."""
    if isinstance(ty, bc.BaseTyp):
        if ty.type_id == bc.SimpleTyp.FLOAT:
            assert isinstance(value, float)
        elif ty.type_id == bc.SimpleTyp.INT:
            assert isinstance(value, int)
        elif ty.type_id == bc.SimpleTyp.BOOL:
            assert isinstance(value, bool)
        elif ty.type_id == bc.SimpleTyp.STR:
            assert isinstance(value, str)
        elif ty.type_id == bc.SimpleTyp.PTR:
            # Assumptions...
            pass
        else:
            raise NotImplementedError(str(ty.type_id))
    elif isinstance(ty, bc.StructTyp):
        assert isinstance(value, list)
    elif isinstance(ty, bc.PointerTyp):
        check_value_type(value, ty.element_typ)
    elif isinstance(ty, bc.ArrayTyp):
        assert isinstance(value, list)
    elif isinstance(ty, bc.FunctionType):
        # Assume fine!
        pass
    else:
        raise NotImplementedError(ty)


def frame_from_function(function: Function, arguments):
    assert len(arguments) == len(function.params)
    # We could type enforce here, in theory, we checked, but just an extra runtime check.
    for arg, p_ty in zip(arguments, function.params):
        # assert types match
        check_value_type(arg, p_ty)

    n_vars = len(function.local_vars)
    frame = Frame(function.code)
    frame._function = function
    frame._locals = arguments + [0] * n_vars
    return frame


class Frame:
    """Call frame."""

    def __init__(self, code):
        # value stack:
        self._stack = []
        self._except_handlers = []
        self._locals = []
        self._pc = 0
        self._code = code
        self._function = None

    def fetch(self):
        return self._code[self._pc]

    def push(self, value):
        self._stack.append(value)

    def pop(self):
        return self._stack.pop()

    def set_local(self, index, value):
        # TBD: enforce strict type checking?
        # check_value_type
        self._locals[index] = value

    def get_local(self, index):
        return self._locals[index]


class VirtualMachine:
    def __init__(self, stdout):
        # Call stack:
        self._frames = []
        self._builtins = get_builtins(args=(), stdout=stdout)
        self._globals = []

    def load(self, prog: Program):
        self.prog = prog
        self.functions_by_name = {}
        self._globals = [
            self.eval_code(initial_value_code) for initial_value_code in prog.globals
        ]
        for f in prog.functions:
            if f.name in self.functions_by_name:
                raise ValueError(f"Duplicate function name: {f.name}")
            else:
                self.functions_by_name[f.name] = f

    def run(self):
        try:
            while self._frames:
                self.dispatch()
        except (IndexError, RuntimeError):
            print("traceback:")
            for frame in self._frames:
                if frame._function:
                    print("in ", frame._function.name)
            raise

    def eval_code(self, code):
        self.push_frame(Frame(code))
        self.dispatch()
        # TODO: run all code?
        value = self.pop_value()
        self.pop_frame()
        return value

    def dispatch(self):
        """Single tick"""
        opcode, args = self._frames[-1].fetch()

        verbose = True
        verbose = False
        if verbose:
            print(
                "dispatch", self._frames[-1]._pc, self._frames[-1]._stack, opcode, args
            )
        self._frames[-1]._pc += 1

        if opcode == OpCode.CONST:
            self.push_value(args[0])
        elif opcode == OpCode.LOCAL_GET:
            value = self.get_local(args[0])
            self.push_value(value)
        elif opcode == OpCode.LOCAL_SET:
            value = self.pop_value()
            self.set_local(args[0], value)
        elif opcode == OpCode.GLOBAL_GET:
            value = self.get_global(args[0])
            self.push_value(value)
        elif opcode == OpCode.GLOBAL_SET:
            value = self.pop_value()
            self.set_global(args[0], value)
        elif opcode == OpCode.LOADFUNC:
            func = self.functions_by_name[args[0]]
            self.push_value(func)
        elif opcode == OpCode.BUILTIN:
            self.push_value(self._builtins[args[0]])
        elif opcode == OpCode.CALL:
            callee = self.pop_value()
            arguments = self.pop_n(args[0])

            # ATTENTION: major hackerij:
            if isinstance(callee, Function):
                self.push_frame(frame_from_function(callee, arguments))
            else:
                # Might be a python function!
                r = callee(*arguments)
                # print('res', r)
                if r is not None:
                    self.push_value(r)
        elif opcode == OpCode.RETURN:
            if args[0] == 1:
                value = self.pop_value()
                self.pop_frame()
                self.push_value(value)
            else:
                self.pop_frame()
        elif opcode == OpCode.RAISE:
            exc_value = self.pop_value()
            # TODO: code below might not be 100% waterproof
            # Let's unwind!
            while True:
                if self._frames[-1]._except_handlers:
                    except_handler = self._frames[-1]._except_handlers.pop()
                    break
                else:
                    self.pop_frame()
            self.push_value(exc_value)
            self.jump(except_handler)

        elif opcode == OpCode.SETUP_EXCEPT:
            self._frames[-1]._except_handlers.append(args[0])
        elif opcode == OpCode.POP_EXCEPT:
            self._frames[-1]._except_handlers.pop()
        elif opcode in binary_op_funcs:
            rhs = self.pop_value()
            lhs = self.pop_value()
            res = binary_op_funcs[opcode](lhs, rhs)
            self.push_value(res)
        elif opcode in unary_op_funcs:
            rhs = self.pop_value()
            res = unary_op_funcs[opcode](rhs)
            self.push_value(res)
        elif opcode == OpCode.CAST:
            val = self.pop_value()
            to_ty = args[0]
            if isinstance(to_ty, bc.BaseTyp):
                if to_ty.type_id == bc.SimpleTyp.FLOAT:
                    cast_val = float(val)
                elif to_ty.type_id == bc.SimpleTyp.INT:
                    cast_val = int(val)
                else:
                    raise NotImplementedError(str(to_ty.type_id))
            else:
                raise NotImplementedError(str(to_ty))
            self.push_value(cast_val)
        elif opcode == OpCode.JUMP_IF:
            v = self.pop_value()
            if v:
                self.jump(args[0])
            else:
                self.jump(args[1])
        elif opcode == OpCode.JUMP:
            self.jump(args[0])
        elif opcode == OpCode.ARRAY_LITERAL:
            # Contrapt a list of values:
            arguments = self.pop_n(args[0])
            self.push_value(arguments)
        elif opcode == OpCode.ARRAY_LITERAL2:
            # Contrapt a list of values:
            size = self.pop_value()
            value = [None] * size
            self.push_value(value)
        elif opcode == OpCode.STRUCT_LITERAL:
            # Treat struct as list of values? Might work!
            arguments = self.pop_n(args[0])
            self.push_value(arguments)
        elif opcode == OpCode.GET_INDEX:
            index = self.pop_value()
            base = self.pop_value()
            self.push_value(base[index])
        elif opcode == OpCode.SET_INDEX:
            value = self.pop_value()
            index = self.pop_value()
            base = self.pop_value()
            base[index] = value
        elif opcode == OpCode.GET_ATTR:
            base = self.pop_value()
            self.push_value(base[args[0]])
        elif opcode == OpCode.SET_ATTR:
            value = self.pop_value()
            base = self.pop_value()
            base[args[0]] = value
        elif opcode == OpCode.DUP:
            value = self.pop_value()
            self.push_value(value)
            self.push_value(value)
        else:
            raise NotImplementedError(str(opcode))

    def push_frame(self, frame: Frame):
        self._frames.append(frame)

    def pop_frame(self):
        self._frames.pop()

    def push_value(self, value):
        if self._frames:
            self._frames[-1].push(value)
        else:
            logger.info(f"Push value: {value}")

    def pop_value(self):
        return self._frames[-1].pop()

    def pop_n(self, n: int):
        values = [self.pop_value() for _ in range(n)]
        values.reverse()
        return values

    def set_local(self, index: int, value):
        self._frames[-1].set_local(index, value)

    def get_local(self, index: int):
        return self._frames[-1].get_local(index)

    def get_global(self, index: int):
        return self._globals[index]

    def set_global(self, index: int, value):
        self._globals[index] = value

    def jump(self, pc: int):
        self._frames[-1]._pc = pc

    def invoke(self, name: str):
        # Invoke function
        func = self.functions_by_name[name]
        self.push_frame(frame_from_function(func, []))
        self.run()


binary_op_funcs = {
    OpCode.DIV: lambda a, b: a / b,
    OpCode.MUL: lambda a, b: a * b,
    OpCode.ADD: lambda a, b: a + b,
    OpCode.SUB: lambda a, b: a - b,
    OpCode.EQ: lambda a, b: a == b,
    OpCode.LT: lambda a, b: a < b,
    OpCode.GT: lambda a, b: a > b,
    OpCode.LTE: lambda a, b: a <= b,
    OpCode.GTE: lambda a, b: a >= b,
    OpCode.AND: lambda a, b: a and b,
    OpCode.OR: lambda a, b: a or b,
}

unary_op_funcs = {OpCode.NOT: lambda a: not a}
