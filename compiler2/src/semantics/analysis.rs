use super::fillscope::ast_to_nodes;
use super::namebinding::bind_names;
use super::pass2::pass2;
use super::pass3::pass3;
use super::phase5_desugar::desugar;
use super::typechecker::check_types;
use super::Context;
use crate::errors::CompilationError;
use crate::parsing::ast;
use crate::tast;
use crate::tast::print_ast;

/// Check a parsed program for type correctness.
pub fn analyze(
    program: ast::Program,
    context: &mut Context,
    show_ast: bool,
) -> Result<tast::Program, CompilationError> {
    let mut typed_prog = ast_to_nodes(program, context)?;
    if show_ast {
        print_ast(&mut typed_prog);
    }

    bind_names(&mut typed_prog, context.builtin_scope.clone())?;
    log::debug!("Name binding done & done");
    if show_ast {
        print_ast(&mut typed_prog);
    }

    pass2(&mut typed_prog)?;
    pass3(&mut typed_prog)?;

    check_types(&mut typed_prog)?;
    log::debug!("Type checking done & done");
    if show_ast {
        print_ast(&mut typed_prog);
    }

    // Compilation starts here.

    desugar(&mut typed_prog, context);
    if show_ast {
        print_ast(&mut typed_prog);
    }

    // Interesting:
    // We can run the type checker again, on our modified program.
    check_types(&mut typed_prog)?;

    Ok(typed_prog)
}
