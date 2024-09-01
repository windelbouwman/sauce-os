
# C code backend
# Translate bytecode into C code.

from std import float_to_str, chr
from rt import int_to_str
from utils import panic, log_info, log_trace
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
    g.gen_program(program)
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

fn is_heap(ty?: bc.Type) -> bool:
    # Test if type is heap like type
    case ty:
        StructRef(index):
            return true
        Array(element_type):
            return true
        Str:
            return true
    else:
        return false

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
        emit("#include {chr(34)}slangrt.h{chr(34)}")

    fn gen_program(program: bc.Program):
        # Struct forward declarations:
        let index = 0
        for struct_def in program.structs:
            emit("struct S{index}_{struct_def.name};")
            index += 1
        
        index = 0
        for struct_def in program.structs:
            # Struct definitions:
            gen_struct_def(index, struct_def)
            index += 1

        for extern_function in program.extern_functions:
            gen_extern_function_decl(extern_function)

        # Forward declarations:
        for function in program.functions:
            gen_function_decl(function)
        
        # Globals!
        for global in program.globals:
            gen_global(global)

        # Function definitions:
        for function in program.functions:
            gen_function(function)

    fn gen_struct_def(index: int, struct_def: bc.Struct):
        let name = "S{index}_{struct_def.name}"
        emit("struct {name} {chr(123)}")
        indent()
        
        let findex = 0
        for field in struct_def.fields:
            let typed_var = get_type_txt(ty: field.ty, name: "f{findex}_{field.name}")
            emit("{typed_var};")
            findex += 1
        dedent()
        emit("{chr(125)};")
        emit("")

        # struct destructor functions
        emit("void {name}_destroyer(void* x) {chr(123)}")
        indent()
        emit("struct {name}* x2 = (struct {name}*)x;")
        findex = 0
        for field in struct_def.fields:
            if is_heap(field.ty):
                emit("rt_decref(x2->f{findex}_{field.name});")
            findex += 1
        if findex == 0:
            emit("(void)(x2);")  # Prevent unused variable warning.

        dedent()
        emit("{chr(125)}")

        # Create struct type info for garbage collector:
        # This can be used during the mark phase of garbage collection to track pointers.
        emit("// {name}_type_info = {chr(123)}")
        indent()
        findex = 0
        for field in struct_def.fields:
            if is_heap(field.ty):
                emit("// offsetof(f{findex}_{field.name}),")
            findex += 1
        emit("// NULL,")
        dedent()
        emit("// {chr(125)}")

    fn get_parameter_text(parameters: List[bc.TypedName]) -> str:
        let parameters2: List[str] = List()
        let index = 0
        for parameter in parameters:
            let name = "P{index}"
            let typed_var = get_type_txt(ty: parameter.ty, name)
            parameters2.append(typed_var)
            index += 1
        return str_join(parts: parameters2, sep: ", ")

    fn gen_extern_function_decl(extern_function: bc.ExternFunction):
        let param_txt = get_parameter_text(parameters: extern_function.parameters)

        let return_type = "void"
        case extern_function.return_type:
            Some(ty):
                return_type = get_type_txt(ty, name: "")
            None:
                return_type = "void"

        let decl = "{return_type} {extern_function.name}({param_txt})"
        if extern_function.no_return:
            emit("#if defined __GNUC__")
            emit("extern {decl} __attribute__((noreturn));")
            emit("#elif defined _MSC_VER")
            emit("__declspec(noreturn) extern {decl};")
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
        for parameter in function.parameters:
            let name = "P{index}_{parameter.name}"
            if fill_param:
                local_parameters.append(Value(name, ty: parameter.ty))
            let typed_var = get_type_txt(ty: parameter.ty, name)
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
        log_trace("Generating bytecode for {function.name}")
        next_id = 1
        local_variables = List()
        local_parameters = List()

        let decl = get_function_decl(function, fill_param: true)
        # TODO: allow string literal escaping
        emit("{decl} {chr(123)}")  # '{' = 123
        indent()
        for local in function.locals:
            let varname = new_named_local_var(name: local.name)
            let ty_txt = get_type_txt(ty: local.ty, name: varname)
            if is_heap(local.ty):
                emit("{ty_txt} = NULL;")
            else:
                emit("{ty_txt};")
            local_variables.append(Value(name: varname, ty: local.ty))

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
                inc_ref(value)
                push(value)
                push(value)

            Literal(literal):
                case literal:
                    Int(value):
                        push(Value(name: "{value}", ty: bc.Type.Int(signed: true, bits: 64)))
                    Float(value):
                        push(Value(name: "{float_to_str(value)}", ty: bc.Type.Float(bits: 64)))
                    Str(value):
                        let varname = new_local_var()
                        let ty = bc.Type.Str()
                        let typed_var = get_type_txt(ty, name: varname)
                        emit("{typed_var} = rt_str_new({chr(34)}{value}{chr(34)});")
                        push(Value(name: varname, ty))
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
            
            DecRef(index):
                let varname = local_variables.get(index)
                #if is_heap(varname.ty):
                #    emit("rt_decref({varname.name});")

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
                        # panic("Cannot box float")
                        emit("{typed_var} = SLANG_BOX_FLOAT{bits}({value.name});")
                    Int(signed, bits):
                        if signed:
                            emit("{typed_var} = SLANG_BOX_INT{bits}({value.name});")
                        else:
                            emit("{typed_var} = SLANG_BOX_UINT{bits}({value.name});")
                    Bool:
                        emit("{typed_var} = SLANG_BOX_BOOL({value.name});")
                    Char:
                        emit("{typed_var} = SLANG_BOX_CHAR({value.name});")
                    Ptr:
                        emit("{typed_var} = {value.name};")
                    Str:
                        emit("{typed_var} = (void*)({value.name});")
                    StructRef(index):
                        emit("{typed_var} = (void*)({value.name});")
                    Function(parameter_types, return_type):
                        panic("Cannot box function")
                    Array(element_type):
                        panic("Cannot box array")
                push(Value(name: varname, ty))

            FromOpaque(ty):
                # Unbox value from opaque pointer type
                let value = pop()
                let varname = new_local_var()
                let typed_var = get_type_txt(ty, name: varname)
                case ty:
                    Int(signed, bits):
                        if signed:
                            emit("{typed_var} = SLANG_UNBOX_INT{bits}({value.name});")
                        else:
                            emit("{typed_var} = SLANG_UNBOX_UINT{bits}({value.name});")
                    Float(bits):
                        emit("{typed_var} = SLANG_UNBOX_FLOAT{bits}({value.name});")
                    Bool:
                        emit("{typed_var} = SLANG_UNBOX_BOOL({value.name});")
                    Str:
                        emit("{typed_var} = (char*)({value.name});")
                    Char:
                        emit("{typed_var} = SLANG_UNBOX_CHAR({value.name});")
                    Function(parameter_types, return_type):
                        panic("Cannot unbox ptr to function")
                    Array(element_type):
                        panic("Cannot unbox ptr to array")
                    Ptr:
                        emit("{typed_var} = {value.name};")
                    StructRef(index):
                        let to_type = get_type_txt(ty, name: "")
                        emit("{typed_var} = ({to_type})({value.name});")
                let value2 = Value(name: varname, ty)
                inc_ref(value2)
                push(value2)

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
                inc_ref(varname)
                push(varname)

            LocalSet(index):
                let value = pop()
                let varname = local_variables.get(index)
                dec_ref(varname)
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
                inc_ref(param)
                push(param)

            ParameterSet(index):
                let value = pop()
                let param = local_parameters.get(index)
                dec_ref(param)
                emit("{param.name} = {value.name};")

            GetAttr(index):
                let base = pop()
                let field = get_struct_field(ty: base.ty, index)
                let varname = new_local_var()
                let typed_var = get_type_txt(ty: field.ty, name: varname)
                emit("{typed_var} = {base.name}->f{index}_{field.name};")
                dec_ref(base)
                let value = Value(name: varname, ty: field.ty)
                inc_ref(value)
                push(value)

            SetAttr(index):
                let value = pop()
                let base = pop()
                let field = get_struct_field(ty: base.ty, index)
                emit("{base.name}->f{index}_{field.name} = {value.name};")
                dec_ref(base)

            GetIndex:
                let index = pop()
                let base = pop()
                let varname = new_local_var()
                let ty = bc.get_element_type_from_type(base.ty)
                let typed_var = get_type_txt(ty, name: varname)
                emit("{typed_var} = {base.name}[{index.name}];")
                dec_ref(base)
                let value = Value(name: varname, ty)
                inc_ref(value)
                push(value)
                
            SetIndex:
                let value = pop()
                let index = pop()
                let base = pop()
                emit("{base.name}[{index.name}] = {value.name};")
                dec_ref(base)

            Return(amount):
                free_heap_refs()
                if amount == 1:
                    let value = pop()
                    emit("return {value.name};")
                else:
                    emit("return;")

            Unreachable:
                emit("SLANG_UNREACHABLE")

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
                emit("{typed_var} = rt_malloc_with_destroyer(sizeof(struct S{index}_{struct_def.name}), S{index}_{struct_def.name}_destroyer);")
                let index2 = 0
                for value in values:
                    let field = struct_def.fields.get(index: index2)
                    emit("{varname}->f{index2}_{field.name} = {value.name};")
                    index2 += 1
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
    
    fn get_struct_field(ty: bc.Type, index: int) -> bc.TypedName:
        case ty:
            StructRef(struct_index):
                return structs.get(index: struct_index).fields.get(index)
        else:
            panic("No struct")

    fn gen_call(callee: str, parameter_types: List[bc.TypedName], return_type: Option[bc.Type]):
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
                let struct_def = structs.get(index)
                return "struct S{index}_{struct_def.name}* {name}"
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

    fn free_heap_refs():
        for v in local_variables:
            dec_ref(v)

        for p in local_parameters:
            dec_ref(p)

    fn inc_ref(value?: Value):
        return # TODO: decide between garbage collection en reference counting
        if is_heap(value.ty):
            emit("rt_incref({value.name});")

    fn dec_ref(value?: Value):
        return # TODO: decide between garbage collection en reference counting
        if is_heap(value.ty):
            emit("rt_decref({value.name});")

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
        return "V{id}"

    fn new_named_local_var(name: str) -> str:
        let id = next_id
        next_id += 1
        return "V{id}_{name}"

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
