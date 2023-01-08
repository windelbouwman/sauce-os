//! Transform enums into tagged unions
//!
//! For example, translate this:
//!
//!     enum Option:
//!         Money(int, float)
//!         Text(str)
//!         None
//!
//! Into:
//!
//!     struct OptionMoneyData:
//!         f_0: int
//!         f_1: float
//!
//!     union OptionData:
//!         money: OptionMoneyData
//!         text: str
//!
//!     struct Option:
//!         tag: int
//!         data: OptionData
//!

use crate::semantics::Context;
use crate::tast::{
    compound, integer_literal, load_local, store_local, tuple_literal, union_literal,
    unreachable_code,
};
use crate::tast::{visit_program, VisitedNode, VisitorApi};
use crate::tast::{Block, Expression, ExpressionKind, Statement, StatementKind};
use crate::tast::{CaseStatement, SwitchArm, SwitchStatement};
use crate::tast::{Definition, EnumDef, LocalVariable, Program, StructDef, StructDefBuilder};
use crate::tast::{NodeId, Ref, SlangType};
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

pub fn rewrite_enums(program: &mut Program, context: &mut Context) {
    log::info!("Rewriting enums into tagged unions");
    let mut rewriter = EnumRewriter::new(context);
    visit_program(&mut rewriter, program);
}

struct EnumRewriter<'d> {
    context: &'d mut Context,
    local_variables: Vec<Rc<RefCell<LocalVariable>>>,
    new_definitions: Vec<Definition>,

    /// Mapping from enum types to tagged-union types!
    enum_map: HashMap<NodeId, SlangType>,
}

impl<'d> EnumRewriter<'d> {
    fn new(context: &'d mut Context) -> Self {
        Self {
            context,
            local_variables: vec![],
            new_definitions: vec![],
            enum_map: HashMap::new(),
        }
    }

    fn lower_statement(&mut self, statement: &mut Statement) {
        match &mut statement.kind {
            StatementKind::Case(case_statement) => {
                let case_statement = std::mem::take(case_statement);

                statement.kind = self.lower_case_statement(case_statement)
            }
            _ => {}
        }
    }

    /// Contrapt new types for the given enum type.
    ///
    fn contrapt_tagged_union(&mut self, enum_def: Rc<EnumDef>) {
        let union_name = format!("{}Data", enum_def.name.name);
        let mut union_builder = StructDefBuilder::new(union_name, self.new_id());

        // let union_builder
        for variant in &enum_def.variants {
            let variant = variant.borrow();
            let union_field_name = format!("{}", variant.name);

            if variant.data.is_empty() {
                // no payload fields required!
                // Add a place holder int as stub ..
                union_builder.add_field(&union_field_name, SlangType::int());
            } else if variant.data.len() == 1 {
                // Single field!
                let variant_typ = variant.data[0].clone();
                union_builder.add_field(&union_field_name, variant_typ);
            } else {
                // multi-payload field, create sub struct!
                let multi_field_enum_struct_name =
                    format!("{}{}Data", enum_def.name.name.clone(), variant.name);
                let mut struct_builder2 =
                    StructDefBuilder::new(multi_field_enum_struct_name, self.new_id());
                for (index, payload_typ) in variant.data.iter().enumerate() {
                    let payload_name = format!("f_{}", index);
                    struct_builder2.add_field(&payload_name, payload_typ.clone());
                }

                let variant_typ = self.define_struct(struct_builder2.finish_struct());
                union_builder.add_field(&union_field_name, variant_typ);
            }
        }

        let union_def = Definition::Union(Rc::new(union_builder.finish_union()));
        let union_typ = union_def.create_type(vec![]);
        self.new_definitions.push(union_def);

        // Create tagged union struct:
        let mut struct_builder = StructDefBuilder::new(enum_def.name.name.clone(), self.new_id());
        struct_builder.add_field("tag", SlangType::int());
        struct_builder.add_field("data", union_typ);
        let tagged_union_typ = self.define_struct(struct_builder.finish_struct());

        // register tagged union for later usage!
        self.enum_map.insert(enum_def.name.id, tagged_union_typ);

        // ?
    }

    // fn define_union() -> a {
    fn define_struct(&mut self, struct_def: StructDef) -> SlangType {
        let struct_def = struct_def.into_def();
        let typ = struct_def.create_type(vec![]);
        self.new_definitions.push(struct_def);
        typ
    }

