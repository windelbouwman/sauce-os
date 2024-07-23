
# C code backend
# Translate bytecode into C code.

from std import float_to_str, chr
from rt import int_to_str
from utils import panic, log_info
from datatypes import List, Option, option_is_some, option_unwrap
from vectype import Vector
from settype import Set
from strlib import str_repeat, str_join
import vm
import bc
from text_gen import TextGenerator

fn gen_c_code(program: bc.Program, output_filename: Option[str]):
    log_info("Generating C-code from bytecode")
    let g = CGenerator()
    g.out.begin(output_filename)
    g.structs = program.structs
    g.globals = program.globals
    g.extern_functions = program.extern_functions
    g.functions = program.functions

    # Runtime function prototypes:
    g.emit_runtime()

    # Struct forward declarations:
    let index = 0
    for struct_def in program.structs:
        if struct_def.is_union:
            g.emit("union U{index};")
        else:
            g.emit("struct S{index};")
        index += 1
    
    # Struct definitions:
    index = 0
    for struct_def in program.structs:
        g.gen_struct_def(sidx: index, struct_def)
        index += 1
    
    for extern_function in g.extern_functions:
        g.gen_extern_function_decl(extern_function)

    # Forward declarations:
    for function in program.functions:
        g.gen_function_decl(function)
    
    # Globals!
    for global in program.globals:
        g.gen_global(global)

    # Function definitions:
    for function in program.functions:
        g.gen_function(function)

    g.out.end()

fn get_target_labels(instructions: Vector[bc.Instruction]) -> Set:
    # Get a set of labels to which is being jumped
    let target_labels = Set()
    for instruction in instructions:
        case instruction:
            Jump(index):
                target_labels.add(int_to_str(index))
            JumpIf(index1, index2):
                target_labels.add(int_to_str(index1))
                target_labels.add(int_to_str(index2))
            SetupTry(try_label, except_label):
                target_labels.add(int_to_str(try_label))
                target_labels.add(int_to_str(except_label))
        else:
            pass
    return target_labels

struct Value:
    ty: bc.Type
    name: str

