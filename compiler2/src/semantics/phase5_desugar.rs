use super::type_system::{SlangType, UserType};
use super::typed_ast;
use super::visitor::{visit_program, VisitedNode, VisitorApi};
use super::{Context, NodeId, Ref, Symbol};
use crate::parsing::ast;
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

pub fn desugar(program: &mut typed_ast::Program, context: &mut Context) {
    log::info!("Desugaring");
    let mut desugarizer = Desugar::new(context);
    visit_program(&mut desugarizer, program);
}

struct Desugar<'d> {
    context: &'d mut Context,
    local_variables: Vec<Rc<RefCell<typed_ast::LocalVariable>>>,
    new_definitions: Vec<typed_ast::Definition>,

    /// Mapping from enum types to tagged-union types!
    enum_map: HashMap<NodeId, SlangType>,
}

impl<'d> Desugar<'d> {
    fn new(context: &'d mut Context) -> Self {
        Self {
            context,
            local_variables: vec![],
            new_definitions: vec![],
            enum_map: HashMap::new(),
        }
    }

    fn lower_stmt(&mut self, stmt: typed_ast::StatementKind) -> typed_ast::StatementKind {
        match stmt {
            typed_ast::StatementKind::Assignment(assignment) => lower_assignment(assignment),
            typed_ast::StatementKind::Let {
                local_ref,
                type_hint: _,
                value,
            } => typed_ast::StatementKind::StoreLocal { local_ref, value },
            typed_ast::StatementKind::For(for_statement) => {
                self.lower_for_statement(for_statement).kind
            }

            typed_ast::StatementKind::Case(case_statement) => {
                self.lower_case_statement(case_statement)
            }
            other => other,
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

    /// Contrapt new types for the given enum type.
    ///
    /// For example, translate this:
    ///
    ///     enum Option:
    ///         Money(int, float)
    ///         Text(str)
    ///         None
    ///
    /// Into:
    ///
    ///     struct OptionMoneyData:
    ///         f_0: int
    ///         f_1: float
    ///
    ///     union OptionData:
    ///         money: OptionMoneyData
    ///         text: str
    ///
    ///     struct Option:
    ///         tag: int
    ///         data: OptionData
    ///
    fn contrapt_tagged_union(&mut self, enum_def: Rc<typed_ast::EnumDef>) {
        let union_name = format!("{}Data", enum_def.name);
        let mut union_builder = typed_ast::StructDefBuilder::new(union_name, self.new_id());

        // let union_builder
        for variant in &enum_def.variants {
            let variant = variant.borrow();
            let union_field_name = format!("{}", variant.name);

            if variant.data.is_empty() {
                // no payload fields required!
            } else if variant.data.len() == 1 {
                // Single field!
                let variant_typ = variant.data[0].clone();
                union_builder.add_field(&union_field_name, variant_typ);
            } else {
                // multi-payload field, create sub struct!
                let multi_field_enum_struct_name =
                    format!("{}{}Data", enum_def.name.clone(), variant.name);
                let mut struct_builder2 =
                    typed_ast::StructDefBuilder::new(multi_field_enum_struct_name, self.new_id());
                for (index, payload_typ) in variant.data.iter().enumerate() {
                    let payload_name = format!("f_{}", index);
                    struct_builder2.add_field(&payload_name, payload_typ.clone());
                }

                let variant_typ = self.define_struct(struct_builder2.finish_struct());
                union_builder.add_field(&union_field_name, variant_typ);
            }
        }

        let union_def = Rc::new(union_builder.finish_union());
        let union_typ = SlangType::User(UserType::Union(Rc::downgrade(&union_def)));
        self.new_definitions
            .push(typed_ast::Definition::Union(union_def));

        // Create tagged union struct:
        let mut struct_builder =
            typed_ast::StructDefBuilder::new(enum_def.name.clone(), self.new_id());
        struct_builder.add_field("tag", SlangType::Int);
        struct_builder.add_field("data", union_typ);
        let tagged_union_typ = self.define_struct(struct_builder.finish_struct());

        // register tagged union for later usage!
        self.enum_map.insert(enum_def.id, tagged_union_typ);

        // ?
    }

    // fn define_union() -> a {
    fn define_struct(&mut self, struct_def: typed_ast::StructDef) -> SlangType {
        let struct_def = Rc::new(struct_def);
        let typ = SlangType::User(UserType::Struct(Rc::downgrade(&struct_def)));
        self.new_definitions
            .push(typed_ast::Definition::Struct(struct_def));
        typ
    }

    /// Transform case statement into switch statement, using a tagged union.
    fn lower_case_statement(
        &mut self,
        mut case_statement: typed_ast::CaseStatement,
    ) -> typed_ast::StatementKind {
        // Load tagged union discriminating tag
        let enum_type = case_statement.value.typ.as_enum();
        let tagged_union_type = self
            .enum_map
            .get(&enum_type.id)
            .expect("Enum is translated")
            .clone();
        let tagged_union_ref =
            self.new_local_variable("tagged_union".to_owned(), tagged_union_type);

        // Store tagged value for later usage
        let prelude = typed_ast::store_local(tagged_union_ref.clone(), case_statement.value);

        // Retrieve tag from tagged value:
        let tag_value = typed_ast::load_local(tagged_union_ref.clone()).get_attr("tag");

        let mut switch_arms = vec![];
        for arm in case_statement.arms.iter_mut() {
            let variant = arm.get_variant();

            // This arm tag:
            let arm_value = typed_ast::integer_literal(variant.borrow().index as i64);
            let payload_name = variant.borrow().name.clone();

            let mut body: typed_ast::Block = vec![];

            // Unpack variant data into local variables:
            if arm.local_refs.is_empty() {
                // Nothing to unpack
            } else if arm.local_refs.len() == 1 {
                // single value to unpack!
                let variant_value = typed_ast::load_local(tagged_union_ref.clone())
                    .get_attr("data")
                    .get_attr(&payload_name);
                let local_ref = arm.local_refs[0].clone();

                body.push(typed_ast::store_local(local_ref, variant_value));
            } else {
                for (index, local_ref) in arm.local_refs.iter().enumerate() {
                    let field_name = format!("f_{}", index);
                    let variant_value = typed_ast::load_local(tagged_union_ref.clone())
                        .get_attr("data")
                        .get_attr(&payload_name)
                        .get_attr(&field_name);
                    body.push(typed_ast::store_local(local_ref.clone(), variant_value));
                }
            }

            body.append(&mut arm.body);

            switch_arms.push(typed_ast::SwitchArm {
                value: arm_value,
                body,
            });
        }

        // Default case, could be an error case?
        let default_block = vec![typed_ast::unreachable_code()];

        typed_ast::compound(vec![
            prelude,
            typed_ast::StatementKind::Switch(typed_ast::SwitchStatement {
                value: tag_value,
                arms: switch_arms,
                default: default_block,
            })
            .into_statement(),
        ])
        .kind
    }

    fn lower_expression(&mut self, expression: &mut typed_ast::Expression) {
        match &mut expression.kind {
            typed_ast::ExpressionKind::StructLiteral { typ, fields } => {
                let values = struct_literal_to_tuple(typ, std::mem::take(fields));
                expression.kind = typed_ast::ExpressionKind::TupleLiteral(values)
            }
            typed_ast::ExpressionKind::EnumLiteral(enum_literal) => {
                let variant_ref = enum_literal.variant.upgrade().unwrap();
                let variant = variant_ref.borrow();

                let tagged_union_typ = self
                    .enum_map
                    .get(&variant.parent.upgrade().unwrap().id)
                    .unwrap()
                    .clone();

                let data_union_type = tagged_union_typ
                    .as_struct()
                    .get_field("data")
                    .unwrap()
                    .borrow()
                    .typ
                    .clone();

                let payload = std::mem::take(&mut enum_literal.arguments);

                // Marker value to indicate variant choice:
                let tag_value = typed_ast::integer_literal(variant.index as i64);

                let payload_name = variant.name.to_owned();

                let union_value = if payload.is_empty() {
                    // No payload
                    typed_ast::undefined_value()
                } else if payload.len() == 1 {
                    // Single payload value
                    let value = payload.into_iter().next().unwrap();

                    typed_ast::union_literal(data_union_type, payload_name, value)
                } else {
                    // multi payload value
                    let payload_struct_type = data_union_type
                        .as_union()
                        .get_field(&payload_name)
                        .unwrap()
                        .borrow()
                        .typ
                        .clone();

                    let struct_value = typed_ast::tuple_literal(payload_struct_type, payload);
                    typed_ast::union_literal(data_union_type, payload_name, struct_value)
                };

                let tagged_union = vec![tag_value, union_value];
                expression.kind = typed_ast::ExpressionKind::TupleLiteral(tagged_union);
                expression.typ = tagged_union_typ;
            }
            _ => {}
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
            name.clone(),
            self.new_id(),
        )));
        new_var.borrow_mut().typ = typ;
        let local_ref = Rc::downgrade(&new_var);

        self.local_variables.push(new_var.clone());
        local_ref
    }

