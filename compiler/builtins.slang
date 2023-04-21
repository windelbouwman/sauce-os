
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

    let std_exit = ast.ExternFunctionDef:
        name: "exit"
        parameter_types: List()
        return_type: Option.None()
    ast.module_define_symbol(m, ast.Definition.ExternFunction(std_exit))
    return m
