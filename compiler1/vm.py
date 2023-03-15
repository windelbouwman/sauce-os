""" Virtual machine to run byte-code.

Having a virtual machine is a way for bootstrapping
a compiler.

"""


class OpCode:
    ADD = 1
    SUB = 2


class VirtualMachine:
    def __init__(self):
        self._stack = []
        self._pc = 0

    def run(self):
        while True:
            opcode, operands = self.fetch()
            self.dispatch(opcode, operands)

    def dispatch(self, opcode, args):
        if opcode == OpCode.ADD:
            a = self.pop_value()
            b = self.pop_value()
            self.push_value(a + b)
        else:
            raise NotImplementedError(str(opcode))
