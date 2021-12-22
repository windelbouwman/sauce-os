mod bytecode;
mod errors;
mod ir_gen;
mod llvm_backend;
mod parsing;
mod type_system;
mod typecheck;
mod typed_ast;

use errors::{print_error, CompilationError};
use parsing::parse_src;

fn main() {
    let matches = clap::App::new("Compiler")
        .version("0")
        .author("Windel Bouwman")
        .about("Cool beans")
        .arg(
            clap::Arg::with_name("source")
                .help("File to compile")
                .required(true),
        )
        .arg(
            clap::Arg::with_name("verbosity")
                .multiple(true)
                .short("v")
                .help("Sets level of verbosity"),
        )
        .arg(
            clap::Arg::with_name("output")
                .long("output")
                .takes_value(true)
                .help("Sets level of verbosity"),
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
    log::info!("Hello, world!");

    let path = std::path::Path::new(matches.value_of("source").unwrap());
    let output_path = matches.value_of("output").map(std::path::Path::new);
    match compile(&path, output_path) {
        Ok(()) => {
            log::info!("Great okidoki");
        }
        Err(err) => {
            log::error!("Compilation errors");
            print_error(path, err);
        }
    }
}

fn compile(
    path: &std::path::Path,
    output_path: Option<&std::path::Path>,
) -> Result<(), CompilationError> {
    log::info!("Reading: {}", path.display());
    let source = std::fs::read_to_string(path).unwrap();
    let prog = parse_src(&source)?;
    log::info!("Parsing done&done");
    let typed_prog = typecheck::type_check(prog)?;
    log::info!("Type check done&done");
    let bc = ir_gen::gen(typed_prog);

    // ============
    // HERE BEGINS STAGE 2
    // Options:
    // - serialize to disk!
    // - run in interpreter
    // - contrapt LLVM code
    // - create WASM module!
    let _serialized = serde_json::to_string_pretty(&bc).unwrap();
    // println!("{}", serialized);

    if let Some(output_path) = output_path {
        log::info!("Writing to: {}", output_path.display());
        let mut output_writer = std::fs::OpenOptions::new()
            .write(true)
            .create(true)
            .open(output_path)
            .unwrap();
        llvm_backend::create_llvm_text_code(bc, &mut output_writer);
    } else {
        let mut buf2 = vec![];
        llvm_backend::create_llvm_text_code(bc, &mut buf2);
        println!("And result: {}", std::str::from_utf8(&buf2).unwrap());
    }

    Ok(())
}
