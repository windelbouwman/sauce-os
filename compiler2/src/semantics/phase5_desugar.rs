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
use crate::tast::{AssignmentStatement, Expression, ExpressionKind, LabeledField, StatementKind};
use crate::tast::{Program, SlangType, Symbol};
use std::collections::HashMap;

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

    fn lower_expression(&mut self, expression: &mut Expression) {
        match &mut expression.kind {
            ExpressionKind::ObjectInitializer { typ, fields } => {
                let values = struct_literal_to_tuple(typ, std::mem::take(fields));
                expression.kind = ExpressionKind::TupleLiteral(values)
            }
            _ => {}
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

/// Turn a list of field initializers into a struct tuple.
///
/// This means, tuple fields sorted by appearance in the struct
/// definition.
fn struct_literal_to_tuple(typ: &SlangType, initializers: Vec<LabeledField>) -> Vec<Expression> {
    // First turn named initializers into a name->value mapping:
    let mut value_map: HashMap<String, Expression> = HashMap::new();
    for initializer in initializers {
        assert!(!value_map.contains_key(&initializer.name));
        value_map.insert(initializer.name, *initializer.value);
    }

    // We can assume we checked for struct-ness
    let fields = typ.as_struct().get_struct_fields();

    let mut values = vec![];
    for (name, _typ) in fields {
        values.push(
            value_map
                .remove(&name)
                .expect("Struct initializer must be legit!"),
        );
    }
    values
}

impl VisitorApi for Desugar {
    fn pre_node(&mut self, _node: VisitedNode) {}

    fn post_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::Statement(statement) => {
                let kind = std::mem::replace(&mut statement.kind, StatementKind::Pass);
                statement.kind = self.lower_statement(kind);
            }
            VisitedNode::Expression(expression) => {
                self.lower_expression(expression);
            }
            _ => {}
        }
    }
}
