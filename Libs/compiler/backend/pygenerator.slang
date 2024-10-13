# Generate python code from AST.

import ast
from utils import panic, log_info
from datatypes import List, option_is_some, option_unwrap, Option
from std import float_to_str2, str_len, str_get, str_slice
from strlib import str_join
from text_gen import TextGenerator

fn gen_python(module_set: ast.ModuleSet, generate_runtime: bool, output_filename: Option[str]):
    log_info("Generating python code")
    let g = PyGenerator()
    g.out.begin(output_filename)
    g.emit("# ATTENTION: AUTOMATICALLY GENERATED PYTHON CODE AHEAD!")
    for module in module_set.modules:
        g.gen_module(module)
    if generate_runtime:
        g.emit("if __name__ == '__main__':")
        g.indent()
        g.emit("import sys")
        g.emit("sys.exit(main2())")
        g.dedent()
    g.out.end()

class PyGenerator:
    var out: TextGenerator = TextGenerator()
    var global_header: str = ""

    fn gen_module(module: ast.Module):
        let global_names: List[str] = List()
        for definition in module.definitions:
            case definition:
                Var(variable_def):
                    case variable_def.value:
                        Intern(value):
                            global_names.append(get_id(id: variable_def.variable.id))
                        Extern(libname, initialized):
                            pass
            else:
                pass
        if global_names.len() > 0:
            let names = str_join(parts: global_names, sep: ", ")
            global_header = "global {names}"
        else:
            global_header = ""

        for definition in module.definitions:
            gen_definition(definition)

    fn gen_definition(definition: ast.Definition):
        case definition:
            Macro(macro_def):
                pass
            Function(function_def):
                let parameter_names: List[str] = List()
                for parameter in function_def.parameters:
                    parameter_names.append(get_id(id: parameter.id))
                let params = str_join(parts: parameter_names, sep: ", ")
                
                case function_def.body:
                    Intern(scoped_block):
                        emit("def {function_def.name}({params}):")
                        if str_len(text: global_header) > 0:
                            indent()
                            emit(global_header)
                            dedent()
                        gen_block(scoped_block)
                        emit("")
                        emit("")
                    Extern(libname):
                        emit("from {libname} import {function_def.name}")

            Struct(struct_def):
                if struct_def.is_union:
                    panic("Unions not supported")
                emit("class {get_id(id: struct_def.id)}:")
                indent()
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
            Enum(enum_def):
                panic("enum-def not supported")
            Var(variable_def):
                case variable_def.value:
                    Intern(value):
                        emit("{get_id(id: variable_def.variable.id)} = {gen_expression(option_unwrap(value), parens: false)}")
                    Extern(libname, initialized):
                        emit("# external: from {libname} import {get_id(id: variable_def.variable.id)}")

    fn gen_block(block?: ast.ScopedBlock):
        indent()
        gen_statement(block.body)
        dedent()

    fn gen_statement(statement?: ast.Statement):
        case statement.kind:
            While(while_statement):
                emit("while {gen_expression(while_statement.condition, parens: false)}:")
                gen_block(while_statement.block)
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
                gen_block(try_statement.try_block)
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
                        let float_division = value.ty.is_float()
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
            panic("gen_statement: Unsupported: {statement}")

    fn gen_if_statement(if_statement: ast.IfStatement, kw: str):
        emit("{kw} {gen_expression(if_statement.condition, parens: false)}:")
        gen_block(if_statement.true_block)
        case if_statement.false_block.body.kind:
            If(if2):
                gen_if_statement(if_statement: if2, kw: "elif")
            Pass:
                pass
        else:
            emit("else:")
            gen_block(if_statement.false_block)

    fn gen_expression(expression?: ast.Expression, parens: bool) -> str:
        let txt = ""
        case expression.kind:
            BoolLiteral(v):
                if v:
                    txt = "True"
                else:
                    txt = "False"
            IntLiteral(v):
                txt = "{v}"
            StringLiteral(s):
                txt = "\"{escape_string(s)}\""
            CharLiteral(c):
                if c == '\' or c == '"':
                    txt = "\"\\{c}\""
                else:
                    txt = "\"{c}\""
            Null:
                txt = "None"
            FloatLiteral(value):
                txt = float_to_str2(value, digits: 20)
            StructLiteral(ty, values):
                let struct_def = ty.get_struct_def()
                let name = get_id(id: struct_def.id)
                let args = gen_expression_list(expressions: values)
                txt = "{name}({args})"
            ArrayLiteral(values):
                let args = gen_expression_list(expressions: values)
                txt = "[{args}]"
            ArrayLiteral2(size, ty):
                let size_txt = gen_expression(size, parens: false)
                txt = "[None] * {size_txt}"
            GetAttr(base, attr):
                let b = gen_expression(base, parens: true)
                txt = "{b}.{attr}"
            GetIndex(base, indici):
                let b = gen_expression(base, parens: true)
                let i = gen_expression_list(expressions: indici)
                txt = "{b}[{i}]"
            TypeCast(ty, value):
                txt = gen_expression(value, parens: true)
                if ty.is_float():
                    txt = "float({txt})"
                elif ty.is_int():
                    txt = "int({txt})"
                else:
                    panic("Cannot cast to {ty}")
            Box(value):
                txt = gen_expression(value, parens: true)
            Unbox(value, to_type):
                txt = gen_expression(value, parens: true)
            ParameterRef(parameter_def):
                txt = get_id(id: parameter_def.id)
            VarRef(variable):
                txt = get_id(id: variable.id)
            FunctionRef(function_def, type_arguments):
                txt = function_def.name
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
                let float_division = binop.lhs.ty.is_float()
                let op = binary_operator_to_str(op: binop.op, float_division)
                txt = "{gen_expression(binop.lhs, parens: true)} {op} {gen_expression(binop.rhs, parens: true)}"
                if parens:
                    txt = "({txt})"
        else:
            panic("Unsupported: {expression}")
        return txt
    
    fn gen_expression_list(expressions: List[ast.Expression]) -> str:
        let parts: List[str] = List()
        for expression in expressions:
            parts.append(gen_expression(expression, parens: false))
        return str_join(parts, sep: ", ")
    
    fn get_id(id: ast.NodeId) -> str:
        return "X{id.id}_{id.name}"

    fn emit(txt?: str):
        out.emit(txt)
    
    fn indent():
        out.indent()
    
    fn dedent():
        out.dedent()

fn binary_operator_to_str(op: ast.BinaryOperator, float_division: bool) -> str:
    let op_txt = ""
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

fn escape_string(text?: str) -> str:
    """ Prefix double quotes and backslashes with an extra backslash """
    let res = ""
    let index = 0
    let begin = 0
    let n = str_len(text)
    while index < n:
        let c = str_get(text, index)
        if c == '\' or c == '"':
            if begin < index:
                res = res + str_slice(text, begin, end: index)
            res = res + "\\{c}"
            begin = index + 1
        index += 1

    if begin == 0:
        return text
    else:
        if begin < index:
            res = res + str_slice(text, begin, end: index)
        return res
