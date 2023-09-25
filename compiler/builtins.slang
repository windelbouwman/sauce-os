
import ast
from datatypes import List, Option, vec1, vec2, vec3

fn get_std_module() -> ast.Module:
    let module = ast.new_module(name: "std", filename: Option.None(), imports: List(), definitions: List())

    let std_print = ast.ExternFunctionDef:
        name: "std_print"
        parameter_types: vec1(ast.str_type())
        return_type: ast.void_type()
    ast.module_define_symbol(module, name: "print", definition: ast.Definition.ExternFunction(extern_function: std_print))

    let std_int_to_str = ast.ExternFunctionDef:
        name: "std_int_to_str"
        parameter_types: vec1(ast.int_type())
        return_type: ast.str_type()
    ast.module_define_symbol(module, name: "int_to_str", definition: ast.Definition.ExternFunction(std_int_to_str))

    let std_str_to_int = ast.ExternFunctionDef:
        name: "std_str_to_int"
        parameter_types: vec1(ast.str_type())
        return_type: ast.int_type()
    ast.module_define_symbol(module, name: "str_to_int", definition: ast.Definition.ExternFunction(std_str_to_int))

    let std_str_to_float = ast.ExternFunctionDef:
        name: "std_str_to_float"
        parameter_types: vec1(ast.str_type())
        return_type: ast.float_type()
    ast.module_define_symbol(module, name: "str_to_float", definition: ast.Definition.ExternFunction(std_str_to_float))

    let std_float_to_str = ast.ExternFunctionDef:
        name: "std_float_to_str"
        parameter_types: vec1(ast.float_type())
        return_type: ast.str_type()
    ast.module_define_symbol(module, name: "float_to_str", definition: ast.Definition.ExternFunction(std_float_to_str))

    let std_exit = ast.ExternFunctionDef:
        name: "std_exit"
        parameter_types: vec1(ast.int_type())
        return_type: ast.void_type()
    ast.module_define_symbol(module, name: "exit", definition: ast.Definition.ExternFunction(std_exit))

    let std_read_file = ast.ExternFunctionDef:
        name: "std_read_file"
        parameter_types: vec1(ast.str_type())
        return_type: ast.str_type()
    ast.module_define_symbol(module, name: "read_file", definition: ast.Definition.ExternFunction(std_read_file))

    let std_ord = ast.ExternFunctionDef:
        name: "std_ord"
        parameter_types: vec1(ast.str_type())
        return_type: ast.int_type()
    ast.module_define_symbol(module, name: "ord", definition: ast.Definition.ExternFunction(std_ord))

    let std_chr = ast.ExternFunctionDef:
        name: "std_chr"
        parameter_types: vec1(ast.int_type())
        return_type: ast.str_type()
    ast.module_define_symbol(module, name: "chr", definition: ast.Definition.ExternFunction(std_chr))

    let std_str_len = ast.ExternFunctionDef:
        name: "std_str_len"
        parameter_types: vec1(ast.str_type())
        return_type: ast.int_type()
    ast.module_define_symbol(module, name: "str_len", definition: ast.Definition.ExternFunction(std_str_len))

    let std_str_slice = ast.ExternFunctionDef:
        name: "std_str_slice"
        parameter_types: vec3(ast.str_type(), ast.int_type(), ast.int_type())
        return_type: ast.str_type()
    ast.module_define_symbol(module, name: "str_slice", definition: ast.Definition.ExternFunction(std_str_slice))

    let std_str_get = ast.ExternFunctionDef:
        name: "std_str_get"
        parameter_types: vec2(ast.str_type(), ast.int_type())
        return_type: ast.str_type()
    ast.module_define_symbol(module, name: "str_get", definition: ast.Definition.ExternFunction(std_str_get))

    # TODO: call this rt (runtime) or std (builtin standard library)?
    let std_str_concat = ast.ExternFunctionDef:
        name: "rt_str_concat"
        parameter_types: vec2(ast.str_type(), ast.str_type())
        return_type: ast.str_type()
    ast.module_define_symbol(module, name: "str_concat", definition: ast.Definition.ExternFunction(std_str_concat))

    let std_get_n_args = ast.ExternFunctionDef:
        name: "std_get_n_args"
        parameter_types: List()
        return_type: ast.int_type()
    ast.module_define_symbol(module, name: "get_n_args", definition: ast.Definition.ExternFunction(std_get_n_args))

    let std_get_arg = ast.ExternFunctionDef:
        name: "std_get_arg"
        parameter_types: vec1(ast.int_type())
        return_type: ast.str_type()
    ast.module_define_symbol(module, name: "get_arg", definition: ast.Definition.ExternFunction(std_get_arg))

    return module
