/*
Loader for generated webassembly files

Run with:

$ node runtime.js program.wasm

*/

const fs = require("fs");

// console.log("Load webassembly script");

const importObject = {
  slangrt: {
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
      return value.toFixed(digits);
    },

    std_exit(value) {
      console.log("In std_exit");
      return 13;
    },

    std_getch() {
      return 0;
    },

    std_read_line() {
      return "";
    },

    std_get_path_separator() {
      return "/";
    },

    std_file_exists() {
      return false;
    },

    std_file_get_stdin() {
      return 0;
    },

    std_file_get_stdout() {
      return 1;
    },

    std_file_open() {
      return -1;
    },

    std_file_close(handle) {
      return;
    },

    std_file_readln(handle) {
      return "";
    },

    std_file_writeln(handle) {
      return;
    },

    std_file_write(handle) {
      //
    },

    std_file_read_n_bytes(handle) {
      //
    },

    std_file_write_n_bytes(handle, buffer, size) {
      //
    },

    std_file_seek(handle, position) {
      //
    },

    std_file_tell(handle) {
      return 0;
    },

    std_read_file(filename) {
      const dataBuffer = fs.readFileSync(filename);
      return dataBuffer;
    },

    std_ord(value) {
      return value;
    },

    std_chr(value) {
      return value;
    },

    std_str_len(value) {
      return rt_str_len(value);
    },

    rt_str_len(value) {
      return value.length;
    },

    std_str_slice(value) {
      console.log("In std_str_slice");
      return 13;
    },

    std_str_get(value, index) {
      return rt_str_get(value, index);
    },

    rt_str_get(value, index) {
      return value.charCodeAt(index);
    },

    std_get_n_args() {
      console.log("In std_get_n_args");
      return 0;
    },

    std_get_arg(index) {
      console.log("In std_get_arg");
      return 13;
    },

    std_get_time() {
      // TODO
      return 0;
    },

    std_pack_f64(value, buffer) {
      // TODO
    },

    std_pack_f32(value, buffer) {
      // TODO
    },

    rt_ctz(value) {
      // TODO
      return 0;
    },

    rt_clz(value) {
      // TODO
      return 0;
    },

    rt_popcnt(value) {
      // TODO
      return 0;
    },
  },
};

let wasm_file = process.argv.at(2);
// console.debug("Loading", wasm_file);
const wasmBuffer = fs.readFileSync(wasm_file);
WebAssembly.instantiate(wasmBuffer, importObject, {
  builtins: ["js-string"],
}).then((wasmModule) => {
  // Exported function live under instance.exports
  const { main2 } = wasmModule.instance.exports;
  const res = main2();
  // console.log("Result of main:", res);
  // process.exit(Number(res));
  process.exit(res);
});
