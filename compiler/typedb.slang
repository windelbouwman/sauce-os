
# Functions to serialize type definitions to JSON.

from std import print
from utils import unimplemented, panic
from utils import log_error, log_info, log_debug
from datatypes import List, Option
from hashmap import HashMap
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

    let saver = SymbolSaver()

    saver.ser.begin_object()
    saver.ser.add_text_attribute(name: "compiler-version", text: "2024")
    saver.ser.begin_array()
    for module in module_set.modules:
        # ast.visit_module(visitor, module)
        log_info("Saving meta-info for module: {module.name}")
        if module.name == "rt":
            continue
        
        saver.save_module(module)
    
    saver.ser.end_array_as_attribute(name: "modules")
    let obj = saver.ser.end_object()
    write_json_to_file(filename, obj)

class SymbolSaver:
    var ser: JsonBuilder = JsonBuilder()

    fn save_module(module: ast.Module):
        ser.begin_object()
        ser.add_text_attribute(name: "name", text: module.name)
        ser.begin_array()
        for definition in module.definitions:
            case definition:
                Function(function_def):
                    save_function_def(function_def)
                Struct(struct_def):
                    save_struct_def(struct_def)
                Class(class_def):
                    save_class_def(class_def)
                Enum(enum_def):
                    save_enum_def(enum_def)
                ExternFunction(extern_function_def):
                    save_extern_function_def(extern_function_def)
                Var(var_def):
                    log_error("TODO: var def")
        ser.end_array_as_attribute(name: "definitions")
        ser.end_object_as_element()

    fn save_enum_def(enum_def: ast.EnumDef):
        log_debug("enum-def: {ast.node_id_to_string(enum_def.id)}")
        ser.begin_object()
        ser.add_text_attribute(name: "kind", text: "enum")
        save_id(id: enum_def.id)
        save_type_parameters(type_parameters: enum_def.type_parameters)

        ser.begin_array()
        for variant in enum_def.variants:
            ser.begin_object()
            ser.add_text_attribute(name: "name", text: variant.name)
            ser.begin_array()
            for payload in variant.payload:
                ser.begin_object()
                save_type(name: "type", ty: payload)
                ser.end_object_as_element()
            ser.end_array_as_attribute(name: "payload")
            ser.end_object_as_element()
        ser.end_array_as_attribute(name: "variants")

        ser.end_object_as_element()

    fn save_class_def(class_def: ast.ClassDef):
        log_debug("   class-def: {ast.node_id_to_string(class_def.id)}")
        ser.begin_object()
        ser.add_text_attribute(name: "kind", text: "class")
        save_id(id: class_def.id)
        save_type_parameters(type_parameters: class_def.type_parameters)
        ser.end_object_as_element()

    fn save_function_def(function_def: ast.FunctionDef):
        log_debug("Saving meta-info for func-def: {ast.node_id_to_string(function_def.id)}")
        ser.begin_object()
        ser.add_text_attribute(name: "kind", text: "function")
        save_id(id: function_def.id)
        save_type_parameters(type_parameters: function_def.type_parameters)

        # Parameters
        ser.begin_array()
        for parameter_def in function_def.parameters:
            ser.begin_object()
            ser.add_text_attribute(name: "name", text: parameter_def.id.name)
            save_type(name: "type", ty: parameter_def.ty)
            ser.end_object_as_element()
        ser.end_array_as_attribute(name: "parameters")
        save_function_info(info: function_def.info)
        ser.end_object_as_element()

    fn save_extern_function_def(extern_function_def: ast.ExternFunctionDef):
        log_debug("Saving meta-info for extern-func-def: {extern_function_def.name}")
        ser.begin_object()
        ser.add_text_attribute(name: "kind", text: "extern-function")
        ser.add_text_attribute(name: "modname", text: extern_function_def.modname)
        ser.add_text_attribute(name: "name", text: extern_function_def.name)
        ser.add_integer_attribute(name: "id", value: 0)
        save_type_parameters(type_parameters: extern_function_def.type_parameters)

        # Parameters
        ser.begin_array()
        for parameter_type in extern_function_def.parameter_types:
            ser.begin_object()
            case parameter_type.label:
                Some(text):
                    ser.add_text_attribute(name: "name", text)
                None:
                    pass
            save_type(name: "type", ty: parameter_type.ty)
            ser.end_object_as_element()
        ser.end_array_as_attribute(name: "parameters")
        save_function_info(info: extern_function_def.info)
        ser.end_object_as_element()
    
    fn save_function_info(info: ast.FunctionInfo):
        save_type(name: "return-type", ty: info.return_type)
        save_type(name: "except-type", ty: info.except_type)
        ser.add_boolean_attribute(name: "no-return", value: info.no_return)

    fn save_struct_def(struct_def: ast.StructDef):
        log_debug("Saving meta-info for struct-def: {ast.node_id_to_string(struct_def.id)}")
        ser.begin_object()

        # Name:
        ser.add_text_attribute(name: "kind", text: "struct")
        save_id(id: struct_def.id)
        save_type_parameters(type_parameters: struct_def.type_parameters)

        # Fields
        ser.begin_array()
        for field in struct_def.fields:
            ser.begin_object()
            ser.add_text_attribute(name: "name", text: field.name)
            save_type(name: "type", ty: field.ty)
            ser.end_object_as_element()
            
        ser.end_array_as_attribute(name: "fields")

        ser.end_object_as_element()

    fn save_type_parameters(type_parameters: List[ast.TypeParameter]):
        ser.begin_array()
        for type_parameter in type_parameters:
            ser.begin_object()
            save_id(id: type_parameter.id)
            ser.end_object_as_element()
        ser.end_array_as_attribute(name: "type-parameters")

    fn save_type(name: str, ty: ast.Type):
        ser.begin_object()
        if ast.is_int_type(ty):
            ser.add_text_attribute(name: "kind", text: "int")
        elif ast.is_str_type(ty):
            ser.add_text_attribute(name: "kind", text: "str")
        elif ast.is_float_type(ty):
            ser.add_text_attribute(name: "kind", text: "float")
        elif ast.is_bool_type(ty):
            ser.add_text_attribute(name: "kind", text: "bool")
        elif ast.is_char_type(ty):
            ser.add_text_attribute(name: "kind", text: "char")
        elif ast.is_void_type(ty):
            ser.add_text_attribute(name: "kind", text: "void")
        elif ast.is_array_type(ty):
            ser.add_text_attribute(name: "kind", text: "array")
            let element_type = ast.get_element_type_from_type(ty)
            save_type(name: "element_type", ty: element_type)
            # TODO: size
            let size = 0
            ser.add_integer_attribute(name: "size", value: size)
        elif ast.is_type_parameter_type(ty):
            ser.add_text_attribute(name: "kind", text: "type-parameter")
            let type_parameter = ast.get_type_parameter_from_type(ty)
            save_id(id: type_parameter.id)
        elif ast.is_tycon_app_type(ty):
            ser.add_text_attribute(name: "kind", text: "app")
            let tycon = ast.get_tycon_from_type(ty)
            let type_arguments = ast.get_type_arguments_from_type(ty)

            case ast.get_tycon_from_type(ty):
                Struct(struct_def):
                    save_id(id: struct_def.id)
                Enum(enum_def):
                    save_id(id: enum_def.id)
                Class(class_def):
                    save_id(id: class_def.id)

            ser.begin_array()
            for type_argument in type_arguments:
                ser.begin_object()
                save_type(name: "type", ty: type_argument)
                ser.end_object_as_element()
            ser.end_array_as_attribute(name: "type-arguments")
        elif ast.is_function_type(ty):
            ser.add_text_attribute(name: "kind", text: "function")
            let parameter_types = ast.get_parameter_types_from_type(ty)
            let return_type = ast.get_return_type_from_type(ty)
            let except_type = ast.get_except_type_from_type(ty)
            ser.begin_array()
            for parameter_type in parameter_types:
                ser.begin_object()
                save_type(name: "type", ty: parameter_type.ty)
                ser.end_object_as_element()
            ser.end_array_as_attribute(name: "argument-types")
            save_type(name: "return-type", ty: return_type)
            save_type(name: "except-type", ty: except_type)
        else:
            panic("Not-impl: {ast.type_to_string(ty)}")
            # ser.add_text_attribute(name, text: "todo")
        ser.end_object_as_attribute(name)

    fn save_id(id: ast.NodeId):
        ser.add_text_attribute(name: "name", text: id.name)
        ser.add_integer_attribute(name: "id", value: id.id)


