"""
Idea: generate slang code with the hypothesis library, and run through the compiler.

This might be useful:

https://hypothesis.readthedocs.io/en/latest/extras.html#hypothesis.extra.lark.from_lark

Run with:

$ pytest test_fuzzy.py --hypothesis-show-statistics


"""

import io
import tempfile
import sys
import subprocess
import string
from dataclasses import dataclass
from pathlib import Path
from compiler1 import compiler
from compiler1.lexer import KEYWORDS
from hypothesis import strategies as st
from hypothesis import given, settings

this_path = Path(__file__).resolve().parent
reserved_identifiers = [
    # pre-defined:
    "true",
    "false",
    "null",
    "main",
    # Types:
    "str",
    "char",
    "int",
    "float",
    "bool",
    "uint8",
    "uint16",
    "uint32",
    "uint64",
    "int8",
    "int16",
    "int32",
    "int64",
    "float32",
    "float64",
    "unreachable",
]

bit_operators = st.sampled_from(["^", "|", "&", ">>", "<<"])
arithmatic_operators = st.sampled_from(["+", "-"])  # TODO: add '*', '/' and '%'
comparison_operators = st.sampled_from(["==", "!=", ">", "<", ">=", "<="])


class Context:
    def __init__(self, func_pool, var_pool):
        self.func_pool = func_pool
        self.var_pool = var_pool

    def add_variable(self, name):
        self.var_pool.append(name)


@dataclass
class FunctionDef:
    name: str
    parameters: list[str]


def expression_const() -> str:
    return st.integers(min_value=0, max_value=4500).map(str)


def expression_var(context: Context):
    return st.sampled_from(context.var_pool)


@st.composite
def expression_binop(draw, context: Context, level) -> str:
    lhs = draw(expression(context, level=level + 1))
    op = draw(arithmatic_operators)
    rhs = draw(expression(context, level=level + 1))
    return f"({lhs} {op} {rhs})"


@st.composite
def expression_call(draw, context: Context, level) -> str:
    f = draw(st.sampled_from(context.func_pool))
    args = []
    for p_name in f.parameters:
        arg = draw(expression(context, level=level + 1))
        args.append(f"{p_name}: {arg}")
    arg_text = ", ".join(args)
    return f"{f.name}({arg_text})"


def expression(context: Context, level=0):
    expr = expression_const()
    if context.var_pool:
        expr = expr | expression_var(context)
    if context.func_pool and level < 2:
        expr = expr | expression_call(context, level)
    if level < 2:
        expr = expr | expression_binop(context, level)
    return expr


identifier = st.text(alphabet=string.ascii_letters, min_size=3, max_size=7)


@st.composite
def unused_identifier(draw, context: Context):
    bad = set(reserved_identifiers)
    bad |= KEYWORDS
    bad |= set(context.var_pool)
    bad |= set(f.name for f in context.func_pool)

    base = draw(identifier)

    if base in bad:
        i = 0
        while True:
            candidate = f"{base}_{i}"
            if candidate in bad:
                i += 1
            else:
                return candidate
    else:
        return base


@st.composite
def function_def(draw, context: Context):
    context = Context(context.func_pool, [])
    n_param = draw(st.integers(min_value=0, max_value=13))
    p_names = []
    for _ in range(n_param):
        p_name = draw(unused_identifier(context))
        context.add_variable(p_name)
        p_names.append(p_name)
    body = draw(some_statements(context))
    body.append(draw(expression(context)))
    name = draw(unused_identifier(context))
    context.func_pool.append(FunctionDef(name, p_names))
    p_text = ", ".join(f"{n}: int" for n in p_names)
    decl = f"fn {name}({p_text}) -> int:"
    return [decl] + indented(body) + [""]


def indented(lines: list[str]) -> list[str]:
    return ["\t" + line for line in lines]


@st.composite
def statement_print(draw, context: Context):
    expr = draw(expression(context))
    return [f"print(int_to_str({expr}))"]


@st.composite
def statement_let(draw, context: Context):
    expr = draw(expression(context))
    varname = draw(unused_identifier(context))
    context.add_variable(varname)
    return [f"let {varname} = {expr}"]


@st.composite
def statement_if(draw, context: Context, level):
    lhs = draw(expression(context))
    op = draw(comparison_operators)
    rhs = draw(expression(context))
    yes = indented(draw(scoped_block(context, level + 1)))
    no = indented(draw(scoped_block(context, level + 1)))
    return [f"if {lhs} {op} {rhs}:"] + yes + ["else:"] + no


def scoped_block(context: Context, level):
    context = Context(context.func_pool, list(context.var_pool))
    return some_statements(context, level=level)


def statement(context: Context, level=0):
    s = statement_print(context) | statement_let(context)
    if level < 2:
        s = s | statement_if(context, level)
    return s


@st.composite
def some_statements(draw, context: Context, level=0):
    code = []
    n_statements = draw(st.integers(min_value=1, max_value=2))
    for _ in range(n_statements):
        code.extend(draw(statement(context)))
    return code


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
    context = Context([], [])
    for _ in range(n_funcs):
        module.extend(draw(function_def(context)))
    # Main body:
    main_body = draw(some_statements(context))
    main_body.append("0")
    main_function = ["fn main() -> int:"] + indented(main_body)
    module.extend(main_function)
    return module


@given(slang_module())
@settings(max_examples=50, deadline=10000)
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
    runtime_filename = this_path / "runtime" / "std.slang"
    compiler.do_compile([example, runtime_filename], f, options)
    stdout = f.getvalue()
    return stdout


def run_code_via_compiler(example: Path, backend) -> str:
    runtime_filename = this_path / "runtime" / "std.slang"
    compiler_exe = this_path / "build" / "compiler5"
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
            ],
            check=True,
        )
        exe_file = example.with_suffix(".exe")
        subprocess.run(
            [
                "gcc",
                "-o",
                exe_file,
                obj_file,
                this_path / "build" / "slangrt.o",
                this_path / "build" / "slangrt_mm.o",
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
            ],
            check=True,
        )
        cmd = [sys.executable, py_file]
    else:
        raise NotImplementedError(f"Backend: {backend}")
    out = subprocess.run(cmd, capture_output=True, check=True)
    return out.stdout.decode("ascii")
