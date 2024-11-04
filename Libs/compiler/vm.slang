
# Virtual machine for bytecode.

from datatypes import List, Option
from dicttype import Dictionary
from vectype import Vector, new_vector
from utils import panic, log_debug, log_info, assert, unimplemented
from bc import Instruction, Program, Function, instruction_to_string
from std import print, float_to_str
import std
import bc
import rt

enum Value:
    Int(value: int)
    Str(value: str)
    Char(value: char)
    Float(value: float)
    Bool(value: bool)
    List(list: ListValue)
    Null
    Undefined

enum FunctionRef:
    ByteCode(func: bc.Function)
    Native(func: ExternFunctionImpl)

struct ListValue:
    values: List[Value]

fn value_to_string(value?: Value) -> str:
    case value:
        Int(value):
            "int({value})"
        Str(value):
            "str({value})"
        Char(value):
            "char({value})"
        Float(value):
            "float({float_to_str(value)})"
        Bool(value):
            if value:
                "bool(true)"
            else:
                "bool(false)"
        List(values):
            "List(..)"
        Null:
            "Null"
        Undefined:
            "undefined"

fn bool_from_value(value?: Value) -> bool:
    case value:
        Bool(value):
            value
    else:
        panic("bool_from_value: no boolean")

fn str_from_value(value?: Value) -> str:
    case value:
        Str(value):
            value
    else:
        panic("str_from_value: no str")

fn int_from_value(value?: Value) -> int:
    case value:
        Int(value):
            value
    else:
        panic("int_from_value: no int")

fn char_from_value(value?: Value) -> char:
    case value:
        Char(value):
            value
    else:
        panic("char_from_value: no char")

fn float_from_value(value?: Value) -> float:
    case value:
        Float(value):
            value
    else:
        panic("float_from_value: no float")

fn list_from_value(value?: Value) -> ListValue:
    case value:
        List(list):
            list
    else:
        panic("list_from_value: no list")

struct ExternFunctionImpl:
    f: fn(List[Value]) -> Option[Value]
    n: int

fn efi_std_ord(arguments: List[Value]) -> Option[Value]:
    let value = std.ord(char_from_value(arguments[0]))
    Option.Some(Value.Int(value))

fn efi_std_chr(arguments: List[Value]) -> Option[Value]:
    let value = std.chr(int_from_value(arguments[0]))
    Option.Some(Value.Char(value))

fn efi_std_float_to_str(arguments: List[Value]) -> Option[Value]:
    let value = std.float_to_str(float_from_value(arguments[0]))
    Option.Some(Value.Str(value))

fn efi_std_float_to_str2(arguments: List[Value]) -> Option[Value]:
    let value = std.float_to_str2(value: float_from_value(arguments[0]), digits: int_from_value(arguments[1]))
    Option.Some(Value.Str(value))

fn efi_std_str_to_float(arguments: List[Value]) -> Option[Value]:
    let value = std.str_to_float(str_from_value(arguments[0]))
    Option.Some(Value.Float(value))

fn efi_std_str_len(arguments: List[Value]) -> Option[Value]:
    let text = str_from_value(arguments[0])
    let value = std.str_len(text)
    Option.Some(Value.Int(value))

fn efi_std_str_get(arguments: List[Value]) -> Option[Value]:
    let text = str_from_value(arguments[0])
    let index = int_from_value(arguments[1])
    let value = std.str_get(text, index)
    Option.Some(Value.Char(value))

fn efi_std_str_slice(arguments: List[Value]) -> Option[Value]:
    let text = str_from_value(arguments[0])
    let begin = int_from_value(arguments[1])
    let end = int_from_value(arguments[2])
    let value = std.str_slice(text, begin, end)
    Option.Some(Value.Str(value))

fn efi_std_print(arguments: List[Value]) -> Option[Value]:
    std.print(str_from_value(arguments.first()))
    Option.None()

fn efi_std_read_line(arguments: List[Value]) -> Option[Value]:
    let value = std.read_line(prompt: str_from_value(arguments.first()))
    Option.Some(Value.Str(value))

