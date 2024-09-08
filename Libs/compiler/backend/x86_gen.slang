
# x86 backend

from utils import log_debug, log_info
from std import print
import bc

fn gen_x86(program: bc.Program):
    log_info("Generating x86 instructions")

    # Turn bytecode into graph of basic blocks?

    let g = X86Generator()

    for function in program.functions:
        g.gen_function(function)


class X86Generator:
    var m_dummy: int = 0

    fn gen_function(function: bc.Function):
        print("FUNC: {function.name}")

