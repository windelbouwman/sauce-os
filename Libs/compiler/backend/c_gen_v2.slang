
# Generate C code directly from AST

# Alternative to c_gen module

from std import float_to_str, chr
from strlib import str_repeat, str_join
import ast
from datatypes import List, option_unwrap, Option, option_is_some
from dicttype import Dictionary
from utils import panic, log_info, log_debug, log_warning, assert, unimplemented
from text_gen import TextGenerator


fn gen_c_code_v2(module_set: ast.ModuleSet, output_filename: Option[str]):
    log_info("Generating C-code")
    let g = CGenerator2()
    g.out.begin(output_filename)
    g.gen_header()
    g.gen_forward_declarations1(module_set)
    g.gen_forward_declarations2(module_set)
    g.gen_struct_defs(module_set)
    g.gen_function_defs(module_set)
    g.out.end()

class CGenerator2:
    var out: TextGenerator = TextGenerator()

    fn gen_header():
        emit("#include <setjmp.h>")
        emit("#include <stdlib.h>")
        emit("#include <stdint.h>")
        emit("#include {chr(34)}slangrt.h{chr(34)}")

    fn gen_forward_declarations1(module_set: ast.ModuleSet):
        for module in module_set.modules:
            for definition in module.definitions:
                case definition:
                    Struct(struct_def):
                        let decl = gen_struct_decl(struct_def)
                        emit("{decl};")
                else:
                    pass

    fn gen_forward_declarations2(module_set: ast.ModuleSet):
        for module in module_set.modules:
            for definition in module.definitions:
                case definition:
                    Function(function_def):
                        let decl = gen_function_decl(function_def)
                        let no_return = ""
                        if function_def.info.no_return:
                            no_return = " __attribute__((noreturn));"
                        emit("{decl}{no_return};")

                    Struct(struct_def):
                        # Create struct constructor function
                        if struct_def.is_union:
                            panic("Unions not supported")
                        let name = gen_id(id: struct_def.id)
                        let parts: List[str] = List()
                        for field in struct_def.fields:
                            parts.append(gen_type(ty: field.ty, name: field.name))
                        let args = str_join(parts, sep: ", ")
                        emit("struct {name}* {name}_new({args});")
                else:
                    pass

    fn gen_struct_defs(module_set: ast.ModuleSet):
        for module in module_set.modules:
            for definition in module.definitions:
                case definition:
                    Struct(struct_def):
                        gen_struct(struct_def)
                    Var(variable_def):
                        let varname = gen_id(id: variable_def.variable.id)
                        let typed_name = gen_type(ty: variable_def.variable.ty, name: varname)
                        case variable_def.value:
                            Intern(value):
                                let initial_value = gen_expression(option_unwrap(value))
                                emit("{typed_name} = {initial_value};")
                            Extern(libname, initialized):
                                unimplemented("Extern variable")
                else:
                    pass

    fn gen_function_defs(module_set: ast.ModuleSet):
        for module in module_set.modules:
            for definition in module.definitions:
                case definition:
                    Function(function_def):
                        gen_function(function_def)
                    Struct(struct_def):
                        gen_struct_ctors(struct_def)
                else:
                    pass

    fn gen_struct_decl(struct_def: ast.StructDef) -> str:
        let name = gen_id(id: struct_def.id)
        return "struct {name}"

    fn gen_struct(struct_def: ast.StructDef):
        let decl = gen_struct_decl(struct_def)
        emit("{decl} {chr(123)}")
        indent()
        for field in struct_def.fields:
            let typed_name = gen_type(ty: field.ty, name: field.name)
            emit("{typed_name};")
        dedent()
        emit("{chr(125)};")
        emit("")
    
    fn gen_struct_ctors(struct_def: ast.StructDef):
        # Create struct constructor function
        if struct_def.is_union:
            panic("Unions not supported")

        let struct_name = gen_id(id: struct_def.id)
        let parts: List[str] = List()
        for field in struct_def.fields:
            parts.append(gen_type(ty: field.ty, name: field.name))
        let args = str_join(parts, sep: ", ")
        emit("struct {struct_name}* {struct_name}_new({args}) {chr(123)}")
        indent()
        emit("struct {struct_name}* X = malloc(sizeof(struct {struct_name}));")
        for field in struct_def.fields:
            emit("X->{field.name} = {field.name};")
        emit("return X;")
        dedent()
        emit("{chr(125)}")
        emit("")

    fn gen_function_decl(function_def: ast.FunctionDef) -> str:
        let name = function_def.name
        let parameter_parts: List[str] = List()
        for parameter_def in function_def.parameters:
            let parameter_name = gen_id(id: parameter_def.id)
            parameter_parts.append(gen_type(ty: parameter_def.ty, name: parameter_name))
        let parameter_text = str_join(parts: parameter_parts, sep: ", ")
        let return_type_text = "void"
        if function_def.info.return_type.is_void():
            return_type_text = "void {name}"
        else:
            return_type_text = gen_type(ty: function_def.info.return_type, name)
        return "{return_type_text}({parameter_text})"

    fn gen_function(function_def: ast.FunctionDef):
        case function_def.body:
            Intern(scoped_block):
                let decl = gen_function_decl(function_def)
                emit("{decl} {chr(123)}")
                gen_block(scoped_block.body)
                emit("{chr(125)}")
                emit("")
            Extern(libname):
                pass
    
    fn gen_type(ty: ast.Type, name: str) -> str:
        if ty.is_int():
            return "intptr_t {name}"
        elif ty.is_bool():
            return "intptr_t {name}"
        elif ty.is_str():
            return "char* {name}"
        elif ty.is_float():
            return "double {name}"
        elif ty.is_char():
            return "char {name}"
        elif ty.is_opaque():
            return "void* {name}"
        elif ty.is_struct():
            let struct_def = ty.get_struct_def()
            let struct_name = gen_id(id: struct_def.id)
            return "struct {struct_name}* {name}"
        elif ty.is_function_type():
            let ret_ty = ty.get_return_type()
            let parts: List[str] = List()
            for param_ty in ast.get_parameter_types_from_type(ty):
                parts.append(gen_type(ty: param_ty.ty, name: ""))
            let param_text = str_join(parts, sep: ", ")
            return gen_type(ty: ret_ty, name: "(*{name})({param_text})")
        elif ty.is_void():
            return "void {name}"
        elif ty.is_array():
            let ety = ty.get_element_type()
            # return gen_type(ty: ety, name: "*{name}")
            let ety2 = gen_type(ty: ety, name)
            return "{ety2}[]"
        else:
            panic("Type: {ty} not supported")

    fn gen_block(statement?: ast.Statement):
        indent()
        gen_statement(statement)
        dedent()

    fn gen_statement(statement?: ast.Statement):
        case statement.kind:
            While(while_statement):
                let value = gen_expression(while_statement.condition)
                emit("while ({value}) {chr(123)}")
                gen_block(while_statement.block.body)
                emit("{chr(125)}")

            If(if_statement):
                gen_if_statement(if_statement, kw: "if")

            Loop(loop_statement):
                emit("while (1) {chr(123)}")
                gen_block(loop_statement.block.body)
                emit("{chr(125)}")

            Compound(body):
                for s in body:
                    gen_statement(s)

            Expr(expression):
                let value = gen_expression(expression)
                emit("{value};")

            Assignment(target, operator, value):
                let target_text = ""
                let op_text = ""
                case operator:
                    Some(op):
                        op_text = "{binary_op_to_str(op)}="
                    None:
                        op_text = "="

                case target.kind:
                    GetAttr(base, attr):
                        let base_txt = gen_expression(base)
                        target_text = "{base_txt}->{attr}"
                    GetIndex(base, indici):
                        let base_txt = gen_expression(base)
                        let args = gen_expression_list(values: indici)
                        target_text = "{base_txt}[{args}]"
                    VarRef(variable):
                        target_text = gen_id(id: variable.id)
                    ParameterRef(parameter_def):
                        target_text = gen_id(id: parameter_def.id)
                else:
                    panic("Unsupported assignment target: {target}")

                let value_text = gen_expression(value)
                emit("{target_text} {op_text} {value_text};")

            Let(let_statement):
                let var_name = gen_id(id: let_statement.variable.id)
                let typed_var = gen_type(ty: let_statement.variable.ty, name: var_name)
                let value = gen_expression(let_statement.value)
                emit("{typed_var} = {value};")

            Break:
                emit("break;")

            Continue:
                emit("continue;")

            Return(value):
                case value:
                    Some(v2):
                        let v3 = gen_expression(v2)
                        emit("return {v3};")
                    None:
                        emit("return;")

            For(for_statement):
                panic("for-statement not supported")

            Case(case_statement):
                panic("case-statement not supported")

            Try(try_statement):
                let param_name = gen_id(id: try_statement.except_var.id)
                # Create a local variable with jmp_buf
                # Also store a backup of the global exception handler.
                let jmp_buf_backup = "jmp_buf_backup_{param_name}"
                let jmp_buf = "jmp_buf_{param_name}"
                emit("jmp_buf {jmp_buf};")
                emit("jmp_buf* {jmp_buf_backup} = g_except_hook;")
                emit("g_except_hook = &{jmp_buf};")
                emit("if (setjmp(*g_except_hook) == 0) {chr(123)}")
                gen_block(try_statement.try_block.body)
                indent()
                emit("g_except_hook = {jmp_buf_backup};")
                dedent()
                emit("{chr(125)} else {chr(123)}")
                indent()
                emit("g_except_hook = {jmp_buf_backup};")
                let typed_var = gen_type(ty: try_statement.except_type, name: param_name)
                emit("{typed_var} = g_except_value;")
                gen_statement(try_statement.except_block.body)
                dedent()
                emit("{chr(125)}")

            Switch(switch_statement):
                # TBD: IDEA: we actually have switch in C!
                panic("switch-statement not supported")
                emit("switch () {chr(123)}")
                indent()
                dedent()
                emit("{chr(125)}")

            Raise(value):
                let value_txt = gen_expression(value)
                emit("g_except_value = {value_txt};")
                emit("longjmp(*g_except_hook, 1);")
            
            Unreachable:
                emit("__builtin_unreachable();")

            Pass:
                pass
    
    fn gen_if_statement(if_statement: ast.IfStatement, kw: str):
        let value = gen_expression(if_statement.condition)
        emit("{kw} ({value}) {chr(123)}")
        gen_block(if_statement.true_block.body)
        case if_statement.false_block.body.kind:
            Pass:
                emit("{chr(125)}")
            If(if_statement2):
                gen_if_statement(if_statement: if_statement2, kw: "{chr(125)} else if")
        else:
            emit("{chr(125)} else {chr(123)}")
            gen_block(if_statement.false_block.body)
            emit("{chr(125)}")

    fn gen_expression(expression?: ast.Expression) -> str:
        # TODO/TBD: optional parenthesis?
        let parens = true
        case expression.kind:
            Binop(binop):
                let v1 = gen_expression(binop.lhs)
                let v2 = gen_expression(binop.rhs)
                let op = binary_op_to_str(op: binop.op)
                return "({v1} {op} {v2})"

            Unop(op, rhs):
                let v = gen_expression(rhs)
                case op:
                    Minus:
                        return "-{v}"
                    Not:
                        return "({v} ? 0 : 1)"

            Call(call):
                let callee = gen_expression(call.callee)
                let values: List[ast.Expression] = List()
                for argument in call.arguments:
                    values.append(argument.value)
                let args = gen_expression_list(values)
                return "{callee}({args})"

            GetAttr(base, name):
                let base_txt = gen_expression(base)
                return "{base_txt}->{name}"
            
            GetIndex(base, indici):
                let base_txt = gen_expression(base)
                let args = gen_expression_list(values: indici)
                return "{base_txt}[{args}]"
            
            TypeCast(ty, value):
                let source = gen_expression(value)
                if ty.is_float():
                    return "(double)({source})"
                elif ty.is_opaque():
                    return "(void*)({source})"
                elif ty.is_str():
                    return "(char*)({source})"
                elif ty.is_int():
                    return "(intptr_t)({source})"
                elif ty.is_bool():
                    return "(intptr_t)({source})"
                elif ty.is_struct():
                    let to_type2 = gen_type(ty: ty, name: "")
                    return "(({to_type2})({source}))"
                elif ty.is_char():
                    return "(char)({source})"
                else:
                    panic("Unsupported cast to: {ty}")

            ParameterRef(parameter_def):
                return gen_id(id: parameter_def.id)
            
            FunctionRef(function_def, type_arguments):
                return function_def.name

            VarRef(variable):
                return gen_id(id: variable.id)
            
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

            CharLiteral(value):
                return "'{value}'"
            
            StructLiteral(ty, values):
                let struct_def = ty.get_struct_def()
                let name = gen_id(id: struct_def.id)
                let args = gen_expression_list(values)
                return "{name}_new({args})"
            
            ArrayLiteral(values):
                let args = gen_expression_list(values)
                return "{chr(123)} {args} {chr(125)}"

            ArrayLiteral2(size, ty):
                let size_2 = gen_expression(size)
                let ty_2 = gen_type(ty, name: "")
                return "calloc({size_2}, sizeof({ty_2}))"

        else:
            panic("Unsupported: {expression}")

    fn gen_expression_list(values: List[ast.Expression]) -> str:
        let parts: List[str] = List()
        for value in values:
            parts.append(gen_expression(value))
        return str_join(parts, sep: ", ")

    fn gen_id(id: ast.NodeId) -> str:
        if id.name == "main":
            return "{id.name}2"
        else:
            return "X{id.id}_{id.name}"

    fn indent():
        out.indent()

    fn dedent():
        out.dedent()

    fn emit(text?: str):
        out.emit(text)


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
        BitAnd:
            op_text = "&"
        BitXor:
            op_text = "^"
        BitOr:
            op_text = "|"
        ShiftLeft:
            op_text = "<<"
        ShiftRight:
            op_text = ">>"

    return op_text