fn efi_default(arguments: List[Value]) -> Option[Value]:
    panic("Not impl EFI")
    Option.None()

fn efi_rt_int_to_str(arguments: List[Value]) -> Option[Value]:
    let value = rt.int_to_str(int_from_value(arguments[0]))
    Option.Some(Value.Str(value))

fn efi_rt_char_to_str(arguments: List[Value]) -> Option[Value]:
    let value = rt.char_to_str(char_from_value(arguments[0]))
    Option.Some(Value.Str(value))

fn efi_rt_str_concat(arguments: List[Value]) -> Option[Value]:
    let a = str_from_value(arguments[0])
    let b = str_from_value(arguments[1])
    # let value = rt.str_concat(a, b)
    let value = a + b
    Option.Some(Value.Str(value))

fn efi_rt_str_compare(arguments: List[Value]) -> Option[Value]:
    let a = str_from_value(arguments[0])
    let b = str_from_value(arguments[1])
    # let value = rt.str_compare(a, b)
    let value = a == b
    Option.Some(Value.Bool(value))

fn get_efi_db() -> Dictionary[ExternFunctionImpl]:
    # Link in external functions:
    let efi_db: Dictionary[ExternFunctionImpl] = Dictionary()

    # std:
    efi_db.insert(key: "std_ord", value: ExternFunctionImpl(f: efi_std_ord, n: 1))
    efi_db.insert(key: "std_chr", value: ExternFunctionImpl(f: efi_std_chr, n: 1))
    efi_db.insert(key: "std_float_to_str", value: ExternFunctionImpl(f: efi_std_float_to_str, n: 1))
    efi_db.insert(key: "std_float_to_str2", value: ExternFunctionImpl(f: efi_std_float_to_str2, n: 2))
    efi_db.insert(key: "std_str_to_float", value: ExternFunctionImpl(f: efi_std_str_to_float, n: 1))
    efi_db.insert(key: "std_str_len", value: ExternFunctionImpl(f: efi_std_str_len, n: 1))
    efi_db.insert(key: "std_str_get", value: ExternFunctionImpl(f: efi_std_str_get, n: 2))
    efi_db.insert(key: "std_str_slice", value: ExternFunctionImpl(f: efi_std_str_slice, n: 3))
    efi_db.insert(key: "std_print", value: ExternFunctionImpl(f: efi_std_print, n: 1))
    efi_db.insert(key: "std_read_line", value: ExternFunctionImpl(f: efi_std_read_line, n: 1))
    efi_db.insert(key: "std_get_path_separator", value: ExternFunctionImpl(f: efi_default, n: 0))
    efi_db.insert(key: "std_exit", value: ExternFunctionImpl(f: efi_default, n: 1))
    efi_db.insert(key: "std_read_file", value: ExternFunctionImpl(f: efi_default, n: 1))
    efi_db.insert(key: "std_file_open", value: ExternFunctionImpl(f: efi_default, n: 2))
    efi_db.insert(key: "std_file_writeln", value: ExternFunctionImpl(f: efi_default, n: 2))
    efi_db.insert(key: "std_file_read_n_bytes", value: ExternFunctionImpl(f: efi_default, n: 3))
    efi_db.insert(key: "std_file_write_n_bytes", value: ExternFunctionImpl(f: efi_default, n: 3))
    efi_db.insert(key: "std_file_close", value: ExternFunctionImpl(f: efi_default, n: 1))
    efi_db.insert(key: "std_get_n_args", value: ExternFunctionImpl(f: efi_default, n: 0))
    efi_db.insert(key: "std_get_arg", value: ExternFunctionImpl(f: efi_default, n: 1))
    
    # rt:
    efi_db.insert(key: "rt_int_to_str", value: ExternFunctionImpl(f: efi_rt_int_to_str, n: 1))
    efi_db.insert(key: "rt_char_to_str", value: ExternFunctionImpl(f: efi_rt_char_to_str, n: 1))
    efi_db.insert(key: "rt_str_concat", value: ExternFunctionImpl(f: efi_rt_str_concat, n: 2))
    efi_db.insert(key: "rt_str_compare", value: ExternFunctionImpl(f: efi_rt_str_compare, n: 2))
    efi_db

