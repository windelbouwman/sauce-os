""" Compiler driver.
"""

from dataclasses import dataclass
import logging, io, tempfile, subprocess

import networkx as nx

from . import ast
from .parsing import parse_file
from .namebinding import ScopeFiller, NameBinder
from .pass3 import NewOpPass, TypeEvaluation
from .typechecker import TypeChecker
from .transforms import (
    LoopRewriter,
    EnumRewriter,
    ClassRewriter,
    SwitchRewriter,
    ConstantFolder,
)
from .flowcheck import flow_check
from .cppgenerator import gen_cppcode
from .pygenerator import gen_pycode
from .bc_gen import gen_bc
from .vm import run_bytecode, print_bytecode
from .builtins import std_module, get_builtins

logger = logging.getLogger("compiler")


@dataclass
class CompilationOptions:
    dump_ast: bool = False
    run_code: bool = False
    backend: str = "vm"


def do_compile(filenames: list[str], output: str | None, options: CompilationOptions):
    """Compile a list of module."""
    if not filenames:
        logger.error("No existing source files provided")
        return

    known_modules = {"std": std_module()}

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

    transform(modules, known_modules["std"])

    if options.dump_ast:
        print_modules(modules)

    flow_check(modules)

    # Generate output
    if options.backend == "vm":
        prog = gen_bc(modules)
        if options.run_code:
            run_bytecode(prog, output)
        else:
            print_bytecode(prog, output)
    elif options.backend == "py":
        if options.run_code:
            f = io.StringIO()
            gen_pycode(modules, f)
            code = f.getvalue()
            logger.info("Invoking python code")
            exec(code, get_builtins(output))
        else:
            gen_pycode(modules, output)
    elif options.backend == "cpp":
        if options.run_code:
            with tempfile.NamedTemporaryFile(
                mode="w",
                prefix="slang_compiler_tmp",
                suffix=".cpp",
                delete=False,
            ) as f:
                filename = f.name
                logger.info(f"Generating C++ code to temporary file: {filename}")
                gen_cppcode(modules, f=f)

            runtime_filename = "runtime/runtime.cpp"
            cpp_sources = [filename, runtime_filename]
            logger.info(f"Invoking the g++ C++ compiler on {cpp_sources}")
            cmd = ["g++"] + cpp_sources
            logger.debug(f"Invoking command: {cmd}")
            subprocess.run(cmd, check=True)

            # Now we compiled our C++, run our exe:
            exe_filename = "./a.out"
            cmd = [exe_filename]
            logger.info(f"Running native executable {exe_filename}")
            logger.debug(f"Invoking command: {cmd}")
            subprocess.run(cmd, check=True)
        else:
            gen_cppcode(modules, f=output)
    else:
        raise ValueError(f"Unknown backend: {options.backend}")

    logger.info(":party_popper:DONE&DONE", extra={"markup": True})


def topo_sort(modules: list[ast.Module]):
    """Sort modules in dependency order (in-place).

    Check each module used other modules, and
    topologically sort the dependency graph.
    """
    g = nx.DiGraph()
    m = {}
    for module in modules:
        m[module.name] = module
        g.add_node(module.name)
        for dep in module.get_deps():
            g.add_edge(module.name, dep)

    logger.debug(f"module dependency graph: {g}")

    order = list(reversed(list(nx.topological_sort(g))))
    logger.info(f"Compilation order: {order}")
    modules.clear()
    for name in order:
        if name in m:
            modules.append(m.pop(name))
    assert not m


def analyze_ast(
    module: ast.Module,
    known_modules: dict[str, ast.Module],
    options: CompilationOptions,
):
    """Fill scopes, resolve symbols, evaluate type expressions."""
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


def transform(modules: list[ast.Module], std_module: ast.Module):
    """Transform a slew of modules (in-place)

    Some real compilation being done here.
    """
    # Rewrite and type-check for each transformation.
    LoopRewriter(std_module).transform(modules)
    check_modules(modules)

    EnumRewriter().transform(modules)
    # print_modules(modules)
    check_modules(modules)

    ClassRewriter().transform(modules)
    # print_modules(modules)
    check_modules(modules)

    # TODO: this can be optional, depending on what the backend supports!
    SwitchRewriter().transform(modules)
    # print_modules(modules)
    check_modules(modules)

    ConstantFolder().transform(modules)
    check_modules(modules)
