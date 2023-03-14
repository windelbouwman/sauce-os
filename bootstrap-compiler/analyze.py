""" Type check code.
"""

import logging
from . import ast

from .typechecker import TypeChecker
from .namebinding import ScopeFiller, NameBinder

logger = logging.getLogger('analyzer')


def analyze_ast(module: ast.Module, code: str, known_modules: dict, options) -> bool:
    logger.info("Type checking")
    filler = ScopeFiller(code, known_modules)
    filler.fill_module(module)
    logger.info("Scopes filled")
    if not filler._ok:
        return False

    binder = NameBinder(code)
    binder.resolve_symbols(module)
    if not binder._ok:
        return False

    if options.dump_ast:
        ast.print_ast(module)

    checker = TypeChecker(code)
    checker.check_module(module)
    return checker._ok
