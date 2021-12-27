mod bytecode;
mod errors;
mod ir_gen;
mod llvm_backend;
mod parsing;
mod type_system;
mod typecheck;
mod typed_ast;
mod typed_ast_printer;
mod vm;

use bytecode::print_bytecode;
use errors::{print_error, CompilationError};
use parsing::parse_src;

fn main() -> Result<(), ()> {
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
            clap::Arg::with_name("dump-bytecode")
                .long("dump-bytecode")
                .help("Spit out bytecode intermediate format."),
        )
        .arg(
            clap::Arg::with_name("execute-bytecode")
                .long("execute-bytecode")
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
    log::info!("Hello, world!");

    let path = std::path::Path::new(matches.value_of("source").unwrap());
    let output_path = matches.value_of("output").map(std::path::Path::new);
    let options = CompileOptions {
        dump_bc: matches.is_present("dump-bytecode") || verbosity > 5,
        dump_ast: verbosity > 5,
        dump_src: verbosity > 5,
        run_bc: false,
    };
    match compile(path, output_path, &options) {
        Ok(()) => {
            log::info!("Great okidoki");
            Ok(())
        }
        Err(err) => {
            log::error!("Compilation errors");
            print_error(path, err);
            Err(())
        }
    }
}

struct CompileOptions {
    dump_src: bool,
    dump_ast: bool,
    dump_bc: bool,
    run_bc: bool,
}

fn compile(
    path: &std::path::Path,
    output_path: Option<&std::path::Path>,
    options: &CompileOptions,
) -> Result<(), CompilationError> {
    log::info!("Reading: {}", path.display());
    let source = std::fs::read_to_string(path).map_err(|err| {
        CompilationError::simple(format!("Error opening {}: {}", path.display(), err))
    })?;
    if options.dump_src {
        log::debug!("Dumpin sourcecode below");
        println!("{}", source);
    }
    let prog = parse_src(&source)?;
    log::info!("Parsing done&done");
    let typed_prog = typecheck::type_check(prog)?;
    log::info!("Type check done&done");
    if options.dump_ast {
        log::debug!("Dumping typed AST");
        typed_ast_printer::print_ast(&typed_prog);
    }
    let bc = ir_gen::gen(typed_prog);

    if options.dump_bc {
        log::debug!("Dumpin bytecode below");
        print_bytecode(&bc);
    }

    if options.run_bc {
        // Run in VM!!!
        vm::execute(bc.clone());
    }

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
        log::info!("Writing LLVM code to: {}", output_path.display());
        let mut output_writer = std::fs::OpenOptions::new()
            .write(true)
            .truncate(true)
            .create(true)
            .open(output_path)
            .unwrap();
        llvm_backend::create_llvm_text_code(bc, &mut output_writer);
    } else {
        log::info!("Output file not given, dumping LLVM code to stdout");
        let mut buf2 = vec![];
        llvm_backend::create_llvm_text_code(bc, &mut buf2);
        println!("And result: {}", std::str::from_utf8(&buf2).unwrap());
    }

    Ok(())
}