fn run_bytecode(program: Program, entry_function: str):
    let vm = VirtualMachine()
    vm.structs = program.structs

    # Link external functions:
    let efi_db = get_efi_db()
    for e in program.extern_functions:
        if efi_db.contains(key: e.name):
            let efi = efi_db.get(key: e.name)
            assert(condition: e.parameters.len() == efi.n, message: "n should match len(parameters)")
            vm.m_functions.append(FunctionRef.Native(efi))
        else:
            panic("Missing extern function: {e.name}")
    for f in program.functions:
        vm.m_functions.append(FunctionRef.ByteCode(f))

    # Initialize global variables:
    for g in program.globals:
        case g.value:
            Some(value):
                vm.globals.append(eval_code(vm, code: value))
            None:
                unimplemented("External variables")

    let top_frame = Frame(code: new_vector())
    vm.push_frame(frame: top_frame)

    # Create mapping from names to index:
    let function_name_to_index: Dictionary[int] = Dictionary()
    let index = 0
    for function in program.functions:
        function_name_to_index.insert(key: function.name, value: index)
        index += 1
    let entry_function_index = function_name_to_index.get(key: entry_function)

    let function = program.functions[entry_function_index]
    let arguments: List[Value] = List()
    let frame = frame_from_function(function, arguments)
    vm.push_frame(frame)
    while vm.frames.len() > 1:
        vm.step()

fn eval_code(vm: VirtualMachine, code: Vector[Instruction]) -> Value:
    """ Evaluate a bytecode expression """
    let top_frame = Frame(code: new_vector())
    vm.push_frame(frame: top_frame)

    let frame = Frame(code)
    vm.push_frame(frame)
    while vm.frames.len() > 1:
        vm.step()

    vm.pop_frame().stack.last()


fn frame_from_function(function: Function, arguments: List[Value]) -> Frame:
    let frame = Frame(code: function.instructions)
    for x in function.parameters:
        pass
    
    for x in arguments:
        frame.arguments.append(x)

    # Fill space for local variables:
    for x in function.locals:
        frame.locals.append(Value.Undefined())
    frame

struct ExceptionHandler:
    except_label: int

class Frame:
    var arguments: List[Value] = List()
    var locals: List[Value] = List()
    var stack: List[Value] = List()
    var exception_handlers: List[ExceptionHandler] = List()
    var pc: int = 0
    var code: Vector[Instruction]

    fn fetch() -> Instruction:
        let instruction = code[pc]
        pc += 1
        instruction

