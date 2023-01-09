use super::{get_attr, integer_literal, undefined_value};
use super::{EnumType, EnumVariant, LabeledField, Ref, SlangType, Symbol};
use crate::parsing::{ast, Location};

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

    // pub fn set_attr(self, attr: &str, value: Expression) -> Statement {
    //     set_attr(self, attr, value)
    // }

    /// Perform a typecast!
    ///
    /// Cast this expression into 'to_type'
    pub fn cast(self, to_type: SlangType) -> Self {
        let location = self.location.clone();
        ExpressionKind::TypeCast {
            value: Box::new(self),
            to_type,
        }
        .into_expr()
        .at(location)
    }

    // pub fn into_i64(self) -> i64 {
    //     match self.kind {
    //         ExpressionKind::Literal(Literal::Integer(value)) => value,
    //         other => panic!("Cannot convert {:?} into i64", other),
    //     }
    // }

    pub fn eval(&self) -> Literal {
        match &self.kind {
            ExpressionKind::Literal(literal) => literal.clone(),
            _other => panic!("Cannot evaluate expression"),
        }
    }
}

impl From<i64> for Expression {
    fn from(value: i64) -> Self {
        integer_literal(value)
    }
}

impl Default for Expression {
    fn default() -> Self {
        undefined_value()
    }
}

pub enum ExpressionKind {
    /// Undefined value
    Undefined,

    /// A literal value.
    Literal(Literal),

    /// Object initializer
    ObjectInitializer {
        typ: SlangType,
        fields: Vec<LabeledField>,
    },

    /// A tuple with mixed type values!
    TupleLiteral {
        typ: SlangType,
        values: Vec<Expression>,
    },

    UnionLiteral {
        typ: SlangType,
        attr: String,
        value: Box<Expression>,
    },

    /// An enum literal value
    EnumLiteral(EnumLiteral),

    // EnumVariant {
    //     typ: SlangType,
    // },
    /// A list literal with equally typed values.
    ListLiteral(Vec<Expression>),

    /// Load the value of the symbol.
    LoadSymbol(Symbol),

    // A TypeConstructor is an expression that can create
    // an instance of a type.
    //
    // TBD: this muight be a dubious expression kind:
    // TypeConstructor(TypeConstructor),
    /// Implicit 'self' in a class method.
    // ImplicitSelf,

    // Instantiate,
    Call {
        callee: Box<Expression>,
        arguments: Vec<Expression>,
    },

    /// Type-cast the given expression into another type
    TypeCast {
        to_type: SlangType,
        value: Box<Expression>,
    },

    /*
    MethodCall {
        instance: Box<Expression>,
        method: String,
        arguments: Vec<Expression>,
    },
    */
    /// Get attribute of some object: base.attr
    GetAttr { base: Box<Expression>, attr: String },

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

impl ExpressionKind {
    pub fn typed_expr(self, typ: SlangType) -> Expression {
        Expression {
            location: Default::default(),
            typ,
            kind: self,
        }
    }

    /// Move this expression kind into an untyped expression.
    pub fn into_expr(self) -> Expression {
        Expression {
            location: Default::default(),
            typ: SlangType::Undefined,
            kind: self,
        }
    }
}

pub struct EnumLiteral {
    pub enum_type: EnumType,
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
