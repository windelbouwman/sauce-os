//! A typed version of the AST.
//!
//! Expressions are assigned types here.
//!
//! This intermediate form has most language
//! constructs, and types attached.

// use super::type_system::{ClassTypeRef, EnumType, SlangType};

pub use super::enum_type::{EnumDef, EnumVariant};
use super::scope::Scope;
use super::symbol::Symbol;
use super::type_system::{FunctionType, SlangType};
use crate::parsing::ast;
use crate::parsing::Location;
use std::cell::RefCell;
use std::rc::{Rc, Weak};
use std::sync::Arc;

pub type NodeId = usize;

pub type Ref<T> = Weak<RefCell<T>>;

#[derive(Debug)]
pub struct Program {
    pub name: String,
    pub path: std::path::PathBuf,
    pub scope: Arc<Scope>,
    pub definitions: Vec<Definition>,
}

#[derive(Debug)]
pub enum Definition {
    Function(Rc<RefCell<FunctionDef>>),
    Class(Rc<ClassDef>),
    Struct(Rc<StructDef>),
    Union(Rc<UnionDef>),
    Enum(Rc<EnumDef>),
    // Field(Arc<FieldDef>),
}

#[derive(Debug)]
pub struct StructDef {
    pub location: Location,
    pub name: String,
    pub id: NodeId,
    pub scope: Arc<Scope>,
    pub fields: Vec<Rc<RefCell<FieldDef>>>,
}

impl std::fmt::Display for StructDef {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "struct(name={}, id={})", self.name, self.id)
    }
}

impl StructDef {
    /// Retrieve the given field from this struct
    pub fn get_field(&self, name: &str) -> Option<Rc<RefCell<FieldDef>>> {
        match self.scope.get(name) {
            Some(symbol) => match symbol {
                Symbol::Field { field_ref } => Some(field_ref.upgrade().unwrap()),
                other => {
                    panic!("Struct may only contain fields, not {:?}", other);
                }
            },
            None => None,
        }
    }
}

pub struct StructDefBuilder {
    name: String,
    id: NodeId,
    location: Location,
    scope: Scope,
    fields: Vec<Rc<RefCell<FieldDef>>>,
}

impl StructDefBuilder {
    pub fn new(name: String, id: NodeId) -> Self {
        StructDefBuilder {
            name,
            id,
            location: Default::default(),
            scope: Scope::new(),
            fields: vec![],
        }
    }

    pub fn add_field(&mut self, name: &str, typ: SlangType) {
        let index = self.fields.len();
        let field = Rc::new(RefCell::new(FieldDef {
            index,
            name: name.to_owned(),
            typ,
            location: Default::default(),
            value: None,
        }));

        self.scope.define(
            name.to_owned(),
            Symbol::Field {
                field_ref: Rc::downgrade(&field),
            },
        );

        self.fields.push(field);
    }

    pub fn finish_struct(self) -> StructDef {
        StructDef {
            name: self.name,
            id: self.id,
            location: self.location,
            fields: self.fields,
            scope: Arc::new(self.scope),
        }
    }

    pub fn finish_union(self) -> UnionDef {
        UnionDef {
            name: self.name,
            id: self.id,
            location: self.location,
            fields: self.fields,
            scope: Arc::new(self.scope),
        }
    }
}

/// A C-style union type.
///
/// This type is not exposed in the language, but is an
/// helper type.
#[derive(Debug)]
pub struct UnionDef {
    pub location: Location,
    pub name: String,
    pub id: NodeId,
    pub scope: Arc<Scope>,
    pub fields: Vec<Rc<RefCell<FieldDef>>>,
}

impl std::fmt::Display for UnionDef {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "union(name={}, id={})", self.name, self.id)
    }
}

impl UnionDef {
    /// Retrieve the given field from this struct
    pub fn get_field(&self, name: &str) -> Option<Rc<RefCell<FieldDef>>> {
        match self.scope.get(name) {
            Some(symbol) => match symbol {
                Symbol::Field { field_ref } => Some(field_ref.upgrade().unwrap()),
                other => {
                    panic!("Union can only contain fields, not {:?}", other);
                }
            },
            None => None,
        }
    }
}

