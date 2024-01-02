# Generate python code from AST.

import ast
from utils import panic, log_info
from datatypes import List, option_is_some, option_unwrap, Option
from std import float_to_str, chr, str_len
from strlib import str_join, str_repeat
from text_gen import TextGenerator

fn gen_python(module_set: ast.ModuleSet, generate_runtime: bool, output_filename: Option[str]):
    log_info("Generating python code")
    let g = PyGenerator()
    g.out.begin(output_filename)
    if generate_runtime:
        g.emit_runtime()
    g.emit("# ATTENTION: AUTOMATICALLY GENERATED PYTHON CODE AHEAD!")
    for module in module_set.modules:
        g.gen_module(module)
    if generate_runtime:
        g.emit("sys.exit(main2())")
    g.out.end()

class PyGenerator:
    var out: TextGenerator = TextGenerator()
    var global_header: str = ""

    fn gen_module(module: ast.Module):
        let global_names: List[str] = List()
        for definition in module.definitions:
            case definition:
                Var(variable_def):
                    global_names.append(get_id(id: variable_def.variable.id))
            else:
                pass
        if global_names.len() > 0:
            let names = str_join(parts: global_names, sep: ", ")
            global_header = "global {names}"
        else:
            global_header = ""

        for definition in module.definitions:
            gen_definition(definition)

    fn emit_runtime():
        # Print out runtime functions required
        # TODO: figure out multiline string support?
        # TBD: how to handle multiline strings. Do we want this?
        let quote = chr(34)
        let left_brace = chr(123)
        let right_brace = chr(125)
        emit("import sys")
        emit("std_print = print")
        emit("rt_int_to_str = str")
        emit("std_str_to_int = int")
        emit("std_float_to_str = lambda x: f{quote}{left_brace}x:f{right_brace}{quote}")
        emit("std_str_to_float = float")
        emit("rt_char_to_str = str")
        emit("std_str_len = len")
        emit("def std_str_get(s, i):  return s[i]")
        emit("def std_str_slice(s,b,e):   return s[b:e]")
        emit("def rt_str_concat(a, b):  return a + b")
        emit("def rt_str_compare(a, b):  return a == b")
        emit("std_ord = ord")
        emit("std_chr = chr")
        emit("def std_get_n_args() -> int: return len(sys.argv) - 1")
        emit("def std_get_arg(index) -> str:  return sys.argv[index + 1]")
        emit("def std_exit(code: int): raise RuntimeError('EXIT with code: ' + str(code))")
        
        emit("def std_read_file(filename: str) -> str:")
        indent()
        emit("with open(filename, 'r') as f:")
        indent()
        emit("return f.read()")
        dedent()
        dedent()
        
        emit("def std_file_open(filename: str) -> int:")
        indent()
        emit("return open(filename, 'w')")
        dedent()

        emit("def std_file_writeln(handle, text: str):")
        indent()
        emit("print(text, file=handle)")
        dedent()

        emit("def std_file_close(handle):")
        indent()
        emit("handle.close()")
        dedent()

    fn gen_definition(definition: ast.Definition):
        case definition:
            Function(function_def):
                let parameter_names: List[str] = List()
                for parameter in function_def.parameters:
                    parameter_names.append(get_id(id: parameter.id))
                let params = str_join(parts: parameter_names, sep: ", ")
                emit("def {get_id(id: function_def.id)}({params}):")
                if str_len(global_header) > 0:
                    indent()
                    emit(global_header)
                    dedent()
                gen_block(function_def.body)
                emit("")
                emit("")
            Struct(struct_def):
                emit("class {get_id(id: struct_def.id)}:")
                indent()
                if struct_def.is_union:
                    emit("def __init__(self, field, value):")
                    indent()
                    emit("setattr(self, field, value)")
                    dedent()
                else:
                    let parameter_names: List[str] = List()
                    for field in struct_def.fields:
                        parameter_names.append(field.name)
                    let params = str_join(parts: parameter_names, sep: ", ")
                    emit("def __init__(self, {params}):")
                    indent()
                    for field in struct_def.fields:
                        emit("self.{field.name} = {field.name}")
                    dedent()
                dedent()
                emit("")
                emit("")
            Class(class_def):
                panic("class-def not supported")
            ExternFunction(extern_function_def):
                emit("# Using external function: {extern_function_def.modname}_{extern_function_def.name}")
            Enum(enum_def):
                panic("enum-def not supported")
            Var(variable_def):
                emit("{get_id(id: variable_def.variable.id)} = {gen_expression(option_unwrap(variable_def.value), parens: false)}")

    fn gen_block(body?: ast.Statement):
        indent()
        gen_statement(body)
        dedent()

    fn gen_statement(statement?: ast.Statement):
        case statement.kind:
            While(while_statement):
                emit("while {gen_expression(while_statement.condition, parens: false)}:")
                gen_block(while_statement.block.body)
            Let(let_statement):
                emit("{get_id(id: let_statement.variable.id)} = {gen_expression(let_statement.value, parens: false)}")
            If(if_statement):
                gen_if_statement(if_statement, kw: "if")
            Pass:
                emit("pass")
            Break:
                emit("break")
            Continue:
                emit("continue")
            Try(try_statement):
                emit("try:")
                gen_block(try_statement.try_block.body)
                let ex_name = "ex_{get_id(id: try_statement.except_var.id)}"
                emit("except ValueError as {ex_name}:")
                indent()
                emit("{get_id(id: try_statement.except_var.id)} = {ex_name}.args[0]")
                gen_statement(try_statement.except_block.body)
                dedent()
            Assignment(target, op, value):
                let op_txt = ""
                case op:
                    None:
                        op_txt = "="
                    Some(op3):
                        let float_division = ast.is_float_type(value.ty)
                        op_txt = "{binary_operator_to_str(op: op3, float_division)}="
                emit("{gen_expression(target, parens: true)} {op_txt} {gen_expression(value, parens: false)}")
            Return(value):
                case value:
                    None:
                        emit("return")
                    Some(value2):
                        emit("return {gen_expression(value2, parens: false)}")
            Raise(value):
                emit("raise ValueError({gen_expression(value, parens: false)})")
            Compound(inner):
                for s in inner:
                    gen_statement(s)
            Expr(expr):
                emit(gen_expression(expr, parens: true))
            Unreachable:
                emit("raise RuntimeError('unreachable')")
        else:
            panic("Unsupported: {ast.statement_to_string(statement)}")

    fn gen_if_statement(if_statement: ast.IfStatement, kw: str):
        emit("{kw} {gen_expression(if_statement.condition, parens: false)}:")
        gen_block(if_statement.true_block.body)
        case if_statement.false_block.body.kind:
            If(if2):
                gen_if_statement(if_statement: if2, kw: "elif")
            Pass:
                pass
        else:
            emit("else:")
            gen_block(if_statement.false_block.body)

    fn gen_expression(expression?: ast.Expression, parens: bool) -> str:
        let txt = "?"
        case expression.kind:
            BoolLiteral(v):
                if v:
                    txt = "True"
                else:
                    txt = "False"
            IntLiteral(v):
                txt = "{v}"
            StringLiteral(s):
                # TODO: implement escaping in string literals
                txt = "{chr(34)}{s}{chr(34)}"
            CharLiteral(s):
                # TODO: implement escaping in string literals
                txt = "{chr(34)}{s}{chr(34)}"
            FloatLiteral(value):
                txt = float_to_str(value)
            StructLiteral(ty, values):
                let struct_def = ast.get_struct_def_from_type(ty)
                let name = get_id(id: struct_def.id)
                let args = gen_expression_list(expressions: values)
                txt = "{name}({args})"
            UnionLiteral(ty, field, value):
                let struct_def = ast.get_struct_def_from_type(ty)
                let name = get_id(id: struct_def.id)
                let value_txt = gen_expression(value, parens: true)
                txt = "{name}('{field}', {value_txt})"
            ArrayLiteral(values):
                let args = gen_expression_list(expressions: values)
                txt = "[{args}]"
            ArrayLiteral2(value, size):
                let value_txt = gen_expression(value, parens: false)
                let size_txt = gen_expression(size, parens: false)
                txt = "[{value_txt}] * {size_txt}"
            GetAttr(base, attr):
                let b = gen_expression(base, parens: true)
                txt = "{b}.{attr}"
            GetIndex(base, indici):
                let b = gen_expression(base, parens: true)
                let i = gen_expression_list(expressions: indici)
                txt = "{b}[{i}]"
            TypeCast(ty, value):
                txt = gen_expression(value, parens: true)
                if ast.is_float_type(ty):
                    txt = "float({txt})"
                elif ast.is_int_type(ty):
                    txt = "int({txt})"
            ExternFunctionRef(extern_function_def):
                txt = "{extern_function_def.modname}_{extern_function_def.name}"
            ParameterRef(parameter_def):
                txt = get_id(id: parameter_def.id)
            VarRef(variable):
                txt = get_id(id: variable.id)
            FunctionRef(function_def, type_parameters):
                txt = get_id(id: function_def.id)
            Call(call):
                let expressions: List[ast.Expression] = List()
                for argument in call.arguments:
                    expressions.append(argument.value)
                let argument_text = gen_expression_list(expressions)
                txt = "{gen_expression(call.callee, parens: true)}({argument_text})"
            Unop(op, value):
                let op2 = "$"
                case op:
                    Not:
                        op2 = "not "
                    Minus:
                        op2 = "-"
                txt = "{op2}{gen_expression(value, parens: true)}"
                if parens:
                    txt = "({txt})"
            Binop(binop):
                let float_division = ast.is_float_type(binop.lhs.ty)
                let op = binary_operator_to_str(op: binop.op, float_division)
                txt = "{gen_expression(binop.lhs, parens: true)} {op} {gen_expression(binop.rhs, parens: true)}"
                if parens:
                    txt = "({txt})"
        else:
            panic("Unsupported: {ast.expression_to_string(expression)}")
        return txt
    
    fn gen_expression_list(expressions: List[ast.Expression]) -> str:
        let parts: List[str] = List()
        for expression in expressions:
            parts.append(gen_expression(expression, parens: false))
        return str_join(parts, sep: ", ")
    
    fn get_id(id: ast.NodeId) -> str:
        if id.name == "main":
            return "{id.name}2"
        else:
            return "X{id.id}_{id.name}"

    fn emit(txt?: str):
        out.emit(txt)
    
    fn indent():
        out.indent()
    
    fn dedent():
        out.dedent()

fn binary_operator_to_str(op: ast.BinaryOperator, float_division: bool) -> str:
    let op_txt = "?"
    case op:
        And:
            op_txt = "and"
        Or:
            op_txt = "or"
        Greater:
            op_txt = ">"
        GreaterEquals:
            op_txt = ">="
        Less:
            op_txt = "<"
        LessEquals:
            op_txt = "<="
        Equals:
            op_txt = "=="
        NotEquals:
            op_txt = "!="
        Add:
            op_txt = "+"
        Sub:
            op_txt = "-"
        Mul:
            op_txt = "*"
        Div:
            if float_division:
                op_txt = "/"
            else:
                op_txt = "//"
        BitAnd:
            op_txt = "&"
        BitXor:
            op_txt = "^"
        BitOr:
            op_txt = "|"
        ShiftLeft:
            op_txt = "<<"
        ShiftRight:
            op_txt = ">>"

    return op_txt
