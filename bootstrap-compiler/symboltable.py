

class Scope:
    def __init__(self):
        self.symbols = {}

    def is_defined(self, name: str):
        return name in self.symbols

    def lookup(self, name: str):
        if name in self.symbols:
            return self.symbols[name]

    def define(self, name: str, symbol):
        self.symbols[name] = symbol


def builtins():
    scope = Scope()
    scope.insert('str', str)
    scope.insert('int', int)
    scope.insert('bool', bool)
    return scope
