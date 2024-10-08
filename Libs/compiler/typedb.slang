
# Functions to serialize type definitions to JSON.

from std import print
from utils import unimplemented, panic
from utils import log_error, log_info, log_debug, log_trace
from datatypes import List, Option, option_is_some
from hashmap import HashMap
from pathlib import basename
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
    let libname = basename(path: filename)
    let saver = SymbolSaver(m_libname: libname)

    saver.m_ser.begin_object()
    saver.save_modules(module_set)
    let obj = saver.m_ser.end_object()
    write_json_to_file(filename, obj)

class SymbolSaver:
    var m_ser: JsonBuilder = JsonBuilder()
    var m_libname: str

    fn save_modules(module_set: ast.ModuleSet):
        m_ser.add_text_attribute(attr: "compiler-version", text: "2024")
        m_ser.add_text_attribute(attr: "libname", text: m_libname)
        m_ser.begin_array()
        for module in module_set.modules:
            if option_is_some(module.filename):
                log_info("Saving meta-info for module: {module.name}")
                save_module(module)
            else:
                log_debug("Skip saving meta-info for module: {module.name}")
        m_ser.end_array_as_attribute(attr: "modules")

    fn save_module(module: ast.Module):
        m_ser.begin_object()
        m_ser.add_text_attribute(attr: "name", text: module.name)
        m_ser.begin_array()
        for imp in module.imports:
            save_import(imp)
        m_ser.end_array_as_attribute(attr: "imports")
        m_ser.begin_array()
        for definition in module.definitions:
            save_definition(definition)
        m_ser.end_array_as_attribute(attr: "definitions")
        m_ser.end_object_as_element()
    
    fn save_import(imp: ast.Import):
        m_ser.begin_object()
        m_ser.add_text_attribute(attr: "modname", text: imp.modname)
        case imp.kind:
            Self:
                pass
            Names(names):
                m_ser.begin_array()
                for name in names:
                    m_ser.add_text_as_element(text: name)
                m_ser.end_array_as_attribute(attr: "names")
        m_ser.end_object_as_element()

    fn save_definition(definition: ast.Definition):
        log_debug("Saving {ast.definition_to_str(definition)}")
        m_ser.begin_object()
        case definition:
            Function(function_def):
                save_function_def(function_def)
            Struct(struct_def):
                save_struct_def(struct_def)
            Class(class_def):
                save_class_def(class_def)
            Enum(enum_def):
                save_enum_def(enum_def)
            Var(var_def):
                save_var_def(var_def)
        m_ser.end_object_as_element()

    fn save_var_def(var_def: ast.VariableDef):
        m_ser.add_text_attribute(attr: "kind", text: "variable")
        save_id(id: var_def.variable.id)
        save_type(attr: "type", ty: var_def.variable.ty)
        let is_initialized = false
        case var_def.value:
            Intern(value):
                is_initialized = option_is_some(value)
            Extern(libname, initialized):
                is_initialized = initialized
        m_ser.add_boolean_attribute(attr: "initialized", value: is_initialized)

    fn save_enum_def(enum_def: ast.EnumDef):
        m_ser.add_text_attribute(attr: "kind", text: "enum")
        save_id(id: enum_def.id)
        save_type_parameters(type_parameters: enum_def.type_parameters)

        m_ser.begin_array()
        for variant in enum_def.variants:
            m_ser.begin_object()
            m_ser.add_text_attribute(attr: "name", text: variant.name)
            m_ser.begin_array()
            for payload in variant.payload:
                m_ser.begin_object()
                save_type(attr: "type", ty: payload)
                m_ser.end_object_as_element()
            m_ser.end_array_as_attribute(attr: "payload")
            m_ser.end_object_as_element()
        m_ser.end_array_as_attribute(attr: "variants")

    fn save_class_def(class_def: ast.ClassDef):
        m_ser.add_text_attribute(attr: "kind", text: "class")
        save_id(id: class_def.id)
        save_type_parameters(type_parameters: class_def.type_parameters)

        m_ser.begin_array()
        for definition in class_def.definitions:
            save_definition(definition)
        m_ser.end_array_as_attribute(attr: "definitions")

    fn save_function_def(function_def: ast.FunctionDef):
        m_ser.add_text_attribute(attr: "kind", text: "function")
        m_ser.add_text_attribute(attr: "name", text: function_def.name)
        m_ser.add_integer_attribute(attr: "id", value: 0)
        save_type_parameters(type_parameters: function_def.type_parameters)

        # Parameters
        m_ser.begin_array()
        for parameter_def in function_def.parameters:
            m_ser.begin_object()
            m_ser.add_text_attribute(attr: "name", text: parameter_def.id.name)
            m_ser.add_boolean_attribute(attr: "label_is_optional", value: parameter_def.label_is_optional)
            save_type(attr: "type", ty: parameter_def.ty)
            m_ser.end_object_as_element()
        m_ser.end_array_as_attribute(attr: "parameters")
        save_function_info(info: function_def.info)

    fn save_function_info(info: ast.FunctionInfo):
        save_type(attr: "return-type", ty: info.return_type)
        save_type(attr: "except-type", ty: info.except_type)
        m_ser.add_boolean_attribute(attr: "no-return", value: info.no_return)

    fn save_struct_def(struct_def: ast.StructDef):
        log_debug("Saving meta-info for struct-def: {ast.node_id_to_string(struct_def.id)}")
        m_ser.add_text_attribute(attr: "kind", text: "struct")
        save_id(id: struct_def.id)
        save_type_parameters(type_parameters: struct_def.type_parameters)

        # Fields
        m_ser.begin_array()
        for field in struct_def.fields:
            m_ser.begin_object()
            m_ser.add_text_attribute(attr: "name", text: field.name)
            save_type(attr: "type", ty: field.ty)
            m_ser.end_object_as_element()
            
        m_ser.end_array_as_attribute(attr: "fields")

    fn save_type_parameters(type_parameters: List[ast.TypeParameter]):
        m_ser.begin_array()
        for type_parameter in type_parameters:
            m_ser.begin_object()
            save_id(id: type_parameter.id)
            m_ser.end_object_as_element()
        m_ser.end_array_as_attribute(attr: "type-parameters")

    fn save_type(attr: str, ty: ast.Type):
        m_ser.begin_object()
        if ty.is_int():
            m_ser.add_text_attribute(attr: "kind", text: "int")
            let signed = ty.is_signed_int()
            let bits = ty.get_bits()
            m_ser.add_boolean_attribute(attr: "signed", value: signed)
            m_ser.add_integer_attribute(attr: "bits", value: bits)
        elif ty.is_str():
            m_ser.add_text_attribute(attr: "kind", text: "str")
        elif ty.is_float():
            m_ser.add_text_attribute(attr: "kind", text: "float")
            let bits = ty.get_bits()
            m_ser.add_integer_attribute(attr: "bits", value: bits)
        elif ty.is_bool():
            m_ser.add_text_attribute(attr: "kind", text: "bool")
        elif ty.is_char():
            m_ser.add_text_attribute(attr: "kind", text: "char")
        elif ty.is_void():
            m_ser.add_text_attribute(attr: "kind", text: "void")
        elif ty.is_array():
            m_ser.add_text_attribute(attr: "kind", text: "array")
            let element_type = ty.get_element_type()
            save_type(attr: "element-type", ty: element_type)
            let size = ty.get_array_size()
            m_ser.add_integer_attribute(attr: "size", value: size)
        elif ty.is_type_parameter():
            m_ser.add_text_attribute(attr: "kind", text: "type-parameter")
            let type_parameter = ty.get_type_parameter()
            save_id(id: type_parameter.id)
        elif ty.is_tycon_app():
            m_ser.add_text_attribute(attr: "kind", text: "app")
            let tycon = ty.get_tycon()
            let type_arguments = ty.get_type_arguments()

            save_tycon(tycon)

            m_ser.begin_array()
            for type_argument in type_arguments:
                m_ser.begin_object()
                save_type(attr: "type", ty: type_argument)
                m_ser.end_object_as_element()
            m_ser.end_array_as_attribute(attr: "type-arguments")
        elif ty.is_function_type():
            m_ser.add_text_attribute(attr: "kind", text: "function")
            let parameter_types = ast.get_parameter_types_from_type(ty)
            let return_type = ty.get_return_type()
            let except_type = ty.get_except_type()
            m_ser.begin_array()
            for parameter_type in parameter_types:
                m_ser.begin_object()
                save_type(attr: "type", ty: parameter_type.ty)
                m_ser.end_object_as_element()
            m_ser.end_array_as_attribute(attr: "parameter-types")
            m_ser.add_boolean_attribute(attr: "no-return", value: false) # TODO
            save_type(attr: "return-type", ty: return_type)
            save_type(attr: "except-type", ty: except_type)
        else:
            panic("Not-impl: {ty}")
        m_ser.end_object_as_attribute(attr)
    
    fn save_tycon(tycon: ast.TyCon):
        case tycon:
            Struct(struct_def):
                save_id(id: struct_def.id)
            Enum(enum_def):
                save_id(id: enum_def.id)
            Class(class_def):
                save_id(id: class_def.id)
            Ref(key):
                panic("Cannot save tycon ref")

    fn save_id(id: ast.NodeId):
        m_ser.add_text_attribute(attr: "name", text: id.name)
        m_ser.add_integer_attribute(attr: "id", value: id.id)


