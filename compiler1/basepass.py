
import logging

from .errors import CompilationError
from .location import Location
from . import ast

logger = logging.getLogger('basepass')


class BasePass(ast.AstVisitor):
    def __init__(self):
        self._errors = []
        self._filename = '?'

    def begin(self, filename: str, msg: str):
        logger.info(msg)
        self._filename = filename

    def error(self, location: Location, msg: str):
        logger.error(f"{self._filename}:{location}: {msg}")
        self._errors.append((self._filename, location, msg))

    def finish(self, msg: str):
        if self._errors:
            raise CompilationError(self._errors)
        else:
            logger.info(msg)
