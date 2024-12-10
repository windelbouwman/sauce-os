


pub struct Range:
    # Range [begin, end)
    begin: int  # inclusive
    end: int    # exclusive

pub fn ranges_overlap(self: Range, other: Range) -> bool:
    return (self.begin <= other.end) and (other.begin <= self.end)

pub fn range_contains(self: Range, value: int) -> bool:
    return (self.begin <= value) and (value < self.end)

pub fn range_to_string(r?: Range) -> str:
    return "[{r.begin},{r.end})"
