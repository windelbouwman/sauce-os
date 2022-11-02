use super::fillscope;
use super::namebinding;
use super::phase5_desugar;
use super::rewriting_classes::rewrite_classes;
use super::rewriting_enums::rewrite_enums;
use super::rewriting_for_loop::rewrite_for_loops;
use super::typechecker::check_types;
use super::typed_ast;
use super::typed_ast_printer::print_ast;
use super::Context;
use crate::errors::CompilationError;
use crate::parsing::ast;

/// Check a parsed program for type correctness.
pub fn analyze(
    program: ast::Program,
    context: &mut Context,
    show_ast: bool,
) -> Result<typed_ast::Program, CompilationError> {
    let mut typed_prog = fillscope::ast_to_nodes(program, context)?;
    if show_ast {
        print_ast(&mut typed_prog);
    }

    namebinding::bind_names(&mut typed_prog, context.builtin_scope.clone())?;
    log::debug!("Name binding done & done");
    if show_ast {
        print_ast(&mut typed_prog);
    }

    check_types(&mut typed_prog)?;
    log::debug!("Type checking done & done");
    if show_ast {
        print_ast(&mut typed_prog);
    }

    phase5_desugar::desugar(&mut typed_prog, context);
    if show_ast {
        print_ast(&mut typed_prog);
    }

    // TBD: what order to rewrite the code?
    rewrite_classes(&mut typed_prog, context);
    check_types(&mut typed_prog)?;

    if show_ast {
        print_ast(&mut typed_prog);
    }

    rewrite_enums(&mut typed_prog, context);
    check_types(&mut typed_prog)?;

    if show_ast {
        print_ast(&mut typed_prog);
    }

    rewrite_for_loops(&mut typed_prog, context);

    // Interesting:
    // We can run the type checker again, on our modified program.
    check_types(&mut typed_prog)?;

    Ok(typed_prog)
}