    /// Create a new unique ID
    fn new_id(&mut self) -> NodeId {
        self.context.id_generator.gimme()
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
            Symbol::LocalVariable { local_ref } => typed_ast::StatementKind::StoreLocal {
                local_ref,
                value: assignment.value,
            },
            other => {
                unimplemented!("TODO: {:?}!", other);
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
    initializers: Vec<typed_ast::FieldInit>,
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

impl<'d> VisitorApi for Desugar<'d> {
    fn pre_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::Program(program) => {
                for definition in &program.definitions {
                    match definition {
                        typed_ast::Definition::Enum(enum_def) => {
                            self.contrapt_tagged_union(enum_def.clone());
                        }
                        _ => {}
                    }
                }
                program.definitions.append(&mut self.new_definitions);
            }
            VisitedNode::TypeExpr(type_expr) => {
                if type_expr.is_enum() {
                    let tagged_union = self.enum_map.get(&type_expr.as_enum().id).unwrap().clone();
                    *type_expr = tagged_union;
                }

                // Replace enums by tagged unions!
            }
            _ => {}
        }
    }

    fn post_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::Program(_) | VisitedNode::TypeExpr(_) => {}
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
                let kind = std::mem::replace(&mut statement.kind, typed_ast::StatementKind::Pass);
                statement.kind = self.lower_stmt(kind);
            }
            VisitedNode::CaseArm(_) => {}
            VisitedNode::Expression(expression) => {
                self.lower_expression(expression);
            }
        }
    }
}
