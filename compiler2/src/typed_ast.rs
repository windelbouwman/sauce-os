//! A typed version of the AST.
//!
//! Expressions are assigned types here.

use super::type_system::MyType;
use crate::parsing::ast;

pub struct Program {
    pub imports: Vec<ast::Import>,
    pub functions: Vec<FunctionDef>,
}

pub struct FunctionDef {
    pub name: String,
    pub parameters: Vec<Parameter>,
    pub locals: Vec<LocalVariable>,
    pub body: Block,
}

pub struct LocalVariable {
    pub name: String,
    pub typ: MyType,
}

pub struct Parameter {
    pub name: String,
    pub typ: MyType,
}

pub type Block = Vec<Statement>;

pub struct Statement {
    pub kind: StatementType,
}

pub enum StatementType {
    Expression(Expression),
    Let {
        name: String,
        value: Expression,
    },
    If {
        condition: Expression,
        if_true: Block,
        if_false: Option<Block>,
    },
    Loop {
        body: Block,
    },
    While {
        condition: Expression,
        body: Block,
    },
    Break,
    Continue,
}

pub struct Expression {
    pub typ: MyType,
    pub kind: ExpressionType,
}

pub enum ExpressionType {
    Bool(bool),
    String(String),
    Integer(i64),
    Float(f64),
    StructLiteral(Vec<Expression>),
    // Identifier(String), // This is resolved in this version of the refined AST.
    LoadGlobal(String),
    LoadFunction(String),
    LoadParameter(String),
    LoadLocal(String),
    Call {
        callee: Box<Expression>,
        arguments: Vec<Expression>,
    },
    GetAttr {
        base: Box<Expression>,
        attr: String,
    },
    Binop {
        lhs: Box<Expression>,
        op: ast::BinaryOperator,
        rhs: Box<Expression>,
    },
}

pub fn print_ast(program: &Program) {
    AstPrinter::new().print_prog(program);
}

struct AstPrinter {
    indent_level: usize,
}

impl AstPrinter {
    fn new() -> Self {
        AstPrinter { indent_level: 0 }
    }

    fn print_prog(&mut self, prog: &Program) {
        for function_def in &prog.functions {
            self.print_function(function_def);
        }
    }

    fn print_function(&mut self, function_def: &FunctionDef) {
        println!("{}fn {}", self.get_indent(), function_def.name);
        self.indent();
        self.print_block(&function_def.body);
        self.dedent();
    }

    fn print_block(&mut self, block: &[Statement]) {
        for statement in block {
            self.print_statement(statement);
        }
    }

    fn print_statement(&mut self, statement: &Statement) {
        match &statement.kind {
            StatementType::Break => {
                println!("{}break", self.get_indent());
            }
            StatementType::Continue => {
                println!("{}continue", self.get_indent());
            }
            StatementType::If {
                condition,
                if_true,
                if_false,
            } => {
                println!("{}if-statement", self.get_indent());
                self.indent();
                self.print_expression(condition);
                self.print_block(if_true);
                if let Some(if_false) = if_false {
                    self.print_block(if_false);
                }
                self.dedent();
            }
            StatementType::While { condition, body } => {
                println!("{}while-statement", self.get_indent());
                self.indent();
                self.print_expression(condition);
                self.print_block(body);
                self.dedent();
            }
            StatementType::Loop { body } => {
                println!("{}loop-statement", self.get_indent());
                self.indent();
                self.print_block(body);
                self.dedent();
            }
            StatementType::Expression(expression) => {
                self.print_expression(expression);
            }
            StatementType::Let { name, value } => {
                println!("{}let-statement name={}", self.get_indent(), name);
                self.indent();
                self.print_expression(value);
                self.dedent();
            }
        }
    }

    fn print_expression(&mut self, expression: &Expression) {
        match &expression.kind {
            ExpressionType::Call { callee, arguments } => {
                println!("{}call", self.get_indent());
                self.indent();
                self.print_expression(callee);
                for argument in arguments {
                    self.print_expression(argument);
                }
                self.dedent();
            }
            ExpressionType::Binop { lhs, op, rhs } => {
                println!(
                    "{}Binary operation {:?} : {:?}",
                    self.get_indent(),
                    op,
                    expression.typ
                );
                self.indent();
                self.print_expression(lhs);
                self.print_expression(rhs);
                self.dedent();
            }
            ExpressionType::Bool(value) => {
                println!(
                    "{}Bool val={} : {:?}",
                    self.get_indent(),
                    value,
                    expression.typ
                );
            }
            ExpressionType::Integer(value) => {
                println!(
                    "{}Integer val={} : {:?}",
                    self.get_indent(),
                    value,
                    expression.typ
                );
            }
            ExpressionType::Float(value) => {
                println!(
                    "{}Float val={} : {:?}",
                    self.get_indent(),
                    value,
                    expression.typ
                );
            }
            ExpressionType::String(value) => {
                println!(
                    "{}String val='{}' : {:?}",
                    self.get_indent(),
                    value,
                    expression.typ
                );
            }
            ExpressionType::StructLiteral(_) => {
                println!("{}Struct literal", self.get_indent());
            }
            ExpressionType::LoadGlobal(name) => {
                println!("{}Load global name={}", self.get_indent(), name);
            }
            ExpressionType::LoadFunction(name) => {
                println!("{}Load function name={}", self.get_indent(), name);
            }
            ExpressionType::LoadParameter(name) => {
                println!(
                    "{}Load parameter name={} : {:?}",
                    self.get_indent(),
                    name,
                    expression.typ
                );
            }
            ExpressionType::LoadLocal(name) => {
                println!(
                    "{}Load local name={} : {:?}",
                    self.get_indent(),
                    name,
                    expression.typ
                );
            }
            ExpressionType::GetAttr { base, attr } => {
                println!("{}get attr={}", self.get_indent(), attr);
                self.indent();
                self.print_expression(base);
                self.dedent();
            }
        }
    }

    fn get_indent(&self) -> String {
        " ".repeat(self.indent_level * 3)
    }

    fn indent(&mut self) {
        self.indent_level += 1;
    }

    fn dedent(&mut self) {
        self.indent_level -= 1;
    }
}