fn load_symbol_table(filename: str) -> List[ast.Module]:
    log_info("Read type info from: {filename}")
    let loader = SymbolLoader()
    try:
        let obj = read_json_from_file(filename)
        loader.push_json(value: obj)
    except (oei : JsonException):
        panic("Invalid json at {oei.pos}: {oei.message}")

    return loader.load_modules()

class SymbolLoader:
    var m_des: JsonBrowser = JsonBrowser()
    var m_tycon_map: HashMap[ast.TyCon] = HashMap()
    var m_type_parameter_map: HashMap[ast.TypeParameter] = HashMap()
    var m_this_type: Option[ast.Type] = Option.None()
    var m_libname: str = "?"

    fn push_json(value: JsonValue):
        m_des.push_value(value)
    
    fn load_modules() -> List[ast.Module]:
        let compiler_version_info = m_des.get_text_attribute(attr: "compiler-version")
        log_info("Compiler-info: {compiler_version_info}")
        m_libname = m_des.get_text_attribute(attr: "libname")

        let modules: List[ast.Module] = List()
        for module_obj in m_des.get_array_attribute(attr: "modules"):
            m_des.push_value(value: module_obj)
            let module = load_module()
            m_des.pop_value()
            modules.append(module)

        return modules

    fn load_module() -> ast.Module:
        let mod_name = m_des.get_text_attribute(attr: "name")
        log_info("Load info for module: {mod_name}")

        let imports: List[ast.Import] = List()
        for import_obj in m_des.get_array_attribute(attr: "imports"):
            m_des.push_value(value: import_obj)
            imports.append(load_import())
            m_des.pop_value()

        let definitions: List[ast.Definition] = List()
        for definition_obj in m_des.get_array_attribute(attr: "definitions"):
            m_des.push_value(value: definition_obj)
            definitions.append(load_definition())
            m_des.pop_value()
        let module = ast.new_module(name: mod_name, filename: Option.None(), imports, definitions)
        return module
    
    fn load_import() -> ast.Import:
        let modname = m_des.get_text_attribute(attr: "modname")
        let location = location_default()
        if m_des.has_attribute(attr: "names"):
            let names: List[str] = List()
            for name_obj in m_des.get_array_attribute(attr: "names"):
                m_des.push_value(value: name_obj)
                names.append(m_des.get_text())
                m_des.pop_value()
            let kind = ast.ImportKind.Names(names)
            return ast.Import(modname, kind, location)
        else:
            let kind = ast.ImportKind.Self()
            return ast.Import(modname, kind, location)

    fn load_definition() -> ast.Definition:
        let def_kind = m_des.get_text_attribute(attr: "kind")
        let def_name = m_des.get_text_attribute(attr: "name")
        let def_id = m_des.get_integer_attribute(attr: "id")
        log_trace("  --> DEF-{def_kind}: {def_name} / {def_id}")
        if def_kind == "function":
            let function_def = load_function(def_name, def_id)
            return ast.Definition.Function(function_def)
        elif def_kind == "struct":
            let struct_def = load_struct_def(def_name, def_id)
            m_tycon_map.insert(key: "{struct_def.id.id}", value: ast.TyCon.Struct(struct_def))
            return ast.Definition.Struct(struct_def)
        elif def_kind == "enum":
            let enum_def = load_enum_def(def_name, def_id)
            m_tycon_map.insert(key: "{enum_def.id.id}", value: ast.TyCon.Enum(enum_def))
            return ast.Definition.Enum(enum_def)
        elif def_kind == "class":
            let class_def = load_class_def(def_name, def_id)
            m_tycon_map.insert(key: "{class_def.id.id}", value: ast.TyCon.Class(class_def))
            return ast.Definition.Class(class_def)
        elif def_kind == "variable":
            let variable_def = load_variable_def(def_name, def_id)
            return ast.Definition.Var(variable_def)
        else:
            panic("Not implemented definition kind: {def_kind}")

    fn load_variable_def(def_name: str, def_id: int) -> ast.VariableDef:
        let id = ast.NodeId(name: def_name, id: def_id)
        let ty = load_type(attr: "type")
        let location = location_default()
        let variable = ast.Variable(id, ty, location)
        let is_initialized = m_des.get_boolean_attribute(attr: "initialized")
        return ast.VariableDef(variable, value: ast.VariableDefValue.Extern(libname: m_libname, is_initialized))

    fn load_function(def_name: str, def_id: int) -> ast.FunctionDef:
        let type_parameters = load_type_parameters()
        let parameters = load_parameters()
        let info = load_function_info()
        let f = ast.extern_function_def:
            libname: m_libname
            name: def_name
            type_parameters
            parameters
            return_type: info.return_type
            location: location_default()
        f.info = info
        case m_this_type:
            Some(ty):
                let this_parameter = ast.parameter_def(name: "this", id: 0, label_is_optional: true, ty, location: location_default())
                f.this_parameter = Option.Some(this_parameter)
            None:
                pass
        return f

    fn load_function_info() -> ast.FunctionInfo:
        let no_return = m_des.get_boolean_attribute(attr: "no-return")
        let return_type = load_type(attr: "return-type")
        let except_type = load_type(attr: "except-type")
        let info = ast.FunctionInfo(no_return, return_type, except_type)
        return info

    fn load_parameters() -> List[ast.ParameterDef]:
        let parameters: List[ast.ParameterDef] = List()
        for parameter_obj in m_des.get_array_attribute(attr: "parameters"):
            m_des.push_value(value: parameter_obj)
            parameters.append(load_parameter())
            m_des.pop_value()
        return parameters
    
    fn load_parameter() -> ast.ParameterDef:
        let name = m_des.get_text_attribute(attr: "name")
        let label_is_optional = m_des.get_boolean_attribute(attr: "label_is_optional")
        let id = 0
        let ty = load_type(attr: "type")
        let location = location_default()
        return ast.parameter_def(name, id, label_is_optional, ty, location)

    fn load_struct_def(def_name: str, def_id: int) -> ast.StructDef:
        let builder = ast.StructBuilder()
        builder.set_name(name: def_name)
        builder.set_id(id: def_id)
        let type_parameters = load_type_parameters()
        for field_obj in m_des.get_array_attribute(attr: "fields"):
            m_des.push_value(value: field_obj)
            let field_name = m_des.get_text_attribute(attr: "name")
            let field_type = load_type(attr: "type")
            builder.add_field(name: field_name, ty: field_type, location: location_default())
            m_des.pop_value()
        let struct_def = builder.finish()
        struct_def.type_parameters = type_parameters
        struct_def.scope = ast.Scope()
        return struct_def
    
    fn load_enum_def(def_name: str, def_id: int) -> ast.EnumDef:
        let location = location_default()
        let type_parameters = load_type_parameters()
        let variants: List[ast.EnumVariant] = List()
        let tag_index = 0
        for variant_obj in m_des.get_array_attribute(attr: "variants"):
            m_des.push_value(value: variant_obj)
            let variant_name = m_des.get_text_attribute(attr: "name")
            let payload = load_types(attr: "payload")
            let variant = ast.EnumVariant(name: variant_name, tag_value: tag_index, location, payload)
            variants.append(variant)
            m_des.pop_value()
            tag_index += 1

        return ast.enum_def(name: def_name, id: def_id, location, type_parameters, variants)

    fn load_class_def(def_name: str, def_id: int) -> ast.ClassDef:
        let id = ast.NodeId(name: def_name, id: def_id)
        let location = location_default()
        let type_parameters = load_type_parameters()

        let this_type = ast.undefined_type()
        m_this_type = Option.Some(this_type)
        let definitions: List[ast.Definition] = List()
        for definition_obj in m_des.get_array_attribute(attr: "definitions"):
            m_des.push_value(value: definition_obj)
            let definition = load_definition()
            definitions.append(definition)
            m_des.pop_value()
        m_this_type = Option.None()

        let class_def = ast.ClassDef(id, location, is_extern: Option.Some(m_libname), type_parameters, definitions, scope: ast.Scope())

        # Patch the this type:
        let type_arguments: List[ast.Type] = List()
        for type_parameter in type_parameters:
            type_arguments.append(ast.type_parameter_ref(type_parameter))
        this_type.change_to(to_type: ast.apply_tycon(tycon: ast.TyCon.Class(class_def), type_arguments))

        return class_def

    fn load_type_parameters() -> List[ast.TypeParameter]:
        let type_parameters: List[ast.TypeParameter] = List()
        for type_parameter_obj in m_des.get_array_attribute(attr: "type-parameters"):
            m_des.push_value(value: type_parameter_obj)
            let id = load_id()
            let location = location_default()
            let type_parameter = ast.new_type_parameter(name: id.name, id: id.id, location)
            m_type_parameter_map.insert(key: "{id.id}", value: type_parameter)
            type_parameters.append(type_parameter)
            m_des.pop_value()
        return type_parameters

    fn load_types(attr: str) -> List[ast.Type]:
        let types: List[ast.Type] = List()
        for type_argument_obj in m_des.get_array_attribute(attr):
            m_des.push_value(value: type_argument_obj)
            types.append(load_type(attr: "type"))
            m_des.pop_value()
        return types

    fn load_type(attr: str) -> ast.Type:
        let ty = ast.undefined_type()
        m_des.enter_attribute(attr)
        let type_name = m_des.get_text_attribute(attr: "kind")
        if type_name == "int":
            let signed = m_des.get_boolean_attribute(attr: "signed")
            let bits = m_des.get_integer_attribute(attr: "bits")
            ty = ast.specific_int_type(signed, bits)
        elif type_name == "str":
            ty = ast.str_type()
        elif type_name == "bool":
            ty = ast.bool_type()
        elif type_name == "float":
            let bits = m_des.get_integer_attribute(attr: "bits")
            ty = ast.specific_float_type(bits)
        elif type_name == "char":
            ty = ast.char_type()
        elif type_name == "void":
            ty = ast.void_type()
        elif type_name == "app":
            let type_arguments = load_types(attr: "type-arguments")
            let id = load_id()
            let tycon = ast.TyCon.Ref(key: ast.node_id_to_string(id))
            ty = ast.new_type(kind: ast.TypeKind.App(tycon, type_arguments))
        elif type_name == "type-parameter":
            let id = load_id()
            let type_parameter = m_type_parameter_map.get(key: "{id.id}")
            ty = ast.type_parameter_ref(type_parameter)
        elif type_name == "array":
            let element_type = load_type(attr: "element-type")
            let size = m_des.get_integer_attribute(attr: "size")
            ty = ast.array_type(element_type, size)
        elif type_name == "function":
            let parameter_types: List[ast.ParameterType] = List()
            for parameter_obj in m_des.get_array_attribute(attr: "parameter-types"):
                m_des.push_value(value: parameter_obj)
                let parameter_type = load_type(attr: "type")
                parameter_types.append(ast.ParameterType(label: Option.None(), ty: parameter_type))
                m_des.pop_value()
            let info = load_function_info()
            ty = ast.function_type(parameter_types, info)
        else:
            panic("Unsupported: {type_name}")
        
        m_des.pop_value()
        return ty
    
    fn load_id() -> ast.NodeId:
        let id = m_des.get_integer_attribute(attr: "id")
        let name = m_des.get_text_attribute(attr: "name")
        return ast.NodeId(id, name)

