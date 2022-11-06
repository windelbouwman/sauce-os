use super::type_system::SlangType;
use super::typed_ast;
use super::visitor::{visit_program, VisitedNode, VisitorApi};
use super::{Context, NodeId, Ref};
use crate::parsing::ast;
use std::cell::RefCell;
use std::rc::Rc;

pub fn rewrite_for_loops(program: &mut typed_ast::Program, context: &mut Context) {
    log::info!("Rewriting for loops into while loops");
    let mut rewriter = ForLoopRewriter::new(context);
    visit_program(&mut rewriter, program);
    assert!(rewriter.local_variables.is_empty());
}

struct ForLoopRewriter<'d> {
    context: &'d mut Context,
    local_variables: Vec<Rc<RefCell<typed_ast::LocalVariable>>>,
}

impl<'d> ForLoopRewriter<'d> {
    fn new(context: &'d mut Context) -> Self {
        Self {
            context,
            local_variables: vec![],
        }
    }

    fn lower_statement(&mut self, statement: &mut typed_ast::Statement) {
        match &mut statement.kind {
            typed_ast::StatementKind::For(for_statement) => {
                let for_statement = std::mem::take(for_statement);
                statement.kind = self.lower_for_statement(for_statement).kind
            }
            _ => {}
        }
    }

    /// Transform for-loop into a while loop.
    ///
    /// Create an extra variable for the loop index.
    fn lower_for_statement(
        &mut self,
        for_statement: typed_ast::ForStatement,
    ) -> typed_ast::Statement {
        // Check if we loop over an array:
        match for_statement.iterable.typ.clone() {
            SlangType::Array(array_type) => {
                let mut for_body = for_statement.body;
                let index_local_ref = self.new_local_variable("index".to_owned(), SlangType::Int);
                let iter_local_ref = self
                    .new_local_variable("iter".to_owned(), SlangType::Array(array_type.clone()));

                // index = 0
                let zero_loop_index = typed_ast::store_local(index_local_ref.clone(), 0);

                // iter_var = iterator
                let set_iter_var =
                    typed_ast::store_local(iter_local_ref.clone(), for_statement.iterable);

                // Get current element: loop_var = array[index]
                let get_loop_var = typed_ast::store_local(
                    for_statement.loop_var,
                    typed_ast::get_index(
                        typed_ast::load_local(iter_local_ref),
                        typed_ast::load_local(index_local_ref.clone()),
                    ),
                );
                for_body.insert(0, get_loop_var);

                // Increment index variable:
                let inc_loop_index = typed_ast::store_local(
                    index_local_ref.clone(),
                    typed_ast::load_local(index_local_ref.clone()) + 1,
                );
                for_body.push(inc_loop_index);

                // While condition:
                let loop_condition = typed_ast::comparison(
                    typed_ast::load_local(index_local_ref),
                    ast::ComparisonOperator::Lt,
                    typed_ast::integer_literal(array_type.size as i64),
                );

                // Translate for-loop into while loop:
                let while_statement = typed_ast::while_loop(loop_condition, for_body);

                let new_block = vec![zero_loop_index, set_iter_var, while_statement];

                typed_ast::compound(new_block)
            }
            other => {
                unimplemented!("Cannot iterate {:?}", other);
            }
        }
    }

    fn new_local_variable(
        &mut self,
        name: String,
        typ: SlangType,
    ) -> Ref<typed_ast::LocalVariable> {
        let new_var = Rc::new(RefCell::new(typed_ast::LocalVariable::new(
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
                    typed_ast::Definition::Function(function_def) => {
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
