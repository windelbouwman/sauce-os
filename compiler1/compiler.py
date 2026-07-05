"""Compiler driver."""

from dataclasses import dataclass
import logging
import io
import sys
import os
from typing import TextIO, Optional

from . import ast
from .parsing import Parser
from .namebinding import resolve_names, base_scope
from .pass3 import evaluate_types
from .typechecker import check_types
from .transforms import (
    rewrite_loops,
    rewrite_enums,
    rewrite_classes,
    rewrite_switch,
    constant_folding,
    replace_unions,
    rewrite_interfaces,
    rewrite_names,
)
from .flowcheck import flow_check
from .pygenerator import gen_pycode
from .bc_gen import gen_bc
from .vm import run_bytecode
from .bc import print_bytecode
from .builtins import create_rt_module, get_builtins

logger = logging.getLogger("slangc")
sys.path.append(os.path.join(os.path.dirname(os.path.dirname(__file__)), "runtime"))
import slangrt

__all__ = ["base_scope"]


@dataclass
class CompilationOptions:
    dump_ast: bool = False
    run_code: bool = False
    backend: str = "vm"
    program_args: tuple = ()


class Compiler:
    def __init__(self, options: CompilationOptions):
        self.options = options
        self.id_context = ast.IdContext()
        self.parser = Parser(self.id_context)

    def do_compile(self, filenames: list[str], output: Optional[TextIO]):
        return do_compile_inner(self, filenames, output)

    def parse(self, filenames):
        modules = []
        rt_module = create_rt_module(self.id_context)
        modules.append(rt_module)
        for filename in filenames:
            module = self.parser.parse_file(filename)
            modules.append(module)
            if self.options.dump_ast:
                ast.print_ast(module)
        return rt_module, modules


def do_compile(
    filenames: list[str], output: Optional[TextIO], options: CompilationOptions
):
    compiler = Compiler(options)
    return do_compile_inner(compiler, filenames, output)


def do_compile_inner(
    compiler: Compiler, filenames: list[str], output: Optional[TextIO]
):
    """Compile a list of module."""
    if not filenames:
        logger.error("No existing source files provided")
        return

    filenames = list(sorted(set(filenames)))

    rt_module, modules = compiler.parse(filenames)

    analyze_ast(modules, compiler.options)

    if compiler.options.backend == "null":
        return modules

    transform(compiler.id_context, modules, rt_module, compiler.options)

    if compiler.options.dump_ast:
        print_modules(modules)

    flow_check(modules)

    # Generate output
    if compiler.options.backend == "vm":
        prog = gen_bc(modules)
        if compiler.options.run_code:
            run_bytecode(prog, output)
        else:
            print_bytecode(prog, output)
    elif compiler.options.backend == "py":
        if compiler.options.run_code:
            f = io.StringIO()
            gen_pycode(modules, f)
            code = f.getvalue()
            logger.info("Invoking python code")

            if output:

                def std_print(txt: str):
                    print(txt, file=output)

            else:

                def std_print(txt: str):
                    print(txt)

            slangrt.std_print = std_print

            # namespace = get_builtins(args=options.program_args, stdout=output)
            namespace = {}
            exec(code, namespace)
            namespace["main_main"]()
        else:
            gen_pycode(modules, output)
    else:
        raise ValueError(f"Unknown backend: {compiler.options.backend}")

    logger.info(":party_popper:DONE&DONE", extra={"markup": True})


def analyze_ast(modules: list[ast.Module], options: CompilationOptions):
    """Fill scopes, resolve symbols, evaluate type expressions."""
    resolve_names(modules)
    evaluate_types(modules)

    if options.dump_ast:
        print_modules(modules)

    check_types(modules)


def print_modules(modules: list[ast.Module]):
    for module in modules:
        ast.print_ast(module)


def transform(
    id_context: ast.IdContext,
    modules: list[ast.Module],
    rt_module: ast.Module,
    options: CompilationOptions,
):
    """Transform a slew of modules (in-place)

    Some real compilation being done here.
    """
    # Rewrite and type-check for each transformation.
    rewrite_loops(id_context, rt_module, modules)
    check_types(modules)

    rewrite_enums(id_context, modules)
    if options.dump_ast:
        print_modules(modules)
    check_types(modules)

    rewrite_classes(id_context, modules)
    if options.dump_ast:
        print_modules(modules)
    check_types(modules)

    # TODO: this can be optional, depending on what the backend supports!
    rewrite_switch(id_context, modules)
    replace_unions(id_context, modules)
    rewrite_interfaces(id_context, modules)
    # print_modules(modules)
    check_types(modules)
    rewrite_names(id_context, modules)

    constant_folding(id_context, modules)
    check_types(modules)
