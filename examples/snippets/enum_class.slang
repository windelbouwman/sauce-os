# Neat combination of classes, generics and enums

from std import print

class Vector[T]:
    var value: T

enum Option[T]:
    None
    Some(value: T)

pub fn main() -> int:
    let instructions: Vector[Instruction] = Vector(value: Instruction.Nop())
    let opt = Option.Some(instructions)
    case opt:
        Some(value):
            print_instructions(value)
        None:
            pass
    0


fn print_instructions(value: Vector[Instruction]):
    case value.value:
        Nop:
            print("nop")
        Typ(b):
            case b:
                Int:
                    print("Ty b = int")
                Float:
                    print("Ty b = float")
    else:
        pass


enum Instruction:
    Nop
    Typ(base: Base)

enum Base:
    Int
    Float
