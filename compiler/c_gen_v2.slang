
# Generate C code directly from AST

# Alternative to c_gen module

from std import print, float_to_str, chr
from strlib import str_repeat, str_join
import ast
from datatypes import List, Dictionary, option_unwrap, Option
from utils import panic, log_info, log_debug


fn gen_c_code_v2(module_set: ast.ModuleSet):
    log_info("Generating C-code")
    let g = CGenerator2()

    g.gen_forward_declarations1(module_set)
    g.gen_forward_declarations2(module_set)
    g.gen_struct_defs(module_set)
    g.gen_function_defs(module_set)

class CGenerator2:
    var indentation: int = 0

    fn gen_forward_declarations1(module_set: ast.ModuleSet):
        for module in module_set.modules:
            for definition in module.definitions:
                case definition:
                    Struct(struct_def):
                        let decl = this.gen_struct_decl(struct_def)
                        this.emit("{decl};")
                else:
                    pass

    fn gen_forward_declarations2(module_set: ast.ModuleSet):
        for module in module_set.modules:
            for definition in module.definitions:
                case definition:
                    Function(function_def):
                        let decl = this.gen_function_decl(function_def)
                        this.emit("{decl};")
                else:
                    pass

    fn gen_struct_defs(module_set: ast.ModuleSet):
        for module in module_set.modules:
            for definition in module.definitions:
                case definition:
                    Struct(struct_def):
                        this.gen_struct(struct_def)
                else:
                    pass

    fn gen_function_defs(module_set: ast.ModuleSet):
        for module in module_set.modules:
            for definition in module.definitions:
                case definition:
                    Function(function_def):
                        this.gen_function(function_def)
                else:
                    pass

    fn gen_struct_decl(struct_def: ast.StructDef) -> str:
        let name = this.gen_id(id: struct_def.id)
        if struct_def.is_union:
            return "union {name}"
        else:
            return "struct {name}"

    fn gen_struct(struct_def: ast.StructDef):
        let decl = this.gen_struct_decl(struct_def)
        this.emit("{decl} {chr(123)}")
        this.indent()
        for field in struct_def.fields:
            let typed_name = this.gen_type(ty: field.ty, name: field.name)
            this.emit("{typed_name};")
        this.dedent()
        this.emit("{chr(125)};")
        this.emit("")

    fn gen_function_decl(function_def: ast.FunctionDef) -> str:
        let name = this.gen_id(id: function_def.id)
        let parameter_parts: List[str] = List()
        for parameter_def in function_def.parameters:
            let parameter_name = this.gen_id(id: parameter_def.id)
            parameter_parts.append(this.gen_type(ty: parameter_def.ty, name: parameter_name))
        let parameter_text = str_join(parts: parameter_parts, sep: ", ")
        return "void {name}({parameter_text})"

    fn gen_function(function_def: ast.FunctionDef):
        let decl = this.gen_function_decl(function_def)
        this.emit("{decl} {chr(123)}")
        this.gen_block(function_def.body)
        this.emit("{chr(125)}")
        this.emit("")
    
    fn gen_type(ty: ast.Type, name: str) -> str:
        if ast.is_int_type(ty):
            return "int {name}"
        elif ast.is_bool_type(ty):
            return "bool {name}"
        elif ast.is_str_type(ty):
            return "char* {name}"
        elif ast.is_float_type(ty):
            return "double {name}"
        elif ast.is_struct_type(ty):
            let struct_def = ast.get_struct_def_from_type(ty)
            let struct_name = this.gen_id(id: struct_def.id)
            if struct_def.is_union:
                return "union {struct_name}* {name}"
            else:
                return "struct {struct_name}* {name}"
        else:
            panic("Type: {ast.type_to_string(ty)} not supported")

    fn gen_block(statement?: ast.Statement):
        this.indent()
        this.gen_statement(statement)
        this.dedent()

    fn gen_statement(statement?: ast.Statement):
        case statement.kind:
            While(while_statement):
                let value = this.gen_expression(while_statement.condition)
                this.emit("while ({value}) {chr(123)}")
                this.gen_block(while_statement.body)
                this.emit("{chr(125)}")

            If(if_statement):
                this.gen_if_statement(if_statement, kw: "if")

            Loop(loop_statement):
                this.emit("while (1) {chr(123)}")
                this.gen_block(loop_statement.body)
                this.emit("{chr(125)}")

            Compound(body):
                for s in body:
                    this.gen_statement(s)

            Expr(expression):
                let value = this.gen_expression(expression)
                this.emit("{value};")

            Assignment(target, operator, value):
                let target_text = this.gen_expression(target)
                let op_text = ""
                case operator:
                    Some(op):
                        op_text = "{binary_op_to_str(op)}="
                    None:
                        op_text = "="
                let value_text = this.gen_expression(value)
                this.emit("{target_text} {op_text} {value_text};")

            Let(let_statement):
                let var_name = this.gen_id(id: let_statement.variable.id)
                let typed_var = this.gen_type(ty: let_statement.variable.ty, name: var_name)
                let value = this.gen_expression(let_statement.value)
                this.emit("{typed_var} = {value};")

            Break:
                this.emit("break;")

            Continue:
                this.emit("continue;")

            Return(value):
                case value:
                    Some(v2):
                        let v3 = this.gen_expression(v2)
                        this.emit("return {v3};")
                    None:
                        this.emit("return;")

            For(for_statement):
                panic("for-statement not supported")

            Case(case_statement):
                panic("case-statement not supported")

            Try(try_statement):
                panic("try-statement not supported")

            Switch(switch_statement):
                # TBD: IDEA: we actually have switch in C!
                panic("switch-statement not supported")
                this.emit("switch () {chr(123)}")
                this.indent()
                this.dedent()
                this.emit("{chr(125)}")

            Raise(value):
                panic("raise-statement not supported")

            Pass:
                pass
    
    fn gen_if_statement(if_statement: ast.IfStatement, kw: str):
        let value = this.gen_expression(if_statement.condition)
        this.emit("{kw} ({value}) {chr(123)}")
        this.gen_block(if_statement.true_body)
        case if_statement.false_body.kind:
            Pass:
                this.emit("{chr(125)}")
            If(if_statement2):
                this.gen_if_statement(if_statement: if_statement2, kw: "{chr(125)} else if")
        else:
            this.emit("{chr(125)} else {chr(123)}")
            this.gen_block(if_statement.false_body)
            this.emit("{chr(125)}")

    fn gen_expression(expression?: ast.Expression) -> str:
        # TODO/TBD: optional parenthesis?
        let parens = true
        case expression.kind:
            Binop(binop):
                let v1 = this.gen_expression(binop.lhs)
                let v2 = this.gen_expression(binop.rhs)
                let op = binary_op_to_str(op: binop.op)
                return "({v1} {op} {v2})"

            Unop(op, rhs):
                let v = this.gen_expression(rhs)
                panic("TODO: unop")

            Call(call):
                let callee = this.gen_expression(call.callee)
                let values: List[ast.Expression] = List()
                for argument in call.arguments:
                    values.append(argument.value)
                let args = this.gen_expression_list(values)
                return "{callee}({args})"

            GetAttr(base, name):
                let base_txt = this.gen_expression(base)
                return "{base_txt}->{name}"
            
            GetIndex(base, indici):
                let base_txt = this.gen_expression(base)
                let args = this.gen_expression_list(values: indici)
                return "{base_txt}[{args}]"
            
            TypeCast(ty, value):
                let source = this.gen_expression(value)
                if ast.is_float_type(ty):
                    return "(double)({source})"
                else:
                    panic("Unsupported cast to: {ast.type_to_string(ty)}")
            
            LoadSymbol(symbol):
                case symbol:
                    Function(function_def):
                        return this.gen_id(id: function_def.id)
                    ExternFunction(extern_function):
                        return extern_function.name
                    Parameter(parameter_def):
                        return this.gen_id(id: parameter_def.id)
                else:
                    panic("todo-symbol: {ast.symbol_to_str(symbol)}")
            
            VarRef(variable):
                return this.gen_id(id: variable.id)
            
            IntLiteral(value):
                return "{value}"

            FloatLiteral(value):
                return "{float_to_str(value)}"

            BoolLiteral(value):
                if value:
                    return "1"
                else:
                    return "0"

            StringLiteral(value):
                return "{chr(34)}{value}{chr(34)}"
            
            StructLiteral(ty, values):
                let struct_def = ast.get_struct_def_from_type(ty)
                let name = this.gen_id(id: struct_def.id)
                let args = this.gen_expression_list(values)
                return "{name}_new({args})"
            
            ArrayLiteral(values):
                panic("TODO: array literal")

            UnionLiteral(ty, field, value):
                let struct_def = ast.get_struct_def_from_type(ty)
                let union_name = this.gen_id(id: struct_def.id)
                let value_text = this.gen_expression(value)
                return "{union_name}_{field}({value_text})"

        else:
            panic("Unsupported: {ast.expression_to_string(expression)}")

    fn gen_expression_list(values: List[ast.Expression]) -> str:
        let parts: List[str] = List()
        for value in values:
            parts.append(this.gen_expression(value))
        return str_join(parts, sep: ", ")

    fn gen_id(id: ast.NodeId) -> str:
        # TODO: we could use id as well?
        # TODO: think more about name mangling
        if id.name == "main":
            return id.name
        else:
            return "X{id.id}_{id.name}"

    fn indent():
        this.indentation += 1

    fn dedent():
        this.indentation -= 1

    fn emit(text?: str):
        let indent = str_repeat(text: "   ", count: this.indentation)
        print(indent + text)


fn binary_op_to_str(op: ast.BinaryOperator) -> str:
    let op_text = "$"
    case op:
        And:
            op_text = "&&"
        Or:
            op_text = "||"
        Add:
            op_text = "+"
        Sub:
            op_text= "-"
        Mul:
            op_text = "*"
        Div:
            op_text = "/"
        Less:
            op_text = "<"
        LessEquals:
            op_text = "<="
        Greater:
            op_text= ">"
        GreaterEquals:
            op_text = ">="
        Equals:
            op_text = "=="
        NotEquals:
            op_text = "!="
    return op_text