class CGenerator:
    # Generate C from bytecode
    var out: TextGenerator = TextGenerator()

    var stack: List[Value] = List()
    var next_id: int = 1
    var local_variables: List[Value] = List()
    var local_parameters: List[Value] = List()
    var structs: List[bc.Struct] = List()
    var globals: List[bc.Global] = List()
    var functions: List[bc.Function] = List()
    var extern_functions: List[bc.ExternFunction] = List()

    fn emit_runtime():
        emit("#include <stdint.h>")
        emit("#include <setjmp.h>")
        emit("#include <stdlib.h>")

        emit("// runtime functions:")
        emit("void* rt_malloc(int size);")
        emit("void rt_incref(void *ptr);")
        emit("void rt_decref(void *ptr);")
        emit("typedef intptr_t slang_int_t;")
        emit("typedef intptr_t slang_bool_t;")
        emit("typedef uint8_t slang_uint8_t;")
        emit("typedef uint16_t slang_uint16_t;")
        emit("typedef uint32_t slang_uint32_t;")
        emit("typedef intptr_t slang_uint64_t;")
        emit("typedef int8_t slang_int8_t;")
        emit("typedef int16_t slang_int16_t;")
        emit("typedef int32_t slang_int32_t;")
        emit("typedef intptr_t slang_int64_t;")
        emit("typedef float slang_float32_t;")
        emit("typedef double slang_float64_t;")
        emit("typedef struct {chr(123)} jmp_buf buf; void* prev; {chr(125)} slang_exception_handler_t;")

        emit("extern slang_exception_handler_t* g_except_hook;")
        emit("extern void* g_except_value;")

    fn gen_struct_def(sidx: int, struct_def: bc.Struct):
        if struct_def.is_union:
            emit("union U{sidx} {chr(123)}")
        else:
            emit("struct S{sidx} {chr(123)}")
        indent()
        let index = 0
        for field in struct_def.fields:
            let typed_var = get_type_txt(ty: field, name: "field{index}")
            emit("{typed_var};")
            index += 1
        dedent()
        emit("{chr(125)};")
        emit("")

    fn gen_extern_function_decl(extern_function: bc.ExternFunction):
        let parameters2: List[str] = List()
        let index = 0
        for parameter_type in extern_function.parameters:
            let pname = "P{index}"
            let typed_var = get_type_txt(ty: parameter_type, name: pname)
            parameters2.append(typed_var)
            index += 1
        let param_txt = str_join(parts: parameters2, sep: ", ")

        let return_type = "void"
        case extern_function.return_type:
            Some(ty):
                return_type = get_type_txt(ty, name: "")
            None:
                return_type = "void"

        let decl = "{return_type} {extern_function.name}({param_txt})"
        if extern_function.no_return:
            emit("#if defined __GNUC__")
            emit("{decl} __attribute__((noreturn));")
            emit("#elif defined _MSC_VER")
            emit("__declspec(noreturn) {decl};")
            emit("#else")
            emit("#error unsupported compiler")
            emit("#endif")
        else:
            emit("extern {decl};")
    
    fn gen_global(global: bc.Global):
        let typed_name = get_type_txt(ty: global.ty, name: global.name)
        case global.value:
            Some(code):
                let value = eval_code_sequence(code)
                emit("{typed_name} = {value};")
            None:
                emit("extern {typed_name};")

    fn gen_function_decl(function: bc.Function):
        let decl = get_function_decl(function, fill_param: false)
        if function.no_return:
            emit("#if defined __GNUC__")
            emit("{decl} __attribute__((noreturn));")
            emit("#elif defined _MSC_VER")
            emit("__declspec(noreturn) {decl};")
            emit("#else")
            emit("#error unsupported compiler")
            emit("#endif")
        else:
            emit("{decl};")

    fn get_function_decl(function: bc.Function, fill_param: bool) -> str:
        let parameters2: List[str] = List()
        let index = 0
        for parameter_type in function.parameters:
            let pname = "P{index}"
            if fill_param:
                local_parameters.append(Value(name: pname, ty: parameter_type))
            let typed_var = get_type_txt(ty: parameter_type, name: pname)
            parameters2.append(typed_var)
            index += 1
        let param_txt = str_join(parts: parameters2, sep: ", ")

        let return_type = "void"
        case function.return_type:
            Some(ty):
                return_type = get_type_txt(ty, name: "")
            None:
                return_type = "void"

        return "{return_type} {function.name}({param_txt})"

    fn gen_function(function: bc.Function):
        next_id = 1
        local_variables = List()
        local_parameters = List()

        let decl = get_function_decl(function, fill_param: true)
        # TODO: allow string literal escaping
        emit("{decl} {chr(123)}")  # '{' = 123
        indent()
        for ty in function.locals:
            let varname = new_local_var()
            let ty_txt = get_type_txt(ty, name: varname)
            emit("{ty_txt};")
            local_variables.append(Value(name: varname, ty))

        let target_labels = get_target_labels(instructions: function.instructions)
        let index = 0
        for instruction in function.instructions:
            if target_labels.contains(int_to_str(index)):
                emit("{get_label_str(index)}:")
            gen_instruction(instruction)
            index += 1
        dedent()
        emit("{chr(125)}") # '}' => 125
        emit("")

    fn gen_instruction(instruction: bc.Instruction):
        case instruction:
            Nop:
                pass

            Dup:
                let value = pop()
                push(value)
                push(value)

            Literal(literal):
                case literal:
                    Int(value):
                        push(Value(name: "{value}", ty: bc.Type.Int(signed: true, bits: 64)))
                    Float(value):
                        push(Value(name: "{float_to_str(value)}", ty: bc.Type.Float(bits: 64)))
                    Str(value):
                        push(Value(name: "{chr(34)}{value}{chr(34)}", ty: bc.Type.Str()))
                    Bool(value):
                        if value:
                            push(Value(name: "1", ty: bc.Type.Bool()))
                        else:
                            push(Value(name: "0", ty: bc.Type.Bool()))
                    Char(value):
                        push(Value(name: "'{value}'", ty: bc.Type.Char()))
                    Null:
                        push(Value(name: "0", ty: bc.Type.Ptr()))

            Jump(label):
                emit("goto {get_label_str(label)};")

            JumpIf(label1, label2):
                let condition = pop()
                emit("if ({condition.name})")
                emit("   goto {get_label_str(label1)};")
                emit("else")
                emit("   goto {get_label_str(label2)};")

            SetupTry(try_label, except_label):
                let bufname = "ebuf{try_label}"
                emit("slang_exception_handler_t {bufname};")
                emit("{bufname}.prev = g_except_hook;")
                emit("g_except_hook = &{bufname};")
                emit("if (setjmp(g_except_hook->buf) == 0)")
                emit("   goto {get_label_str(try_label)};")
                emit("else")
                emit("   goto {get_label_str(except_label)};")

            Raise:
                let value = pop()
                emit("g_except_value = {value.name};")
                emit("longjmp(g_except_hook->buf, 1);")

            PopTry:
                emit("g_except_hook = g_except_hook->prev;")

            GetExceptionValue:
                let value = Value(name: "g_except_value", ty: bc.Type.Ptr())
                push(value)

            Not:
                let rhs = pop()
                let varname = new_local_var()
                let ty = rhs.ty
                let typed_var = get_type_txt(ty, name: varname)
                emit("const {typed_var} = {rhs.name} ? 0 : 1;")
                push(Value(name: varname, ty))

            Neg:
                let rhs = pop()
                let varname = new_local_var()
                let ty = rhs.ty
                let typed_var = get_type_txt(ty, name: varname)
                emit("const {typed_var} = -{rhs.name};")
                push(Value(name: varname, ty))

            Binop(op):
                let rhs = pop()
                let lhs = pop()
                let varname = new_local_var()
                let ty = lhs.ty
                let typed_var = get_type_txt(ty, name: varname)
                let op_txt = "$"
                case op:
                    Add:
                        op_txt = "+"
                    Sub:
                        op_txt = "-"
                    Multiply:
                        op_txt = "*"
                    Divide:
                        op_txt = "/"
                emit("const {typed_var} = {lhs.name} {op_txt} {rhs.name};")

                push(Value(name: varname, ty))
            
            Comparison(op):
                let rhs = pop()
                let lhs = pop()
                let varname = new_local_var()
                let ty = bc.Type.Bool()
                let typed_var = get_type_txt(ty, name: varname)
                let op_txt = "$"
                case op:
                    Less:
                        op_txt = "<"
                    LessEquals:
                        op_txt = "<="
                    Greater:
                        op_txt = ">"
                    GreaterEquals:
                        op_txt = ">="
                    Equals:
                        op_txt = "=="
                    NotEquals:
                        op_txt = "!="
                emit("const {typed_var} = ({lhs.name} {op_txt} {rhs.name});")
                push(Value(name: varname, ty))
            
            Bitop(op):
                let rhs = pop()
                let lhs = pop()
                let op_txt = "$"
                case op:
                    And:
                        op_txt = "&"
                    Or:
                        op_txt = "|"
                    Xor:
                        op_txt = "^"
                    Shr:
                        op_txt = ">>"
                    Shl:
                        op_txt = "<<"
                let ty = lhs.ty
                let varname = new_local_var()
                let typed_var = get_type_txt(ty, name: varname)
                emit("const {typed_var} = ({lhs.name} {op_txt} {rhs.name});")
                push(Value(name: varname, ty))

            IntToFloat:
                let value = pop()
                let varname = new_local_var()
                let bits = 64 # TODO
                let ty = bc.Type.Float(bits)
                let typed_var = get_type_txt(ty, name: varname)
                emit("{typed_var} = (slang_float{bits}_t)({value.name});")
                push(Value(name: varname, ty))

            FloatToInt:
                let value = pop()
                let varname = new_local_var()
                let signed = true # TODO
                let bits = 64 # TODO
                let ty = bc.Type.Int(signed, bits)
                let typed_var = get_type_txt(ty, name: varname)
                if signed:
                    emit("{typed_var} = (slang_int{bits}_t)({value.name});")
                else:
                    emit("{typed_var} = (slang_uint{bits}_t)({value.name});")
                push(Value(name: varname, ty))
            
            IntCast(signed, bits):
                let value = pop()
                let varname = new_local_var()
                let ty = bc.Type.Int(signed, bits)
                let typed_var = get_type_txt(ty, name: varname)
                if signed:
                    emit("{typed_var} = (slang_int{bits}_t)({value.name});")
                else:
                    emit("{typed_var} = (slang_uint{bits}_t)({value.name});")
                push(Value(name: varname, ty))

            ToOpaque(ty3):
                let value = pop()
                let varname = new_local_var()
                let ty = bc.Type.Ptr()
                let typed_var = get_type_txt(ty, name: varname)
                case ty3:
                    Float(bits):
                        emit("{typed_var} = bit_cast<void*>({value.name});")
                    Int(signed, bits):
                        if signed:
                            emit("{typed_var} = (void*)((intptr_t)({value.name}));")
                        else:
                            emit("{typed_var} = (void*)((uintptr_t)({value.name}));")
                else:
                    emit("{typed_var} = (void*)({value.name});")
                push(Value(name: varname, ty))

            FromOpaque(ty):
                # Unbox value from opaque pointer type
                let value = pop()
                let varname = new_local_var()
                let typed_var = get_type_txt(ty, name: varname)
                case ty:
                    Int(signed, bits):
                        if signed:
                            emit("{typed_var} = (slang_int{bits}_t)((intptr_t)({value.name}));")
                        else:
                            emit("{typed_var} = (slang_uint{bits}_t)((uintptr_t)({value.name}));")
                    Float(bits):
                        emit("{typed_var} = (slang_float{bits}_t)({value.name});")
                    Bool:
                        emit("{typed_var} = (slang_int_t)({value.name});")
                    Str:
                        emit("{typed_var} = (char*)({value.name});")
                    Char:
                        emit("{typed_var} = (char)({value.name});")
                    Function(parameter_types, return_type):
                        panic("Cannot unbox ptr to function")
                    Array(element_type):
                        panic("Cannot unbox ptr to array")
                    Ptr:
                        panic("Cannot unbox ptr to ptr")
                    StructRef(index):
                        let to_type = get_type_txt(ty, name: "")
                        emit("{typed_var} = ({to_type})({value.name});")
                push(Value(name: varname, ty))

            Call(index):
                if index < extern_functions.len():
                    let function = extern_functions.get(index)
                    let callee = function.name
                    gen_call(callee, parameter_types: function.parameters, return_type: function.return_type)
                else:
                    index = index - extern_functions.len()
                    let function = functions.get(index)
                    let callee = function.name
                    gen_call(callee, parameter_types: function.parameters, return_type: function.return_type)

            CallIndirect(parameter_types, return_type):
                let target = pop()
                let callee = "{target.name}"
                gen_call(callee, parameter_types, return_type)

            LocalGet(index):
                let varname = local_variables.get(index)
                push(varname)

            LocalSet(index):
                let value = pop()
                let varname = local_variables.get(index)
                emit("{varname.name} = {value.name};")
            
            GlobalGet(index):
                let global = globals.get(index)
                let name = global.name
                let ty = global.ty
                let value = Value(name, ty)
                push(value)

            GlobalSet(index):
                let value = pop()
                let name = globals.get(index).name
                emit("{name} = {value.name};")

            ParameterGet(index):
                let param = local_parameters.get(index)
                push(param)

            ParameterSet(index):
                let value = pop()
                let param = local_parameters.get(index)
                emit("{param.name} = {value.name};")

            GetAttr(index, ty):
                let base = pop()
                let varname = new_local_var()
                let typed_var = get_type_txt(ty, name: varname)
                emit("{typed_var} = {base.name}->field{index};")
                push(Value(name: varname, ty))

            SetAttr(index):
                let value = pop()
                let base = pop()
                emit("{base.name}->field{index} = {value.name};")

            GetIndex:
                let index = pop()
                let base = pop()
                let varname = new_local_var()
                let ty = bc.get_element_type_from_type(base.ty)
                let typed_var = get_type_txt(ty, name: varname)
                emit("{typed_var} = {base.name}[{index.name}];")
                push(Value(name: varname, ty))
                
            SetIndex:
                let value = pop()
                let index = pop()
                let base = pop()
                emit("{base.name}[{index.name}] = {value.name};")

            Return(amount):
                if amount == 1:
                    let value = pop()
                    emit("return {value.name};")
                else:
                    emit("return;")

            Unreachable:
                emit("#if defined __GNUC__")
                emit("__builtin_unreachable();")
                emit("#elif defined _MSC_VER")
                emit("__assume(0);")
                emit("#else")
                emit("#error unsupported compiler")
                emit("#endif")

            LoadFunc(index):
                if index < extern_functions.len():
                    let function = extern_functions.get(index)
                    let callee = function.name
                    push(Value(name: callee, ty: bc.Type.Ptr()))
                else:
                    index = index - extern_functions.len()
                    let function = functions.get(index)
                    let callee = function.name
                    push(Value(name: callee, ty: bc.Type.Ptr()))

            StructLiteral(index):
                # we can derive count from struct type:
                let struct_def = structs.get(index)
                let values = pop_n(count: struct_def.fields.len())
                # Malloc it!
                let varname = new_local_var()
                let ty = bc.Type.StructRef(index)  # "struct S{index}*"
                let typed_var = get_type_txt(ty, name: varname)
                emit("{typed_var} = rt_malloc(sizeof(struct S{index}));")
                let index2 = 0
                for value in values:
                    emit("{varname}->field{index2} = {value.name};")
                    index2 += 1
                push(Value(name: varname, ty))

            UnionLiteral(struct_index, field_index):
                let value = pop()
                # Treat unions as structs (for now)
                # Malloc it!
                let varname = new_local_var()
                let ty = bc.Type.StructRef(struct_index)   # "union U{struct_index}*"
                let typed_var = get_type_txt(ty, name: varname)
                emit("{typed_var} = rt_malloc(sizeof(union U{struct_index}));")
                emit("{varname}->field{field_index} = {value.name};")
                push(Value(name: varname, ty))

            ArrayLiteral(size):
                let varname = new_local_var()
                let values = pop_n(count: size)
                let parts: List[str] = List()
                for value in values:
                    parts.append(value.name)
                let arg_text = str_join(parts, sep: ", ")
                let ety = values.first().ty
                let element_type_text = get_type_txt(ty: ety, name: "")
                let ty = bc.Type.Array(ty: ety)
                let typed_var = get_type_txt(ty, name: varname)
                emit("{typed_var} = rt_malloc({size} * sizeof({element_type_text}));")
                let index = 0
                for value in values:
                    emit("{varname}[{index}] = {value.name};")
                    index += 1
                push(Value(name: varname, ty))

            ArrayLiteral2:
                let size = pop()
                let value = pop()
                let varname = new_local_var()
                let ty = bc.Type.Array(ty: value.ty)
                let typed_var = get_type_txt(ty, name: varname)
                let element_type_text = get_type_txt(ty: value.ty, name: "")
                emit("{typed_var} = rt_malloc({size.name} * sizeof({element_type_text}));")
                emit("{varname}[0] = {value.name};")
                # Copy value to all elements:
                emit("for (int i = 1; i < {size.name}; i++)")
                emit("  {varname}[i] = {varname}[0];")
                push(Value(name: varname, ty))

    fn gen_call(callee: str, parameter_types: List[bc.Type], return_type: Option[bc.Type]):
        let args = pop_n(count: parameter_types.len())
        let args2: List[str] = List()
        for arg in args:
            args2.append(arg.name)
        let arg_text = str_join(parts: args2, sep: ", ")
        case return_type:
            Some(ty):
                let varname = new_local_var()
                let typed_var = get_type_txt(ty, name: varname)
                emit("{typed_var} = {callee}({arg_text});")
                push(Value(name: varname, ty))
            None:
                emit("{callee}({arg_text});")

    fn get_type_txt(ty: bc.Type, name: str) -> str:
        case ty:
            Int(signed, bits):
                if signed:
                    return "slang_int{bits}_t {name}"
                else:
                    return "slang_uint{bits}_t {name}"
            Str:
                return "char* {name}"
            Char:
                return "char {name}"
            Bool:
                return "slang_bool_t {name}"
            Float(bits):
                return "slang_float{bits}_t {name}"
            Ptr:
                return "void* {name}"
            StructRef(index):
                if structs.get(index).is_union:
                    return "union U{index}* {name}"
                else:
                    return "struct S{index}* {name}"
            Function(parameter_types, return_type):
                let parts: List[str] = List()
                for p in parameter_types:
                    parts.append(get_type_txt(ty: p, name: ""))
                let param_text = str_join(parts, sep: ", ")
                let return_text = "void"
                case return_type:
                    Some(ty):
                        return_text = get_type_txt(ty, name: "")
                    None:
                        return_text = "void"
                return "{return_text} (*{name})({param_text})"
            Array(element_type):
                let e = get_type_txt(ty: element_type, name: "")
                return "{e}* {name}"

    fn push(value?: Value):
        stack.append(value)
    
    fn pop_n(count: int) -> List[Value]:
        let values: List[Value] = List()
        while count > 0:
            let val = pop()
            values.append(val)
            count -= 1
        return values.reversed()

    fn pop() -> Value:
        return stack.pop_last()
    
    fn get_label_str(index?: int) -> str:
        return "L{index}"
    
    fn new_local_var() -> str:
        let id = next_id
        next_id += 1
        return "VAR{id}"

    fn indent():
        out.indent()

    fn dedent():
        out.dedent()

    fn emit(text?: str):
        out.emit(text)

fn eval_code_sequence(code: Vector[bc.Instruction]) -> str:
    let m = vm.VirtualMachine()
    let value = vm.eval_code(vm: m, code)
    case value:
        Int(v):
            return "{v}"
        Bool(v):
            if v:
                return "1"
            else:
                return "0"
        Float(v):
            return float_to_str(v)
        Str(v):
            let quote = chr(34)
            return "{quote}{v}{quote}"
        Char(v):
            return "'{v}'"
    else:
        panic("Unsupported initial value")
