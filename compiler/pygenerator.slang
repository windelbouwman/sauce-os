# Generate python code from AST.

import ast
from utils import panic
from datatypes import List
from std import print, float_to_str, chr
from strlib import str_join

fn gen_python(prog: ast.Module):
    let g = PyGenerator()
    g.gen_module(prog)

class PyGenerator:
    var indent_level: int = 0

    fn gen_module(prog: ast.Module):
        for definition in prog.definitions:
            this.gen_definition(definition)

    fn gen_definition(definition: ast.Definition):
        case definition:
            Function(function_def):
                let parameter_names: List[str] = List()
                for parameter in function_def.parameters:
                    parameter_names.append(this.get_id(id: parameter.id))
                let params = str_join(parts: parameter_names, sep: ", ")
                this.emit("def {this.get_id(id: function_def.id)}({params}):")
                this.indent()
                this.gen_statement(function_def.body)
                this.dedent()
                this.emit("")
                this.emit("")
            Struct(struct_def):
                this.emit("class {this.get_id(id: struct_def.id)}:")
                this.indent()
                if struct_def.is_union:
                    this.emit("def __init__(self, field, value):")
                    this.indent()
                    this.emit("setattr(self, field, value)")
                    this.dedent()
                else:
                    let parameter_names: List[str] = List()
                    for field1 in struct_def.fields:
                        parameter_names.append(field1.name)
                    let params = str_join(parts: parameter_names, sep: ", ")
                    this.emit("def __init__(self, {params}):")
                    this.indent()
                    for field2 in struct_def.fields:
                        this.emit("self.{field2.name} = {field2.name}")
                    this.dedent()
                this.dedent()
                this.emit("")
                this.emit("")
            Class(class_def):
                panic("class-def not supported")
            ExternFunction(e):
                panic("extern-function not supported")
            Enum(enum_def):
                panic("enum-def not supported")
            Var(variable_def):
                panic("var-def not supported")

    fn gen_statement(statement?: ast.Statement):
        case statement.kind:
            While(while_statement):
                this.emit("while {this.gen_expression(while_statement.condition, parens: false)}:")
                this.indent()
                this.gen_statement(while_statement.body)
                this.dedent()
            Loop(loop_statement):
                panic("loop statement not supported")
            Let(let_statement):
                this.emit("{this.get_id(id: let_statement.variable.id)} = {this.gen_expression(let_statement.value, parens: false)}")
            If(if_statement):
                this.gen_if_statement(if_statement, kw: "if")
            Pass:
                this.emit("pass")
            Break:
                this.emit("break")
            Continue:
                this.emit("continue")
            For(for_statement):
                panic("Please rewrite for-loop!")
            Try(try_statement):
                this.emit("try:")
                this.indent()
                this.gen_statement(try_statement.try_body)
                this.dedent()
                let ex_name = "ex_{this.get_id(id: try_statement.except_param.id)}"
                this.emit("except ValueError as {ex_name}:")
                this.indent()
                this.emit("{this.get_id(id: try_statement.except_param.id)} = {ex_name}.args[0]")
                this.gen_statement(try_statement.except_body)
                this.dedent()
            Case(case_statement):
                panic("Please rewrite case-statement!")
            Switch(switch_statement):
                panic("Please rewrite switch-statement!")
            Assignment(target, op, value):
                # TODO: implement 'op'
                let op_txt = ""
                case op:
                    None:
                        op_txt = "="
                    Some(op3):
                        op_txt = "{ast.binary_op_to_str(op: op3)}="
                this.emit("{this.gen_expression(target, parens: true)} {op_txt} {this.gen_expression(value, parens: false)}")
            Return(value):
                case value:
                    None:
                        this.emit("return")
                    Some(value2):
                        this.emit("return {this.gen_expression(value2, parens: false)}")
            Raise(value):
                this.emit("raise ValueError({this.gen_expression(value, parens: false)})")
            Compound(inner):
                for s in inner:
                    this.gen_statement(s)
            Expr(expr):
                this.emit(this.gen_expression(expr, parens: true))

    fn gen_if_statement(if_statement: ast.IfStatement, kw: str):
        this.emit("{kw} {this.gen_expression(if_statement.condition, parens: false)}:")
        this.indent()
        this.gen_statement(if_statement.true_body)
        this.dedent()
        case if_statement.false_body.kind:
            If(if2):
                this.gen_if_statement(if_statement: if2, kw: "elif")
            Pass:
                pass
        else:
            this.emit("else:")
            this.indent()
            this.gen_statement(if_statement.false_body)
            this.dedent()

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
                txt = "{chr(34)}{s}{chr(34)}"
            FloatLiteral(value):
                txt = float_to_str(value)
            StructLiteral(ty, values):
                let struct_def = ast.get_struct_def_from_type(ty)
                let name = this.get_id(id: struct_def.id)
                let args = this.gen_expression_list(expressions: values)
                txt = "{name}({args})"
            UnionLiteral(ty, field, value):
                let struct_def = ast.get_struct_def_from_type(ty)
                let name = this.get_id(id: struct_def.id)
                let value_txt = this.gen_expression(value, parens: true)
                txt = "{name}('{field}', {value_txt})"
            ArrayLiteral(values):
                let args = this.gen_expression_list(expressions: values)
                txt = "[{args}]"
            EnumLiteral(a, b, c):
                panic("Enum literal not supported")
            Variant(a, b):
                panic("Enum variant not supported")
            ClassLiteral(ty, arguments):
                panic("Class literal not supported")
            GetAttr(base, attr):
                let b = this.gen_expression(base, parens: true)
                txt = "{b}.{attr}"
            GetIndex(base, indici):
                let b = this.gen_expression(base, parens: true)
                let i = this.gen_expression_list(expressions: indici)
                txt = "{b}[{i}]"
            TypeCast(ty, value):
                # TODO
                txt = this.gen_expression(value, parens: true)
            ToString(value):
                panic("ToString not supported, rewrite language construct")
            Typ(ty):
                panic("Type not supported")
            TypeConstructor(tycon):
                panic("TypeConstructor not supported")
            LoadSymbol(symbol):
                case symbol:
                    Mod(m):
                        panic("Load module not allowed")
                    Function(function_def):
                        txt = this.get_id(id: function_def.id)
                    ExternFunction(extern_function):
                        txt = extern_function.name
                    Parameter(parameter):
                        txt = this.get_id(id: parameter.id)
                    Var(variable):
                        txt = this.get_id(id: variable.id)
                    TypeConstructor(tycon):
                        panic("Load type constructor not allowed")
                    Typ(ty):
                        panic("Load type not allowed")
                    Variant(variant):
                        panic("Load variant not allowed")
                    Field(field):
                        panic("Load field not allowed")
            NameRef(name):
                panic("unresolved 'NameRef' not allowed")
            VarRef(variable):
                txt = this.get_id(id: variable.id)
            Call(call):
                let expressions: List[ast.Expression] = List()
                for argument in call.arguments:
                    expressions.append(argument.value)
                let argument_text = this.gen_expression_list(expressions)
                txt = "{this.gen_expression(call.callee, parens: true)}({argument_text})"
            Unop(op, value):
                let op2 = "$"
                case op:
                    Not:
                        op2 = "not "
                    Minus:
                        op2 = "-"
                txt = "{op2}{this.gen_expression(value, parens: true)}"
                if parens:
                    txt = "({txt})"
            Binop(binop):
                let op = "$"
                case binop.op:
                    Or:
                        op = "or"
                    And:
                        op = "and"
                    Equals:
                        op = "=="
                    NotEquals:
                        op = "!="
                    Less:
                        op = "<"
                    LessEquals:
                        op = "<="
                    Greater:
                        op = ">"
                    GreaterEquals:
                        op = ">="
                    Add:
                        op = "+"
                    Sub:
                        op = "-"
                    Mul:
                        op = "*"
                    Div:
                        op = "/"

                txt = "{this.gen_expression(binop.lhs, parens: true)} {op} {this.gen_expression(binop.rhs, parens: true)}"
                if parens:
                    txt = "({txt})"
            Undefined:
                panic("undefined not supported")
        return txt
    
    fn gen_expression_list(expressions: List[ast.Expression]) -> str:
        let parts: List[str] = List()
        for expression in expressions:
            parts.append(this.gen_expression(expression, parens: false))
        return str_join(parts, sep: ", ")
    
    fn get_id(id: ast.NodeId) -> str:
        # TODO: we could use id as well?
        # TODO: think more about name mangling
        if id.name == "main":
            return id.name
        else:
            return "X{id.id}_{id.name}"

    fn emit(txt?: str):
        let space = ""
        let i = 0
        while i < this.indent_level:
            space += "    "
            i += 1
        print(space + txt)
    
    fn indent():
        this.indent_level += 1
    
    fn dedent():
        this.indent_level -= 1
