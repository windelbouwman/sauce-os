""" Type check code.
"""

import logging
from . import ast

from .typechecker import TypeChecker
from .namebinding import ScopeFiller, NameBinder

logger = logging.getLogger('analyzer')


def analyze_ast(module: ast.Module, known_modules: dict, options):
    filler = ScopeFiller(known_modules)
    filler.fill_module(module)

    binder = NameBinder()
    binder.resolve_symbols(module)

    if options.dump_ast:
        ast.print_ast(module)

    checker = TypeChecker()
    checker.check_module(module)
