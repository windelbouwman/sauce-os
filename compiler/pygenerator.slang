
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
                this.emit("def {function_def.name}():")
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
                this.emit("if {this.gen_expression(if_statement.condition)}:")
                this.indent()
                this.gen_statement(if_statement.true_body)
                this.dedent()
                this.emit("else:")
                this.indent()
                this.gen_statement(if_statement.false_body)
                this.dedent()
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
            LoadSymbol(sym):
                panic("LoadSymbol not supported")
            NameRef(name):
                panic("NameRef not supported")
            VarRef(v):
                panic("VarRef not supported")
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
        let x = ""
        let counter = expressions.len()
        for expression in expressions:
            x += this.gen_expression(expression)
            if counter > 0:
                x += ", "
                counter -= 1
        return x

    fn emit(txt: str):
        let space = ""
        let i = 0
        while i < this.indent_level * 4:
            space += " "
            i += 1
        print(space + txt)
    
    fn indent():
        this.indent_level += 1
    
    fn dedent():
        this.indent_level -= 1
    