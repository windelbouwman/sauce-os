
from std import print
from unittest import assert_int_equals, assert_str_equals
from datetime import unix_to_datetime, unix_to_str, datetime_to_unix, DateTime, datetime_to_str

fn main() -> int:
    test_example1()
    test_example2()
    test_2024_example()
    test_90s()
    test_roundtrip()
    test_12_months_and_14_years()
    print("OK")
    return 0

fn test_example1():
    # Epoch on Saturday, April 13, 2024 7:25:11 PM
    let d = unix_to_datetime(z: 1713036311)
    assert_int_equals(d.year, 2024)
    assert_int_equals(d.month, 4)
    assert_int_equals(d.day, 13)
    assert_int_equals(d.hour, 19)
    assert_int_equals(d.minute, 25)
    assert_int_equals(d.second, 11)

fn test_example2():
    # Epoch on Saturday, April 13, 2024 7:25:11 PM
    let d = unix_to_datetime(z: 1705219696)
    assert_int_equals(d.year, 2024)
    assert_int_equals(d.month, 1)
    assert_int_equals(d.day, 14)
    assert_int_equals(d.hour, 8)
    assert_int_equals(d.minute, 8)
    assert_int_equals(d.second, 16)

fn test_2024_example():
    # Epoch 1713036311 -> on Saturday, April 13, 2024 7:25:11 PM
    let txt = unix_to_str(seconds: 1713036311)
    assert_str_equals(txt, "2024-04-13-T-19:25:11")

fn test_90s():
    # 652285149 -> Sunday, September 2, 1990 2:19:09 PM
    let txt = unix_to_str(seconds: 652285149)
    assert_str_equals(txt, "1990-09-02-T-14:19:09")

fn test_roundtrip():
    let z = 1713036311
    let dt = unix_to_datetime(z)
    let z2 = datetime_to_unix(dt)
    assert_int_equals(z, z2)

fn test_12_months_and_14_years():
    let year = 2016
    while year < 2030:
        let month = 1
        while month < 13:
            let dt2 = DateTime(year, month, day: 25, hour: 13, minute: 37, second: 2)
            let z3 = datetime_to_unix(dt: dt2)
            let dt3 = unix_to_datetime(z: z3)
            # print("{datetime_to_str(d: dt2)} == {datetime_to_str(d: dt3)}")
            assert_datetime_equals(dt2, dt3)
            month += 1
        year += 1

fn assert_datetime_equals(dt2: DateTime, dt3: DateTime):
    assert_int_equals(dt2.year, dt3.year)
    assert_int_equals(dt2.month, dt3.month)
    assert_int_equals(dt2.day, dt3.day)
    assert_int_equals(dt2.hour, dt3.hour)
    assert_int_equals(dt2.minute, dt3.minute)
    assert_int_equals(dt2.second, dt3.second)
