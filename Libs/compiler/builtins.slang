
import ast
from datatypes import List, Option, list1, list2
from location import location_default

fn get_rt_module() -> ast.Module:
    let libname = "slangrt"
    let modname = "rt"
    let module = ast.new_module(name: modname, filename: Option.None(), imports: List(), definitions: List())
    let type_parameters: List[ast.TypeParameter] = List()

    let int_to_str = ast.extern_function_def:
        libname
        name: "int_to_str"
        type_parameters
        parameters: list1(ast.unlabeled_parameter(ty: ast.int_type()))
        return_type: ast.str_type()
        location: location_default()
    ast.module_define_function(module, function_def: int_to_str)

    let char_to_str = ast.extern_function_def:
        libname
        name: "char_to_str"
        type_parameters
        parameters: list1(ast.unlabeled_parameter(ty: ast.char_type()))
        return_type: ast.str_type()
        location: location_default()
    ast.module_define_function(module, function_def: char_to_str)

    let str_concat = ast.extern_function_def:
        libname
        name: "str_concat"
        type_parameters
        parameters: list2(ast.unlabeled_parameter(ty: ast.str_type()), ast.unlabeled_parameter(ty: ast.str_type()))
        return_type: ast.str_type()
        location: location_default()
    ast.module_define_function(module, function_def: str_concat)

    let str_compare = ast.extern_function_def:
        libname
        name: "str_compare"
        type_parameters
        parameters: list2(ast.unlabeled_parameter(ty: ast.str_type()), ast.unlabeled_parameter(ty: ast.str_type()))
        return_type: ast.bool_type()
        location: location_default()
    ast.module_define_function(module, function_def: str_compare)

    return module