#[derive(Debug)]
pub struct ClassDef {
    pub location: Location,
    pub id: NodeId,
    pub name: String,
    pub scope: Arc<Scope>,
    pub fields: Vec<Rc<RefCell<FieldDef>>>,
    pub methods: Vec<Rc<RefCell<FunctionDef>>>,
    // pub definitions: Vec<Definition>,
    // Hmm, having this type here is a bit odd..
    // pub typ: ClassTypeRef,
}

impl ClassDef {
    pub fn get_field(&self, name: &str) -> Option<Symbol> {
        self.scope.get(name).cloned()
        //     Some(Symbol::Field { field_ref }) => Some(field_ref.upgrade().unwrap()),
        //     _other => None,
        // }
    }
}

#[derive(Debug)]
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
#[derive(Debug)]
pub struct Import {
    pub name: String,
    // pub node_id: NodeId,
}

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
#[derive(Debug)]
pub struct FunctionDef {
    pub name: String,
    pub id: NodeId,
    pub location: Location,
    pub parameters: Vec<Rc<RefCell<Parameter>>>,
    pub return_type: Option<SlangType>,
    pub scope: Arc<Scope>,
    pub locals: Vec<Rc<RefCell<LocalVariable>>>,
    pub body: Block,
}

impl FunctionDef {
    pub fn get_type(&self) -> SlangType {
        // unimplemented!();
        // log::warn!("Oei, get func type?");
        let mut argument_types = vec![];
        for p in &self.parameters {
            // TODO: we clone this type here, is this good?
            argument_types.push(p.borrow().typ.clone());
        }
        SlangType::Function(FunctionType {
            argument_types,
            return_type: self.return_type.clone().map(|x| Box::new(x)),
        })
    }
}

#[derive(Debug)]
pub struct LocalVariable {
    pub location: Location,
    pub mutable: bool,
    pub name: String,
    pub typ: SlangType,
    pub id: NodeId,
}

impl LocalVariable {
    pub fn new(location: Location, mutable: bool, name: String, id: NodeId) -> Self {
        Self {
            location,
            mutable,
            name,
            typ: SlangType::Undefined,
            id,
        }
    }
}

#[derive(Debug)]
pub struct Parameter {
    pub location: Location,
    pub name: String,
    pub typ: SlangType,
    pub id: NodeId,
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

#[derive(Debug)]
pub struct Statement {
    pub location: Location,
    pub kind: StatementKind,
}

#[derive(Debug)]
pub enum StatementKind {
    Expression(Expression),
    Let {
        local_ref: Ref<LocalVariable>,
        type_hint: Option<SlangType>,
        value: Expression,
    },
    Assignment(AssignmentStatement),
    StoreLocal {
        local_ref: Ref<LocalVariable>,
        value: Expression,
    },

    SetAttr {
        base: Expression,
        attr: String,
        value: Expression,
    },

    SetIndex {
        base: Box<Expression>,
        index: Box<Expression>,
        value: Expression,
    },

    If(IfStatement),
    Loop {
        body: Block,
    },
    While(WhileStatement),
    For(ForStatement),
    Return {
        value: Option<Expression>,
    },
    Case(CaseStatement),
    Switch(SwitchStatement),
    Compound(Block),
    Pass,
    Break,
    Continue,

    /// Marker statement which cannot be reached!
    Unreachable,
}

impl StatementKind {
    pub fn into_statement(self) -> Statement {
        Statement {
            location: Default::default(),
            kind: self,
        }
    }
}

#[derive(Debug)]
pub struct CaseStatement {
    pub value: Expression,
    pub arms: Vec<CaseArm>,
}

#[derive(Debug)]
pub struct CaseArm {
    pub location: Location,

    /// Index into the chosen enum variant:
    pub constructor: Expression,

    /// Id's of local variables used for this arms unpacked values
    pub local_refs: Vec<Ref<LocalVariable>>,

    pub scope: Arc<Scope>,

