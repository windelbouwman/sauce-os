from compiler1.parsing import parse_expr, process_fstrings
from compiler1.location import Location


def test_parse_expr():
    n = parse_expr('1 + 2', Location(5, 5))
    print(n)


# def test_parse_bad_expr():
#     parse_expr('a b')


def test_process_fstrings():
    location = Location(1, 1)
    parts = process_fstrings('bla bla {x} foo {x+1} bar', location)
    # assert len(parts) == 5
    # assert parts == ['bla bla ', 2, 3, ' bar']


def test_process_fstrings2():
    text = 'bla bla bar'
    location = Location(1, 1)
    expr = process_fstrings(text, location)
    assert expr.kind.text == text


def test_process_fstrings3():
    text = ''
    location = Location(1, 1)
    expr = process_fstrings(text, location)
    assert expr.kind.text == text
