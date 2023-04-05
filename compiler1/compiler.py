
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
from .transforms import LoopRewriter, EnumRewriter, ClassRewriter
from .flowcheck import flow_check
from .cppgenerator import gencode
from .pygenerator import gencode as gen_pycode
from .bc_gen import gen_bc

logger = logging.getLogger('compiler')


@dataclass
class CompilationOptions:
    dump_ast: bool = False
    run_code: bool = False


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


def do_compile(filenames: list[str], output: str | None, options: CompilationOptions):
    """ Compile a list of module.
    """
    known_modules = {'std': std_module()}

    modules = []
    for filename in filenames:
        module = parse_file(filename)
        modules.append(module)
        if options.dump_ast:
            ast.print_ast(module)
    topo_sort(modules)

    for module in modules:
        analyze_ast(module, known_modules, options)
        if options.dump_ast:
            ast.print_ast(module)

    transform(modules)

    if options.dump_ast:
        print_modules(modules)

    flow_check(modules)

    # Generate output
    if 1:
        gen_bc(modules)
    elif 0:
        code = gen_pycode(modules)
        if options.run_code:
            logger.info("Invoking python code")
            exec(code, {})
    else:
        if output:
            with open(output, 'w') as f:
                gencode(modules, f=f)
        else:
            gencode(modules)

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


def check_modules(modules: list[ast.Module]):
    for module in modules:
        TypeChecker().check_module(module)


def print_modules(modules: list[ast.Module]):
    for module in modules:
        ast.print_ast(module)


def transform(modules: list[ast.Module]):
    """ Transform a slew of modules (in-place)

    Some real compilation being done here.
    """
    # Rewrite and type-check for each transformation.
    LoopRewriter().transform(modules)
    check_modules(modules)

    EnumRewriter().transform(modules)
    # print_modules(modules)
    check_modules(modules)

    ClassRewriter().transform(modules)
    # print_modules(modules)
    check_modules(modules)
