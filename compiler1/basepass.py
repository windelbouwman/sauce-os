import logging

from .errors import CompilationError
from .location import Location
from . import ast

logger = logging.getLogger("basepass")


class BasePass(ast.AstVisitor):
    name = "base-pass"

    def __init__(self):
        self._errors = []
        self._filename = "?"

    def run(self, module: ast.Module):
        self.begin(module.filename, f"Running {self.name} pass on '{module.name}'")
        self.visit_module(module)
        self.finish(f"Pass {self.name} completed:party_popper:")

    def begin(self, filename: str, msg: str):
        logger.info(msg)
        self._filename = filename

    def error(self, location: Location, msg: str):
        logger.error(f"{self._filename}:{location}: {msg}", extra={"markup": True})
        self._errors.append((self._filename, location, msg))

    def warning(self, location: Location, msg: str):
        logger.warning(f"{self._filename}:{location}: {msg}", extra={"markup": True})

    def finish(self, msg: str):
        if self._errors:
            raise CompilationError(self._errors)
        else:
            logger.info(msg, extra={"markup": True})
