
from datatypes import List
from utils import panic
from bc import Instruction

enum Value:
    Int(value: int)
    Str(value: str)
    Float(value: float)
    Bool(value: bool)


class Frame:
    var locals: List[Value] = List()
    var stack: List[Value] = List()

class VM:
    var frames: List[Frame] = List()

    fn tick(instruction: Instruction):
        case instruction:
            Nop:
                pass
            Dup:
                let val = this.pop()
                this.push(val)
                this.push(val)
            Literal(literal):
                case literal:
                    Int(val):
                        this.push(Value.Int(val))
                    Str(val):
                        this.push(Value.Str(val))
                    Bool(val):
                        this.push(Value.Bool(val))
                    Float(val):
                        this.push(Value.Float(val))
            LocalGet(index):
                let val = this.frames.last().locals.get(index)
                this.push(val)
            LocalSet(index):
                panic("TODO")
            ParameterGet(index):
                panic("TODO: parameter-get")
            GetAttr(index, ty):
                let base = this.pop()
                panic("TODO")
            SetAttr(index):
                let value = this.pop()
                let base = this.pop()
                panic("TODO")
            Not:
                let value = this.pop()
                # TODO!
                this.push(value)
            Neg:
                panic("TODO: neg")
            Binop(op):
                case op:
                    Add:
                        let rhs = this.pop()
                        let lhs = this.pop()
                        let value = rhs
                        this.push(value)
                    Sub:
                        panic("TODO: sub")
                    Divide:
                        panic("TODO: div")
                    Multiply:
                        panic("TODO: mul")
                    Less:
                        panic("TODO: lt")
                    LessEquals:
                        panic("TODO: lte")
                    Greater:
                        panic("TODO: gt")
                    GreaterEquals:
                        panic("TODO: gte")
                    Equals:
                        panic("TODO: eq")
                    NotEquals:
                        panic("TODO: ne")
            IntToFloat:
                panic("TODO int-to-float")
            Jump(target):
                panic("TODO")
            JumpIf(target, target2):
                panic("TODO: jump-if")
            Call(n, result_type):
                let arguments = this.pop_n(count: n)
                let callee = this.pop()
                panic("TODO: call")
            Return(amount):
                if amount == 1:
                    let val = this.pop()
                panic("Return not impl")
            LoadFunc(name):
                panic("TODO: load func")
            StructLiteral(struct_index):
                let count = 13333  # TODO: retrieve from struct def array
                let values = this.pop_n(count)
                panic("TODO: struct literal")
            UnionLiteral(struct_index, field_index):
                panic("TODO: union literal")
            ArrayLiteral(count):
                let values = this.pop_n(count)
                panic("TODO: array literal")
    
    fn push(value?: Value):
        this.frames.last().stack.append(value)
    
    fn pop() -> Value:
        return this.frames.last().stack.pop_last()
    
    fn pop_n(count: int) -> List[Value]:
        let values: List[Value] = List()
        while count > 0:
            let val = this.pop()
            values.append(val)
            count -= 1
        return values
