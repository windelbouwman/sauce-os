
# Signal processing routines

from datatypes import List
from utils import panic, unimplemented

fn butter(n: int) -> DigitalFilter:
    # Create a butter worth filter
    unimplemented("butter")

fn cheby(n: int) -> DigitalFilter:
    # Create a butter worth filter
    unimplemented("cheby")

struct DigitalFilter:
    b: List[float]
    a: List[float]

fn filter(filt: DigitalFilter, values: List[float]):
    unimplemented("filter")
