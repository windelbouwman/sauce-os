
# C code backend
# Translate bytecode into C code.

from std import float_to_str, print, chr, int_to_str
from utils import panic
from datatypes import List, Set
from strlib import str_repeat, str_join
import bc

fn gen_c_code(program: bc.Program):
    let g = CGenerator()
    g.structs = program.structs

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

    # Forward declarations:
    for function0 in program.functions:
        let decl = g.get_function_decl(function: function0, fill_param: false)
        g.emit("{decl};")

    # Function definitions:
    for function in program.functions:
        g.gen_function(function)

fn get_target_labels(instructions: List[bc.Instruction]) -> Set:
    # Get a set of labels to which is being jumped
    let target_labels = Set()
    for instruction in instructions:
        case instruction:
            Jump(index):
                target_labels.add(int_to_str(index))
            JumpIf(index1, index2):
                target_labels.add(int_to_str(index1))
                target_labels.add(int_to_str(index2))
        else:
            pass
    return target_labels

struct Value:
    ty: bc.Type
    name: str

class CGenerator:
    # Generate C from bytecode
    var indentation: int = 0
    var stack: List[Value] = List()
    var next_id: int = 1
    var local_variables: List[Value] = List()
    var local_parameters: List[Value] = List()
    var structs: List[bc.Struct] = List()

    fn emit_runtime():
        emit("// runtime functions:")

        emit("void* rt_malloc(int size);")
        emit("void rt_incref(void *ptr);")
        emit("void rt_decref(void *ptr);")

        emit("void std_print(char *message);")
        emit("void std_exit(int code);")

        emit("char* std_read_file(char *filename);")

        emit("char* rt_str_concat(char*, char*);")
        emit("int rt_str_compare(char *a, char *b);")
        emit("int std_str_len(char* txt);")
        emit("char* std_str_slice(char* txt, int begin, int end);")
        emit("char* std_str_get(char* txt, int pos);")

        emit("int std_ord(char *txt);")

        emit("char *std_int_to_str(int x);")
        emit("int std_str_to_int(char *x);")
        emit("char *std_float_to_str(double x);")

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
                        push(Value(name: "{value}", ty: bc.Type.Int()))
                    Float(value):
                        push(Value(name: "{float_to_str(value)}", ty: bc.Type.Float()))
                    Str(value):
                        push(Value(name: "{chr(34)}{value}{chr(34)}", ty: bc.Type.Str()))
                    Bool(value):
                        if value:
                            push(Value(name: "1", ty: bc.Type.Int()))
                        else:
                            push(Value(name: "0", ty: bc.Type.Int()))

            Jump(label):
                emit("goto {get_label_str(label)};")

            JumpIf(label1, label2):
                let condition = pop()
                emit("if ({condition.name}) goto {get_label_str(label1)};")
                emit("  else goto {get_label_str(label2)};")

            # Raise
                # let value = pop()
                # emit("longjmp(jmpbuf, {value.name});")

            Not:
                panic("TODO: not")

            Neg:
                panic("TODO: neg")

            Binop(op):
                let rhs = pop()
                let lhs = pop()
                let varname = new_local_var()
                let ty = lhs.ty
                case op:
                    Add:
                        ty = lhs.ty
                    Sub:
                        ty = lhs.ty
                    Multiply:
                        ty = lhs.ty
                    Divide:
                        ty = lhs.ty
                    Less:
                        ty = bc.Type.Int()
                    LessEquals:
                        ty = bc.Type.Int()
                    Greater:
                        ty = bc.Type.Int()
                    GreaterEquals:
                        ty = bc.Type.Int()
                    Equals:
                        ty = bc.Type.Int()
                    NotEquals:
                        ty = bc.Type.Int()

                let typed_var = get_type_txt(ty, name: varname)
                case op:
                    Add:
                        emit("const {typed_var} = {lhs.name} + {rhs.name};")
                    Sub:
                        emit("const {typed_var} = {lhs.name} - {rhs.name};")
                    Multiply:
                        emit("const {typed_var} = {lhs.name} * {rhs.name};")
                    Divide:
                        emit("const {typed_var} = {lhs.name} / {rhs.name};")

                    Less:
                        emit("const {typed_var} = ({lhs.name} < {rhs.name});")
                    LessEquals:
                        emit("const {typed_var} = ({lhs.name} <= {rhs.name});")
                    Greater:
                        emit("const {typed_var} = ({lhs.name} > {rhs.name});")
                    GreaterEquals:
                        emit("const {typed_var} = ({lhs.name} >= {rhs.name});")
                    Equals:
                        emit("const {typed_var} = ({lhs.name} == {rhs.name});")
                    NotEquals:
                        emit("const {typed_var} = ({lhs.name} != {rhs.name});")
                push(Value(name: varname, ty))

            IntToFloat:
                let value = pop()
                let varname = new_local_var()
                let ty = bc.Type.Float()
                let typed_var = get_type_txt(ty, name: varname)
                emit("{typed_var} = (double)({value.name});")
                push(Value(name: varname, ty))
            Call(n_args, result_type):
                let args = pop_n(count: n_args)
                let callee = pop().name
                let args2: List[str] = List()
                for arg in args:
                    args2.append(arg.name)
                let arg_text = str_join(parts: args2, sep: ", ")
                case result_type:
                    Some(ty):
                        let varname = new_local_var()
                        let typed_var = get_type_txt(ty, name: varname)
                        emit("{typed_var} = {callee}({arg_text});")
                        push(Value(name: varname, ty))
                    None:
                        emit("{callee}({arg_text});")

            LocalGet(index):
                let varname = local_variables.get(index)
                push(varname)

            LocalSet(index):
                let value = pop()
                let varname = local_variables.get(index)
                emit("{varname.name} = {value.name};")

            ParameterGet(index):
                let varname = local_parameters.get(index)
                push(varname)

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

            Return(amount):
                if amount == 1:
                    let value = pop()
                    emit("return {value.name};")
                else:
                    emit("return;")

            LoadFunc(name):
                push(Value(name, ty: bc.Type.Ptr()))

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
                let arg_text = str_join(parts, sep: ",")
                emit("const int {varname} [{size}] = | {arg_text} |;")
                push(Value(name: varname, ty: bc.Type.Int()))

    fn get_type_txt(ty: bc.Type, name: str) -> str:
        case ty:
            Int:
                return "int {name}"
            Str:
                return "char* {name}"
            Float:
                return "double {name}"
            Ptr:
                return "void* {name}"
            StructRef(index):
                if structs.get(index).is_union:
                    return "union U{index}* {name}"
                else:
                    return "struct S{index}* {name}"
            Function(parameter_types):
                let parts: List[str] = List()
                for p in parameter_types:
                    parts.append(get_type_txt(ty: p, name: ""))
                let param_text = str_join(parts, sep: ", ")
                return "void (*{name})({param_text})"

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
        indentation += 1

    fn dedent():
        indentation -= 1

    fn emit(text?: str):
        let indent = str_repeat(text: "   ", count: indentation)
        print(indent + text)
