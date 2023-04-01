
""" Compiler driver.
"""

from dataclasses import dataclass
import logging

import networkx as nx

from . import ast
from .parsing import parse_file
from .namebinding import ScopeFiller, NameBinder
from .pass3 import NewOpPass, TypeEvaluation
from .typechecker import TypeChecker
from .transforms import transform
from .flowcheck import flow_check
from .cppgenerator import gencode

logger = logging.getLogger('compiler')


@dataclass
class CompilationOptions:
    dump_ast: bool = False


def std_module():
    mod = ast.Module('std', [], [])
    mod.add_definition(
        'print',
        ast.BuiltinFunction('std_print', [ast.str_type], ast.void_type))
    mod.add_definition(
        'int_to_str',
        ast.BuiltinFunction('std_int_to_str', [ast.int_type], ast.str_type))
    mod.add_definition(
        'read_file',
        ast.BuiltinFunction('std_read_file', [ast.str_type], ast.str_type))
    mod.add_definition(
        'float_to_str',
        ast.BuiltinFunction('std_float_to_str', [ast.float_type], ast.str_type))

    return mod


def do_compile(filenames: list[str], output: str | None, options: CompilationOptions, progress, task):
    """ Compile a list of module.
    """
    known_modules = {'std': std_module()}

    progress.advance(task, 10)
    modules = []
    for filename in filenames:
        module = parse_file(filename)
        modules.append(module)
        if options.dump_ast:
            logger.info('Dumping AST')
            ast.print_ast(module)
    topo_sort(modules)
    progress.advance(task, 20)

    for module in modules:
        analyze_ast(module, known_modules, options)
        if options.dump_ast:
            logger.info('Dumping AST')
            ast.print_ast(module)

    progress.advance(task, 30)
    transform(modules)
    progress.advance(task, 10)

    for module in modules:
        if options.dump_ast:
            logger.info('Dumping AST')
            ast.print_ast(module)

    flow_check(modules)
    progress.advance(task, 20)

    # Generate output
    if output:
        with open(output, 'w') as f:
            gencode(modules, f=f)
    else:
        gencode(modules)
    progress.advance(task, 10)

    logger.info(':party_popper:DONE&DONE', extra={'markup': True})


def topo_sort(modules: list[ast.Module]):
    """ Sort modules in dependency order (in-place).

    Check each module used other modules, and
    topologically sort the dependency graph.
    """
    g = nx.DiGraph()
    m = {}
    for module in modules:
        m[module.name] = module
        for dep in module.get_deps():
            g.add_edge(module.name, dep)

    order = list(reversed(list(nx.topological_sort(g))))
    logger.info(f"Compilation order: {order}")
    modules.clear()
    for name in order:
        if name in m:
            modules.append(m.pop(name))
    assert not m


def analyze_ast(module: ast.Module, known_modules: dict[str, ast.Module], options: CompilationOptions):
    """ Fill scopes, resolve symbols, evaluate type expressions."""
    ScopeFiller(known_modules).fill_module(module)
    NameBinder().resolve_symbols(module)
    TypeEvaluation().run(module)
    NewOpPass().run(module)

    if options.dump_ast:
        ast.print_ast(module)

    TypeChecker().check_module(module)
