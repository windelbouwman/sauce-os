//!
//! SLANG compiler.
//!
//! Command line arguments can be given.
//!
mod builtins;
mod bytecode;
mod compilation;
mod errors;
mod ir_gen;
mod llvm_backend;
mod parsing;
mod semantics;
mod tast;
mod transformation;
mod vm;

use compilation::CompileOptions;
use errors::{print_error, CompilationError};

fn main() -> Result<(), ()> {
    let matches = clap::App::new("Compiler")
        .version("0")
        .author("Windel Bouwman")
        .about("Cool beans")
        .arg(
            clap::Arg::with_name("source")
                .help("File to compile")
                .multiple(true)
                .required(true),
        )
        .arg(
            clap::Arg::with_name("verbosity")
                .multiple(true)
                .short("v")
                .help("Sets level of verbosity"),
        )
        .arg(
            clap::Arg::with_name("dump-ast")
                .long("dump-ast")
                .help("Print out bytecode intermediate format."),
        )
        .arg(
            clap::Arg::with_name("dump-bytecode")
                .long("dump-bytecode")
                .help("Print out bytecode intermediate format."),
        )
        .arg(
            clap::Arg::with_name("emit-bytecode")
                .long("emit-bytecode")
                .help("Spit out bytecode intermediate format in json format."),
        )
        .arg(
            clap::Arg::with_name("execute-bytecode")
                .long("execute-bytecode")
                .short("r")
                .help("Run bytecode intermediate format. (sort of python-ish mode)"),
        )
        .arg(
            clap::Arg::with_name("output")
                .long("output")
                .takes_value(true)
                .help("Where to write the output to"),
        )
        .get_matches();

    let verbosity = matches.occurrences_of("verbosity");
    let log_level = match verbosity {
        0 => log::Level::Warn,
        1 => log::Level::Info,
        2 => log::Level::Debug,
        _ => log::Level::Trace,
    };

    simple_logger::init_with_level(log_level).unwrap();

    let options = CompileOptions {
        dump_bc: matches.is_present("dump-bytecode"),
        dump_ast: matches.is_present("dump-ast"),
    };

    // Compile source to bytecode
    let paths: Vec<&std::path::Path> = matches
        .values_of("source")
        .unwrap()
        .map(std::path::Path::new)
        .collect();

    let bc = compilation::compile_to_bytecode(&paths, &options).map_err(|err| {
        log::error!("Compilation errors");
        print_error(err);
    })?;

    log::info!("Great okidoki");

    // ============
    // HERE BEGINS STAGE 2
    // Options:
    // - serialize to disk!
    // - run in interpreter
    // - contrapt LLVM code
    // - contrapt QBE IR code.
    // - create WASM module!

    // Execute or compile to LLVM
    if matches.is_present("execute-bytecode") {
        log::info!("Running interpreted, python style!");
        // Run in VM!!!
        vm::execute(bc);
        log::info!("Interpreting done & done");
    } else if matches.is_present("emit-bytecode") {
        let serialized = serde_json::to_string_pretty(&bc).unwrap();
        println!("bytecode json: {}", serialized);
    } else {
        let output_path = matches.value_of("output").map(std::path::Path::new);
        compilation::bytecode_to_llvm(bc, output_path);
    }

    Ok(())
}
