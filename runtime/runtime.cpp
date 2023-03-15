
#include <iostream>

// Header:

std::string std_int_to_str(int value)
{
    return std::to_string(value);
}

std::string std_float_to_str(double value)
{
    return std::to_string(value);
}

void std_print(std::string msg)
{
    std::cout << msg << std::endl;
}
