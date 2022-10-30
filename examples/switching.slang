
import std

fn main():
    # let x = 2
    for x in [1,2,3,4,5,6,7,8,9, 11, 13]:
        switch x:
            0:
                std::print("Zero!")
            1:
                std::print("One!")
            2:
                std::print("Two!")
            13:
                std::print("Drie + 10!")
            4:
                std::print("IV")
            5:
                std::print("V")
            133:
                std::print("Muchos!")
        else:
            std::print("Defaulty!")