class VirtualMachine:
    var frames: List[Frame] = List()
    var globals: List[Value] = List()
    var exception_value: Value = Value.Undefined()
    var m_functions: List[FunctionRef] = List()
    var structs: List[bc.Struct] = List()

    fn step():
        let instruction = fetch()
        execute(instruction)

    fn fetch() -> Instruction:
        frames.last().fetch()

    fn execute(instruction: Instruction):
        log_debug("Executing: {instruction_to_string(instruction)}")
        case instruction:
            Nop:
                pass
            Dup:
                let value = pop()
                push(value)
                push(value)
            Literal(literal):
                case literal:
                    Int(val):
                        push(Value.Int(val))
                    Str(val):
                        push(Value.Str(val))
                    Char(value):
                        push(Value.Char(value))
                    Bool(val):
                        push(Value.Bool(val))
                    Float(val):
                        push(Value.Float(val))
                    Null:
                        push(Value.Null())
            LocalGet(index):
                let value = get_local(index)
                push(value)
            LocalSet(index):
                set_local(index, value: pop())
            GlobalGet(index):
                let value = get_global(index)
                push(value)
            GlobalSet(index):
                set_global(index, value: pop())
            ParameterGet(index):
                let value = get_parameter(index)
                push(value)
            ParameterSet(index):
                set_parameter(index, value: pop())
            GetAttr(index):
                let base = pop()
                let list = list_from_value(base)
                let value = list.values.get(index)
                push(value)
            SetAttr(index):
                let value = pop()
                let base = pop()
                let list = list_from_value(base)
                list.values.set(index, value)
            GetIndex:
                let index = pop()
                let base = pop()
                let list = list_from_value(base)
                let index2 = int_from_value(index)
                let value = list.values.get(index: index2)
                push(value)
            SetIndex:
                let value = pop()
                let index = pop()
                let base = pop()
                let list = list_from_value(base)
                let index2 = int_from_value(index)
                list.values.set(index: index2, value)
            Not:
                let value = pop()
                if bool_from_value(value):
                    push(Value.Bool(false))
                else:
                    push(Value.Bool(true))
            Neg:
                let value = pop()
                case value:
                    Int(v):
                        push(Value.Int(-v))
                    Float(v):
                        push(Value.Float(-v))
                else:
                    panic("Cannot negate: {value_to_string(value)}")
            Comparison(op):
                let rhs = pop()
                let lhs = pop()
                case lhs:
                    Int(lhs_value):
                        let rhs_value = int_from_value(rhs)
                        let value = eval_comparison_int(op, lhs: lhs_value, rhs: rhs_value)
                        push(Value.Bool(value))
                    Float(lhs_value):
                        let rhs_value = float_from_value(rhs)
                        let value = eval_comparison_float(op, lhs: lhs_value, rhs: rhs_value)
                        push(Value.Bool(value))
                    List(values):
                        case rhs:
                            Null:
                                push(Value.Bool(false))
                        else:
                            panic("Cannot compare list to: {value_to_string(rhs)}")
                    Null:
                        case rhs:
                            Null:
                                push(Value.Bool(true))
                        else:
                            panic("Cannot compare null to: {value_to_string(rhs)}")
                else:
                    panic("Cannot compare: {value_to_string(lhs)}")
            Binop(op):
                let rhs = pop()
                let lhs = pop()
                case lhs:
                    Int(lhs_value):
                        let rhs_value = int_from_value(rhs)
                        let value = eval_binop_int(op, lhs: lhs_value, rhs: rhs_value)
                        push(Value.Int(value))
                    Float(lhs_value):
                        let rhs_value = float_from_value(rhs)
                        let value = eval_binop_float(op, lhs: lhs_value, rhs: rhs_value)
                        push(Value.Float(value))
                else:
                    panic("Cannot binop")
            Bitop(op):
                let rhs = pop()
                let lhs = pop()
                let lhs_value = int_from_value(lhs)
                let rhs_value = int_from_value(rhs)
                let value = eval_bitop(op, lhs: lhs_value, rhs: rhs_value)
                push(Value.Int(value))
            IntToFloat:
                let value = int_from_value(value: pop())
                let f = float(value)
                push(Value.Float(f))
            FloatToInt:
                let value = float_from_value(value: pop())
                let f = int(value)
                push(Value.Int(f))
            IntCast(signed, bits):
                pass # No-op?
            FromOpaque(ty):
                pass  # VM values are all opaque
            ToOpaque(ty):
                pass  # VM values are all opaque
            Jump(target):
                jump(target)
            JumpIf(target, target2):
                let value = pop()
                if bool_from_value(value):
                    jump(target)
                else:
                    jump(target2)
            Call(index):
                log_debug("Call function!")
                let function_ref = m_functions.get(index)
                case function_ref:
                    ByteCode(function):
                        let n = function.parameters.len()
                        let arguments = pop_n(count: n)
                        let frame = frame_from_function(function, arguments)
                        push_frame(frame)
                    Native(efi):
                        let arguments = pop_n(count: efi.n)
                        case efi.f(arguments):
                            Some(value):
                                push(value)
                            None:
                                pass
            CallIndirect(parameter_types, return_type):
                let func_pointer = pop()
                let index = int_from_value(func_pointer)
                let n = parameter_types.len()
                let arguments = pop_n(count: n)
                let function_ref = m_functions.get(index)
                case function_ref:
                    ByteCode(function):
                        let frame = frame_from_function(function, arguments)
                        push_frame(frame)
                    Native(efi):
                        case efi.f(arguments):
                            Some(value):
                                push(value)
                            None:
                                pass
            Return(amount):
                if amount == 1:
                    let value = pop()
                    let stub_frame = pop_frame()
                    push(value)
                else:
                    let stub_frame = pop_frame()
            Unreachable:
                panic("Reached unreachable")
            SetupTry(try_label, except_label):
                frames.last().exception_handlers.append(ExceptionHandler(except_label))
                jump(try_label)
            Raise:
                # Find matching exception handler in inner most frame!
                exception_value = pop()
                loop:
                    if frames.is_empty():
                        panic("No exception handler found!")
                    else:
                        let frame = frames.last()
                        if frame.exception_handlers.is_empty():
                            frames.drop_last()
                        else:
                            let handler = frame.exception_handlers.last()
                            jump(handler.except_label)
                            break
            PopTry:
                frames.last().exception_handlers.drop_last()
            DecRef(index):
                print("TODO?: dec ref {index}")
            GetExceptionValue:
                push(exception_value)
            LoadFunc(index):
                push(Value.Int(index))
            StructLiteral(struct_index):
                let struc = structs[struct_index]
                let count = struc.fields.len()
                let values = pop_n(count)
                let list = ListValue(values)
                push(Value.List(list))
            ArrayLiteral(count):
                let values = pop_n(count)
                let list = ListValue(values)
                push(Value.List(list))
            ArrayLiteral2(ty):
                let size = pop()
                let value = Value.Undefined()
                let size2 = int_from_value(size)
                let values: List[Value] = List()
                while size2 > 0:
                    size2 -= 1
                    values.append(value)
                let list = ListValue(values)
                push(Value.List(list))
    
    fn push(value?: Value):
        frames.last().stack.append(value)
    
    fn pop() -> Value:
        frames.last().stack.pop_last()
    
    fn pop_n(count: int) -> List[Value]:
        let values: List[Value] = List()
        while count > 0:
            let val = pop()
            values.prepend(val)
            count -= 1
        values
    
    fn jump(pc?: int):
        frames.last().pc = pc

    fn get_local(index: int) -> Value:
        frames.last().locals.get(index)
    
    fn set_local(index: int, value: Value):
        frames.last().locals.set(index, value)
    
    fn get_parameter(index: int) -> Value:
        frames.last().arguments.get(index)

    fn set_parameter(index: int, value: Value):
        frames.last().arguments.set(index, value)

    fn get_global(index: int) -> Value:
        globals.get(index)

    fn set_global(index: int, value: Value):
        globals.set(index, value)

    fn pop_frame() -> Frame:
        frames.pop_last()

    fn push_frame(frame: Frame):
        frames.append(frame)


