use crate::bytecode;
use crate::errors::{print_error, CompilationError};
use crate::llvm_backend;
use crate::parsing::{ast, parse_src};
use crate::semantics::type_system::MyType;
use crate::semantics::{print_ast, type_check, typed_ast};
use crate::semantics::{Scope, Symbol};
use crate::{ir_gen, vm};

pub struct CompileOptions {
    pub dump_src: bool,
    pub dump_ast: bool,
    pub dump_bc: bool,
}

/// Define functions provided by 'std' module.
fn load_std_module(scope: &mut Scope) {
    let mut std_scope = Scope::new();

    // TODO: these could be loaded from interface/header like file?
    std_scope.define_func("putc", vec![MyType::String], None);
    std_scope.define_func("print", vec![MyType::String], None);
    std_scope.define_func("read_file", vec![MyType::String], Some(MyType::String));
    let name = "std".to_owned();
    scope.define(
        name.clone(),
        Symbol::Module {
            name,
            scope: std_scope,
        },
    );
}

fn add_to_pool(name: String, prog: &typed_ast::Program, scope: &mut Scope) {
    log::info!("Adding '{}' in the module mix!", name);
    let mut inner_scope = Scope::new();

    // Fill type-defs:
    for typ_def in &prog.type_defs {
        inner_scope.define_type(&typ_def.name, typ_def.typ.clone());
    }

    for func_def in &prog.functions {
        inner_scope.define_func(
            &func_def.name,
            func_def.parameters.iter().map(|p| p.typ.clone()).collect(),
            func_def.return_type.clone(),
        );
    }

    let module_obj = Symbol::Module {
        name: name.clone(),
        scope: inner_scope,
    };

    scope.define(name, module_obj);
}

fn parse_one(
    path: &std::path::Path,
    options: &CompileOptions,
) -> Result<ast::Program, CompilationError> {
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
    Ok(prog)
}

fn stage1(
    path: &std::path::Path,
    options: &CompileOptions,
    module_scope: &Scope,
) -> Result<typed_ast::Program, CompilationError> {
    let prog = parse_one(path, options)?;
    let typed_prog = type_check(prog, module_scope.clone())?;
    log::info!("Type check done&done");
    if options.dump_ast {
        log::debug!("Dumping typed AST");
        print_ast(&typed_prog);
    }

    Ok(typed_prog)
}

pub fn compile_to_bytecode(
    path: &std::path::Path,
    options: &CompileOptions,
) -> Result<bytecode::Program, CompilationError> {
    let mut module_scope = Scope::new();
    load_std_module(&mut module_scope);

    let typed_prog = stage1(path, options, &module_scope)?;

    let bc = ir_gen::gen(typed_prog);
    if options.dump_bc {
        log::debug!("Dumping bytecode below");
        bytecode::print_bytecode(&bc);
    }

    Ok(bc)
}

/// Compile a single source file to a single LLVM output file
pub fn compile(
    path: &std::path::Path,
    output_path: Option<&std::path::Path>,
    options: &CompileOptions,
) -> Result<(), CompilationError> {
    let bc = compile_to_bytecode(path, options)?;

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

/// Build a slew of source files.
///
/// This is a sort of driver mode, which loads sources onto a work queue
/// and progresses where possible.
pub fn build_multi(paths: &[&std::path::Path], options: &CompileOptions) {
    let mut backlog = vec![];
    for path in paths {
        backlog.push(WorkItem::File(path.to_path_buf()));
    }

    let mut module_scope = Scope::new();
    load_std_module(&mut module_scope);

    while !backlog.is_empty() {
        let x = backlog.pop().unwrap();
        match x {
            WorkItem::File(path) => {
                log::info!("Parsing: {}", path.display());
                match parse_one(&path, options) {
                    Ok(program) => {
                        backlog.push(WorkItem::Ast { path, program });
                    }
                    Err(err) => {
                        print_error(&path, err);
                    }
                }
            }
            WorkItem::Ast { path, program } => {
                // test if all imports are satisfied?
                if program.deps().iter().all(|n| module_scope.is_defined(n)) {
                    log::info!("Checking module: {}", path.display());
                    match type_check(program, module_scope.clone()) {
                        Ok(typed_prog) => {
                            let modname: String =
                                path.file_stem().unwrap().to_str().unwrap().to_owned();
                            add_to_pool(modname, &typed_prog, &mut module_scope);

                            let bc = ir_gen::gen(typed_prog);
                            if options.dump_bc {
                                log::debug!("Dumpin bytecode below");
                                bytecode::print_bytecode(&bc);
                            }

                            // TODO: store for later usage? What now?
                        }
                        Err(err) => {
                            print_error(&path, err);
                        }
                    }
                } else {
                    log::error!("Too bad, module deps not all satisfied!");
                    // TODO: retry? sort?
                }
            }
        }
    }
}

enum WorkItem {
    File(std::path::PathBuf),
    Ast {
        path: std::path::PathBuf,
        program: ast::Program,
    },
}
