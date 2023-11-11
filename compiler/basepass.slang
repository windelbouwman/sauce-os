
# Unique number generator

class IdGen:
    var counter: int = 1

    fn new_id() -> int:
        let v = counter
        counter += 1
        return v
