
# x86 backend

from utils import log_info
from std import print
import bc
import sil
from bc_to_sil import to_sil

pub fn gen_x86(program: bc.Program):
    log_info("Generating x86 instructions")

    # Turn bytecode into graph of basic blocks?
    let p2 = to_sil(program)
    p2.dump()

    let g = X86Generator()

    for function in p2.functions:
        g.gen_function(function)


class X86Generator:
    var m_dummy: int = 0

    fn gen_function(function: sil.Function):
        print("FUNC: {function.name}")
