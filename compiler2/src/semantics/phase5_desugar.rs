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

use super::type_system::{SlangType, UserType};
use super::typed_ast;
use super::visitor::{visit_program, VisitedNode, VisitorApi};
use super::{Context, Symbol};
use std::collections::HashMap;

pub fn desugar(program: &mut typed_ast::Program, _context: &mut Context) {
    log::info!("Desugaring");
    let mut desugarizer = Desugar::new();
    visit_program(&mut desugarizer, program);
}

struct Desugar {}

impl Desugar {
    fn new() -> Self {
        Self {}
    }

    fn lower_statement(&mut self, stmt: typed_ast::StatementKind) -> typed_ast::StatementKind {
        match stmt {
            typed_ast::StatementKind::Assignment(assignment) => lower_assignment(assignment),
            typed_ast::StatementKind::Let {
                local_ref,
                type_hint: _,
                value,
            } => typed_ast::StatementKind::StoreLocal { local_ref, value },

            other => other,
        }
    }

    fn lower_expression(&mut self, expression: &mut typed_ast::Expression) {
        match &mut expression.kind {
            typed_ast::ExpressionKind::ObjectInitializer { typ, fields } => {
                let values = struct_literal_to_tuple(typ, std::mem::take(fields));
                expression.kind = typed_ast::ExpressionKind::TupleLiteral(values)
            }
            _ => {}
        }
    }
}

fn lower_assignment(assignment: typed_ast::AssignmentStatement) -> typed_ast::StatementKind {
    match assignment.target.kind {
        typed_ast::ExpressionKind::GetAttr { base, attr } => typed_ast::StatementKind::SetAttr {
            base: *base,
            attr,
            value: assignment.value,
        },

        typed_ast::ExpressionKind::GetIndex { base, index } => typed_ast::StatementKind::SetIndex {
            base,
            index,
            value: assignment.value,
        },

        typed_ast::ExpressionKind::LoadSymbol(symbol) => match symbol {
            Symbol::LocalVariable(local_ref) => typed_ast::StatementKind::StoreLocal {
                local_ref,
                value: assignment.value,
            },
            other => {
                unimplemented!("TODO: {}!", other);
            }
        },
        other => {
            unimplemented!("TODO: {:?}", other);
        }
    }
}

/// Turn a list of field initializers into a struct tuple.
///
/// This means, tuple fields sorted by appearance in the struct
/// definition.
fn struct_literal_to_tuple(
    typ: &SlangType,
    initializers: Vec<typed_ast::LabeledField>,
) -> Vec<typed_ast::Expression> {
    match typ {
        SlangType::User(UserType::Struct(struct_def)) => {
            // First turn named initializers into a name->value mapping:
            let mut value_map: HashMap<String, typed_ast::Expression> = HashMap::new();
            for initializer in initializers {
                assert!(!value_map.contains_key(&initializer.name));
                value_map.insert(initializer.name, *initializer.value);
            }

            // Loop over the struct fields in turn
            let struct_def = struct_def.upgrade().unwrap();
            let mut values = vec![];
            for field in &struct_def.fields {
                values.push(
                    value_map
                        .remove(&field.borrow().name)
                        .expect("Struct initializer must be legit!"),
                );
            }
            values
        }
        other => {
            panic!("Expected struct type, not {:?}", other);
        }
    }
}

impl VisitorApi for Desugar {
    fn pre_node(&mut self, _node: VisitedNode) {}

    fn post_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::Statement(statement) => {
                let kind = std::mem::replace(&mut statement.kind, typed_ast::StatementKind::Pass);
                statement.kind = self.lower_statement(kind);
            }
            VisitedNode::Expression(expression) => {
                self.lower_expression(expression);
            }
            _ => {}
        }
    }
}