    /// The code of this case arm.
    pub body: Block,
}

impl CaseArm {
    pub fn get_variant(&self) -> Rc<RefCell<EnumVariant>> {
        match &self.constructor.kind {
            ExpressionKind::TypeConstructor(TypeConstructor::EnumVariant(variant))
            | ExpressionKind::LoadSymbol(Symbol::EnumVariant(variant)) => {
                variant.upgrade().unwrap()
            }
            other => {
                panic!("Arm constructor contains no variant, but {:?}", other);
            }
        }
    }
}

#[derive(Debug)]
pub struct SwitchStatement {
    pub value: Expression,
    pub arms: Vec<SwitchArm>,
    pub default: Block,
}
#[derive(Debug)]
pub struct SwitchArm {
    pub value: Expression,

    /// The code of this case arm.
    pub body: Block,
}

#[derive(Debug)]
pub struct AssignmentStatement {
    pub target: Expression,
    pub value: Expression,
}

#[derive(Debug)]
pub struct IfStatement {
    pub condition: Expression,
    pub if_true: Block,
    pub if_false: Option<Block>,
}

#[derive(Debug)]
pub struct WhileStatement {
    pub condition: Expression,
    pub body: Block,
}

#[derive(Debug)]
pub struct ForStatement {
    pub loop_var: Ref<LocalVariable>,
    pub iterable: Expression,
    pub body: Block,
}

#[derive(Debug)]
pub struct Expression {
    pub location: Location,
    pub kind: ExpressionKind,
    pub typ: SlangType,
}

impl Expression {
    pub fn new(location: Location, kind: ExpressionKind) -> Self {
        Self {
            location,
            kind,
            typ: SlangType::Undefined,
        }
    }

    /// Take expression, and return it again, with the location attribute set.
    pub fn at(mut self, location: Location) -> Self {
        self.location = location;
        self
    }

    pub fn get_attr(self, attr: &str) -> Self {
        get_attr(self, attr)
    }

    /*
    pub fn has_type(&self) -> bool {
        self.typ.lock().unwrap().as_ref().is_some()
    }
    pub fn get_type(&self) -> SlangType {
        self.typ.lock().unwrap().as_ref().unwrap().clone()
    }

    pub fn set_type(&self, typ: SlangType) {
        *self.typ.lock().unwrap() = Option::Some(typ);
    }
    */

    // pub fn into_i64(self) -> i64 {
    //     match self.kind {
    //         ExpressionKind::Literal(Literal::Integer(value)) => value,
    //         other => panic!("Cannot convert {:?} into i64", other),
    //     }
    // }

    pub fn eval(&self) -> Literal {
        match &self.kind {
            ExpressionKind::Literal(literal) => literal.clone(),
            other => panic!("Cannot evaluate {:?}", other),
        }
    }
}

impl From<i64> for Expression {
    fn from(value: i64) -> Self {
        integer_literal(value)
    }
}

#[derive(Debug)]
pub enum ExpressionKind {
    /// Undefined value
    Undefined,

    /// A literal value.
    Literal(Literal),

    // StructLiteral(Vec<Expression>),
    StructLiteral {
        typ: SlangType,
        fields: Vec<FieldInit>,
    },

    /// A tuple with mixed type values!
    TupleLiteral(Vec<Expression>),

    UnionLiteral {
        attr: String,
        value: Box<Expression>,
    },

    /// An enum literal value
    EnumLiteral(EnumLiteral),

    /// A list literal with equally typed values.
    ListLiteral(Vec<Expression>),

    /// Load the value of the symbol.
    LoadSymbol(Symbol),

    // A TypeConstructor is an expression that can create
    // an instance of a type.
    //
    // TBD: this muight be a dubious expression kind:
    TypeConstructor(TypeConstructor),

    /// Implicit 'self' in a class method.
    // ImplicitSelf,

    // Instantiate,
    Call {
        callee: Box<Expression>,
        arguments: Vec<Expression>,
    },
    /*
    MethodCall {
        instance: Box<Expression>,
        method: String,
        arguments: Vec<Expression>,
    },
    */
    /// Get attribute of some object: base.attr
    GetAttr {
        base: Box<Expression>,
        attr: String,
    },

    /// Array like indexing operator: base[i]
    GetIndex {
        base: Box<Expression>,
        index: Box<Expression>,
    },

    /// Binary operation with a left-hand-side and a right-hand-side.
    Binop {
        lhs: Box<Expression>,
        op: ast::BinaryOperator,
        rhs: Box<Expression>,
    },

    /// A reference to a named thing. Can be undefined.
    Object(ast::ObjRef),
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
        other => panic!("Cannot index type: {:?}", other),
    };