    /// Transform case statement into switch statement, using a tagged union.
    fn lower_case_statement(&mut self, mut case_statement: CaseStatement) -> StatementKind {
        // Load tagged union discriminating tag
        let enum_type = case_statement.value.typ.as_enum();
        let tagged_union_type = self
            .enum_map
            .get(&enum_type.enum_ref.upgrade().unwrap().name.id)
            .expect("Enum is translated")
            .clone();
        let tagged_union_ref =
            self.new_local_variable("tagged_union".to_owned(), tagged_union_type);

        // Store tagged value for later usage
        let prelude = store_local(tagged_union_ref.clone(), case_statement.value);

        // Retrieve tag from tagged value:
        let tag_value = load_local(tagged_union_ref.clone()).get_attr("tag");

        let mut switch_arms = vec![];
        for arm in case_statement.arms.iter_mut() {
            let variant = arm.get_variant();

            // This arm tag:
            let arm_value = integer_literal(variant.borrow().index as i64);
            let payload_name = variant.borrow().name.clone();

            let mut body: Block = vec![];

            // Unpack variant data into local variables:
            if arm.local_refs.is_empty() {
                // Nothing to unpack
            } else if arm.local_refs.len() == 1 {
                // single value to unpack!
                let variant_value = load_local(tagged_union_ref.clone())
                    .get_attr("data")
                    .get_attr(&payload_name);
                let local_ref = arm.local_refs[0].clone();

                body.push(store_local(local_ref, variant_value));
            } else {
                for (index, local_ref) in arm.local_refs.iter().enumerate() {
                    let field_name = format!("f_{}", index);
                    let variant_value = load_local(tagged_union_ref.clone())
                        .get_attr("data")
                        .get_attr(&payload_name)
                        .get_attr(&field_name);
                    body.push(store_local(local_ref.clone(), variant_value));
                }
            }

            body.append(&mut arm.body);

            switch_arms.push(SwitchArm {
                value: arm_value,
                body,
            });
        }

        // Default case, could be an error case?
        let default_block = vec![unreachable_code()];

        compound(vec![
            prelude,
            StatementKind::Switch(SwitchStatement {
                value: tag_value,
                arms: switch_arms,
                default: default_block,
            })
            .into_statement(),
        ])
        .kind
    }

    fn lower_expression(&mut self, expression: &mut Expression) {
        match &mut expression.kind {
            ExpressionKind::EnumLiteral(enum_literal) => {
                let variant_ref = enum_literal.variant.upgrade().unwrap();
                let variant = variant_ref.borrow();

                let tagged_union_typ = self
                    .enum_map
                    .get(&variant.parent.upgrade().unwrap().name.id)
                    .unwrap()
                    .clone();

                let data_union_type = tagged_union_typ.as_struct().get_attr_type("data").unwrap();

                let payload = std::mem::take(&mut enum_literal.arguments);

                // Marker value to indicate variant choice:
                let tag_value = integer_literal(variant.index as i64);

                let payload_name = variant.name.to_owned();

                let value = if payload.is_empty() {
                    // No payload (store int as dummy value)
                    integer_literal(0)
                } else if payload.len() == 1 {
                    // Single payload value
                    payload.into_iter().next().unwrap()
                } else {
                    // multi payload value
                    let payload_struct_type = data_union_type
                        .as_union()
                        .get_attr_type(&payload_name)
                        .unwrap();

                    tuple_literal(payload_struct_type, payload)
                };
                let union_value = union_literal(data_union_type, payload_name, value);

                let tagged_union = vec![tag_value, union_value];
                expression.kind = ExpressionKind::TupleLiteral {
                    typ: tagged_union_typ,
                    values: tagged_union,
                };
            }
            _ => {}
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

impl<'d> VisitorApi for EnumRewriter<'d> {
    fn pre_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::Program(program) => {
                for definition in &program.definitions {
                    match definition {
                        Definition::Enum(enum_def) => {
                            self.contrapt_tagged_union(enum_def.clone());
                        }
                        _ => {}
                    }
                }
                program.definitions.append(&mut self.new_definitions);
            }
            VisitedNode::TypeExpr(type_expr) => {
                if type_expr.is_enum() {
                    let enum_type = type_expr.as_enum();
                    let tagged_union = self
                        .enum_map
                        .get(&enum_type.enum_ref.upgrade().unwrap().name.id)
                        .unwrap()
                        .clone();
                    *type_expr = tagged_union;
                }

                // Replace enums by tagged unions!
            }
            _ => {}
        }
    }

    fn post_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::Program(program) => {
                // remove enum's from definitions:
                program
                    .definitions
                    .retain(|d| !matches!(d, Definition::Enum(_)));
            }
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
            VisitedNode::Expression(expression) => {
                self.lower_expression(expression);
            }
            _ => {}
        }
    }
}
