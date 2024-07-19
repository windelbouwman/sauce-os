#
# WebAssembly backend
# ===================
#
# Generate WebAssembly from AST.
#
# - Pointers are mapped to i32 type
# - floats are mapped to f64
# - ints are mapped to i64
# - linear memory is imported from javascript side

import webassembly
import ast
from webassembly import Instruction
from datatypes import List, vec1, Option, option_is_none, option_is_some, option_unwrap
from dicttype import Dictionary
from location import location_default
from std import print, str_len, ord
from utils import panic, log_info, log_debug, assert, log_error


fn gen_webassembly(module_set: ast.ModuleSet):
    log_info("Generating WebAssembly")
    let generator = WasmGenerator()
    generator.gen_module_set(modules: module_set.modules)

class WasmGenerator:
    var types: List[webassembly.Type] = List()
    var imports: List[webassembly.Import] = List()
    var functions: List[webassembly.Function] = List()
    var exports: List[webassembly.Export] = List()
    var datas: List[webassembly.Data] = List()
    var code: List[webassembly.Instruction] = List()

    var n_parameters: int = 0
    var local_variables: List[webassembly.ValueType] = List()
    var index_mapping: Dictionary[int] = Dictionary()
    var literal_offset: int = 0
    var block_stack: List[bool] = List()

    fn gen_module_set(modules: List[ast.Module]):
        let type_parameters: List[ast.TypeParameter] = List()
        let malloc_def = ast.extern_function_def(libname: "js", name: "js_malloc", type_parameters, parameters: vec1(ast.unlabeled_parameter(ty: ast.int_type())), return_type: ast.opaque_type(), location: location_default())
        gen_external_function(function_def: malloc_def)

        for module in modules:
            log_info("Generating external functions {module.name}")
            for definition in module.definitions:
                case definition:
                    Function(function_def):
                        case function_def.body:
                            Intern(scoped_block):
                                pass
                            Extern(libname):
                                gen_external_function(function_def)
                else:
                    pass

        let counter = imports.len()
        for module in modules:
            for definition in module.definitions:
                case definition:
                    Function(function_def):
                        case function_def.body:
                            Intern(scoped_block):
                                let key = function_def.name
                                let funcidx = counter
                                index_mapping.insert(key, value: funcidx)
                                let name = function_def.name
                                exports.append(webassembly.Export(name, funcidx))

                                counter += 1
                            Extern(libname):
                                pass
                else:
                    pass

        for module in modules:
            gen_module(module)

        # Create module:
        let wasm_module = webassembly.Module:
            types
            imports
            functions
            exports
            datas
        webassembly.to_wat(module: wasm_module)

    fn gen_external_function(function_def: ast.FunctionDef):
        # log_debug("extern function def: {extern_function_def.name}")
        let funcidx = imports.len()
        index_mapping.insert(key: function_def.name, value: funcidx)

        let parameter_types: List[ast.Type] = List()
        for parameter in function_def.parameters:
            parameter_types.append(parameter.ty)

        let func_ty = reg_signature(parameter_types, return_type: function_def.info.return_type)
        case function_def.body:
            Intern(scoped_block):
                panic("Invalid extern function")
            Extern(libname):
                imports.append(webassembly.Import(module: libname, name: function_def.name, ty: func_ty))

    fn gen_module(module: ast.Module):
        for definition in module.definitions:
            case definition:
                Function(function_def):
                    gen_function(function_def)
                Struct(struct_def):
                    log_debug("Struct def: {struct_def.id.name}")
            else:
                panic("Definition {ast.definition_to_str(definition)} not supported")

    fn get_wasm_type(ty?: ast.Type) -> webassembly.ValueType:
        if ast.is_int_type(ty):
            return webassembly.ValueType.i64()
        elif ast.is_opaque_type(ty) or ast.is_tycon_app_type(ty):
            return webassembly.ValueType.i32()
        elif ast.is_str_type(ty):
            return webassembly.ValueType.i32()
        elif ast.is_float_type(ty):
            return webassembly.ValueType.f64()
        elif ast.is_char_type(ty):
            return webassembly.ValueType.i32()
        elif ast.is_bool_type(ty):
            return webassembly.ValueType.i32()
        elif ast.is_function_type(ty):
            return webassembly.ValueType.i32()
        else:
            panic("TODO: {ast.type_to_string(ty)}!")

    fn reg_signature(parameter_types: List[ast.Type], return_type: ast.Type) -> int:
        let params: List[webassembly.ValueType] = List()
        let results: List[webassembly.ValueType] = List()
        for pt in parameter_types:
            params.append(get_wasm_type(pt))
        if not ast.is_void_type(return_type):
            results.append(get_wasm_type(return_type))
        let ft = webassembly.Type(params, results)
        let key = webassembly.type_to_string(ft)
        let index = 0
        if index_mapping.contains(key):
            index = index_mapping.get(key)
        else:
            index = types.len()
            index_mapping.insert(key, value: index)
            types.append(ft)
        return index

    fn gen_function(function_def: ast.FunctionDef):
        log_info("Generating code for: {ast.function_def_to_str(function_def)}")
        code = List()
        local_variables = List()
        n_parameters = 0

        let parameter_types: List[ast.Type] = List()
        for parameter in function_def.parameters:
            let x = create_parameter(id: parameter.id, ty: parameter.ty)
            parameter_types.append(parameter.ty)
        let func_ty = reg_signature(parameter_types, return_type: function_def.info.return_type)
        
        case function_def.body:
            Intern(scoped_block):
                let body = scoped_block.body
                gen_statement(body)

                # Introduce an unreachable instruction, when we cannot reach this point.
                if body.is_terminator:
                    emit(Instruction.ctrl_unreachable())
            Extern(libname):
                panic("Function without body")

        let f = webassembly.Function:
            ty: func_ty
            locals: local_variables
            code
        functions.append(f)

    fn gen_statement(statement?: ast.Statement):
        case statement.kind:
            Break:
                let distance = get_loop()
                emit(Instruction.ctrl_br(distance + 1))

            Continue:
                let distance = get_loop()
                emit(Instruction.ctrl_br(distance))

            Compound(inner):
                for sub_statement in inner:
                    gen_statement(sub_statement)

            Expr(expression):
                gen_expression(expression)

            Assignment(target, op, value):
                case target.kind:
                    GetAttr(base, attr):
                        let index = ast.get_struct_field_index(ty: base.ty, attr)
                        let offset = offsetof(ty: base.ty, index)
                        gen_expression(base)
                        gen_expression(value)
                        gen_store(offset, ty: value.ty)

                    VarRef(variable):
                        gen_expression(value)
                        let localidx = get_local_index(id: variable.id)
                        emit(Instruction.local_set(localidx))

                    ParameterRef(parameter_def):
                        let localidx = get_local_index(id: parameter_def.id)
                        emit(Instruction.local_set(localidx))
                else:
                    panic("Unsupported assignment target: {ast.expression_to_string(target)}")

            Let(let_statement):
                gen_expression(let_statement.value)
                let localidx = create_local(id: let_statement.variable.id, ty: let_statement.variable.ty)
                emit(Instruction.local_set(localidx))

            If(if_statement):
                gen_expression(if_statement.condition)
                enter_block(is_loop: false)
                emit(Instruction.ctrl_if())
                gen_statement(if_statement.true_block.body)
                emit(Instruction.ctrl_else())
                gen_statement(if_statement.false_block.body)
                emit(Instruction.ctrl_end())
                leave_block()

            While(while_statement):
                enter_block(is_loop: true)
                emit(Instruction.ctrl_block())
                emit(Instruction.ctrl_loop())
                gen_expression(while_statement.condition)
                emit(Instruction.i32_eqz())
                emit(Instruction.ctrl_br_if(1))
                gen_statement(while_statement.block.body)
                emit(Instruction.ctrl_br(0))
                emit(Instruction.ctrl_end())
                emit(Instruction.ctrl_end())
                leave_block()

            Pass:
                pass

            Unreachable:
                emit(Instruction.ctrl_unreachable())

            Return(value):
                case value:
                    None:
                        pass
                    Some(v2):
                        gen_expression(v2)
                emit(Instruction.ctrl_return())
            
            Raise(value):
                panic("TODO: raise!")
        else:
            panic("Not implemented: {ast.statement_to_string(statement)}")

    fn gen_expression(expression?: ast.Expression):
        case expression.kind:
            IntLiteral(value):
                emit(Instruction.i64_const(value))

            BoolLiteral(value):
                if value:
                    emit(Instruction.i32_const(value: 1))
                else:
                    emit(Instruction.i32_const(value: 0))

            StringLiteral(value):
                let offset = add_literal(data: "{value}\\00")
                emit(Instruction.i32_const(offset))

            CharLiteral(value):
                emit(Instruction.i32_const(ord(value)))

            FloatLiteral(value):
                emit(Instruction.f64_const(value))

            StructLiteral(ty, values):
                let size = sizeof(ty)

                let node_id = ast.NodeId(name: "$ptr$", id: 0)
                let ptr_index = create_local(id: node_id, ty: ast.opaque_type())
                gen_malloc_call(size)
                emit(Instruction.local_set(ptr_index))

                let index = 0
                for value in values:
                    emit(Instruction.local_get(ptr_index))
                    gen_expression(value)
                    let offset = offsetof(ty, index)
                    gen_store(offset, ty: value.ty)
                    index += 1
                emit(Instruction.local_get(ptr_index))

            UnionLiteral(ty, field, value):
                let size = sizeof(ty)
                let node_id = ast.NodeId(name: "$ptr$", id: 0)
                let ptr_index = create_local(id: node_id, ty: ast.opaque_type())
                gen_malloc_call(size)
                emit(Instruction.local_set(ptr_index))

                let index = ast.get_struct_field_index(ty, attr: field)
                let offset = offsetof(ty, index)

                emit(Instruction.local_get(ptr_index))
                gen_expression(value)
                gen_store(offset, ty: value.ty)

                emit(Instruction.local_get(ptr_index))

            Binop(binop):
                gen_binop(binop)

            Unop(op, value):
                case op:
                    Not:
                        assert(condition: ast.is_bool_type(value.ty), message: "'not' operator only supports booleans")
                        gen_expression(value)
                        emit(Instruction.i32_eqz())
                    Minus:
                        if ast.is_int_type(value.ty):
                            emit(Instruction.i64_const(0))
                            gen_expression(value)
                            emit(Instruction.i64_sub())
                        else:
                            panic("unop(-) for {ast.type_to_string(value.ty)}")

            Call(call):
                for argument in call.arguments:
                    gen_expression(argument.value)

                let funcidx = 0

                case call.callee.kind:
                    FunctionRef(function_def, type_arguments):
                        let key = function_def.name
                        funcidx = index_mapping.get(key)
                else:
                    gen_expression(call.callee)
                    emit(Instruction.ctrl_call_indirect(1337))
                    panic("Cannot call! {ast.expression_to_string(call.callee)}")

                emit(Instruction.ctrl_call(funcidx))

            TypeCast(ty, value):
                gen_expression(value)
                gen_type_cast(from_type: value.ty, to_type: ty)

            GetAttr(base, attr):
                let index = ast.get_struct_field_index(ty: base.ty, attr)
                let offset = offsetof(ty: base.ty, index)
                gen_expression(base)
                gen_load(offset, ty: expression.ty)

            ParameterRef(parameter_def):
                let localidx = get_local_index(id: parameter_def.id)
                emit(Instruction.local_get(localidx))

            VarRef(variable):
                let localidx = get_local_index(id: variable.id)
                emit(Instruction.local_get(localidx))

            FunctionRef(function_def, type_args):
                # TODO: figure out index?
                emit(Instruction.i32_const(1337))
                panic("FN {function_def.name}")
        else:
            panic("Not implemented: {ast.expression_to_string(expression)}")

    fn gen_binop(binop: ast.BinopExpression):
        gen_expression(binop.lhs)
        gen_expression(binop.rhs)
        if ast.is_int_type(binop.lhs.ty):
            case binop.op:
                Add:
                    emit(Instruction.i64_add())
                Sub:
                    emit(Instruction.i64_sub())
                Mul:
                    emit(Instruction.i64_mul())
                Div:
                    emit(Instruction.i64_div_s())
                Less:
                    emit(Instruction.i64_lt_s())
                LessEquals:
                    emit(Instruction.i64_le_s())
                Greater:
                    emit(Instruction.i64_gt_s())
                GreaterEquals:
                    emit(Instruction.i64_ge_s())
                Equals:
                    emit(Instruction.i64_eq())
                NotEquals:
                    emit(Instruction.i64_ne())
                BitAnd:
                    emit(Instruction.i64_and())
                BitXor:
                    emit(Instruction.i64_xor())
                BitOr:
                    emit(Instruction.i64_or())
                ShiftLeft:
                    emit(Instruction.i64_shl())
                ShiftRight:
                    # TBD: unsigned or signed shift right?
                    emit(Instruction.i64_shr_u())
            else:
                panic("Invalid int binop: {ast.binary_op_to_str(binop.op)}")
        elif ast.is_bool_type(binop.lhs.ty):
            case binop.op:
                And:
                    emit(Instruction.i32_and())
                Or:
                    emit(Instruction.i32_or())
            else:
                panic("Invalid bool binop: {ast.binary_op_to_str(binop.op)}")
        elif ast.is_float_type(binop.lhs.ty):
            case binop.op:
                Add:
                    emit(Instruction.f64_add())
                Sub:
                    emit(Instruction.f64_sub())
                Mul:
                    emit(Instruction.f64_mul())
                Div:
                    emit(Instruction.f64_div())
                Less:
                    emit(Instruction.f64_lt())
                LessEquals:
                    emit(Instruction.f64_le())
                Greater:
                    emit(Instruction.f64_gt())
                GreaterEquals:
                    emit(Instruction.f64_ge())
                Equals:
                    emit(Instruction.f64_eq())
                NotEquals:
                    emit(Instruction.f64_ne())
            else:
                panic("Invalid str binop: {ast.binary_op_to_str(binop.op)}")
        elif ast.is_char_type(binop.lhs.ty):
            case binop.op:
                Equals:
                    emit(Instruction.i32_eq())
                NotEquals:
                    emit(Instruction.i32_ne())
            else:
                panic("Invalid char binop: {ast.binary_op_to_str(binop.op)}")
        else:
            panic("Binop type not supported: {ast.type_to_string(binop.lhs.ty)}")

    fn gen_type_cast(from_type: ast.Type, to_type: ast.Type):
        if ast.is_float_type(to_type):
            if ast.is_int_type(from_type):
                emit(Instruction.f64_convert_i64_s())
            else:
                panic("TODO: cast {ast.type_to_string(from_type)} to float")
        elif ast.is_str_type(to_type):
            if ast.is_opaque_type(from_type):
                pass
            else:
                panic("TODO: cast to tycon-app: {ast.type_to_string(from_type)}")
        elif ast.is_int_type(to_type):
            if ast.is_opaque_type(from_type):
                emit(Instruction.i64_extend_i32_s())
            else:
                panic("TODO: cast to int from: {ast.type_to_string(from_type)}")
        elif ast.is_bool_type(to_type):
            if ast.is_opaque_type(from_type):
                pass
            else:
                panic("TODO: cast to bool: {ast.type_to_string(from_type)}")
        elif ast.is_opaque_type(to_type):
            if ast.is_tycon_app_type(from_type):
                pass
            elif ast.is_opaque_type(from_type):
                pass
            elif ast.is_str_type(from_type):
                pass
            elif ast.is_int_type(from_type):
                # integers are 64 bit, pointers 32 bit.
                # TODO: this fails for large integers!
                emit(Instruction.i32_wrap_i64())
            elif ast.is_bool_type(from_type):
                pass
            else:
                panic("TODO: cast to opaque: {ast.type_to_string(from_type)}")
        elif ast.is_tycon_app_type(to_type):
            if ast.is_opaque_type(from_type):
                pass
            else:
                panic("TODO: cast to tycon-app: {ast.type_to_string(from_type)}")
        else:
            panic("TODO: cast to {ast.type_to_string(to_type)}")

    fn gen_malloc_call(size: int):
        emit(Instruction.i64_const(size))
        let funcidx = index_mapping.get(key: "malloc")
        emit(Instruction.ctrl_call(funcidx))

    fn sizeof(ty: ast.Type) -> int:
        let layout = get_struct_layout(ty)
        return layout.size

    fn offsetof(ty: ast.Type, index: int) -> int:
        let layout = get_struct_layout(ty)
        return layout.offsets.get(index)

    fn get_struct_layout(ty: ast.Type) -> StructLayout:
        # TODO: cache results.
        let struct_def = ast.get_struct_def_from_type(ty)
        let size: int = 0
        let offsets: List[int] = List()
        for field in struct_def.fields:
            offsets.append(size)
            let field_size = 8

            size += field_size
        return StructLayout(size, offsets)

    fn gen_store(offset: int, ty: ast.Type):
        let wasm_ty = get_wasm_type(ty)
        case wasm_ty:
            i32:
                emit(Instruction.i32_store(align: 4, offset))
            f32:
                emit(Instruction.f32_store(align: 4, offset))
            i64:
                emit(Instruction.i64_store(align: 8, offset))
            f64:
                emit(Instruction.f64_store(align: 8, offset))

    fn gen_load(offset: int, ty: ast.Type):
        let wasm_ty = get_wasm_type(ty)
        case wasm_ty:
            i32:
                emit(Instruction.i32_load(align: 4, offset))
            f32:
                emit(Instruction.f32_load(align: 4, offset))
            i64:
                emit(Instruction.i64_load(align: 8, offset))
            f64:
                emit(Instruction.f64_load(align: 8, offset))

    fn get_local_index(id: ast.NodeId) -> int:
        return index_mapping.get(key: ast.node_id_to_string(id))

    fn create_parameter(id: ast.NodeId, ty: ast.Type) -> int:
        let idx = n_parameters
        n_parameters += 1
        index_mapping.insert(key: ast.node_id_to_string(id), value: idx)
        return idx

    fn create_local(id: ast.NodeId, ty: ast.Type) -> int:
        let idx = local_variables.len() + n_parameters
        let wasm_ty = get_wasm_type(ty)
        local_variables.append(wasm_ty)
        index_mapping.insert(key: ast.node_id_to_string(id), value: idx)
        return idx

    fn emit(instruction?: Instruction):
        # log_info("WASM INSTR> {webassembly.to_string(instruction)}")
        code.append(instruction)

    fn enter_block(is_loop: bool):
        block_stack.append(is_loop)

    fn leave_block():
        block_stack.drop_last()

    fn get_loop() -> int:
        let blocks2 = block_stack.reversed()
        let index = 0
        for b in blocks2:
            if b:
                return index
            else:
                index += 1
        panic("Not in a loop!")

    fn add_literal(data: str) -> int:
        let offset = literal_offset
        literal_offset += str_len(text: data) + 3  # Some extra space for trailing zeroes
        datas.append(webassembly.Data(offset, text: data))
        log_debug("STRING LITERAL> {data}")
        return offset

struct StructLayout:
    size: int
    offsets: List[int]
