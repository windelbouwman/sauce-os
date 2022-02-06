use super::semantics::typed_ast;
use super::simple_ast;

pub fn print_ast(program: &simple_ast::Program) {
    AstPrinter::new().print_prog(program);
}

struct AstPrinter {
    indent_level: usize,
}

impl AstPrinter {
    fn new() -> Self {
        AstPrinter { indent_level: 0 }
    }

    fn print_prog(&mut self, prog: &simple_ast::Program) {
        println!("======== SIMPLE AST ============>>");
        // Imports?
        for function_def in &prog.functions {
            self.print_function(function_def);
        }
    }

    fn print_function(&mut self, function_def: &simple_ast::FunctionDef) {
        println!(
            "{}fn {} : {:?}",
            self.get_indent(),
            function_def.name,
            function_def.return_type
        );
        self.indent();
        for (index, parameter) in function_def.parameters.iter().enumerate() {
            println!(
                "{}parameter index={} name={} : {:?}",
                self.get_indent(),
                index,
                parameter.name,
                parameter.typ
            );
        }
        println!("{}locals:", self.get_indent(),);
        self.indent();
        for (index, local) in function_def.locals.iter().enumerate() {
            println!(
                "{}index={} name={} : {:?}",
                self.get_indent(),
                index,
                local.name,
                local.typ
            );
        }
        self.dedent();
        println!("{}code:", self.get_indent());
        self.indent();
        self.print_block(&function_def.body);
        self.dedent();
        self.dedent();
    }

    fn print_block(&mut self, block: &[simple_ast::Statement]) {
        for statement in block {
            self.print_statement(statement);
        }
    }

    fn print_statement(&mut self, statement: &simple_ast::Statement) {
        match statement {
            simple_ast::Statement::Break => {
                println!("{}break", self.get_indent());
            }
            simple_ast::Statement::Continue => {
                println!("{}continue", self.get_indent());
            }
            simple_ast::Statement::Pass => {
                println!("{}pass", self.get_indent());
            }
            simple_ast::Statement::Return { value } => {
                println!("{}return", self.get_indent());
                if let Some(value) = value {
                    self.indent();
                    self.print_expression(value);
                    self.dedent();
                }
            }
            simple_ast::Statement::Compound(block) => {
                self.print_block(block);
            }
            simple_ast::Statement::If(simple_ast::IfStatement {
                condition,
                if_true,
                if_false,
            }) => {
                println!("{}if-statement", self.get_indent());
                self.indent();
                self.print_expression(condition);
                self.print_block(if_true);
                if let Some(if_false) = if_false {
                    self.print_block(if_false);
                }
                self.dedent();
            }
            simple_ast::Statement::While(simple_ast::WhileStatement { condition, body }) => {
                println!("{}while-statement", self.get_indent());
                self.indent();
                self.print_expression(condition);
                self.print_block(body);
                self.dedent();
            }
            simple_ast::Statement::Loop { body } => {
                println!("{}loop-statement", self.get_indent());
                self.indent();
                self.print_block(body);
                self.dedent();
            }
            simple_ast::Statement::Case(simple_ast::CaseStatement {
                value,
                enum_type,
                arms,
            }) => {
                println!("{}case-statement : {:?}", self.get_indent(), enum_type);
                self.indent();
                self.print_expression(value);
                for arm in arms {
                    self.indent();
                    println!("{}> {}", self.get_indent(), arm.choice);
                    self.indent();
                    self.print_block(&arm.body);
                    self.dedent();
                    self.dedent();
                }
                self.dedent();
            }
            simple_ast::Statement::Switch(switch_statement) => {
                println!("{}switch-statement", self.get_indent());
                self.indent();
                self.print_expression(&switch_statement.value);
                for arm in &switch_statement.arms {
                    self.indent();
                    // self.print_expression(&arm.value);
                    self.indent();
                    self.print_block(&arm.body);
                    self.dedent();
                    self.dedent();
                }
                self.indent();
                println!("{}default:", self.get_indent());
                self.indent();
                self.print_block(&switch_statement.default);
                self.dedent();
                self.dedent();
                self.dedent();
            }
            simple_ast::Statement::Expression(expression) => {
                self.print_expression(expression);
            }
            simple_ast::Statement::StoreLocal { index, value } => {
                println!("{}store-local-statement index={}", self.get_indent(), index);
                self.indent();
                self.print_expression(value);
                self.dedent();
            }
            simple_ast::Statement::SetAttr {
                base,
                base_typ: _,
                index,
                value,
            } => {
                println!("{}set-attr-statement index={}", self.get_indent(), index);
                self.indent();
                self.print_expression(base);
                self.print_expression(value);
                self.dedent();
            }
        }
    }

