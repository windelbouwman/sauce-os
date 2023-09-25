
# C code backend

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
    for struct0 in program.structs:
        g.emit("struct S{index};")
        index += 1
    
    # Struct definitions:
    index = 0
    for struct1 in program.structs:
        g.gen_struct_def(sidx: index, struct1)
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
    ty: str
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
        this.emit("// runtime functions:")

        this.emit("void* rt_malloc(int size);")
        this.emit("void rt_incref(void *ptr);")
        this.emit("void rt_decref(void *ptr);")

        this.emit("void std_print(char *message);")
        this.emit("void std_exit(int code);")

        this.emit("char* std_read_file(char *filename);")

        this.emit("char* rt_str_concat(char*, char*);")
        this.emit("int rt_str_compare(char *a, char *b);")
        this.emit("int std_str_len(char* txt);")
        this.emit("char* std_str_slice(char* txt, int begin, int end);")
        this.emit("char* std_str_get(char* txt, int pos);")

        this.emit("int std_ord(char *txt);")
        this.emit("char *std_int_to_str(int x);")
        this.emit("int std_str_to_int(char *x);")

    fn gen_struct_def(sidx: int, struct1: bc.Struct):
        this.emit("struct S{sidx} {chr(123)}")
        this.indent()
        let index = 0
        for field in struct1.fields:
            let ty = this.get_type_txt(ty: field)
            this.emit("{ty} field{index};")
            index += 1
        this.dedent()
        this.emit("{chr(125)};")

    fn get_function_decl(function: bc.Function, fill_param: bool) -> str:
        let parameters2: List[str] = List()
        let index = 0
        for p in function.parameters:
            let pty = this.get_type_txt(ty: p)
            let pname = "P{index}"
            if fill_param:
                this.local_parameters.append(Value(name: pname, ty: pty))
            parameters2.append("{pty} {pname}")
            index += 1
        let param_txt = str_join(parts: parameters2, sep: ", ")

        let return_type = "void"
        case function.return_type:
            Some(ty):
                return_type = this.get_type_txt(ty)
            None:
                pass
        return "{return_type} {function.name}({param_txt})"

    fn gen_function(function: bc.Function):
        this.next_id = 1
        this.local_variables = List()
        this.local_parameters = List()

        let decl = this.get_function_decl(function, fill_param: true)
        # TODO: allow string literal escaping
        this.emit("{decl} {chr(123)}")  # '{' = 123
        this.indent()
        for ty in function.locals:
            let varname = this.new_local_var()
            let ty_txt = this.get_type_txt(ty)
            this.emit("{ty_txt} {varname};")
            this.local_variables.append(Value(name: varname, ty: ty_txt))

        let target_labels = get_target_labels(instructions: function.instructions)
        let index = 0
        for instruction in function.instructions:
            if target_labels.contains(int_to_str(index)):
                this.emit("{this.get_label_str(index)}:")
            this.gen_instruction(instruction)
            index += 1
        this.dedent()
        this.emit("{chr(125)}") # '}' => 125

    fn gen_instruction(instruction: bc.Instruction):
        case instruction:
            Nop:
                pass
            Dup:
                let value = this.pop()
                this.push(value)
                this.push(value)

            Literal(literal):
                case literal:
                    Int(value):
                        this.push(Value(name: "{value}", ty: "int"))
                    Float(value):
                        this.push(Value(name: "{float_to_str(value)}", ty: "float"))
                    Str(value):
                        this.push(Value(name: "{chr(34)}{value}{chr(34)}", ty: "char*"))
                    Bool(value):
                        if value:
                            this.push(Value(name: "1", ty: "int"))
                        else:
                            this.push(Value(name: "0", ty: "int"))

            Jump(label):
                this.emit("goto {this.get_label_str(label)};")
            JumpIf(label1, label2):
                let condition = this.pop()
                this.emit("if ({condition.name}) goto {this.get_label_str(label1)}; else goto {this.get_label_str(label2)};")
            Not:
                panic("TODO: not")
            Neg:
                panic("TODO: neg")
            
            Binop(op):
                let rhs = this.pop()
                let lhs = this.pop()
                let varname = this.new_local_var()
                let varType = "int" # TODO
                case op:
                    Add:
                        this.emit("const {varType} {varname} = {lhs.name} + {rhs.name};")
                    Sub:
                        this.emit("const {varType} {varname} = {lhs.name} - {rhs.name};")
                    Multiply:
                        this.emit("const {varType} {varname} = {lhs.name} * {rhs.name};")
                    Divide:
                        this.emit("const {varType} {varname} = {lhs.name} / {rhs.name};")

                    Less:
                        this.emit("const {varType} {varname} = {lhs.name} < {rhs.name};")
                    LessEquals:
                        this.emit("const {varType} {varname} = {lhs.name} <= {rhs.name};")
                    Greater:
                        this.emit("const {varType} {varname} = {lhs.name} > {rhs.name};")
                    GreaterEquals:
                        this.emit("const {varType} {varname} = {lhs.name} >= {rhs.name};")
                    Equals:
                        this.emit("const {varType} {varname} = {lhs.name} == {rhs.name};")
                    NotEquals:
                        this.emit("const {varType} {varname} = {lhs.name} != {rhs.name};")
                this.push(Value(name: varname, ty: varType))

            Call(n_args, result_type):
                let args = this.pop_n(count: n_args)
                let callee = this.pop().name
                let args2: List[str] = List()
                for arg in args:
                    args2.append(arg.name)
                let arg_text = str_join(parts: args2, sep: ", ")
                case result_type:
                    Some(ty):
                        let varname = this.new_local_var()
                        let ty_txt = this.get_type_txt(ty)
                        this.emit("{ty_txt} {varname} = {callee}({arg_text});")
                        this.push(Value(name: varname, ty: ty_txt))
                    None:
                        this.emit("{callee}({arg_text});")

            LocalGet(index):
                let varname = this.local_variables.get(index)
                this.push(varname)
            LocalSet(index):
                let value = this.pop()
                let varname = this.local_variables.get(index)
                this.emit("{varname.name} = {value.name};")
            ParameterGet(index):
                let varname = this.local_parameters.get(index)
                this.push(varname)
            GetAttr(index, ty0):
                let base = this.pop()
                let ty = this.get_type_txt(ty: ty0)
                let varname = this.new_local_var()
                this.emit("{ty} {varname} = {base.name}->field{index};")
                this.push(Value(name: varname, ty))
            SetAttr(index):
                let value = this.pop()
                let base = this.pop()
                this.emit("{base.name}->field{index} = {value.name};")
            Return(amount):
                if amount == 1:
                    let value = this.pop()
                    this.emit("return {value.name};")
                else:
                    this.emit("return;")

            LoadFunc(name):
                this.push(Value(ty: "void", name))

            StructLiteral(index):
                # we can derive count from struct type:
                let struct_def = this.structs.get(index)
                let values = this.pop_n(count: struct_def.fields.len())
                # Malloc it!
                let varname = this.new_local_var()
                let ty = "struct S{index}*"
                this.emit("{ty} {varname} = rt_malloc(sizeof(struct S{index}));")
                let index2 = 0
                for value in values:
                    this.emit("{varname}->field{index2} = {value.name};")
                    index2 += 1
                this.push(Value(name: varname, ty))
            UnionLiteral(field):
                panic("TODO: union literal")
            ArrayLiteral(size):
                let varname = this.new_local_var()
                let values = this.pop_n(count: size)
                let parts: List[str] = List()
                for value in values:
                    parts.append(value.name)
                let arg_text = str_join(parts, sep: ",")
                this.emit("const int {varname} [{size}] = | {arg_text} |;")
                this.push(Value(name: varname, ty: "int"))

    fn get_type_txt(ty: bc.Type) -> str:
        case ty:
            Int:
                return "int"
            Str:
                return "char*"
            Float:
                return "float"
            Ptr:
                return "void*"
            StructRef(index):
                return "struct S{index}*"

    fn push(value?: Value):
        this.stack.append(value)
    
    fn pop_n(count: int) -> List[Value]:
        let values: List[Value] = List()
        while count > 0:
            let val = this.pop()
            values.append(val)
            count -= 1
        return values.reversed()

    fn pop() -> Value:
        return this.stack.pop_last()
    
    fn get_label_str(index?: int) -> str:
        return "L{index}"
    
    fn new_local_var() -> str:
        let id = this.next_id
        this.next_id += 1
        return "VAR{id}"

    fn indent():
        this.indentation += 1

    fn dedent():
        this.indentation -= 1

    fn emit(text?: str):
        let indent = str_repeat(text: "  ", count: this.indentation)
        print(indent + text)
