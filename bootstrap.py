
from compiler1 import compiler, errors

options = compiler.CompilationOptions()
sources = [
    'compiler/ast.slang'
]
known_modules = {'std': compiler.std_module()}

try:
    compiler.do_compile(sources, None, known_modules, options)
except errors.CompilationError as ex:
    print('ERRORS')
    errors.print_errors(ex.errors)
else:
    print('OK')
