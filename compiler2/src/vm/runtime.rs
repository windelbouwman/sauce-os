use super::Value;

pub fn std_print(parameters: Vec<Value>) -> Option<Value> {
    // println!("std_print: {}", parameters[0].as_string());
    println!("{}", parameters[0].as_string());
    None
}
