use crate::bytecode::print_bytecode;
use crate::errors::CompilationError;
use crate::llvm_backend;
use crate::parsing::parse_src;
use crate::semantics::{print_ast, type_check};
use crate::{bytecode, ir_gen, vm};

pub struct CompileOptions {
    pub dump_src: bool,
    pub dump_ast: bool,
    pub dump_bc: bool,
    pub run_bc: bool,
}

fn stage1(
    path: &std::path::Path,
    options: &CompileOptions,
) -> Result<bytecode::Program, CompilationError> {
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
    let typed_prog = type_check(prog)?;
    log::info!("Type check done&done");
    if options.dump_ast {
        log::debug!("Dumping typed AST");
        print_ast(&typed_prog);
    }
    let bc = ir_gen::gen(typed_prog);

    Ok(bc)
}

pub fn compile(
    path: &std::path::Path,
    output_path: Option<&std::path::Path>,
    options: &CompileOptions,
) -> Result<(), CompilationError> {
    let bc = stage1(path, options)?;
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
