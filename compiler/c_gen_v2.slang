
# Generate C code directly from AST

# Alternative to c_gen module

from std import print, float_to_str, chr
from strlib import str_repeat, str_join
import ast
from datatypes import List, Dictionary, option_unwrap, Option
from utils import panic, log_info, log_debug, log_warning


fn gen_c_code_v2(module_set: ast.ModuleSet):
    log_info("Generating C-code")
    let g = CGenerator2()

    g.gen_header()
    g.gen_forward_declarations1(module_set)
    g.gen_forward_declarations2(module_set)
    g.gen_struct_defs(module_set)
    g.gen_function_defs(module_set)

class CGenerator2:
    var indentation: int = 0

    fn gen_header():
        this.emit("#include <setjmp.h>")
        this.emit("#include <stdlib.h>")
        this.emit("")

        # MEH: copy/pasted from c_gen.slang ..
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
        this.emit("char std_str_get(char* txt, int pos);")

        this.emit("int std_ord(char txt);")
        this.emit("char std_chr(int val);")

        this.emit("char *std_int_to_str(int x);")
        this.emit("int std_str_to_int(char *x);")
        this.emit("char *std_float_to_str(double x);")
        this.emit("double std_str_to_float(char *x);")
        this.emit("char *std_char_to_str(char x);")

        this.emit("char *std_get_arg(int);")
        this.emit("int std_get_n_args();")

        this.emit("jmp_buf g_except_hook;")
        this.emit("char* g_except_value;")

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
                    Struct(struct_def):
                        # Create struct constructor function
                        let name = this.gen_id(id: struct_def.id)
                        if struct_def.is_union:
                            for field in struct_def.fields:
                                let arg = this.gen_type(ty: field.ty, name: field.name)
                                this.emit("union {name}* {name}_{field.name}({arg});")
                        else:
                            this.emit("struct {name}* {name}_new();")
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
                    Struct(struct_def):
                        this.gen_struct_ctors(struct_def)
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
    
    fn gen_struct_ctors(struct_def: ast.StructDef):
        # Create struct constructor function
        let struct_name = this.gen_id(id: struct_def.id)
        if struct_def.is_union:
            for field in struct_def.fields:
                let arg = this.gen_type(ty: field.ty, name: field.name)
                this.emit("union {struct_name}* {struct_name}_{field.name}({arg}) {chr(123)}")
                this.indent()
                this.emit("union {struct_name}* X = malloc(sizeof(union {struct_name}));")
                this.emit("X->{field.name} = {field.name};")
                this.emit("return X;")
                this.dedent()
                this.emit("{chr(125)}")
                this.emit("")
        else:
            let parts: List[str] = List()
            for field in struct_def.fields:
                parts.append(this.gen_type(ty: field.ty, name: field.name))
            let args = str_join(parts, sep: ", ")
            this.emit("struct {struct_name}* {struct_name}_new({args}) {chr(123)}")
            this.indent()
            this.emit("struct {struct_name}* X = malloc(sizeof(struct {struct_name}));")
            for field in struct_def.fields:
                this.emit("X->{field.name} = {field.name};")
            this.emit("return X;")
            this.dedent()
            this.emit("{chr(125)}")
            this.emit("")

    fn gen_function_decl(function_def: ast.FunctionDef) -> str:
        let name = this.gen_id(id: function_def.id)
        let parameter_parts: List[str] = List()
        for parameter_def in function_def.parameters:
            let parameter_name = this.gen_id(id: parameter_def.id)
            parameter_parts.append(this.gen_type(ty: parameter_def.ty, name: parameter_name))
        let parameter_text = str_join(parts: parameter_parts, sep: ", ")
        let return_type_text = "void"
        if ast.is_void_type(function_def.return_type):
            return_type_text = "void {name}"
        else:
            return_type_text = this.gen_type(ty: function_def.return_type, name)
        return "{return_type_text}({parameter_text})"

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
            return "int {name}"
        elif ast.is_str_type(ty):
            return "char* {name}"
        elif ast.is_float_type(ty):
            return "double {name}"
        elif ast.is_char_type(ty):
            return "char {name}"
        elif ast.is_struct_type(ty):
            let struct_def = ast.get_struct_def_from_type(ty)
            let struct_name = this.gen_id(id: struct_def.id)
            if struct_def.is_union:
                return "union {struct_name}* {name}"
            else:
                return "struct {struct_name}* {name}"
        elif ast.is_type_parameter_type(ty):
            # Treat generics as void pointers
            return "void* {name}"
        elif ast.is_function_type(ty):
            let ret_ty = ast.get_return_type_from_type(ty)
            let parts: List[str] = List()
            for param_ty in ast.get_parameter_types_from_type(ty):
                parts.append(this.gen_type(ty: param_ty, name: ""))
            let param_text = str_join(parts, sep: ", ")
            return this.gen_type(ty: ret_ty, name: "(*{name})({param_text})")
        elif ast.is_void_type(ty):
            return "void {name}"
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
                this.gen_block(while_statement.block.body)
                this.emit("{chr(125)}")

            If(if_statement):
                this.gen_if_statement(if_statement, kw: "if")

            Loop(loop_statement):
                this.emit("while (1) {chr(123)}")
                this.gen_block(loop_statement.block.body)
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
                # this.emit("jmpbuf buf1;")
                log_warning("try-catch C logic is probably wrong.")
                this.emit("if (setjmp(g_except_hook) == 0) {chr(123)}")
                this.gen_block(try_statement.try_block.body)
                this.emit("{chr(125)} else {chr(123)}")
                let param_name = this.gen_id(id: try_statement.except_param.id)
                let typed_var = this.gen_type(ty: try_statement.except_param.ty, name: param_name)
                this.indent()
                this.emit("{typed_var} = g_except_value;")
                this.gen_statement(try_statement.except_block.body)
                this.dedent()
                this.emit("{chr(125)}")

            Switch(switch_statement):
                # TBD: IDEA: we actually have switch in C!
                panic("switch-statement not supported")
                this.emit("switch () {chr(123)}")
                this.indent()
                this.dedent()
                this.emit("{chr(125)}")

            Raise(value):
                let value_txt = this.gen_expression(value)
                this.emit("g_except_value = {value_txt};")
                this.emit("longjmp(g_except_hook, 1);")

            Pass:
                pass
    
    fn gen_if_statement(if_statement: ast.IfStatement, kw: str):
        let value = this.gen_expression(if_statement.condition)
        this.emit("{kw} ({value}) {chr(123)}")
        this.gen_block(if_statement.true_block.body)
        case if_statement.false_block.body.kind:
            Pass:
                this.emit("{chr(125)}")
            If(if_statement2):
                this.gen_if_statement(if_statement: if_statement2, kw: "{chr(125)} else if")
        else:
            this.emit("{chr(125)} else {chr(123)}")
            this.gen_block(if_statement.false_block.body)
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
                case op:
                    Minus:
                        return "-{v}"
                    Not:
                        return "({v} ? 0 : 1)"

            Call(call):
                let callee = this.gen_expression(call.callee)
                let values: List[ast.Expression] = List()
                for argument in call.arguments:
                    values.append(argument.value)
                let args = this.gen_expression_list(values)
                let value = "{callee}({args})"
                # TODO: type promotion
                #let from_type = ?
                #let to_type = expression.ty
                #return this.promote_type(from_type, to_type, value: )
                # HACK: not all values need castig:
                if ast.is_struct_type(expression.ty):
                    let to_type2 = this.gen_type(ty: expression.ty, name: "")
                    value = "(({to_type2})({value}))"
                return value

            GetAttr(base, name):
                let base_txt = this.gen_expression(base)
                # Might introduce type erasure here!
                let from_type = get_field_type(ty: base.ty, attr: name)
                return this.promote_type(from_type, to_type: expression.ty, value: "{base_txt}->{name}")
            
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

            CharLiteral(value):
                return "'{value}'"
            
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

    fn promote_type(from_type: ast.Type, to_type: ast.Type, value: str) -> str:
        if ast.is_type_parameter_type(from_type) and not ast.is_type_parameter_type(to_type):
            let to_type2 = this.gen_type(ty: to_type, name: "")
            return "(({to_type2})({value}))"
        else:
            return value

    fn gen_id(id: ast.NodeId) -> str:
        if id.name == "main":
            return "{id.name}2"
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


fn get_field_type(ty: ast.Type, attr: str) -> ast.Type:
    let struct_def = ast.get_struct_def_from_type(ty)
    case struct_def.scope.lookup(name: attr):
        Some(sym):
            case sym:
                Field(field):
                    return field.ty
            else:
                panic("Struct member must be field")
        None:
            panic("Struct has no field {attr}")
