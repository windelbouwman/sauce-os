
import ast
from datatypes import List, Option

fn get_std_module() -> ast.Module:
    let m = ast.new_module("std", List(), List())

    let std_print = ast.ExternFunctionDef:
        name: "print"
        parameter_types: List()
        return_type: Option.None()
    ast.module_define_symbol(m, ast.Definition.ExternFunction(std_print))

    let std_int_to_str = ast.ExternFunctionDef:
        name: "int_to_str"
        parameter_types: List()
        return_type: Option.None()
    ast.module_define_symbol(m, ast.Definition.ExternFunction(std_int_to_str))

    let std_str_to_int = ast.ExternFunctionDef:
        name: "str_to_int"
        parameter_types: List()
        return_type: Option.None()
    ast.module_define_symbol(m, ast.Definition.ExternFunction(std_str_to_int))

    let std_exit = ast.ExternFunctionDef:
        name: "exit"
        parameter_types: List()
        return_type: Option.None()
    ast.module_define_symbol(m, ast.Definition.ExternFunction(std_exit))

    let std_read_file = ast.ExternFunctionDef:
        name: "read_file"
        parameter_types: List()
        return_type: Option.None()
    ast.module_define_symbol(m, ast.Definition.ExternFunction(std_read_file))

    let std_ord = ast.ExternFunctionDef:
        name: "ord"
        parameter_types: List()
        return_type: Option.None()
    ast.module_define_symbol(m, ast.Definition.ExternFunction(std_ord))

    let std_str_len = ast.ExternFunctionDef:
        name: "str_len"
        parameter_types: List()
        return_type: Option.None()
    ast.module_define_symbol(m, ast.Definition.ExternFunction(std_str_len))

    let std_str_slice = ast.ExternFunctionDef:
        name: "str_slice"
        parameter_types: List()
        return_type: Option.None()
    ast.module_define_symbol(m, ast.Definition.ExternFunction(std_str_slice))

    let std_str_get = ast.ExternFunctionDef:
        name: "str_get"
        parameter_types: List()
        return_type: Option.None()
    ast.module_define_symbol(m, ast.Definition.ExternFunction(std_str_get))

    return m
