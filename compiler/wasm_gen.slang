
import webassembly
import ast
from std import print
from utils import panic, log_info


fn gen_webassembly(module_set: ast.ModuleSet):
    log_info("Generating WebAssembly")
    let generator = WasmGenerator()
    for module in module_set.modules:
        generator.gen_module(module)

class WasmGenerator:
    var dummy: int = 0

    fn gen_module(module: ast.Module):
        for definition in module.definitions:
            case definition:
                Function(function_def):
                    this.gen_function(function_def)
            else:
                panic("Not supported")

    fn gen_function(function_def: ast.FunctionDef):
        print("++ Function: {function_def.id.name}")
        this.gen_statement(function_def.body)

    fn gen_statement(statement?: ast.Statement):
        case statement.kind:
            Break:
                panic("TODO: break")

            Continue:
                panic("TODO: continue")

            Compound(inner):
                for s in inner:
                    this.gen_statement(s)

            Expr(expression):
                this.gen_expression(expression)
            
            Assignment(target, op, value):
                panic("TODO: assignment")

            Let(let_statement):
                this.gen_expression(let_statement.value)
                let localidx = this.create_local(id: let_statement.variable.id)
                this.emit(webassembly.Instruction.local_set(localidx))

            If(if_statement):
                this.gen_expression(if_statement.condition)
                this.emit(webassembly.Instruction.ctrl_if())
                this.gen_statement(if_statement.true_block.body)
                this.emit(webassembly.Instruction.ctrl_else())
                this.gen_statement(if_statement.false_block.body)
                this.emit(webassembly.Instruction.ctrl_end())

            While(while_statement):
                this.gen_expression(while_statement.condition)
                this.gen_statement(while_statement.block.body)

            Pass:
                pass

            Return(value):
                case value:
                    None:
                        pass
                    Some(v2):
                        this.gen_expression(v2)
                this.emit(webassembly.Instruction.ctrl_return())
        else:
            panic("Not implemented: {ast.statement_to_string(statement)}")
    
    fn gen_expression(expression?: ast.Expression):
        case expression.kind:
            IntLiteral(value):
                this.emit(webassembly.Instruction.i64_const(value))

            StringLiteral(value):
                print(value)

            Binop(binop):
                this.gen_expression(binop.lhs)
                this.gen_expression(binop.rhs)
                if ast.is_int_type(binop.lhs.ty):
                    case binop.op:
                        Add:
                            this.emit(webassembly.Instruction.i64_add())
                        Sub:
                            this.emit(webassembly.Instruction.i64_sub())
                        Mul:
                            this.emit(webassembly.Instruction.i64_mul())
                        Div:
                            this.emit(webassembly.Instruction.i64_div_s())
                        Less:
                            this.emit(webassembly.Instruction.i64_lt_s())
                        LessEquals:
                            this.emit(webassembly.Instruction.i64_le_s())
                        Greater:
                            this.emit(webassembly.Instruction.i64_gt_s())
                        GreaterEquals:
                            this.emit(webassembly.Instruction.i64_ge_s())
                        Equals:
                            this.emit(webassembly.Instruction.i64_eq())
                        NotEquals:
                            this.emit(webassembly.Instruction.i64_ne())
                        And:
                            panic("and not impl")
                        Or:
                            panic("or not impl")
                else:
                    panic("Binop type not supported: {ast.type_to_string(binop.lhs.ty)}")

            Call(call):
                this.gen_expression(call.callee)
                
                for argument in call.arguments:
                    this.gen_expression(argument.value)

                let funcidx = 1337  # TODO!
                this.emit(webassembly.Instruction.ctrl_call(funcidx))

            LoadSymbol(symbol):
                case symbol:
                    ExternFunction(external_function):
                        # TODO: import external function!
                        print("ext -> {external_function.name}")
                    Parameter(p):
                        let localidx = this.get_local_index(id: p.id)
                        this.emit(webassembly.Instruction.local_get(localidx))
                else:
                    panic("Not impl symbol")

            VarRef(v):
                let localidx = this.get_local_index(id: v.id)
                this.emit(webassembly.Instruction.local_get(localidx))

            FunctionRef(f, type_args):
                print("FN {f.id.name}")
        else:
            panic("Not implemented: {ast.expression_to_string(expression)}")

    fn get_local_index(id: ast.NodeId) -> int:
        return 13
    
    fn create_local(id: ast.NodeId) -> int:
        return 12

    fn emit(instruction?: webassembly.Instruction):
        print("WASM INSTR> {webassembly.to_string(instruction)}")
