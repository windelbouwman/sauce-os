""" Virtual machine to run byte-code.

Having a virtual machine is a way for bootstrapping
a compiler.

"""

import logging

logger = logging.getLogger('vm')


class Program:
    """ A bytecode program """

    def __init__(self, functions: list['Function']):
        self.functions = functions


class Function:
    def __init__(self, name: str, code, n_locals: int):
        self.name = name
        self.code = code
        self.n_locals = n_locals  # locals + parameters!


def run_bytecode(prog: Program):
    """ Take bytecode and invoke 'main' function.
    """
    logger.info('Running byte-code!')
    m = VirtualMachine()
    m.load(prog)
    m.invoke('main')


class Frame:
    """ Call frame. """

    def __init__(self, function: Function, arguments):
        # value stack:
        self._stack = []
        n_vars = function.n_locals - len(arguments)
        self._locals = arguments + [0] * n_vars

        self._pc = 0
        self._function = function

    def fetch(self):
        return self._function.code[self._pc]

    def push(self, value):
        self._stack.append(value)

    def pop(self):
        return self._stack.pop()

    def set_local(self, index, value):
        self._locals[index] = value

    def get_local(self, index):
        return self._locals[index]


class VirtualMachine:
    def __init__(self):
        # Call stack:
        self._frames = []

    def load(self, prog: Program):
        self.prog = prog
        self.functions_by_name = {f.name: f for f in prog.functions}

    def run(self):
        while self._frames:
            self.dispatch()

    def dispatch(self):
        """ Single tick"""
        opcode, args = self._frames[-1].fetch()

        verbose = True
        verbose = False
        if verbose:
            print('dispatch', self._frames[-1]._pc,
                  self._frames[-1]._stack, opcode, args)
        self._frames[-1]._pc += 1

        if opcode == 'CONST':
            self.push_value(args[0])
        elif opcode == 'LOCAL_GET':
            value = self.get_local(args[0])
            self.push_value(value)
        elif opcode == 'LOCAL_SET':
            value = self.pop_value()
            self.set_local(args[0], value)
        elif opcode == 'LOADFUNC':
            func = self.functions_by_name[args[0]]
            self.push_value(func)
        elif opcode == 'BUILTIN':
            builtins = {
                'std_print': print,
                'str_to_int': int,
                'std_int_to_str': str,
            }
            self.push_value(builtins[args[0]])
        elif opcode == 'CALL':
            callee = self.pop_value()
            arguments = self.pop_n(args[0])

            # ATTENTION: major hackerij:
            if isinstance(callee, Function):
                self._frames.append(Frame(callee, arguments))
            else:
                # Might be a python function!
                r = callee(*arguments)
                # print('res', r)
                if r is not None:
                    self.push_value(r)
        elif opcode == 'RETURN':
            # TODO: return value?
            # Return from frame.
            self._frames.pop()
        elif opcode in binary_op_funcs:
            rhs = self.pop_value()
            lhs = self.pop_value()
            res = binary_op_funcs[opcode](lhs, rhs)
            self.push_value(res)
        elif opcode == 'JUMP-IF':
            v = self.pop_value()
            if v:
                self.jump(args[0])
            else:
                self.jump(args[1])
        elif opcode == 'JUMP':
            self.jump(args[0])
        elif opcode == 'ARRAY_LIT':
            # Contrapt a list of values:
            arguments = self.pop_n(args[0])
            self.push_value(arguments)
        elif opcode == 'STRUC_LIT':
            # Treat struct as list of values? Might work!
            arguments = self.pop_n(args[0])
            self.push_value(arguments)
        elif opcode == 'GET_INDEX':
            index = self.pop_value()
            base = self.pop_value()
            self.push_value(base[index])
        elif opcode == 'SET_INDEX':
            index = self.pop_value()
            base = self.pop_value()
            value = self.pop_value()
            base[index] = value
        elif opcode == 'GET_ATTR':
            base = self.pop_value()
            self.push_value(base[args[0]])
        elif opcode == 'SET_ATTR':
            base = self.pop_value()
            value = self.pop_value()
            base[args[0]] = value
        else:
            raise NotImplementedError(str(opcode))

    def push_value(self, value):
        self._frames[-1].push(value)

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

    def jump(self, pc: int):
        self._frames[-1]._pc = pc

    def invoke(self, name: str):
        # Invoke function
        func = self.functions_by_name[name]
        self._frames.append(Frame(func, []))
        self.run()


binary_op_funcs = {
    'DIV': lambda a, b: a / b,
    'MUL': lambda a, b: a * b,
    'ADD': lambda a, b: a + b,
    'SUB': lambda a, b: a - b,
    'EQ': lambda a, b: a == b,
    'LT': lambda a, b: a < b,
    'GT': lambda a, b: a > b,
    'LTE': lambda a, b: a <= b,
    'GTE': lambda a, b: a >= b,
    'AND': lambda a, b: a and b,
    'OR': lambda a, b: a or b,
}
