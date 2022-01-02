mod bytecode;
mod compilation;
mod errors;
mod ir_gen;
mod llvm_backend;
mod parsing;
mod semantics;
mod vm;

use compilation::{compile, CompileOptions};
use errors::{print_error, CompilationError};

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
