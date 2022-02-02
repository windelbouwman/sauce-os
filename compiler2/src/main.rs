mod bytecode;
mod compilation;
mod desugar;
mod errors;
mod ir_gen;
mod llvm_backend;
mod parsing;
mod semantics;
mod simple_ast;
mod simple_ast_printer;
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
                .help("Spit out bytecode intermediate format."),
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

    let options = CompileOptions {
        dump_bc: matches.is_present("dump-bytecode") || verbosity > 5,
        dump_ast: matches.is_present("dump-ast") || verbosity > 5,
        dump_src: verbosity > 5,
    };

    if matches.is_present("execute-bytecode") {
        let path = std::path::Path::new(matches.value_of("source").unwrap());
        interpret_mode(path, &options);
        Ok(())
    } else if matches.occurrences_of("source") > 1 {
        let paths: Vec<&std::path::Path> = matches
            .values_of("source")
            .unwrap()
            .map(std::path::Path::new)
            .collect();
        for path in &paths {
            log::debug!("Got: {}", path.display());
        }
        compilation::build_multi(&paths, &options);
        Ok(())
    } else {
        let path = std::path::Path::new(matches.value_of("source").unwrap());
        let output_path = matches.value_of("output").map(std::path::Path::new);
        let res = compilation::compile(path, output_path, &options);
        match res {
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
}

fn interpret_mode(path: &std::path::Path, options: &CompileOptions) {
    match compilation::compile_to_bytecode(path, options) {
        Ok(bc) => {
            log::info!("Running interpreted, python style!");
            // Run in VM!!!
            vm::execute(bc);
            log::info!("Interpreting done & done");
        }
        Err(err) => {
            print_error(path, err);
        }
    }
}
