
# Functions to serialize type definitions to JSON.

from std import print
from utils import unimplemented, panic
from utils import log_info
from datatypes import List, Option
from json import JsonBuilder, JsonException, write_json_to_file, read_json_from_file
from json import JsonValue, JsonBrowser
from location import location_default
import ast

fn store_symbol_table(module_set: ast.ModuleSet, filename: str):
    # Save symbol table for later use.
    # This is useful when saving a symbol table
    # to file.
    # This is done when compiling a library. When using this library
    # we must reload types from this stored data.
    log_info("Saving type info to: {filename}")

    # TODO: we could use ast.Visitor here

    let ser = JsonBuilder()

    ser.begin_object()
    ser.add_text_attribute(name: "compiler-version", text: "2024")
    ser.begin_array()
    for module in module_set.modules:
        # ast.visit_module(visitor, module)
        print("module: {module.name}")
        if module.name == "rt":
            continue

        ser.begin_object()
        ser.add_text_attribute(name: "name", text: module.name)
        ser.begin_array()
        for definition in module.definitions:
            case definition:
                Function(function_def):
                    print("   func-def: {ast.node_id_to_string(function_def.id)}")
                    ser.begin_object()

                    # Name:
                    ser.add_text_attribute(name: "kind", text: "function")
                    ser.add_text_attribute(name: "name", text: function_def.id.name)
                    ser.add_integer_attribute(name: "id", value: function_def.id.id)

                    # Parameters
                    ser.begin_array()
                    for parameter_def in function_def.parameters:
                        ser.begin_object()
                        ser.add_text_attribute(name: "name", text: parameter_def.id.name)
                        ser.add_text_attribute(name: "type", text: "int")  # TODO!
                        ser.end_object_as_element()
                    ser.end_array_as_attribute(name: "parameters")
                    ser.add_text_attribute(name: "return-type", text: "TODO")

                    ser.end_object_as_element()

                Struct(struct_def):
                    print("   struct-def: {ast.node_id_to_string(struct_def.id)}")
                Class(class_def):
                    print("   class-def: {ast.node_id_to_string(class_def.id)}")
                Enum(enum_def):
                    print("   enum-def: {ast.node_id_to_string(enum_def.id)}")
            else:
                print("Unsupp def")
        ser.end_array_as_attribute(name: "definitions")
        ser.end_object_as_element()
    
    ser.end_array_as_attribute(name: "modules")
    let obj = ser.end_object()
    write_json_to_file(filename, obj)

fn load_symbol_table(filename: str) -> List[ast.Module]:
    log_info("Read type info from: {filename}")
    let des = JsonBrowser()
    try:
        let obj = read_json_from_file(filename)
        des.push_value(value: obj)
    except (oei : JsonException):
        panic("Invalid json at {oei.pos}: {oei.message}")

    let compiler_version_info = des.get_text_attribute(name: "compiler-version")
    let modules: List[ast.Module] = List()
    log_info("Compiler-info: {compiler_version_info}")
    for module_obj in des.get_array_attribute(name: "modules"):
        des.push_value(value: module_obj)

        let mod_name = des.get_text_attribute(name: "name")
        print("Module: {mod_name}")
        let module = ast.new_module(name: mod_name, filename: Option.None(), imports: List(), definitions: List())
        modules.append(module)

        for definition_obj in des.get_array_attribute(name: "definitions"):
            des.push_value(value: definition_obj)
            let def_name = des.get_text_attribute(name: "name")
            let def_id = des.get_integer_attribute(name: "id")
            let def_kind = des.get_text_attribute(name: "kind")
            print("  --> DEF-{def_kind}: {def_name}")
            if def_kind == "function":
                let parameter_types: List[ast.Type] = List()
                for parameter_obj in des.get_array_attribute(name: "parameters"):
                    des.push_value(value: parameter_obj)
                    parameter_types.append(ast.int_type())
                    des.pop_value()

                let exten_function_def = ast.extern_function_def:
                    modname: "X{def_id}"  # Some sort of hack to be able to call external function
                    name: def_name
                    parameter_types
                    return_type: ast.int_type()
                    location: location_default()
                ast.module_define_symbol(module, name: def_name, definition: ast.Definition.ExternFunction(exten_function_def))

            des.pop_value()

        des.pop_value()
    
    return modules
