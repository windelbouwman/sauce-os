/*
Desugar phase

Significant program rewriting happens here.

For example:

- enum types are rewritten into tagged unions, this involves:
    - enum variables become tagged union variables
    - enum literals become struct literals
    - case statements become switch statements
- for loops are translated into while loops.

*/

use super::Context;
use crate::tast::{visit_program, VisitedNode, VisitorApi};
use crate::tast::{AssignmentStatement, ExpressionKind, StatementKind};
use crate::tast::{Program, Symbol};

pub fn desugar(program: &mut Program, _context: &mut Context) {
    log::info!("Desugaring");
    let mut desugarizer = Desugar::new();
    visit_program(&mut desugarizer, program);
}

struct Desugar {}

impl Desugar {
    fn new() -> Self {
        Self {}
    }

    fn lower_statement(&mut self, stmt: StatementKind) -> StatementKind {
        match stmt {
            StatementKind::Assignment(assignment) => lower_assignment(assignment),
            StatementKind::Let {
                local_ref,
                type_hint: _,
                value,
            } => StatementKind::StoreLocal { local_ref, value },

            other => other,
        }
    }
}

fn lower_assignment(assignment: AssignmentStatement) -> StatementKind {
    match assignment.target.kind {
        ExpressionKind::GetAttr { base, attr } => StatementKind::SetAttr {
            base: *base,
            attr,
            value: assignment.value,
        },

        ExpressionKind::GetIndex { base, index } => StatementKind::SetIndex {
            base,
            index,
            value: assignment.value,
        },

        ExpressionKind::LoadSymbol(symbol) => match symbol {
            Symbol::LocalVariable(local_ref) => StatementKind::StoreLocal {
                local_ref,
                value: assignment.value,
            },
            other => {
                unimplemented!("TODO: {}!", other);
            }
        },
        _other => {
            unimplemented!("TODO");
        }
    }
}

impl VisitorApi for Desugar {
    fn pre_node(&mut self, _node: VisitedNode) {}

    fn post_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::Statement(statement) => {
                let kind = std::mem::replace(&mut statement.kind, StatementKind::Pass);
                statement.kind = self.lower_statement(kind);
            }
            _ => {}
        }
    }
}
