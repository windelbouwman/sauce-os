use super::{Block, DefinitionRef, FunctionDef, LocalVariable, Ref, Symbol, WhileStatement};
use super::{Expression, ExpressionKind, Literal, SlangType, Statement, StatementKind};
use crate::parsing::ast;

/// Access base by index.
///
/// For example:
///     `base[index]`
///
pub fn get_index<E>(base: Expression, index: E) -> Expression
where
    E: Into<Expression>,
{
    let index = index.into();
    let typ: SlangType = match &base.typ {
        SlangType::Array(array_type) => *array_type.element_type.clone(),
        other => panic!("Cannot index type: {}", other),
    };

    ExpressionKind::GetIndex {
        base: Box::new(base),
        index: Box::new(index),
    }
    .typed_expr(typ)
}

/// Access expression by attribute
///
/// For example:
///     `base.my_variable`
///
pub fn get_attr(base: Expression, attr: &str) -> Expression {
    let typ: SlangType = match &base.typ {
        SlangType::User(user_type) => {
            if let Some(field) = user_type.get_field(attr) {
                let typ = field.borrow().typ.clone();
                typ
            } else {
                panic!("User type {} has no attribute '{}'", user_type, attr);
            }
        }
        other => panic!("Cannot get attribute '{}' from type: {}", attr, other),
    };

    ExpressionKind::GetAttr {
        base: Box::new(base),
        attr: attr.to_owned(),
    }
    .typed_expr(typ)
}

// pub fn set_attr(base: Expression, attr: &str, value: Expression) -> Statement {
//     assert!(base.typ.get_attr(attr).is_some());
//     StatementKind::SetAttr {
//         base,
//         attr: attr.to_owned(),
//         value,
//     }
//     .into_statement()
// }

pub fn return_value(value: Expression) -> Statement {
    StatementKind::Return { value: Some(value) }.into_statement()
}

/// Produce an integer literal expression
pub fn integer_literal(value: i64) -> Expression {
    ExpressionKind::Literal(Literal::Integer(value)).typed_expr(SlangType::int())
}

pub fn union_literal(typ: SlangType, attr: String, value: Expression) -> Expression {
    // Some sanity checking:
    let union_type = typ.as_struct();
    assert!(union_type.is_union());
    if union_type.get_field(&attr).is_none() {
        panic!("Union has no attribute named '{}'", attr);
    }

    ExpressionKind::UnionLiteral {
        typ: typ.clone(),
        attr,
        value: Box::new(value),
    }
    .typed_expr(typ)
}

/// Create a tuple literal expression
pub fn tuple_literal(tuple_typ: SlangType, values: Vec<Expression>) -> Expression {
    ExpressionKind::TupleLiteral {
        typ: tuple_typ.clone(),
        values,
    }
    .typed_expr(tuple_typ)
}

/// Produce an expression of undefined value and undefined type
pub fn undefined_value() -> Expression {
    ExpressionKind::Undefined.typed_expr(SlangType::Undefined)
}

pub fn store_local<E>(local_ref: Ref<LocalVariable>, value: E) -> Statement
where
    E: Into<Expression>,
{
    let value = value.into();
    StatementKind::StoreLocal { local_ref, value }.into_statement()
}

pub fn binop(lhs: Expression, op: ast::BinaryOperator, rhs: Expression) -> Expression {
    let typ = lhs.typ.clone();
    ExpressionKind::Binop {
        lhs: Box::new(lhs),
        op,
        rhs: Box::new(rhs),
    }
    .typed_expr(typ)
}

pub fn comparison(lhs: Expression, cmp_op: ast::ComparisonOperator, rhs: Expression) -> Expression {
    ExpressionKind::Binop {
        lhs: Box::new(lhs),
        op: ast::BinaryOperator::Comparison(cmp_op),
        rhs: Box::new(rhs),
    }
    .typed_expr(SlangType::bool())
}

pub fn while_loop(condition: Expression, body: Block) -> Statement {
    StatementKind::While(WhileStatement { condition, body }).into_statement()
}

pub fn unreachable_code() -> Statement {
    StatementKind::Unreachable.into_statement()
}

pub fn compound(block: Block) -> Statement {
    StatementKind::Compound(block).into_statement()
}

pub fn load_local(local_ref: Ref<LocalVariable>) -> Expression {
    let typ = local_ref.upgrade().unwrap().borrow().typ.clone();
    ExpressionKind::LoadSymbol(Symbol::LocalVariable(local_ref)).typed_expr(typ)
}

// pub fn load_parameter(parameter_ref: Ref<Parameter>) -> Expression {
//     let typ = parameter_ref.upgrade().unwrap().borrow().typ.clone();
//     ExpressionKind::LoadSymbol(Symbol::Parameter(parameter_ref)).typed_expr(typ)
// }

pub fn load_function(function_ref: Ref<FunctionDef>) -> Expression {
    let typ = SlangType::Undefined; // TODO!
    ExpressionKind::LoadSymbol(Symbol::Definition(DefinitionRef::Function(function_ref)))
        .typed_expr(typ)
}

#[allow(dead_code)]
pub fn obj_ref(obj_ref: ast::ObjRef) -> Expression {
    ExpressionKind::Unresolved(obj_ref).typed_expr(SlangType::Undefined)
}
