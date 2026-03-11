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

const example_menu = document.getElementById("example-menu");
const editor = document.getElementById("input-code");
const output = document.getElementById("output-code");
const console_output = document.getElementById("console-output");
const clear_console_button = document.getElementById("clear-console");
const extra_args_input = document.getElementById("extra-args");

class TextFileWriter {
  constructor(fs, path) {
    this.fs = fs;
    this.path = path;
    this.parts = [];
  }

  writeText(text) {
    this.parts.push(text);
  }

  close() {
    let contents = this.parts.join("");
    this.fs.setFileContents(this.path, contents);
  }
}

class MemoryFS {
  constructor() {
    this.files = new Map();
    this.file_handles = new Map();
    this.handle_counter = 0;
  }

  fileExists(path) {
    return this.files.has(path);
  }

  setFileContents(path, contents) {
    this.files.set(path, contents);
  }

  getFileContents(path) {
    if (this.files.has(path)) {
      return this.files.get(path);
    } else {
      throw new Error("File not found: " + path);
    }
  }

  openFile(path, mode) {
    let handle = this.handle_counter;
    this.handle_counter += 1;
    if (mode == "w") {
      this.file_handles.set(handle, new TextFileWriter(this, path));
      // } else if (mode == "wb") {
    } else {
      throw new Error("Unknown mode: " + mode);
    }
    return handle;
  }

  writeText(handle, text) {
    if (this.file_handles.has(handle)) {
      let f = this.file_handles.get(handle);
      f.writeText(text);
    } else {
      throw new Error("Invalid file handle:" + handle);
    }
  }

  closeFile(handle) {
    if (this.file_handles.has(handle)) {
      let f = this.file_handles.get(handle);
      f.close();
      this.file_handles.delete(handle);
    } else {
      throw new Error("Invalid file handle:" + handle);
    }
  }
}

let fs = new MemoryFS();
let env = {
  args: [],
};

function die(message) {
  console.log(message);
  process.exit(1);
}

function std_print(text) {
  console_output.value += text + "\n";
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

function std_file_open(filename, mode) {
  return BigInt(fs.openFile(filename, mode));
}

function std_file_close(handle) {
  fs.closeFile(Number(handle));
}

function std_file_readln(handle) {
  die("TODO: std_file_readln");
  return "";
}

function std_file_writeln(handle, text) {
  fs.writeText(Number(handle), text);
  fs.writeText(Number(handle), "\n");
}

function std_file_write(handle, text) {
  fs.writeText(Number(handle), text);
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
  return fs.getFileContents(filename);
}

function std_get_n_args() {
  return BigInt(env.args.length);
}

function std_get_arg(index) {
  return env.args[index];
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

async function loadSource(url) {
  let response = await fetch(url);
  let code = await response.text();
  return code;
}

let libbase = await loadModule("libbase.wasm", { slangrt });
let libcompiler = await loadModule("libcompiler.wasm", {
  slangrt,
  libbase: libbase.instance.exports,
});
let libimage = await loadModule("libimage.wasm", {
  slangrt,
  libbase: libbase.instance.exports,
});
let libscience = await loadModule("libscience.wasm", {
  slangrt,
  libbase: libbase.instance.exports,
});
let compiler = await loadModule("compiler.wasm", {
  slangrt,
  libbase: libbase.instance.exports,
  libcompiler: libcompiler.instance.exports,
});

async function runUnitTest(name) {
  std_print("Running test: " + name);
  let url = "tests/" + name + ".wasm";
  let testModule = await loadModule(url, {
    slangrt,
    libbase: libbase.instance.exports,
    libcompiler: libcompiler.instance.exports,
    libimage: libimage.instance.exports,
    libscience: libscience.instance.exports,
  });
  let res = testModule.instance.exports.main2();
  console.assert(Number(res) === 0, "Test failed");
}

async function runUnitTests() {
  // TODO: would be nice to somehow get this from file?
  let test_names = [
    "test_base64",
    "test_bitset",
    "test_bytes",
    "test_compiler",
    "test_crypto",
    "test_datetime",
    "test_deflate",
    "test_diff",
    "test_functools",
    "test_geometries",
    "test_gif",
    "test_hashmap",
    "test_hash",
    "test_heapq",
    "test_igraph",
    "test_integer_set",
    "test_json",
    "test_list",
    "test_math",
    "test_opt",
    "test_queue",
    "test_regex",
    "test_riscv",
    "test_rope",
    "test_rt",
    "test_set",
    "test_signal",
    "test_sorting",
    "test_strlib",
    "test_vector",
    "test_x86",
  ];
  for (let name of test_names) {
    await runUnitTest(name);
  }
}

runUnitTests();

let std_code = await loadSource("std.slang");
fs.setFileContents("std.slang", std_code);

async function selectSnippet(name) {
  let url = "snippets/" + name + ".slang";
  editor.value = await loadSource(url);
  doCompile();
}

example_menu.addEventListener("change", (event) => {
  selectSnippet(example_menu.value);
});

function invokeCompiler(args) {
  env.args = args;
  let res = compiler.instance.exports.main2();
  console.assert(Number(res) === 0, "Compiler failed");
}

function doCompile() {
  let srcFilename = "example.slang";
  let outFilename = "foo.py";
  fs.setFileContents(srcFilename, editor.value);
  let extra_args = extra_args_input.value.split(" ");
  invokeCompiler(
    [srcFilename, "std.slang", "-o", outFilename].concat(extra_args),
  );
  output.value = fs.getFileContents(outFilename);
}

editor.addEventListener("input", () => {
  doCompile();
});

extra_args_input.addEventListener("blur", () => {
  doCompile();
});

clear_console_button.addEventListener("click", () => {
  console_output.value = "";
});

selectSnippet(example_menu.value);
