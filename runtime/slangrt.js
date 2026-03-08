function rt_int_to_str(value) {
  return value.toString();
}

function rt_char_to_str(value) {
  return String.fromCharCode(value);
}

function rt_str_concat(a, b) {
  return a.concat(b);
}

function rt_str_compare(a, b) {
  return a === b ? 1 : 0;
}

function std_float_to_str(value) {
  return value.toFixed(6);
}

function std_float_to_str2(value, digits) {
  return value.toFixed(Number(digits));
}

function std_ord(value) {
  return BigInt(value);
}

function std_chr(value) {
  return Number(value);
}

function rt_str_len(value) {
  return BigInt(value.length);
}

function std_str_slice(text, begin, end) {
  return text.substring(Number(begin), Number(end));
}

function rt_str_get(value, index) {
  return value.charCodeAt(Number(index));
}

export {
  rt_int_to_str,
  rt_char_to_str,
  rt_str_concat,
  rt_str_compare,
  std_float_to_str,
  std_float_to_str2,
  std_ord,
  std_chr,
  rt_str_len,
  std_str_slice,
  rt_str_get,
};
