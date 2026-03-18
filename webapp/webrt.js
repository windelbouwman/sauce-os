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
import { MemoryFS } from "./memfs.js";

const example_menu = document.getElementById("example-menu");
const editor = document.getElementById("input-code");
const output = document.getElementById("output-code");
const console_output = document.getElementById("console-output");
const run_button = document.getElementById("run-button");
const backend_menu = document.getElementById("backend-menu");
const extra_args_input = document.getElementById("extra-args");

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
  console_output.scrollTop = console_output.scrollHeight;
}

function cls() {
  console_output.value = "";
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
  let data = extract_array_from_wasm(buffer, Number(size));
  fs.writeData(Number(handle), data);
  return size;
}

function std_file_seek(handle, position) {
  fs.seek(Number(handle), Number(position));
}

function std_file_tell(handle) {
  return BigInt(fs.tell(Number(handle)));
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
  let wasmModule = await WebAssembly.instantiateStreaming(
    fetch(url),
    importObject,
    {
      builtins: ["js-string"],
    },
  );
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

function extract_array_from_wasm(buffer, bufsize) {
  let data = new Uint8Array(bufsize);
  for (let i = 0; i < bufsize; i++) {
    let b = libbase.instance.exports.bytes_get_byte_from_array(
      buffer,
      BigInt(i),
    );
    data[i] = Number(b);
  }
  return data;
}

async function runApp(url) {
  let appModule = await loadModule(url, {
    slangrt,
    libbase: libbase.instance.exports,
    libcompiler: libcompiler.instance.exports,
    libimage: libimage.instance.exports,
    libscience: libscience.instance.exports,
  });
  return appModule.instance.exports.main2();
}

async function runUnitTest(name) {
  std_print("Running test: " + name);
  let url = "tests/" + name + ".wasm";
  let res = await runApp(url);
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
  std_print("All tests ran!");
}

let std_code = await loadSource("std.slang");
fs.setFileContents("std.slang", std_code);

async function selectSnippet(name) {
  let url = "snippets/" + name + ".slang";
  editor.value = await loadSource(url);
  await doCompile();
}

example_menu.addEventListener("change", (event) => {
  selectSnippet(example_menu.value);
});

function invokeCompiler(args) {
  env.args = args;
  let res = compiler.instance.exports.main2();
  console.assert(Number(res) === 0, "Compiler failed");
}

let srcFilename = "example.slang";
let outFilename = "foo.py";

function setVisible(control, value) {
  if (value) {
    control.classList.remove("hidden");
  } else {
    control.classList.add("hidden");
  }
}

async function doCompile() {
  fs.setFileContents(srcFilename, editor.value);
  let extra_args = extra_args_input.value
    .split(" ")
    .map((i) => i.trim())
    .filter((i) => i.length > 0);
  invokeCompiler(
    [srcFilename, "std.slang", "-o", outFilename].concat(extra_args),
  );
  let outputData = fs.getFileContents(outFilename);
  if (outputData instanceof Uint8Array) {
    output.value = "binary";
    setVisible(output, false);
  } else {
    output.value = outputData;
    setVisible(output, true);
  }
  setVisible(run_button, extra_args.includes("--backend-wasm"));
}

backend_menu.addEventListener("change", (event) => {
  extra_args_input.value = backend_menu.value;
  doCompile();
});

async function doRun() {
  let outputData = fs.getFileContents(outFilename);
  if (outputData instanceof Uint8Array) {
    let wasmModule = await WebAssembly.instantiate(
      outputData,
      { slangrt },
      {
        builtins: ["js-string"],
      },
    );
    cls();
    let res = wasmModule.instance.exports.main2();
    console.log("Exit code: " + res);
  }
}

editor.addEventListener("keydown", (e) => {
  if (e.key === "Tab") {
    e.preventDefault();
    const start = editor.selectionStart;
    const end = editor.selectionEnd;
    editor.value =
      editor.value.substring(0, start) + "\t" + editor.value.substring(end);
    editor.selectionStart = editor.selectionEnd = start + 1;
  }
});

editor.addEventListener("input", () => {
  doCompile();
});

extra_args_input.addEventListener("blur", () => {
  doCompile();
});

document
  .getElementById("clear-console-button")
  .addEventListener("click", () => {
    cls();
  });

document.getElementById("run-tests-button").addEventListener("click", () => {
  runUnitTests();
});

document.getElementById("run-mandel-button").addEventListener("click", () => {
  runApp("apps/mandel.wasm");
});

run_button.addEventListener("click", () => {
  doRun();
});

selectSnippet(example_menu.value);
