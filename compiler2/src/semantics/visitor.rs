use super::generics::GenericDef;
use super::type_system::{SlangType, UserType};
use super::typed_ast;
use std::cell::RefCell;
use std::rc::Rc;

pub enum VisitedNode<'n> {
    Program(&'n mut typed_ast::Program),
    Generic(&'n GenericDef),
    Definition(&'n typed_ast::Definition),
    Function(&'n typed_ast::FunctionDef),
    Statement(&'n mut typed_ast::Statement),
    CaseArm(&'n mut typed_ast::CaseArm),
    Expression(&'n mut typed_ast::Expression),
    TypeExpr(&'n mut SlangType),
}

pub trait VisitorApi {
    fn pre_node(&mut self, node: VisitedNode);
    fn post_node(&mut self, node: VisitedNode);
}

pub fn visit_program<V: VisitorApi>(visitor: &mut V, program: &mut typed_ast::Program) {
    visitor.pre_node(VisitedNode::Program(program));

    for generic in &program.generics {
        visitor.pre_node(VisitedNode::Generic(generic));
        visit_definition(visitor, &generic.base);
        visitor.post_node(VisitedNode::Generic(generic));
    }

    for definition in &program.definitions {
        visit_definition(visitor, definition);
    }
    visitor.post_node(VisitedNode::Program(program));
}

fn visit_definition<V: VisitorApi>(visitor: &mut V, definition: &typed_ast::Definition) {
    visitor.pre_node(VisitedNode::Definition(definition));
    match definition {
        typed_ast::Definition::Function(function) => {
            visit_function(visitor, function);
        }
        typed_ast::Definition::Class(class_def) => {
            for field in &class_def.fields {
                visit_field(visitor, field);
            }

            for method in &class_def.methods {
                visitor.pre_node(VisitedNode::Function(&method.borrow()));
                visit_function(visitor, method);
                visitor.post_node(VisitedNode::Function(&method.borrow()));
            }
        }
        typed_ast::Definition::Struct(struct_def) => {
            for field_def in &struct_def.fields {
                visit_field(visitor, field_def);
            }
        }
        typed_ast::Definition::Union(union_def) => {
            for field_def in &union_def.fields {
                visit_field(visitor, field_def);
            }
        }
        typed_ast::Definition::Enum(enum_def) => {
            for enum_variant in &enum_def.variants {
                for payload_type in &mut enum_variant.borrow_mut().data {
                    visit_type_expr(visitor, payload_type);
                }
            }
        }
    }
    visitor.post_node(VisitedNode::Definition(definition));
}

fn visit_field<V: VisitorApi>(visitor: &mut V, field_def: &Rc<RefCell<typed_ast::FieldDef>>) {
    visit_type_expr(visitor, &mut field_def.borrow_mut().typ);

    // assert!(field_def.borrow().value.is_none());
    if let Some(value) = &mut field_def.borrow_mut().value {
        visit_expr(visitor, value);
    }
}

fn visit_signature<V: VisitorApi>(visitor: &mut V, signature: &mut typed_ast::FunctionSignature) {
    for parameter in &signature.parameters {
        visit_type_expr(visitor, &mut parameter.borrow_mut().typ);
    }

    if let Some(ret_type) = &mut signature.return_type {
        visit_type_expr(visitor, ret_type);
    }
}

fn visit_function<V: VisitorApi>(visitor: &mut V, function: &Rc<RefCell<typed_ast::FunctionDef>>) {
    visit_signature(visitor, &mut function.borrow().signature.borrow_mut());

    for local in &function.borrow().locals {
        visit_type_expr(visitor, &mut local.borrow_mut().typ);
    }

    visit_block(visitor, &mut function.borrow_mut().body);
}

fn visit_type_expr<V: VisitorApi>(visitor: &mut V, type_expr: &mut SlangType) {
    visitor.pre_node(VisitedNode::TypeExpr(type_expr));
    match type_expr {
        SlangType::GenericInstance {
            type_parameters, ..
        } => {
            for type_parameter in type_parameters {
                visit_type_expr(visitor, type_parameter);
            }
        }
        SlangType::User(UserType::Function(signature)) => {
            let mut signature = signature.borrow_mut();
            for parameter in &signature.parameters {
                let mut parameter = parameter.borrow_mut();
                visit_type_expr(visitor, &mut parameter.typ);
            }
            if let Some(t) = &mut signature.return_type {
                visit_type_expr(visitor, t);
            }
        }
        _ => {}
    }
    visitor.post_node(VisitedNode::TypeExpr(type_expr));
}

fn visit_block<V: VisitorApi>(visitor: &mut V, block: &mut [typed_ast::Statement]) {
    for statement in block {
        visit_statement(visitor, statement);
    }
}

fn visit_statement<V: VisitorApi>(visitor: &mut V, statement: &mut typed_ast::Statement) {
    visitor.pre_node(VisitedNode::Statement(statement));

    match &mut statement.kind {
        typed_ast::StatementKind::Break => {}
        typed_ast::StatementKind::Continue => {}
        typed_ast::StatementKind::Pass => {}
        typed_ast::StatementKind::Unreachable => {}
        typed_ast::StatementKind::Return { value } => {
            if let Some(value) = value {
                visit_expr(visitor, value);
            }
        }
        typed_ast::StatementKind::If(typed_ast::IfStatement {
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
        typed_ast::StatementKind::While(typed_ast::WhileStatement { condition, body }) => {
            visit_expr(visitor, condition);
            visit_block(visitor, body);
        }
        typed_ast::StatementKind::Loop { body } => {
            visit_block(visitor, body);
        }
        typed_ast::StatementKind::Compound(block) => {
            visit_block(visitor, block);
        }
        typed_ast::StatementKind::For(for_statement) => {
            visit_expr(visitor, &mut for_statement.iterable);
            visit_block(visitor, &mut for_statement.body);
        }
        typed_ast::StatementKind::Let {
            local_ref: _,
            type_hint,
            value,
        } => {
            if let Some(type_hint) = type_hint {
                visit_type_expr(visitor, type_hint)
            }

            visit_expr(visitor, value);
        }
        typed_ast::StatementKind::Assignment(assignment) => {
            visit_expr(visitor, &mut assignment.target);
            visit_expr(visitor, &mut assignment.value);
        }
        typed_ast::StatementKind::StoreLocal {
            local_ref: _,
            value,
        } => {
            visit_expr(visitor, value);
        }

        typed_ast::StatementKind::SetAttr {
            base,
            attr: _,
            value,
        } => {
            visit_expr(visitor, base);
            visit_expr(visitor, value);
        }

        typed_ast::StatementKind::SetIndex { base, index, value } => {
            visit_expr(visitor, base);
            visit_expr(visitor, index);
            visit_expr(visitor, value);
        }
        typed_ast::StatementKind::Case(typed_ast::CaseStatement { value, arms }) => {
            visit_expr(visitor, value);
            for arm in arms {
                visitor.pre_node(VisitedNode::CaseArm(arm));
                // visit_expr(visitor, &mut arm.constructor);
                visit_block(visitor, &mut arm.body);
                visitor.post_node(VisitedNode::CaseArm(arm));
            }
        }
        typed_ast::StatementKind::Switch(typed_ast::SwitchStatement {
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
        typed_ast::StatementKind::Expression(expression) => {
            visit_expr(visitor, expression);
        }
    }

    visitor.post_node(VisitedNode::Statement(statement));
}

fn visit_expr<V: VisitorApi>(visitor: &mut V, expression: &mut typed_ast::Expression) {
    visitor.pre_node(VisitedNode::Expression(expression));

    match &mut expression.kind {
        typed_ast::ExpressionKind::Undefined => {}
        typed_ast::ExpressionKind::Object(_) => {}
        typed_ast::ExpressionKind::Call { callee, arguments } => {
            visit_expr(visitor, callee);
            for argument in arguments {
                visit_expr(visitor, argument);
            }
        }
        typed_ast::ExpressionKind::Binop { lhs, op: _, rhs } => {
            visit_expr(visitor, lhs);
            visit_expr(visitor, rhs);
        }
        typed_ast::ExpressionKind::TypeCast { value, to_type: _ } => {
            // TBD: visit to_type?
            visit_expr(visitor, value);
        }
        typed_ast::ExpressionKind::Literal(_) => {}
        typed_ast::ExpressionKind::ObjectInitializer { typ, fields } => {
            visit_type_expr(visitor, typ);
            for field in fields {
                visit_expr(visitor, &mut field.value);
            }
        }
        typed_ast::ExpressionKind::TupleLiteral(values) => {
            for value in values {
                visit_expr(visitor, value);
            }
        }
        typed_ast::ExpressionKind::UnionLiteral { attr: _, value } => {
            visit_expr(visitor, value);
        }
        typed_ast::ExpressionKind::ListLiteral(values) => {
            for value in values {
                visit_expr(visitor, value);
            }
        }
        // typed_ast::ExpressionKind::ImplicitSelf => {}
        // typed_ast::ExpressionKind::Instantiate => {}
        // typed_ast::ExpressionKind::TypeConstructor(_) => {}
        typed_ast::ExpressionKind::EnumLiteral(typed_ast::EnumLiteral {
            variant: _,
            arguments,
        }) => {
            for value in arguments {
                visit_expr(visitor, value);
            }
        }

        typed_ast::ExpressionKind::LoadSymbol(_) => {}
        // typed_ast::ExpressionKind::TypeConstructor(_) => {}

        /*
        typed_ast::ExpressionKind::MethodCall {
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
        typed_ast::ExpressionKind::GetAttr { base, attr: _ } => {
            visit_expr(visitor, base);
        }
        typed_ast::ExpressionKind::GetIndex { base, index } => {
            visit_expr(visitor, base);
            visit_expr(visitor, index);
        }
    }

    visitor.post_node(VisitedNode::Expression(expression));
}
