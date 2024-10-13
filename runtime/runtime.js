
/*
Loader for generated webassembly files

Run with:

$ node runtime.js

*/

const fs = require('fs');

console.log("Load webassembly script");

const heapPtr = new WebAssembly.Global({ value: "i32", mutable: true }, 1000);
const memory = new WebAssembly.Memory({
    initial: 100,
    maximum: 100,
});

function get_string(memory, address) {
    // console.log("address", address, typeof(address));
    let buffer = new Uint8Array(memory.buffer, address, memory.buffer.byteLength - address);
    let term = buffer.indexOf(0); // Search for 0 terminator
    return new TextDecoder().decode(buffer.subarray(0, term));
}

function alloc(size) {
    let ptr = heapPtr.value;
    heapPtr.value = ptr + Number(size);
    // console.log("ALLOC", ptr, heapPtr.value, size, typeof(size));
    return ptr;
}

function alloc_string(memory, text) {
    let encoder = new TextEncoder();
    let encodedString = encoder.encode(text);
    let dataSize = encodedString.byteLength + 1;  // add space for 0-terminator
    let ptr = alloc(dataSize);
    let buffer = new Uint8Array(memory.buffer, Number(ptr), dataSize);
    buffer.set(encodedString);
    return ptr;
}

const importObject = {
    js: {
        mem: memory,
        malloc: alloc,
        heap: heapPtr,
    },
    rt: {
        int_to_str(value) {
            // console.log("In std_int_to_str", value, typeof(value));
            return alloc_string(memory, value.toString());
        },

        char_to_str(value) {
            console.log("In std_char_to_str");
            return 13;
        },

        str_concat(a, b) {
            // console.log("In rt_str_concat");
            let text1 = get_string(memory, a);
            let text2 = get_string(memory, b);
            let text3 = text1 + text2;
            let address = alloc_string(memory, text3);
            return address;
        },

        str_compare(a, b) {
            // console.log("In rt_str_compare");
            let text1 = get_string(memory, a);
            let text2 = get_string(memory, b);
            if (text1 === text2) {
                return 1;
            } else {
                return 0;
            }
        },
    },
    std: {
        print(text) {
            // console.log("In std_print", text, typeof(text));
            let text2 = get_string(memory, text);
            console.log(text2);
        },

        str_to_float: function (value) {
            console.log("In std_str_to_float");
            return 13;
        },

        float_to_str: function (value) {
            // console.log("In std_float_to_str");
            return alloc_string(memory, value.toString());
        },

        exit(value) {
            console.log("In std_exit");
            return 13;
        },

        read_file(filenamePtr) {
            console.log("In std_read_file");
            let filename = get_string(memory, filenamePtr);
            const dataBuffer = fs.readFileSync(filename);
            return alloc_string(memory, dataBuffer)
        },

        ord(value) {
            console.log("In std_ord");
            return 13;
        },

        chr(value) {
            console.log("In std_chr");
            return 13;
        },

        str_len(value) {
            console.log("In std_str_len");
            return 13;
        },

        str_slice(value) {
            console.log("In std_str_slice");
            return 13;
        },

        str_get(value) {
            console.log("In std_str_get");
            return 13;
        },


        get_n_args() {
            console.log("In std_get_n_args");
            return 0;
        },

        get_arg(index) {
            console.log("In std_get_arg");
            return 13;
        }
    }
};

// let wasm_file = 'build/wasm/mandel.wasm';
// let wasm_file = 'build/wasm/unreachable.wasm';
// let wasm_file = 'build/wasm/list-generic-oo.wasm';
let wasm_file = 'build/wasm/loops.wasm';
// let wasm_file = 'build/wasm/struct-passing.wasm';
// let wasm_file = 'build/wasm/hello-world.wasm';
// let wasm_file = 'linkable.wasm';
const wasmBuffer = fs.readFileSync(wasm_file);
WebAssembly.instantiate(wasmBuffer, importObject).then(wasmModule => {
    // Exported function live under instance.exports
    const { main } = wasmModule.instance.exports;
    const res = main();
    console.log("Result of main:", res);
});

