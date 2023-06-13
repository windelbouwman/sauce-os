
from datatypes import List
from utils import panic
from bc import Instruction

enum Value:
    Int(int)
    Str(str)
    Float(float)
    Bool(bool)


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
            GetAttr(index):
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
            Jump(target):
                panic("TODO")
            JumpIf(target, target2):
                panic("TODO")
            Call(n):
                let callee = this.pop()
                panic("TODO")
            Return(amount):
                if amount == 1:
                    let val = this.pop()
                panic("Return not impl")
            LoadFunc(name):
                panic("TODO: load func")
            StructLiteral(count):
                while count > 0:
                    let val = this.pop()
                    count -= 1
                panic("TODO: struct literal")
    
    fn push(value: Value):
        this.frames.last().stack.append(value)
    
    fn pop() -> Value:
        return this.frames.last().stack.pop_last()
