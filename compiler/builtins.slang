
import ast
from datatypes import List, Option, vec1, vec2, vec3
from location import location_default

fn get_rt_module() -> ast.Module:
    let modname = "rt"
    let module = ast.new_module(name: modname, filename: Option.None(), imports: List(), definitions: List())

    let int_to_str = ast.extern_function_def:
        modname
        name: "int_to_str"
        parameter_types: vec1(ast.int_type())
        return_type: ast.str_type()
        location: location_default()
    ast.module_define_symbol(module, name: "int_to_str", definition: ast.Definition.ExternFunction(int_to_str))

    let char_to_str = ast.extern_function_def:
        modname
        name: "char_to_str"
        parameter_types: vec1(ast.char_type())
        return_type: ast.str_type()
        location: location_default()
    ast.module_define_symbol(module, name: "char_to_str", definition: ast.Definition.ExternFunction(char_to_str))

    let str_concat = ast.extern_function_def:
        modname
        name: "str_concat"
        parameter_types: vec2(ast.str_type(), ast.str_type())
        return_type: ast.str_type()
        location: location_default()
    ast.module_define_symbol(module, name: "str_concat", definition: ast.Definition.ExternFunction(str_concat))

    let str_compare = ast.extern_function_def:
        modname
        name: "str_compare"
        parameter_types: vec2(ast.str_type(), ast.str_type())
        return_type: ast.bool_type()
        location: location_default()
    ast.module_define_symbol(module, name: "str_compare", definition: ast.Definition.ExternFunction(str_compare))

    return module