    fn print_expression(&mut self, expression: &simple_ast::Expression) {
        match expression {
            simple_ast::Expression::Call {
                callee,
                arguments,
                typ,
            } => {
                println!("{}call : {:?}", self.get_indent(), typ);
                self.indent();
                self.print_expression(callee);
                for argument in arguments {
                    self.print_expression(argument);
                }
                self.dedent();
            }
            simple_ast::Expression::Binop {
                lhs,
                op,
                rhs,
                typ,
                op_typ: _,
            } => {
                println!("{}Binary operation {:?} : {:?}", self.get_indent(), op, typ);
                self.indent();
                self.print_expression(lhs);
                self.print_expression(rhs);
                self.dedent();
            }
            simple_ast::Expression::Literal(literal) => {
                self.print_literal(literal);
            }
            simple_ast::Expression::VoidLiteral => {
                println!("{}Void literal", self.get_indent());
            }
            simple_ast::Expression::StructLiteral { typ, values } => {
                println!("{}Struct literal : {:?}", self.get_indent(), typ);
                self.indent();
                for value in values {
                    self.print_expression(value);
                }
                self.dedent();
            }
            simple_ast::Expression::UnionLiteral { typ, index, value } => {
                println!(
                    "{}Union literal index={} : {:?}",
                    self.get_indent(),
                    index,
                    typ
                );
                self.indent();
                self.print_expression(value);
                self.dedent();
            }
            simple_ast::Expression::ArrayLiteral { typ, values } => {
                println!("{}array-literal : {:?}", self.get_indent(), typ);
                self.indent();
                for value in values {
                    self.print_expression(value);
                }
                self.dedent();
            }
            simple_ast::Expression::LoadFunction(name) => {
                println!("{}Load function name={}", self.get_indent(), name);
            }
            simple_ast::Expression::LoadParameter { index } => {
                println!("{}Load parameter index={}", self.get_indent(), index);
            }
            simple_ast::Expression::LoadLocal { index, typ } => {
                println!(
                    "{}Load local index={} : {:?}",
                    self.get_indent(),
                    index,
                    typ
                );
            }
            simple_ast::Expression::GetAttr {
                base,
                base_typ,
                index,
            } => {
                println!(
                    "{}get-attr from {:?} index={}",
                    self.get_indent(),
                    base_typ,
                    index
                );
                self.indent();
                self.print_expression(base);
                self.dedent();
            }
            simple_ast::Expression::GetIndex { base, index } => {
                println!("{}get-index", self.get_indent());
                self.indent();
                self.print_expression(base);
                self.print_expression(index);
                self.dedent();
            }
        }
    }

    fn print_literal(&self, literal: &typed_ast::Literal) {
        match literal {
            typed_ast::Literal::Bool(value) => {
                println!("{}Bool val={}", self.get_indent(), value);
            }
            typed_ast::Literal::Integer(value) => {
                println!("{}Integer val={}", self.get_indent(), value);
            }
            typed_ast::Literal::Float(value) => {
                println!("{}Float val={}", self.get_indent(), value);
            }
            typed_ast::Literal::String(value) => {
                println!("{}String val='{}'", self.get_indent(), value);
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
