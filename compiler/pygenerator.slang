# Generate python code from AST.

import ast
from utils import panic
from datatypes import List
from std import print

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
                    parameter_names.append(parameter.name)
                let params = str_join(parameter_names, ", ")
                this.emit("def {function_def.name}({params}):")
                this.indent()
                this.gen_statement(function_def.body)
                this.dedent()
                this.emit("")
        else:
            pass

    fn gen_statement(statement: ast.Statement):
        case statement.kind:
            While(while_statement):
                this.emit("while {this.gen_expression(while_statement.condition)}:")
                this.indent()
                this.gen_statement(while_statement.body)
                this.dedent()
            Loop(loop_statement):
                panic("loop statement not supported")
            Let(let_statement):
                this.emit("{let_statement.variable.name} = {this.gen_expression(let_statement.value)}")
            If(if_statement):
                this.gen_if_statement(if_statement, "if")
            Pass:
                this.emit("pass")
            Break:
                this.emit("break")
            Continue:
                this.emit("continue")
            For(for_statement):
                panic("Please rewrite for-loop!")
            Try(try_statement):
                panic("TODO: try")
            Case(case_statement):
                panic("Please rewrite case-statement!")
            Switch(switch_statement):
                panic("Please rewrite switch-statement!")
            Assignment(target, op, value):
                # TODO: implement 'op'
                this.emit("{this.gen_expression(target)} = {this.gen_expression(value)}")
            Return(value):
                case value:
                    None:
                        this.emit("return")
                    Some(value2):
                        this.emit("return {this.gen_expression(value2)}")
            Raise(value):
                this.emit("raise {this.gen_expression(value)}")
            Compound(inner):
                for s in inner:
                    this.gen_statement(s)
            Expr(expr):
                this.emit(this.gen_expression(expr))

    fn gen_if_statement(if_statement: ast.IfStatement, kw: str):
        this.emit("{kw} {this.gen_expression(if_statement.condition)}:")
        this.indent()
        this.gen_statement(if_statement.true_body)
        this.dedent()
        case if_statement.false_body.kind:
            If(if2):
                this.gen_if_statement(if2, "elif")
        else:
            this.emit("else:")
            this.indent()
            this.gen_statement(if_statement.false_body)
            this.dedent()

    fn gen_expression(expression: ast.Expression) -> str:
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
                txt = "'{s}'"
            FloatLiteral(v):
                # TODO!
                txt = "1337.3.14"
            StructLiteral(ty, values):
                let args = this.gen_expression_list(values)
                txt = "struct ({args})"
                # panic("Struct literal not supported")
            EnumLiteral(a, b, c):
                panic("Enum literal not supported")
            Variant(a, b):
                panic("Enum variant not supported")
            ClassLiteral(a):
                panic("Class literal not supported")
            GetAttr(base, attr):
                let b = this.gen_expression(base)
                txt = "{b}.{attr}"
            GetIndex(base, indici):
                let b = this.gen_expression(base)
                let i = this.gen_expression_list(indici)
                txt = "{b}[{i}]"
            ObjInit(a, b):
                panic("ObjInit not supported")
            Type(ty):
                panic("Type not supported")
            TypeConstructor(tycon):
                panic("TypeConstructor not supported")
            LoadSymbol(symbol):
                case symbol:
                    Mod(m):
                        panic("Load module not allowed")
                    Function(function_def):
                        txt = function_def.name
                    ExternFunction(extern_function):
                        txt = extern_function.name
                    Parameter(parameter):
                        txt = parameter.name
                    Var(variable):
                        txt = variable.name
                    TypeConstructor(tycon):
                        panic("Load type constructor not allowed")
                    Type(ty):
                        panic("Load type not allowed")
                    Variant(variant):
                        panic("Load variant not allowed")
                    Field(field):
                        panic("Load field not allowed")
            NameRef(name):
                panic("unresolved 'NameRef' not allowed")
            VarRef(variable):
                txt = variable.name
            Call(call):
                let arguments = this.gen_expression_list(call.arguments)
                txt = "{this.gen_expression(call.callee)}({arguments})"
            Unop(op, value):
                let op2 = "$"
                txt = "{op2}{this.gen_expression(value)}"
            Binop(binop):
                let op = "$"
                txt = "({this.gen_expression(binop.lhs)} {op} {this.gen_expression(binop.lhs)})"
            Undefined:
                panic("undefined not supported")
        return txt
    
    fn gen_expression_list(expressions: List[ast.Expression]) -> str:
        let parts: List[str] = List()
        for expression in expressions:
            parts.append(this.gen_expression(expression))
        return str_join(parts, ", ")

    fn emit(txt: str):
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

fn str_join(parts: List[str], sep: str) -> str:
    let x = ""
    let counter = parts.len()
    for part in parts:
        x += part
        if counter > 1:
            x += sep
            counter -= 1
    return x
