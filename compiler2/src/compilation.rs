//! Main compiler driver.
//!
//! Drive code through the various stages of compilation.
use crate::builtins::{define_builtins, load_std_module};
use crate::bytecode;
use crate::errors::CompilationError;
use crate::ir_gen;
use crate::llvm_backend;
use crate::parsing::{ast, parse_file};
use crate::semantics::{analyze, print_ast, Context, Scope, Symbol};
use std::collections::HashMap;
use std::rc::Rc;

pub struct CompileOptions {
    pub dump_ast: bool,
    pub dump_bc: bool,
}

/// Compile source files into bytecode.
///
/// Performs:
/// - parsing
/// - type checking
/// - compilation into bytecode
pub fn compile_to_bytecode(
    paths: &[&std::path::Path],
    options: &CompileOptions,
) -> Result<bytecode::Program, CompilationError> {
    log::info!("Parsing sources");
    let mut parsed_programs = vec![];
    for path in paths {
        let program = parse_file(path)?;
        parsed_programs.push(program);
    }

    // We have all modules, determine inter-dependencies
    let sorted_programs = determine_dependecy_order(parsed_programs)?;

    let mut builtin_scope = Scope::new();
    define_builtins(&mut builtin_scope);

    let mut context = Context::new(builtin_scope);
    load_std_module(&mut context.modules_scope);

    log::info!("Type checking");
    let mut typed_programs = vec![];
    for program in sorted_programs {
        log::info!("Checking module: {}", program.name);

        let mut typed_prog = analyze(program, &mut context, options.dump_ast)?;
        if options.dump_ast {
            log::debug!("Dumping typed AST");
            print_ast(&mut typed_prog);
        }

        let typed_prog_ref = Rc::new(typed_prog);
        context.modules_scope.define(
            typed_prog_ref.name.clone(),
            Symbol::Module {
                module_ref: typed_prog_ref.clone(),
            },
        );
        typed_programs.push(typed_prog_ref);
    }

    let bc = ir_gen::gen(&typed_programs);

    if options.dump_bc {
        log::debug!("Dumping bytecode below");
        bytecode::print_bytecode(&bc);
    }

    Ok(bc)
}

pub fn bytecode_to_llvm(bc: bytecode::Program, output_path: Option<&std::path::Path>) {
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
}

/// Determine dependency order of loaded programs.
///
/// This is done using import statements.
/// Detects eventual dependency cycles.
fn determine_dependecy_order(
    parsed_programs: Vec<ast::Program>,
) -> Result<Vec<ast::Program>, CompilationError> {
    let mut dep_graph = petgraph::graphmap::DiGraphMap::new();

    // Sort in topological order!
    for program in &parsed_programs {
        dep_graph.add_node(&program.name);
        for dep in program.deps() {
            dep_graph.add_edge(&program.name, dep, 1);
        }
    }

    let order = match petgraph::algo::toposort(&dep_graph, None) {
        Ok(node_ids) => {
            let mut order: Vec<String> = node_ids.into_iter().map(|n| n.clone()).collect();
            order.reverse();
            order
        }
        Err(cycle) => {
            return Err(CompilationError::simple(format!(
                "Module dependency cycles : {:?}",
                cycle
            )));
        }
    };
    log::info!("Dependency order: {:?}", order);

    // Now sort modules based upon order
    let mut prog_map: HashMap<String, ast::Program> = HashMap::new();
    for program in parsed_programs {
        assert!(!prog_map.contains_key(&program.name));
        prog_map.insert(program.name.clone(), program);
    }

    let mut sorted_programs = vec![];
    for name in order {
        if prog_map.contains_key(&name) {
            let program = prog_map.remove(&name).unwrap();
            sorted_programs.push(program);
        }
    }

    assert!(prog_map.is_empty());

    Ok(sorted_programs)
}