    Expression {
        location: Default::default(),
        typ,
        kind: ExpressionKind::GetIndex {
            base: Box::new(base),
            index: Box::new(index),
        },
    }
}

/// Access expression by attribute
///
/// For example:
///     `base.my_variable`
///
pub fn get_attr(base: Expression, attr: &str) -> Expression {
    let typ: SlangType = match &base.typ {
        SlangType::User(user_type) => {
            if let Some(field) = user_type.get_field(&attr) {
                let typ = field.borrow().typ.clone();
                typ.clone()
            } else {
                panic!("User type {} has no attribute '{}'", user_type, attr);
            }
        }
        other => panic!("Cannot get attribute '{}' from type: {}", attr, other),
    };

    Expression {
        location: Default::default(),
        typ,
        kind: ExpressionKind::GetAttr {
            base: Box::new(base),
            attr: attr.to_owned(),
        },
    }
}

pub fn integer_literal(value: i64) -> Expression {
    Expression {
        location: Default::default(),
        typ: SlangType::Int,
        kind: ExpressionKind::Literal(Literal::Integer(value)),
    }
}

pub fn union_literal(union_type: SlangType, attr: String, value: Expression) -> Expression {
    // Some sanity checking:
    if union_type.as_union().get_field(&attr).is_none() {
        panic!("Union has no attribute named '{}'", attr);
    }

    Expression {
        location: Default::default(),
        typ: union_type,
        kind: ExpressionKind::UnionLiteral {
            attr,
            value: Box::new(value),
        },
    }
}

pub fn tuple_literal(tuple_typ: SlangType, values: Vec<Expression>) -> Expression {
    Expression {
        location: Default::default(),
        typ: tuple_typ,
        kind: ExpressionKind::TupleLiteral(values),
    }
}

/// Produce an expression of undefined value and undefined type
pub fn undefined_value() -> Expression {
    Expression {
        location: Default::default(),
        typ: SlangType::Undefined,
        kind: ExpressionKind::Undefined,
    }
}

pub fn store_local<E>(local_ref: Ref<LocalVariable>, value: E) -> Statement
where
    E: Into<Expression>,
{
    let value = value.into();
    StatementKind::StoreLocal { local_ref, value }.into_statement()
}

pub fn binop(lhs: Expression, op: ast::BinaryOperator, rhs: Expression) -> Expression {
    Expression {
        location: Default::default(),
        typ: lhs.typ.clone(),
        kind: ExpressionKind::Binop {
            lhs: Box::new(lhs),
            op,
            rhs: Box::new(rhs),
        },
    }
}

pub fn comparison(lhs: Expression, cmp_op: ast::ComparisonOperator, rhs: Expression) -> Expression {
    Expression {
        location: Default::default(),
        typ: SlangType::Bool,
        kind: ExpressionKind::Binop {
            lhs: Box::new(lhs),
            op: ast::BinaryOperator::Comparison(cmp_op),
            rhs: Box::new(rhs),
        },
    }
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
    Expression {
        location: Default::default(),
        typ,
        kind: ExpressionKind::LoadSymbol(Symbol::LocalVariable { local_ref }),
    }
}

pub fn obj_ref(obj_ref: ast::ObjRef) -> Expression {
    Expression {
        typ: SlangType::Undefined,
        location: Default::default(),
        kind: ExpressionKind::Object(obj_ref),
    }
}

#[derive(Debug)]
pub struct EnumLiteral {
    pub variant: Ref<EnumVariant>,
    pub arguments: Vec<Expression>,
}

#[derive(Debug, Clone)]
pub enum Literal {
    Bool(bool),
    String(String),
    Integer(i64),
    Float(f64),
}

impl Literal {
    pub fn into_i64(self) -> i64 {
        match self {
            Literal::Integer(value) => value,
            other => panic!("Cannot convert {:?} into i64", other),
        }
    }
}

#[derive(Debug)]
pub struct FieldInit {
    pub location: Location,
    pub name: String,
    pub value: Box<Expression>,
}

#[derive(Debug)]
pub enum TypeConstructor {
    // Any(SlangType),
    ClassRef(NodeId),
    EnumVariant(Ref<EnumVariant>),
}
