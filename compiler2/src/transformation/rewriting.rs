use super::rewriting_classes::rewrite_classes;
use super::rewriting_enums::rewrite_enums;
use super::rewriting_for_loop::rewrite_for_loops;
use super::rewriting_generics::rewrite_generics;

use crate::semantics::{check_types, Context};
use crate::tast::{print_ast, Program};

/// Transform full blown TAST program into TAST program with only basic
/// structures.
pub fn transform(program: &mut Program, context: &mut Context, show_ast: bool) {
    // TBD: what order to rewrite the code?
    rewrite_classes(program, context);
    check_types(program).unwrap();

    if show_ast {
        print_ast(program);
    }

    rewrite_enums(program, context);

    if show_ast {
        print_ast(program);
    }

    check_types(program).unwrap();

    rewrite_for_loops(program, context);

    rewrite_generics(program);

    if show_ast {
        print_ast(program);
    }
    check_types(program).unwrap();
}
