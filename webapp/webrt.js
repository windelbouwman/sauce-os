import {
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
} from "./slangrt.js";

let output_parts = [];

function die(message) {
  console.log(message);
  process.exit(1);
}

function std_print(text) {
  console.log(text);
}

function std_exit(value) {
  process.exit(Number(value));
}

function std_getch() {
  die("TODO: std_getch");
  return 0;
}

function std_read_line() {
  die("TODO: std_read_line");
  return "";
}

function std_get_path_separator() {
  return "/";
}

function std_file_exists() {
  die("TODO: std_file_exists");
  return false;
}

function std_file_get_stdin() {
  return BigInt(0);
}

function std_file_get_stdout() {
  return BigInt(1);
}

function std_file_open() {
  die("TODO: std_file_open");
  return -1;
}

function std_file_close(handle) {
  die("TODO: std_file_close");
}

function std_file_readln(handle) {
  die("TODO: std_file_readln");
  return "";
}

function std_file_writeln(handle, text) {
  // console.log(text);
  output_parts.push(text);
  output_parts.push("\n");
}

function std_file_write(handle, text) {
  // console.log(text);
  output_parts.push(text);
}

function std_file_read_n_bytes(handle) {
  die("TODO: std_file_read_n_bytes");
}

function std_file_write_n_bytes(handle, buffer, size) {
  die("TODO: std_file_write_n_bytes");
}

function std_file_seek(handle, position) {
  die("TODO: std_file_seek");
}

function std_file_tell(handle) {
  die("TODO: std_file_tell");
  return 0;
}

function std_read_file(filename) {
  const dataBuffer = fs.readFileSync(filename);
  return dataBuffer;
}

function std_get_n_args() {
  console.log("In std_get_n_args");
  die("TODO: std_get_n_args");
  return 0;
}

function std_get_arg(index) {
  console.log("In std_get_arg");
  die("TODO: std_get_arg");
  return 13;
}

function std_get_time() {
  return BigInt(Math.round(performance.now() * 1000000));
}

function std_pack_f64(value, buffer) {
  die("TODO: std_pack_f64");
}

function std_pack_f32(value, buffer) {
  die("TODO: std_pack_f32");
}

const slangrt = {
  rt_int_to_str,
  rt_char_to_str,
  rt_str_concat,
  rt_str_compare,
  std_print,
  std_float_to_str,
  std_float_to_str2,
  std_exit,
  std_getch,
  std_read_line,
  std_get_path_separator,
  std_file_exists,
  std_file_get_stdin,
  std_file_get_stdout,
  std_file_open,
  std_file_close,
  std_file_readln,
  std_file_writeln,
  std_file_write,
  std_file_read_n_bytes,
  std_file_write_n_bytes,
  std_file_seek,
  std_file_tell,
  std_read_file,
  std_ord,
  std_chr,
  std_str_len: rt_str_len,
  rt_str_len,
  std_str_slice,
  std_str_get: rt_str_get,
  rt_str_get,
  std_get_n_args,
  std_get_arg,
  std_get_time,
  std_pack_f64,
  std_pack_f32,
};

async function loadModule(url, importObject) {
  let response = await fetch(url);
  let bytes = await response.arrayBuffer();
  let wasmModule = WebAssembly.instantiate(bytes, importObject, {
    builtins: ["js-string"],
  });
  return wasmModule;
}

const exampleCodes = {
  bare: `
pub fn main() -> int:
	2 + 3
`,
  hello: `
import std

pub fn main() -> int:
	let msg = "Hello cool world!!"
	std.print(msg)
	# std.print(msg)
	foo()
	std.print("Cool escaping: hex-41:\x41 backslash:\\ double-quote:\"")
	std.print("Yes" if 1 > 1 else "No" if false else "maybe")
	0

fn foo():
	if 2 < 7 - 1:
		std.print("Hello world2")
`,
};

console.log("Load webassembly script");

let libbase = await loadModule("libbase.wasm", { slangrt });
let libcompiler = await loadModule("libcompiler.wasm", {
  slangrt,
  libbase: libbase.instance.exports,
});
let hello_world = await loadModule("snippets/hello_world.wasm", {
  slangrt,
});

// Do something with the results!
const res = hello_world.instance.exports.main2();
console.log("Result of main:", res);

const menu = document.getElementById("example-menu");
const editor = document.getElementById("input-code");
const output = document.getElementById("output-code");

menu.addEventListener("change", (event) => {
  editor.value = exampleCodes[menu.value];
  doCompile();
});

function doCompile() {
  output_parts.length = 0; // clear array
  libcompiler.instance.exports.driver_slang_to_python(editor.value);
  let res2 = output_parts.join("");
  output.value = res2;
}

editor.addEventListener("input", () => {
  doCompile();
});

editor.value = exampleCodes[menu.value];
doCompile();
