
# Idea: This backend emits slang code, sort of a no-op operation?

from utils import panic, log_info
from std import float_to_str
from strlib import str_join
import ast
from text_gen import TextGenerator
from datatypes import Option, option_unwrap, List

fn gen_slang(module_set: ast.ModuleSet, output_filename: Option[str]):
    """ Create slang-lang source code."""
    log_info("Generating slang code")
    let g = SlangGenerator()
    g.out.begin(output_filename)
    for module in module_set.modules:
        g.gen_module(module)
    g.out.end()

class SlangGenerator:
    var out: TextGenerator = TextGenerator()

    fn gen_module(module: ast.Module):
        for definition in module.definitions:
            gen_definition(definition)

    fn gen_definition(definition: ast.Definition):
        case definition:
            Function(function_def):
                let parameter_texts: List[str] = List()
                for parameter in function_def.parameters:
                    # All parameter labels are optional..
                    parameter_texts.append("{get_id(parameter.id)}?: {gen_type(parameter.ty)}")
                let params = str_join(parts: parameter_texts, sep: ", ")
                let return_types = ""
                if not function_def.info.return_type.is_void():
                    return_types = return_types + " -> {gen_type(function_def.info.return_type)}"
                if not function_def.info.except_type.is_void():
                    return_types = return_types + " -> {gen_type(function_def.info.except_type)}"

                case function_def.body:
                    Intern(scoped_block):
                        emit("fn {function_def.name}({params}){return_types}:")
                        gen_block(scoped_block)
                    Extern(libname):
                        emit("extern \"{libname}\" fn {function_def.name}({params}){return_types}")
            Struct(struct_def):
                let struct_name = get_id(struct_def.id)
                emit("struct {struct_name}:")
                indent()
                for field in struct_def.fields:
                    let typed_name = gen_type(field.ty)
                    emit("{field.name}: {gen_type(field.ty)}")
                dedent()
            Var(variable_def):
                let variable_name = get_id(variable_def.variable.id)
                emit("var {variable_name} = 0")
        else:
            panic("gen_definition: Unsupported: {ast.definition_to_str(definition)}")
        emit("")
    
    fn gen_type(ty?: ast.Type) -> str:
        if ty.is_int():
            let bits = ty.get_bits()
            if ty.is_signed_int():
                return "int{bits}"
            else:
                return "uint{bits}"
        elif ty.is_bool():
            return "bool"
        elif ty.is_str():
            return "str"
        elif ty.is_float():
            return "float"
        elif ty.is_char():
            return "char"
        elif ty.is_struct():
            let struct_def = ty.get_struct_def()
            let struct_name = get_id(struct_def.id)
            return struct_name
        elif ty.is_opaque():
            return "ptr"
        elif ty.is_array():
            let ety = ty.get_element_type()
            return "[{gen_type(ety)}]"
        elif ty.is_function_type():
            let ret_ty = ty.get_return_type()
            let parts: List[str] = List()
            for param_ty in ast.get_parameter_types_from_type(ty):
                parts.append(gen_type(param_ty.ty))
            let params = str_join(parts, sep: ", ")
            let suffix = ""
            if not ret_ty.is_void():
                suffix = suffix + " -> {gen_type(ret_ty)}"
            return "fn ({params}){suffix}"
        else:
            panic("gen_type: Unsupported: {ty}")

    fn gen_block(block?: ast.ScopedBlock):
        indent()
        gen_statement(block.body)
        dedent()

    fn gen_statement(statement?: ast.Statement):
        case statement.kind:
            While(while_statement):
                emit("while {gen_expression(while_statement.condition, parens: false)}:")
                gen_block(while_statement.block)
            If(if_statement):
                gen_if_statement(if_statement, kw: "if")
            Let(let_statement):
                # TODO: insert type hint?
                emit("let {get_id(let_statement.variable.id)} = {gen_expression(let_statement.value, parens: false)}")
            Pass:
                emit("pass")
            Break:
                emit("break")
            Continue:
                emit("continue")
            Compound(inner):
                for s in inner:
                    gen_statement(s)
            Expr(expr):
                emit(gen_expression(expr, parens: true))
            Assignment(target, op, value):
                let op_txt = ""
                case op:
                    None:
                        op_txt = "="
                    Some(op3):
                        op_txt = "{ast.binary_op_to_str(op3)}="
                emit("{gen_expression(target, parens: true)} {op_txt} {gen_expression(value, parens: false)}")
            Try(try_statement):
                emit("try:")
                gen_block(try_statement.try_block)
                let ex_name = "ex_{get_id(try_statement.except_var.id)}"
                emit("except ValueError as {ex_name}:")
                gen_block(try_statement.except_block)
            Return(value):
                case value:
                    None:
                        emit("return")
                    Some(value2):
                        emit("return {gen_expression(value2, parens: false)}")
            Raise(value):
                emit("raise {gen_expression(value, parens: false)}")
            Unreachable:
                emit("unreachable")
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
        let txt = "?"
        case expression.kind:
            Null:
                txt = "null"
            BoolLiteral(v):
                if v:
                    txt = "true"
                else:
                    txt = "false"
            IntLiteral(v):
                txt = "{v}"
            StringLiteral(s):
                txt = "\"{s}\""
            CharLiteral(s):
                txt = "'{s}'"
            FloatLiteral(value):
                txt = float_to_str(value)
            StructLiteral(ty, values):
                let struct_def = ty.get_struct_def()
                let name = get_id(struct_def.id)
                let value_iter = values.iter()
                let parts: List[str] = List()
                for field in struct_def.fields:
                    let value = option_unwrap(value_iter.next())
                    parts.append("{field.name}: {gen_expression(value, parens: false)}")
                let args = str_join(parts, sep: ", ")
                txt = "{name}({args})"
            ArrayLiteral(values):
                let args = gen_expression_list(expressions: values)
                txt = "[{args}]"
            ArrayLiteral2(size, ty):
                let size_txt = gen_expression(size, parens: false)
                let ty_txt = gen_type(ty)
                txt = "[{size_txt} : {ty_txt}]"
            ParameterRef(parameter_def):
                txt = get_id(parameter_def.id)
            VarRef(variable):
                txt = get_id(variable.id)
            FunctionRef(function_def, type_arguments):
                txt = function_def.name
            TypeCast(ty, value):
                txt = "cast {gen_type(ty)}({gen_expression(value, parens: true)})"
            Box(value):
                txt = "box {gen_expression(value, parens: true)}"
            Unbox(value, to_type):
                txt = "unbox {gen_expression(value, parens: true)}"
            Call(call):
                let expressions: List[ast.Expression] = List()
                for argument in call.arguments:
                    expressions.append(argument.value)
                let argument_text = gen_expression_list(expressions)
                txt = "{gen_expression(call.callee, parens: true)}({argument_text})"
            GetAttr(base, attr):
                let b = gen_expression(base, parens: true)
                txt = "{b}.{attr}"
            GetIndex(base, indici):
                let b = gen_expression(base, parens: true)
                let i = gen_expression_list(expressions: indici)
                txt = "{b}[{i}]"
            Binop(binop):
                let op = ast.binary_op_to_str(op: binop.op)
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

    fn get_id(id?: ast.NodeId) -> str:
        return "X{id.id}_{id.name}"

    fn emit(txt?: str):
        out.emit(txt)

    fn indent():
        out.indent()

    fn dedent():
        out.dedent()

