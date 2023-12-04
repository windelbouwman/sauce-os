
from std import print

fn main():
    display()
    modify()
    display()


var x : int = 3
var y : str = "bla bla"


fn modify():
    x = 42
    y = "yo!"

fn display():
    print("x={x}, y={y}")
