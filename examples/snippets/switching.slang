
from std import print

pub fn main() -> int:
    # let x = 2
    for x in [1,2,3,4,5,6,7,8,9, 11, 13]:
        switch x:
            0:
                print("Zero!")
            1:
                print("One!")
            2:
                print("Two!")
            13:
                print("Drie + 10!")
            4:
                print("IV")
            5:
                print("V")
            133:
                print("Muchos!")
        else:
            print("Defaulty!")
    0
