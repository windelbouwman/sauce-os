
import ast
from datatypes import List, Option, vec1, vec2, vec3

fn get_std_module() -> ast.Module:
    let module = ast.new_module(name: "std", imports: List(), definitions: List())

    let std_print = ast.ExternFunctionDef:
        name: "print"
        parameter_types: vec1(ast.str_type())
        return_type: ast.void_type()
    ast.module_define_symbol(module, definition: ast.Definition.ExternFunction(extern_function: std_print))

    let std_int_to_str = ast.ExternFunctionDef:
        name: "int_to_str"
        parameter_types: vec1(ast.int_type())
        return_type: ast.str_type()
    ast.module_define_symbol(module, definition: ast.Definition.ExternFunction(std_int_to_str))

    let std_str_to_int = ast.ExternFunctionDef:
        name: "str_to_int"
        parameter_types: vec1(ast.str_type())
        return_type: ast.int_type()
    ast.module_define_symbol(module, definition: ast.Definition.ExternFunction(std_str_to_int))

    let std_exit = ast.ExternFunctionDef:
        name: "exit"
        parameter_types: vec1(ast.int_type())
        return_type: ast.void_type()
    ast.module_define_symbol(module, definition: ast.Definition.ExternFunction(std_exit))

    let std_read_file = ast.ExternFunctionDef:
        name: "read_file"
        parameter_types: vec1(ast.str_type())
        return_type: ast.str_type()
    ast.module_define_symbol(module, definition: ast.Definition.ExternFunction(std_read_file))

    let std_ord = ast.ExternFunctionDef:
        name: "ord"
        parameter_types: vec1(ast.str_type())
        return_type: ast.int_type()
    ast.module_define_symbol(module, definition: ast.Definition.ExternFunction(std_ord))

    let std_str_len = ast.ExternFunctionDef:
        name: "str_len"
        parameter_types: vec1(ast.str_type())
        return_type: ast.int_type()
    ast.module_define_symbol(module, definition: ast.Definition.ExternFunction(std_str_len))

    let std_str_slice = ast.ExternFunctionDef:
        name: "str_slice"
        parameter_types: vec3(ast.str_type(), ast.int_type(), ast.int_type())
        return_type: ast.str_type()
    ast.module_define_symbol(module, definition: ast.Definition.ExternFunction(std_str_slice))

    let std_str_get = ast.ExternFunctionDef:
        name: "str_get"
        parameter_types: vec2(ast.str_type(), ast.int_type())
        return_type: ast.str_type()
    ast.module_define_symbol(module, definition: ast.Definition.ExternFunction(std_str_get))

    return module
