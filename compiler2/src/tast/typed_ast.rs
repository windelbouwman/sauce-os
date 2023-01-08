//! A typed version of the AST.
//!
//! Expressions are assigned types here.
//!
//! This intermediate form has most language
//! constructs, and types attached.

// use super::type_system::{ClassTypeRef, EnumType, SlangType};

use super::{ClassDef, StructDef, UnionDef};
use super::{ClassType, EnumType, SlangType, StructType, UnionType, UserType};
use super::{EnumDef, EnumVariant};
use super::{Expression, ExpressionKind, Literal, Statement, StatementKind, WhileStatement};
use super::{NameNodeId, NodeId, Ref};
use super::{Scope, Symbol};
use crate::parsing::ast;
use crate::parsing::Location;
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::Arc;

pub struct Program {
    pub name: String,
    pub path: std::path::PathBuf,
    pub scope: Arc<Scope>,
    pub definitions: Vec<Definition>,
}

#[derive(Clone)]
pub enum Definition {
    Function(Rc<RefCell<FunctionDef>>),
    Class(Rc<ClassDef>),
    Struct(Rc<StructDef>),
    Union(Rc<UnionDef>),
    Enum(Rc<EnumDef>),
    // Field(Arc<FieldDef>),
}

impl Definition {
    /// Create type for this definition!
    pub fn create_type(&self, type_arguments: Vec<SlangType>) -> SlangType {
        let user_type = match self {
            Definition::Struct(struct_def) => {
                assert!(type_arguments.len() == struct_def.type_parameters.len());
                UserType::Struct(StructType {
                    struct_ref: Rc::downgrade(struct_def),
                    type_arguments,
                })
            }
            Definition::Union(union_def) => {
                assert!(type_arguments.len() == union_def.type_parameters.len());
                UserType::Union(UnionType {
                    union_ref: Rc::downgrade(union_def),
                    type_arguments,
                })
            }
            Definition::Enum(enum_def) => {
                assert!(type_arguments.len() == enum_def.type_parameters.len());
                UserType::Enum(EnumType {
                    enum_ref: Rc::downgrade(enum_def),
                    type_arguments,
                })
            }
            Definition::Class(class_def) => {
                assert!(type_arguments.is_empty());
                UserType::Class(ClassType {
                    class_ref: Rc::downgrade(class_def),
                    type_arguments,
                })
            }
            Definition::Function(_function_def) => {
                // UserType::Function(function_def.borrow().signature.clone())
                unimplemented!();
            }
        };

        SlangType::User(user_type)
    }

    /// Narrow the type to struct type.
    #[allow(dead_code)]
    pub fn as_struct(&self) -> Rc<StructDef> {
        if let Definition::Struct(struct_def) = self {
            struct_def.clone()
        } else {
            panic!("Expected struct type");
        }
    }

    /// Get attribute from this definition
    #[allow(dead_code)]
    pub fn get_attr(&self, name: &str) -> Option<Symbol> {
        match self {
            Definition::Struct(struct_def) => struct_def.get_attr(name),
            Definition::Union(union_def) => union_def.get_attr(name),
            Definition::Class(class_def) => class_def.get_attr(name),
            _ => None,
        }
    }
}

pub struct FieldDef {
    pub location: Location,
    pub name: String,
    pub index: usize,
    pub typ: SlangType,
    pub value: Option<Expression>,
}

/*
pub struct TypeDef {
    pub name: String,
    pub typ: SlangType,
}
*/

/*
#[derive(Debug)]
pub struct TypeExpr {
    pub node_id: NodeId,
    pub kind: TypeExprKind,
}

#[derive(Debug)]
pub enum TypeExprKind {
    Object(ast::ObjRef),
    Type(SlangType),
}
*/

/// A function definition.
pub struct FunctionDef {
    pub name: NameNodeId,
    pub location: Location,
    pub signature: Rc<RefCell<FunctionSignature>>,
    pub this_param: Option<Rc<RefCell<Parameter>>>,
    pub scope: Arc<Scope>,
    pub locals: Vec<Rc<RefCell<LocalVariable>>>,
    pub body: Block,
}

/// A function signature.
pub struct FunctionSignature {
    pub parameters: Vec<Rc<RefCell<Parameter>>>,
    pub return_type: Option<SlangType>,
}

impl FunctionSignature {
    /// Check if the types of signatures are equal
    pub fn compatible_signature(&self, other: &Self) -> bool {
        if self.parameters.len() != other.parameters.len() {
            return false;
        }

        for (p1, p2) in self.parameters.iter().zip(other.parameters.iter()) {
            if p1.borrow().typ != p2.borrow().typ {
                return false;
            }
        }
        self.return_type == other.return_type
    }
}

impl FunctionDef {
    pub fn get_type(&self) -> SlangType {
        SlangType::User(UserType::Function(self.signature.clone()))
    }
}

pub struct LocalVariable {
    pub location: Location,
    pub mutable: bool,
    pub name: NameNodeId,
    pub typ: SlangType,
}

impl LocalVariable {
    pub fn new(location: Location, mutable: bool, name: String, id: NodeId) -> Self {
        Self {
            location,
            mutable,
            name: NameNodeId { name, id },
            typ: SlangType::Undefined,
        }
    }
}

pub struct Parameter {
    pub location: Location,
    pub name: NameNodeId,
    pub typ: SlangType,
}

impl Parameter {
    // pub fn new(location: Location, name: String, typ: SlangType, id: NodeId) -> Self {
    //     Self {
    //         location,
    //         name,
    //         typ,
    //         id,
    //     }
    // }
}

pub type Block = Vec<Statement>;

pub enum VariantRef {
    Name(String),
    Variant(Ref<EnumVariant>),
}

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

pub fn union_literal(union_type: SlangType, attr: String, value: Expression) -> Expression {
    // Some sanity checking:
    if union_type.as_union().get_field(&attr).is_none() {
        panic!("Union has no attribute named '{}'", attr);
    }

    ExpressionKind::UnionLiteral {
        attr,
        value: Box::new(value),
    }
    .typed_expr(union_type)
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

impl<E> std::ops::Add<E> for Expression
where
    E: Into<Expression>,
{
    type Output = Self;

    fn add(self, other: E) -> Self {
        binop(
            self,
            ast::BinaryOperator::Math(ast::MathOperator::Add),
            other.into(),
        )
    }
}

impl<E> std::ops::Sub<E> for Expression
where
    E: Into<Expression>,
{
    type Output = Self;

    fn sub(self, other: E) -> Self {
        binop(
            self,
            ast::BinaryOperator::Math(ast::MathOperator::Sub),
            other.into(),
        )
    }
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
    ExpressionKind::LoadSymbol(Symbol::Function(function_ref)).typed_expr(typ)
}

#[allow(dead_code)]
pub fn obj_ref(obj_ref: ast::ObjRef) -> Expression {
    ExpressionKind::Object(obj_ref).typed_expr(SlangType::Undefined)
}

pub struct EnumLiteral {
    pub enum_type: EnumType,
    pub variant: Ref<EnumVariant>,
    pub arguments: Vec<Expression>,
}

pub struct LabeledField {
    pub location: Location,
    pub name: String,
    pub value: Box<Expression>,
}

// pub enum TypeConstructor {
//     // Any(SlangType),
//     ClassRef(NodeId),
//     EnumVariant(Ref<EnumVariant>),
// }
