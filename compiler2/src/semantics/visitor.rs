//! Visitor logic
//!
//! This logic can visit a whole typed ast.

use super::tast::{
    CaseArm, CaseStatement, EnumLiteral, IfStatement, SwitchStatement, WhileStatement,
};
use super::tast::{Definition, FieldDef, FunctionDef, FunctionSignature, Program};
use super::tast::{Expression, ExpressionKind, Statement, StatementKind};
use super::tast::{SlangType, UserType};
use std::cell::RefCell;
use std::rc::Rc;

pub enum VisitedNode<'n> {
    Program(&'n mut Program),
    Definition(&'n Definition),
    Function(&'n FunctionDef),
    Statement(&'n mut Statement),
    CaseArm(&'n mut CaseArm),
    Expression(&'n mut Expression),
    TypeExpr(&'n mut SlangType),
}

pub trait VisitorApi {
    fn pre_node(&mut self, node: VisitedNode);
    fn post_node(&mut self, node: VisitedNode);
}

pub fn visit_program<V: VisitorApi>(visitor: &mut V, program: &mut Program) {
    visitor.pre_node(VisitedNode::Program(program));

    for definition in &program.definitions {
        visit_definition(visitor, definition);
    }
    visitor.post_node(VisitedNode::Program(program));
}

fn visit_definition<V: VisitorApi>(visitor: &mut V, definition: &Definition) {
    visitor.pre_node(VisitedNode::Definition(definition));
    match definition {
        Definition::Function(function) => {
            visit_function(visitor, function);
        }
        Definition::Class(class_def) => {
            for field in &class_def.fields {
                visit_field(visitor, field);
            }

            for method in &class_def.methods {
                visitor.pre_node(VisitedNode::Function(&method.borrow()));
                visit_function(visitor, method);
                visitor.post_node(VisitedNode::Function(&method.borrow()));
            }
        }
        Definition::Struct(struct_def) => {
            for field_def in &struct_def.fields {
                visit_field(visitor, field_def);
            }
        }
        Definition::Union(union_def) => {
            for field_def in &union_def.fields {
                visit_field(visitor, field_def);
            }
        }
        Definition::Enum(enum_def) => {
            for enum_variant in &enum_def.variants {
                for payload_type in &mut enum_variant.borrow_mut().data {
                    visit_type_expr(visitor, payload_type);
                }
            }
        }
    }
    visitor.post_node(VisitedNode::Definition(definition));
}

fn visit_field<V: VisitorApi>(visitor: &mut V, field_def: &Rc<RefCell<FieldDef>>) {
    visit_type_expr(visitor, &mut field_def.borrow_mut().typ);

    // assert!(field_def.borrow().value.is_none());
    if let Some(value) = &mut field_def.borrow_mut().value {
        visit_expr(visitor, value);
    }
}

fn visit_signature<V: VisitorApi>(visitor: &mut V, signature: &mut FunctionSignature) {
    for parameter in &signature.parameters {
        visit_type_expr(visitor, &mut parameter.borrow_mut().typ);
    }

    if let Some(ret_type) = &mut signature.return_type {
        visit_type_expr(visitor, ret_type);
    }
}

fn visit_function<V: VisitorApi>(visitor: &mut V, function: &Rc<RefCell<FunctionDef>>) {
    visit_signature(visitor, &mut function.borrow().signature.borrow_mut());

    for local in &function.borrow().locals {
        visit_type_expr(visitor, &mut local.borrow_mut().typ);
    }

    visit_block(visitor, &mut function.borrow_mut().body);
}

fn visit_type_expr<V: VisitorApi>(visitor: &mut V, type_expr: &mut SlangType) {
    visitor.pre_node(VisitedNode::TypeExpr(type_expr));
    match type_expr {
        SlangType::User(user_type) => match user_type {
            UserType::Struct(struct_type) => {
                for type_argument in &mut struct_type.type_arguments {
                    visit_type_expr(visitor, type_argument);
                }
            }
            UserType::Enum(enum_type) => {
                for type_argument in &mut enum_type.type_arguments {
                    visit_type_expr(visitor, type_argument);
                }
            }
            UserType::Function(signature) => {
                let mut signature = signature.borrow_mut();
                for parameter in &signature.parameters {
                    let mut parameter = parameter.borrow_mut();
                    visit_type_expr(visitor, &mut parameter.typ);
                }
                if let Some(t) = &mut signature.return_type {
                    visit_type_expr(visitor, t);
                }
            }
            // TODO: visit other types?
            _ => {}
        },
        SlangType::Unresolved(type_expr) => visit_expr(visitor, &mut type_expr.expr),
        _ => {}
    }
    visitor.post_node(VisitedNode::TypeExpr(type_expr));
}

fn visit_block<V: VisitorApi>(visitor: &mut V, block: &mut [Statement]) {
    for statement in block {
        visit_statement(visitor, statement);
    }
}

fn visit_statement<V: VisitorApi>(visitor: &mut V, statement: &mut Statement) {
    visitor.pre_node(VisitedNode::Statement(statement));

    match &mut statement.kind {
        StatementKind::Break => {}
        StatementKind::Continue => {}
        StatementKind::Pass => {}
        StatementKind::Unreachable => {}
        StatementKind::Return { value } => {
            if let Some(value) = value {
                visit_expr(visitor, value);
            }
        }
        StatementKind::If(IfStatement {
            condition,
            if_true,
            if_false,
        }) => {
            visit_expr(visitor, condition);
            visit_block(visitor, if_true);
            if let Some(if_false) = if_false {
                visit_block(visitor, if_false);
            }
        }
        StatementKind::While(WhileStatement { condition, body }) => {
            visit_expr(visitor, condition);
            visit_block(visitor, body);
        }
        StatementKind::Loop { body } => {
            visit_block(visitor, body);
        }
        StatementKind::Compound(block) => {
            visit_block(visitor, block);
        }
        StatementKind::For(for_statement) => {
            visit_expr(visitor, &mut for_statement.iterable);
            visit_block(visitor, &mut for_statement.body);
        }
        StatementKind::Let {
            local_ref: _,
            type_hint,
            value,
        } => {
            if let Some(type_hint) = type_hint {
                visit_type_expr(visitor, type_hint)
            }

            visit_expr(visitor, value);
        }
        StatementKind::Assignment(assignment) => {
            visit_expr(visitor, &mut assignment.target);
            visit_expr(visitor, &mut assignment.value);
        }
        StatementKind::StoreLocal {
            local_ref: _,
            value,
        } => {
            visit_expr(visitor, value);
        }

        StatementKind::SetAttr {
            base,
            attr: _,
            value,
        } => {
            visit_expr(visitor, base);
            visit_expr(visitor, value);
        }

        StatementKind::SetIndex { base, index, value } => {
            visit_expr(visitor, base);
            visit_expr(visitor, index);
            visit_expr(visitor, value);
        }
        StatementKind::Case(CaseStatement { value, arms }) => {
            visit_expr(visitor, value);
            for arm in arms {
                visitor.pre_node(VisitedNode::CaseArm(arm));
                // visit_expr(visitor, &mut arm.constructor);
                visit_block(visitor, &mut arm.body);
                visitor.post_node(VisitedNode::CaseArm(arm));
            }
        }
        StatementKind::Switch(SwitchStatement {
            value,
            arms,
            default,
        }) => {
            visit_expr(visitor, value);
            for arm in arms {
                visit_expr(visitor, &mut arm.value);
                visit_block(visitor, &mut arm.body);
            }
            visit_block(visitor, default);
        }
        StatementKind::Expression(expression) => {
            visit_expr(visitor, expression);
        }
    }

    visitor.post_node(VisitedNode::Statement(statement));
}

fn visit_expr<V: VisitorApi>(visitor: &mut V, expression: &mut Expression) {
    visitor.pre_node(VisitedNode::Expression(expression));

    match &mut expression.kind {
        ExpressionKind::Undefined => {}
        ExpressionKind::Object(_) => {}
        ExpressionKind::Call { callee, arguments } => {
            visit_expr(visitor, callee);
            for argument in arguments {
                visit_expr(visitor, argument);
            }
        }
        ExpressionKind::Binop { lhs, op: _, rhs } => {
            visit_expr(visitor, lhs);
            visit_expr(visitor, rhs);
        }
        ExpressionKind::TypeCast { value, to_type: _ } => {
            // TBD: visit to_type?
            visit_expr(visitor, value);
        }
        ExpressionKind::Literal(_) => {}
        ExpressionKind::ObjectInitializer { typ, fields } => {
            visit_type_expr(visitor, typ);
            for field in fields {
                visit_expr(visitor, &mut field.value);
            }
        }
        ExpressionKind::TupleLiteral(values) => {
            for value in values {
                visit_expr(visitor, value);
            }
        }
        ExpressionKind::UnionLiteral { attr: _, value } => {
            visit_expr(visitor, value);
        }
        ExpressionKind::ListLiteral(values) => {
            for value in values {
                visit_expr(visitor, value);
            }
        }
        // ExpressionKind::ImplicitSelf => {}
        // ExpressionKind::Instantiate => {}
        // ExpressionKind::TypeConstructor(_) => {}
        ExpressionKind::EnumLiteral(EnumLiteral {
            variant: _,
            enum_type: _,
            arguments,
        }) => {
            for value in arguments {
                visit_expr(visitor, value);
            }
        }

        ExpressionKind::LoadSymbol(_) => {}
        // ExpressionKind::TypeConstructor(_) => {}

        /*
        ExpressionKind::MethodCall {
        instance,
        method: _,
        arguments,
        } => {
        visit_expr(visitor, instance);
        for argument in arguments {
        visit_expr(visitor, argument);
        }
        }
         */
        ExpressionKind::GetAttr { base, attr: _ } => {
            visit_expr(visitor, base);
        }
        ExpressionKind::GetIndex { base, index } => {
            visit_expr(visitor, base);
            visit_expr(visitor, index);
        }
    }

    visitor.post_node(VisitedNode::Expression(expression));
}
