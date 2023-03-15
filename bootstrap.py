
""" Helper script to bootstrap the compiler

Use the python based bootstrap compiler to compile the compiler itself.

"""

from compiler1 import compiler, errors

options = compiler.CompilationOptions()
sources = [
    'compiler/ast.slang',
    'compiler/token.slang',
    'compiler/main.slang',
    'compiler/lexer.slang',
    'compiler/parsing.slang',
    'compiler/location.slang',
]

try:
    compiler.do_compile(sources, None, options)
except errors.CompilationError as ex:
    print('ERRORS')
    errors.print_errors(ex.errors)
else:
    print('OK')