fn eval_binop_int(op: bc.BinaryOperator, lhs: int, rhs: int) -> int:
    case op:
        Add:
            lhs + rhs
        Sub:
            lhs - rhs
        Divide:
            lhs / rhs
        Multiply:
            lhs * rhs

fn eval_comparison_int(op: bc.ComparisonOperator, lhs: int, rhs: int) -> bool:
    case op:
        Less:
            lhs < rhs
        LessEquals:
            lhs <= rhs
        Greater:
            lhs > rhs
        GreaterEquals:
            lhs >= rhs
        Equals:
            lhs == rhs
        NotEquals:
            lhs != rhs

fn eval_binop_float(op: bc.BinaryOperator, lhs: float, rhs: float) -> float:
    case op:
        Add:
            lhs + rhs
        Sub:
            lhs - rhs
        Divide:
            lhs / rhs
        Multiply:
            lhs * rhs

fn eval_comparison_float(op: bc.ComparisonOperator, lhs: float, rhs: float) -> bool:
    case op:
        Less:
            lhs < rhs
        LessEquals:
            lhs <= rhs
        Greater:
            lhs > rhs
        GreaterEquals:
            lhs >= rhs
        Equals:
            lhs == rhs
        NotEquals:
            lhs != rhs

fn eval_bitop(op: bc.BitOperator, lhs: int, rhs: int) -> int:
    case op:
        Shr:
            lhs >> rhs
        Shl:
            lhs << rhs
        And:
            lhs & rhs
        Or:
            lhs | rhs
        Xor:
            lhs ^ rhs