fn load_symbol_table(filename: str) -> List[ast.Module]:
    log_info("Read type info from: {filename}")
    let loader = SymbolLoader()
    try:
        let obj = read_json_from_file(filename)
        loader.push_json(value: obj)
    except (oei : JsonException):
        panic("Invalid json at {oei.pos}: {oei.message}")

    let compiler_version_info = loader.m_des.get_text_attribute(name: "compiler-version")
    let modules: List[ast.Module] = List()
    log_info("Compiler-info: {compiler_version_info}")
    for module_obj in loader.m_des.get_array_attribute(name: "modules"):
        loader.m_des.push_value(value: module_obj)
        let module = loader.load_module()
        loader.m_des.pop_value()
        modules.append(module)
    loader.do_fixup()
    
    return modules

class SymbolLoader:
    var m_des: JsonBrowser = JsonBrowser()
    var m_to_resolve: List[ToResolve] = List()
    var m_tycon_map: HashMap[ast.TyCon] = HashMap()
    var m_typar_map: HashMap[ast.TypeParameter] = HashMap()

    fn push_json(value: JsonValue):
        m_des.push_value(value)
    
    fn load_module() -> ast.Module:
        let mod_name = m_des.get_text_attribute(name: "name")
        log_debug("Load info for module: {mod_name}")

        let definitions: List[ast.Definition] = List()

        for definition_obj in m_des.get_array_attribute(name: "definitions"):
            m_des.push_value(value: definition_obj)
            let definition = load_definition()
            m_des.pop_value()
            definitions.append(definition)
        let module = ast.new_module(name: mod_name, filename: Option.None(), imports: List(), definitions)
        return module

    fn load_definition() -> ast.Definition:
        let def_kind = m_des.get_text_attribute(name: "kind")
        let def_name = m_des.get_text_attribute(name: "name")
        let def_id = m_des.get_integer_attribute(name: "id")
        log_debug("  --> DEF-{def_kind}: {def_name} / {def_id}")
        if def_kind == "function":
            let exten_function_def = load_function(def_name, def_id)
            return ast.Definition.ExternFunction(exten_function_def)
        elif def_kind == "extern-function":
            let exten_function_def = load_extern_function(def_name)
            return ast.Definition.ExternFunction(exten_function_def)
        elif def_kind == "struct":
            let struct_def = load_struct_def(def_name, def_id)
            m_tycon_map.insert(key: "{struct_def.id.id}", value: ast.TyCon.Struct(struct_def))
            return ast.Definition.Struct(struct_def)
        elif def_kind == "enum":
            let enum_def = load_enum_def(def_name, def_id)
            m_tycon_map.insert(key: "{enum_def.id.id}", value: ast.TyCon.Enum(enum_def))
            return ast.Definition.Enum(enum_def)
        else:
            panic("Not implemented definition kind: {def_kind}")

    fn load_function(def_name: str, def_id: int) -> ast.ExternFunctionDef:
        let type_parameters = load_type_parameters()
        let parameter_types = load_parameter_types()
        let return_type = load_type(attr: "return-type")
        let f = ast.extern_function_def:
            modname: "X{def_id}"  # Some sort of hack to be able to call external function
            name: def_name
            type_parameters
            parameter_types
            return_type
            location: location_default()
        return f

    fn load_extern_function(def_name: str) -> ast.ExternFunctionDef:
        let type_parameters = load_type_parameters()
        let parameter_types = load_parameter_types()
        let modname = m_des.get_text_attribute(name: "modname")
        let return_type = load_type(attr: "return-type")
        let f = ast.extern_function_def:
            modname
            name: def_name
            type_parameters
            parameter_types
            return_type
            location: location_default()
        return f
    
    fn load_parameter_types() -> List[ast.ParameterType]:
        let parameter_types: List[ast.ParameterType] = List()
        for parameter_obj in m_des.get_array_attribute(name: "parameters"):
            m_des.push_value(value: parameter_obj)
            let label: Option[str] = Option.None()
            if m_des.has_attribute(name: "name"):
                label = Option.Some(m_des.get_text_attribute(name: "name"))
            parameter_types.append(ast.ParameterType(label, ty: load_type(attr: "type")))
            m_des.pop_value()
        return parameter_types

    fn load_struct_def(def_name: str, def_id: int) -> ast.StructDef:
        let builder = ast.StructBuilder()
        builder.set_name(name: def_name)
        builder.set_id(id: def_id)
        let type_parameters = load_type_parameters()
        for field_obj in m_des.get_array_attribute(name: "fields"):
            m_des.push_value(value: field_obj)
            let field_name = m_des.get_text_attribute(name: "name")
            let field_type = load_type(attr: "type")
            builder.add_field(name: field_name, ty: field_type, location: location_default())
            m_des.pop_value()
        let struct_def = builder.finish()
        struct_def.scope = ast.Scope()
        return struct_def
    
    fn load_enum_def(def_name: str, def_id: int) -> ast.EnumDef:
        let location = location_default()
        let type_parameters = load_type_parameters()
        let variants: List[ast.EnumVariant] = List()
        for variant_obj in m_des.get_array_attribute(name: "variants"):
            m_des.push_value(value: variant_obj)
            let variant_name = m_des.get_text_attribute(name: "name")
            let payload = load_types(attr: "payload")
            let variant = ast.EnumVariant(name: variant_name, tag_value: 0, location, payload)
            variants.append(variant)
            m_des.pop_value()

        return ast.enum_def(name: def_name, id: def_id, location, type_parameters, variants)

    fn load_type_parameters() -> List[ast.TypeParameter]:
        let type_parameters: List[ast.TypeParameter] = List()
        for type_parameter_obj in m_des.get_array_attribute(name: "type-parameters"):
            m_des.push_value(value: type_parameter_obj)
            let id = load_id()
            let location = location_default()
            let type_parameter = ast.new_type_parameter(name: id.name, id: id.id, location)
            m_typar_map.insert(key: "{id.id}", value: type_parameter)
            type_parameters.append(type_parameter)
            m_des.pop_value()
        return type_parameters

    fn load_types(attr: str) -> List[ast.Type]:
        let types: List[ast.Type] = List()
        for type_argument_obj in m_des.get_array_attribute(name: attr):
            m_des.push_value(value: type_argument_obj)
            types.append(load_type(attr: "type"))
            m_des.pop_value()
        return types

    fn load_type(attr: str) -> ast.Type:
        let ty = ast.undefined_type()
        m_des.enter_attribute(name: attr)
        let type_name = m_des.get_text_attribute(name: "kind")
        if type_name == "int":
            ty = ast.int_type()
        elif type_name == "str":
            ty = ast.str_type()
        elif type_name == "bool":
            ty = ast.bool_type()
        elif type_name == "float":
            ty = ast.float_type()
        elif type_name == "char":
            ty = ast.char_type()
        elif type_name == "void":
            ty = ast.void_type()
        elif type_name == "app":
            let type_arguments = load_types(attr: "type-arguments")
            ty = ast.undefined_type()
            let id = load_id()
            fixup_later(ToResolve.App(ty, id: id.id, type_arguments))
        elif type_name == "type-parameter":
            let id = load_id()
            let type_parameter = m_typar_map.get(key: "{id.id}")
            ty = ast.type_parameter_ref(type_parameter)
        else:
            panic("Unsupported: {type_name}")
        
        m_des.pop_value()
        return ty
    
    fn load_id() -> ast.NodeId:
        let id = m_des.get_integer_attribute(name: "id")
        let name = m_des.get_text_attribute(name: "name")
        return ast.NodeId(id, name)

    fn fixup_later(r?: ToResolve):
        m_to_resolve.append(r)
    
    fn do_fixup():
        for r in m_to_resolve:
            case r:
                App(ty, id, type_arguments):
                    log_info("App id: {id}")
                    let tycon = m_tycon_map.get(key: "{id}")
                    let ty2 = ast.apply_tycon(tycon, type_arguments)
                    ast.change_type_to(ty, ty2)

enum ToResolve:
    App(ty: ast.Type, id: int, type_arguments: List[ast.Type])

