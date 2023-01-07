use super::tast::{
    comparison, compound, get_index, integer_literal, load_local, store_local, while_loop,
};
use super::tast::{Definition, LocalVariable, Program, SlangType};
use super::tast::{ForStatement, Statement, StatementKind};
use super::tast::{NodeId, Ref};
use super::visitor::{visit_program, VisitedNode, VisitorApi};
use super::Context;
use crate::parsing::ast;
use std::cell::RefCell;
use std::rc::Rc;

pub fn rewrite_for_loops(program: &mut Program, context: &mut Context) {
    log::info!("Rewriting for loops into while loops");
    let mut rewriter = ForLoopRewriter::new(context);
    visit_program(&mut rewriter, program);
    assert!(rewriter.local_variables.is_empty());
}

struct ForLoopRewriter<'d> {
    context: &'d mut Context,
    local_variables: Vec<Rc<RefCell<LocalVariable>>>,
}

impl<'d> ForLoopRewriter<'d> {
    fn new(context: &'d mut Context) -> Self {
        Self {
            context,
            local_variables: vec![],
        }
    }

    fn lower_statement(&mut self, statement: &mut Statement) {
        match &mut statement.kind {
            StatementKind::For(for_statement) => {
                let for_statement = std::mem::take(for_statement);
                statement.kind = self.lower_for_statement(for_statement).kind
            }
            _ => {}
        }
    }

    /// Transform for-loop into a while loop.
    ///
    /// Create an extra variable for the loop index.
    fn lower_for_statement(&mut self, for_statement: ForStatement) -> Statement {
        // Check if we loop over an array:
        match for_statement.iterable.typ.clone() {
            SlangType::Array(array_type) => {
                let mut for_body = for_statement.body;
                let index_local_ref = self.new_local_variable("index".to_owned(), SlangType::int());
                let iter_local_ref = self
                    .new_local_variable("iter".to_owned(), SlangType::Array(array_type.clone()));

                // index = 0
                let zero_loop_index = store_local(index_local_ref.clone(), 0);

                // iter_var = iterator
                let set_iter_var = store_local(iter_local_ref.clone(), for_statement.iterable);

                // Get current element: loop_var = array[index]
                let get_loop_var = store_local(
                    for_statement.loop_var,
                    get_index(
                        load_local(iter_local_ref),
                        load_local(index_local_ref.clone()),
                    ),
                );
                for_body.insert(0, get_loop_var);

                // Increment index variable:
                let inc_loop_index = store_local(
                    index_local_ref.clone(),
                    load_local(index_local_ref.clone()) + 1,
                );
                for_body.push(inc_loop_index);

                // While condition:
                let loop_condition = comparison(
                    load_local(index_local_ref),
                    ast::ComparisonOperator::Lt,
                    integer_literal(array_type.size as i64),
                );

                // Translate for-loop into while loop:
                let while_statement = while_loop(loop_condition, for_body);

                let new_block = vec![zero_loop_index, set_iter_var, while_statement];

                compound(new_block)
            }
            other => {
                unimplemented!("Cannot iterate {:?}", other);
            }
        }
    }

    fn new_local_variable(&mut self, name: String, typ: SlangType) -> Ref<LocalVariable> {
        let new_var = Rc::new(RefCell::new(LocalVariable::new(
            Default::default(),
            false,
            name,
            self.new_id(),
        )));
        new_var.borrow_mut().typ = typ;
        let local_ref = Rc::downgrade(&new_var);

        self.local_variables.push(new_var);
        local_ref
    }

    /// Create a new unique ID
    fn new_id(&mut self) -> NodeId {
        self.context.id_generator.gimme()
    }
}

impl<'d> VisitorApi for ForLoopRewriter<'d> {
    fn pre_node(&mut self, _node: VisitedNode) {}

    fn post_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::Definition(definition) => {
                match definition {
                    Definition::Function(function_def) => {
                        if !self.local_variables.is_empty() {
                            // Append newly created local variables:
                            function_def
                                .borrow_mut()
                                .locals
                                .append(&mut self.local_variables);
                        }
                    }
                    _other => {}
                }
            }
            VisitedNode::Statement(statement) => {
                self.lower_statement(statement);
            }
            _ => {}
        }
    }
}
