
# Date time function
from math import modulo

fn unix_to_str(seconds: int) -> str:
    # Convert unix timestamp to str
    # Unix epoch is 1-1-1970 00:00:00
    let seconds_per_day = 24 * 60 * 60
    let days = seconds / seconds_per_day
    let seconds_in_day = modulo(value: seconds, divisor: seconds_per_day)

    let year = 1970
    loop:
        if days < 365:
            break
        else:
            days -= 365
        year += 1
    
    # TODO: determine month and day.

    return "{year}-{days}-T-{seconds_in_day}"




