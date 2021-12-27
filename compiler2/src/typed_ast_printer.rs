use super::typed_ast;

pub fn print_ast(program: &typed_ast::Program) {
    AstPrinter::new().print_prog(program);
}

struct AstPrinter {
    indent_level: usize,
}

impl AstPrinter {
    fn new() -> Self {
        AstPrinter { indent_level: 0 }
    }

    fn print_prog(&mut self, prog: &typed_ast::Program) {
        for type_def in &prog.type_defs {
            println!("{}type : {:?}", self.get_indent(), type_def);
        }
        for function_def in &prog.functions {
            self.print_function(function_def);
        }
    }

    fn print_function(&mut self, function_def: &typed_ast::FunctionDef) {
        println!("{}fn {}", self.get_indent(), function_def.name);
        self.indent();
        for parameter in &function_def.parameters {
            println!(
                "{}parameter {} : {:?}",
                self.get_indent(),
                parameter.name,
                parameter.typ
            );
        }
        for local in &function_def.locals {
            println!(
                "{}local {} : {:?}",
                self.get_indent(),
                local.name,
                local.typ
            );
        }
        self.print_block(&function_def.body);
        self.dedent();
    }

    fn print_block(&mut self, block: &[typed_ast::Statement]) {
        for statement in block {
            self.print_statement(statement);
        }
    }

    fn print_statement(&mut self, statement: &typed_ast::Statement) {
        match &statement.kind {
            typed_ast::StatementType::Break => {
                println!("{}break", self.get_indent());
            }
            typed_ast::StatementType::Continue => {
                println!("{}continue", self.get_indent());
            }
            typed_ast::StatementType::If {
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
            typed_ast::StatementType::While { condition, body } => {
                println!("{}while-statement", self.get_indent());
                self.indent();
                self.print_expression(condition);
                self.print_block(body);
                self.dedent();
            }
            typed_ast::StatementType::Loop { body } => {
                println!("{}loop-statement", self.get_indent());
                self.indent();
                self.print_block(body);
                self.dedent();
            }
            typed_ast::StatementType::Expression(expression) => {
                self.print_expression(expression);
            }
            typed_ast::StatementType::Let { name, index, value } => {
                println!(
                    "{}let-statement name={} index={}",
                    self.get_indent(),
                    name,
                    index
                );
                self.indent();
                self.print_expression(value);
                self.dedent();
            }
        }
    }

    fn print_expression(&mut self, expression: &typed_ast::Expression) {
        match &expression.kind {
            typed_ast::ExpressionType::Call { callee, arguments } => {
                println!("{}call", self.get_indent());
                self.indent();
                self.print_expression(callee);
                for argument in arguments {
                    self.print_expression(argument);
                }
                self.dedent();
            }
            typed_ast::ExpressionType::Binop { lhs, op, rhs } => {
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
            typed_ast::ExpressionType::Bool(value) => {
                println!(
                    "{}Bool val={} : {:?}",
                    self.get_indent(),
                    value,
                    expression.typ
                );
            }
            typed_ast::ExpressionType::Integer(value) => {
                println!(
                    "{}Integer val={} : {:?}",
                    self.get_indent(),
                    value,
                    expression.typ
                );
            }
            typed_ast::ExpressionType::Float(value) => {
                println!(
                    "{}Float val={} : {:?}",
                    self.get_indent(),
                    value,
                    expression.typ
                );
            }
            typed_ast::ExpressionType::String(value) => {
                println!(
                    "{}String val='{}' : {:?}",
                    self.get_indent(),
                    value,
                    expression.typ
                );
            }
            typed_ast::ExpressionType::StructLiteral(values) => {
                println!("{}Struct literal", self.get_indent());
                self.indent();
                for value in values {
                    self.print_expression(value);
                }
                self.dedent();
            }
            typed_ast::ExpressionType::LoadModule { modname } => {
                println!("{}Load module name={}", self.get_indent(), modname);
            }
            typed_ast::ExpressionType::LoadFunction(name) => {
                println!("{}Load function name={}", self.get_indent(), name);
            }
            typed_ast::ExpressionType::LoadParameter { name, index } => {
                println!(
                    "{}Load parameter name={} index={}: {:?}",
                    self.get_indent(),
                    name,
                    index,
                    expression.typ
                );
            }
            typed_ast::ExpressionType::LoadLocal { name, index } => {
                println!(
                    "{}Load local name={} index={} : {:?}",
                    self.get_indent(),
                    name,
                    index,
                    expression.typ
                );
            }
            typed_ast::ExpressionType::GetAttr { base, attr } => {
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
