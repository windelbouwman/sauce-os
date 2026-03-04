/*
Loader for generated webassembly files

Run with:

$ node runtime.js program.wasm

*/

import fs from "fs";

// console.log("Load webassembly script");

function die(message) {
  console.log(message);
  process.exit(1);
}

const slangrt = {
  rt_int_to_str(value) {
    return value.toString();
  },

  rt_char_to_str(value) {
    return String.fromCharCode(value);
  },

  rt_str_concat(a, b) {
    return a.concat(b);
  },

  rt_str_compare(a, b) {
    return a === b ? 1 : 0;
  },

  std_print(text) {
    console.log(text);
  },

  std_float_to_str: function (value) {
    return value.toFixed(6);
  },

  std_float_to_str2: function (value, digits) {
    return value.toFixed(Number(digits));
  },

  std_exit(value) {
    process.exit(Number(value));
  },

  std_getch() {
    die("TODO: std_getch");
    return 0;
  },

  std_read_line() {
    die("TODO: std_read_line");
    return "";
  },

  std_get_path_separator() {
    return "/";
  },

  std_file_exists() {
    die("TODO: std_file_exists");
    return false;
  },

  std_file_get_stdin() {
    die("TODO: std_file_get_stdin");
    return 0;
  },

  std_file_get_stdout() {
    die("TODO: std_file_get_stdout");
    return 1;
  },

  std_file_open() {
    die("TODO: std_file_open");
    return -1;
  },

  std_file_close(handle) {
    die("TODO: std_file_close");
  },

  std_file_readln(handle) {
    die("TODO: std_file_readln");
    return "";
  },

  std_file_writeln(handle) {
    die("TODO: std_file_writeln");
  },

  std_file_write(handle) {
    die("TODO: std_file_write");
  },

  std_file_read_n_bytes(handle) {
    die("TODO: std_file_read_n_bytes");
  },

  std_file_write_n_bytes(handle, buffer, size) {
    die("TODO: std_file_write_n_bytes");
  },

  std_file_seek(handle, position) {
    die("TODO: std_file_seek");
  },

  std_file_tell(handle) {
    die("TODO: std_file_tell");
    return 0;
  },

  std_read_file(filename) {
    const dataBuffer = fs.readFileSync(filename);
    return dataBuffer;
  },

  std_ord(value) {
    return BigInt(value);
  },

  std_chr(value) {
    return Number(value);
  },

  std_str_len(value) {
    return rt_str_len(value);
  },

  rt_str_len(value) {
    return BigInt(value.length);
  },

  std_str_slice(value) {
    console.log("In std_str_slice");
    die("TODO: std_str_slice");
    return 13;
  },

  std_str_get(value, index) {
    return rt_str_get(value, index);
  },

  rt_str_get(value, index) {
    return value.charCodeAt(Number(index));
  },

  std_get_n_args() {
    console.log("In std_get_n_args");
    die("TODO: std_get_n_args");
    return 0;
  },

  std_get_arg(index) {
    console.log("In std_get_arg");
    die("TODO: std_get_arg");
    return 13;
  },

  std_get_time() {
    die("TODO: std_get_time");
    return 0;
  },

  std_pack_f64(value, buffer) {
    die("TODO: std_pack_f64");
  },

  std_pack_f32(value, buffer) {
    die("TODO: std_pack_f32");
  },

  rt_ctz(value) {
    die("TODO: rt_ctz");
    return 0;
  },

  rt_clz(value) {
    die("TODO: rt_clz");
    return 0;
  },

  rt_popcnt(value) {
    die("TODO: rt_popcnt");
    return 0;
  },
};

if (process.argv.length < 3) {
  const baseWasmBuffer = await fs.promises.readFile("build/wasm/libbase.wasm");
  const libbase = await WebAssembly.instantiate(
    baseWasmBuffer,
    {
      slangrt,
    },
    {
      builtins: ["js-string"],
    },
  );

  const scienceWasmBuffer = await fs.promises.readFile(
    "build/wasm/libscience.wasm",
  );
  const libscience = await WebAssembly.instantiate(
    scienceWasmBuffer,
    {
      slangrt,
      libbase: libbase.instance.exports,
    },
    {
      builtins: ["js-string"],
    },
  );

  const compilerWasmBuffer = await fs.promises.readFile(
    "build/wasm/libcompiler.wasm",
  );

  // Exported function live under instance.exports
  const { math_abs } = libbase.instance.exports;
  console.log("Result of math_abs:", math_abs(BigInt(-9)));
  console.log(
    "Result of math_radians:",
    libbase.instance.exports.math_radians(181),
  );
  console.log("Result of math_pi:", libbase.instance.exports.math_pi.value);
  console.log(
    "Result of strlib_str_repeat:",
    libbase.instance.exports.strlib_str_repeat("poah", BigInt(7)),
  );
} else {
  let wasm_file = process.argv.at(2);
  // console.debug("Loading", wasm_file);
  const wasmBuffer = await fs.promises.readFile(wasm_file);
  const importObject = {
    slangrt,
  };
  const wasmModule = await WebAssembly.instantiate(wasmBuffer, importObject, {
    builtins: ["js-string"],
  });
  // Exported function live under instance.exports
  const { main2 } = wasmModule.instance.exports;
  const res = main2();
  // console.log("Result of main:", res);
  process.exit(Number(res));
  // process.exit(res);
}
