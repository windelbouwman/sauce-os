

class Scope:
    def __init__(self, parent):
        self.parent = parent
        self.symbols = {}

    def is_defined(self, name, search_parents=True):
        if name in self.symbols:
            return True
        elif not search_parents:
            return False
        else:
            if self.parent:
                return self.parent.is_defined(name, search_parents=search_parents)
            else:
                return False

    def lookup(self, name):
        if name in self.symbols:
            return self.symbols[name]
        else:
            return self.parent.lookup(name)

    def define(self, name, symbol):
        self.symbols[name] = symbol


def builtins():
    scope = Scope()
    scope.insert('str', str)
    scope.insert('int', int)
    scope.insert('bool', bool)
    return scope
