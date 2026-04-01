/*
Loader for generated webassembly files

Run with:

$ node runtime.js program.wasm

*/

import fs from "fs";
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

// console.log("Load webassembly script");

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
  die("TODO: std_file_get_stdin");
  return 0;
}

function std_file_get_stdout() {
  die("TODO: std_file_get_stdout");
  return 1;
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

function std_file_writeln(handle) {
  die("TODO: std_file_writeln");
}

function std_file_write(handle) {
  die("TODO: std_file_write");
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

async function loadModule(path, importObject) {
  const wasmBuffer = await fs.promises.readFile(path);
  const module = await WebAssembly.instantiate(wasmBuffer, importObject, {
    builtins: ["js-string"],
  });
  return module;
}

async function runUnitTests() {
  const libbase = await loadModule("build/wasm/libbase.wasm", {
    slangrt,
  });
  const libscience = await loadModule("build/wasm/libscience.wasm", {
    slangrt,
    libbase: libbase.instance.exports,
  });
  const libimage = await loadModule("build/wasm/libimage.wasm", {
    slangrt,
    libbase: libbase.instance.exports,
  });
  const libcompiler = await loadModule("build/wasm/libcompiler.wasm", {
    slangrt,
    libbase: libbase.instance.exports,
  });

  // Exported function live under instance.exports
  console.log(
    "Result of math_abs:",
    libbase.instance.exports.base_math_abs(BigInt(-9)),
  );
  console.log(
    "Result of math_radians:",
    libbase.instance.exports.base_math_radians(181),
  );
  console.log(
    "Result of math_pi:",
    libbase.instance.exports.base_math_pi.value,
  );
  console.log(
    "Result of strlib_str_repeat:",
    libbase.instance.exports.base_strlib_str_repeat("poah", BigInt(7)),
  );

  // Unit test
  for (const dir of ["build/wasm/tests", "build/wat/tests"]) {
    for await (const testModulePath of fs.promises.glob(dir + "/test*.wasm")) {
      console.log("Running unit test:", testModulePath);
      const test_module = await loadModule(testModulePath, {
        slangrt,
        libbase: libbase.instance.exports,
        libcompiler: libcompiler.instance.exports,
        libimage: libimage.instance.exports,
        libscience: libscience.instance.exports,
      });
      const res = test_module.instance.exports.main_main();
      console.assert(res == 0, "Result must be 0");
    }
  }
  console.log("GREAT SUCCES");
}

async function runSnippet(filename) {
  const wasmModule = await loadModule(filename, {
    slangrt,
  });
  // Exported function live under instance.exports
  const res = wasmModule.instance.exports.main_main();
  process.exit(Number(res));
}

if (process.argv.length < 3) {
  await runUnitTests();
} else {
  let wasm_file = process.argv.at(2);
  await runSnippet(wasm_file);
}
