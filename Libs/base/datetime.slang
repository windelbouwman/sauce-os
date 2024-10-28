
# Date time function

from math import modulo
from utils import assert
from strlib import str_pad_left

fn unix_to_str(seconds: int) -> str:
    # Convert unix timestamp to str
    # Unix epoch is 1-1-1970 00:00:00
    let d = unix_to_datetime(z: seconds)
    datetime_to_str(d)

fn unix_to_datetime(z: int) -> DateTime:
    let seconds_per_day = 24 * 60 * 60
    let days = z / seconds_per_day

    let date = civil_from_days(z: days)
    let year = date.year
    let month = date.month
    let day = date.day

    let second = modulo(value: z, divisor: seconds_per_day)
    let minute = second / 60
    second = modulo(value: second, divisor: 60)
    let hour = minute / 60
    minute = modulo(value: minute, divisor: 60)

    DateTime(year, month, day, hour, minute, second)

fn datetime_to_unix(dt: DateTime) -> int:
    let ymd = Civil(year: dt.year, month: dt.month, day: dt.day)
    let z = days_from_civil(ymd) * 24 * 3600
    z += dt.hour * 3600 + dt.minute * 60 + dt.second
    z

fn two_digits(n?: int) -> str:
    str_pad_left(text: "{n}", length: 2, fill: "0")

fn datetime_to_str(d: DateTime) -> str:
    let year = d.year
    let month = two_digits(d.month)
    let day = two_digits(d.day)
    let hour = two_digits(d.hour)
    let minute = two_digits(d.minute)
    let second = two_digits(d.second)

    "{year}-{month}-{day}-T-{hour}:{minute}:{second}"

struct DateTime:
    year: int
    month: int
    day: int
    hour: int
    minute: int
    second: int

struct Civil:
    year: int
    month: int
    day: int

fn days_from_civil(ymd: Civil) -> int:
    let y = ymd.year
    let m = ymd.month
    let d = ymd.day

    # Useful background info: http://howardhinnant.github.io/date_algorithms.html

    # Use years which start at 1 march
    # This has the benefit that leap day is the last day of the year
    if m <= 2:
        y -= 1

    # Use era's of 400 years
    assert(condition: y > 0, message: "negative years not supported")
    let era = y / 400

    # Year of era [0, 399]:
    let yoe = y - (era * 400)

    # Day of year [0, 365]:
    let x = 0
    if m > 2:
        x = m - 3
    else:
        x = m + 9
    let doy = (153 * x + 2) / 5 + d - 1
    
    # Day of era [0, 146096]:
    let doe = yoe * 365 + yoe / 4 - yoe/100 + doy
    era * 146097 + doe - 719468

fn civil_from_days(z: int) -> Civil:
    z = z + 719468
    let era = z / 146097

    # Day of era [0, 146096]:
    let doe = z - era * 146097

    # Year of era [0, 399]
    let yoe = (doe - doe/1460 + doe /36524 - doe/146096) / 365
    let year = yoe + era * 400

    # Day of year [0, 365]:
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)

    let mp = (5 * doy + 2) / 153
    let day = doy - (153 * mp + 2) / 5 + 1
    let month = 0
    if mp < 10:
        month = mp + 3
    else:
        month = mp - 9
    
    if month <= 2:
        year += 1

    Civil(year, month, day)
