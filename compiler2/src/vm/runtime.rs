use super::Value;

pub fn std_print(parameters: Vec<Value>) -> Option<Value> {
    // println!("std_print: {}", parameters[0].as_string());
    println!("{}", parameters[0].as_string());
    None
}

pub fn std_int_to_str(parameters: Vec<Value>) -> Option<Value> {
    let int_value = parameters.into_iter().next().unwrap().as_int();
    Some(Value::String(format!("{}", int_value)))
}

pub fn std_float_to_str(parameters: Vec<Value>) -> Option<Value> {
    let float_value = parameters.into_iter().next().unwrap().as_float();
    Some(Value::String(format!("{}", float_value)))
}
