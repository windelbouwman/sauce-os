"""
Idea: generate slang code with the hypothesis library, and run through the compiler.

This might be useful:

https://hypothesis.readthedocs.io/en/latest/extras.html#hypothesis.extra.lark.from_lark

"""

import io
import tempfile
import sys
import subprocess
from dataclasses import dataclass
from pathlib import Path
from compiler1 import compiler
from compiler1.lexer import KEYWORDS
from hypothesis import strategies as st
from hypothesis import given, settings


bit_operators = st.sampled_from(["^", "|", "&", ">>", "<<"])
arithmatic_operators = st.sampled_from(["+", "-", "*", "/"])
comparison_operators = st.sampled_from(["==", "!=", ">", "<", ">=", "<="])


@st.composite
def expression_const(draw) -> str:
    value = draw(st.integers(min_value=0, max_value=4500))
    return f"{value}"


@st.composite
def expression_var(draw, var_pool) -> str:
    name = draw(st.sampled_from(var_pool))
    return name


@st.composite
def expression_call(draw, func_pool, var_pool) -> str:
    f = draw(st.sampled_from(func_pool))
    args = []
    for p_name in f.parameters:
        arg = draw(expression_simple(var_pool))
        args.append(f"{p_name}: {arg}")
    arg_text = ", ".join(args)
    return f"{f.name}({arg_text})"


def expression(func_pool, var_pool):
    expr = expression_simple(var_pool)
    if func_pool:
        expr = expr | expression_call(func_pool, var_pool)
    return expr


def expression_simple(var_pool):
    """A simple expression, such as a constant or variable reference."""
    expr = expression_const()
    if var_pool:
        expr = expr | expression_var(var_pool)
    return expr


identifier = st.text(
    alphabet=st.characters(min_codepoint=97, max_codepoint=122), min_size=4, max_size=9
)


@st.composite
def unused_identifier(draw, func_pool, var_pool):
    bad_identifiers = {"true", "false", "null", "main"}
    bad_identifiers |= KEYWORDS
    bad_identifiers |= set(var_pool)
    bad_identifiers |= set(f.name for f in func_pool)
    return draw(identifier.filter(lambda n: n not in bad_identifiers))


@dataclass
class FunctionDef:
    name: str
    parameters: list[str]


@st.composite
def function_def(draw, func_pool):
    var_pool = []
    n_param = draw(st.integers(min_value=0, max_value=13))
    p_names = []
    for _ in range(n_param):
        p_name = draw(unused_identifier(func_pool, var_pool))
        var_pool.append(p_name)
        p_names.append(p_name)
    expr = draw(expression(func_pool, var_pool))
    body = [expr]
    name = draw(unused_identifier(func_pool, var_pool))
    func_pool.append(FunctionDef(name, p_names))
    p_text = ", ".join(f"{n}: int" for n in p_names)
    decl = f"fn {name}({p_text}) -> int:"
    return [decl] + indented(body)


def indented(lines: list[str]) -> list[str]:
    return ["\t" + line for line in lines]


@st.composite
def statement_print(draw, func_pool, var_pool):
    expr = draw(expression(func_pool, var_pool))
    return f"print(int_to_str({expr}))"


@st.composite
def statement_let(draw, func_pool, var_pool):
    expr = draw(expression(func_pool, var_pool))
    varname = draw(unused_identifier(func_pool, var_pool))
    var_pool.append(varname)
    return f"let {varname} = {expr}"


def statement(func_pool, var_pool):
    return statement_print(func_pool, var_pool) | statement_let(func_pool, var_pool)


@st.composite
def slang_module(draw):
    module = []
    imports = [
        "from std import print",
        "from rt import int_to_str",
        "",
    ]
    module.extend(imports)
    n_funcs = draw(st.integers(min_value=1, max_value=5))
    func_pool = []
    for _ in range(n_funcs):
        module.extend(draw(function_def(func_pool)))
    # Main body:
    var_pool = []
    main_body = []
    n_statements = draw(st.integers(min_value=3, max_value=15))
    for _ in range(n_statements):
        main_body.append(draw(statement(func_pool, var_pool)))
    main_body.append("0")
    main_function = ["fn main() -> int:"] + indented(main_body)
    module.extend(main_function)
    return module


@given(slang_module())
@settings(max_examples=50)
def test_w00t(code):
    # Run sample code through different backends, and compare the outputs
    with tempfile.NamedTemporaryFile(mode="w", suffix=".slang", delete=False) as tmp:
        tmp.writelines([x + "\n" for x in code])
        example_path = Path(tmp.name)

    # Run various compilation incantations, output should be the same.
    output1 = run_code_via_compiler1(example_path, "py")
    output2 = run_code_via_compiler1(example_path, "vm")
    assert output1 == output2

    output3 = run_code_via_compiler(example_path, "vm")
    assert output1 == output3
    output4 = run_code_via_compiler(example_path, "x86")
    assert output1 == output4
    # output5 = run_code_via_compiler(example_path, "py")
    # assert output1 == output5


def run_code_via_compiler1(example: Path, backend) -> str:
    """Run the given code using the specified backend."""
    options = compiler.CompilationOptions(
        dump_ast=False, run_code=True, backend=backend
    )
    f = io.StringIO()
    runtime_filename = "runtime/std.slang"
    compiler.do_compile([example, runtime_filename], f, options)
    stdout = f.getvalue()
    return stdout


def run_code_via_compiler(example: Path, backend) -> str:
    runtime_filename = "runtime/std.slang"
    compiler_exe = "./build/compiler5"
    if backend == "vm":
        cmd = [compiler_exe, "--run", "--backend-bc", example, runtime_filename]
    elif backend == "x86":
        obj_file = example.with_suffix(".o")
        subprocess.run(
            [
                compiler_exe,
                "--backend-x86",
                "-o",
                obj_file,
                example,
                runtime_filename,
            ]
        )
        exe_file = example.with_suffix(".exe")
        subprocess.run(
            [
                "gcc",
                "-o",
                exe_file,
                obj_file,
                "./build/slangrt.o",
                "./build/slangrt_mm.o",
            ],
            check=True,
        )
        cmd = [exe_file]
    elif backend == "py":
        py_file = example.with_suffix(".py")
        subprocess.run(
            [
                compiler_exe,
                "--backend-py",
                "-o",
                py_file,
                example,
                runtime_filename,
            ]
        )
        cmd = [sys.executable, py_file]
    else:
        raise NotImplementedError(f"Backend: {backend}")
    out = subprocess.run(cmd, capture_output=True, check=True)
    return out.stdout.decode("ascii")
