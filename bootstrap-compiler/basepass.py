from .errors import print_error
from .location import Location
from . import ast


class BasePass(ast.AstVisitor):
    def __init__(self, code: str):
        self._ok = True
        self._code = code

    def error(self, location: Location, msg: str):
        print("**************** ERROR *******************")
        print_error(self._code, location, msg)
        print("******************************************")
        self._ok = False
