use super::refer;
use super::visitor::{visit_program, VisitedNode, VisitorApi};
use crate::tast::{AssignmentStatement, CaseStatement, ForStatement, IfStatement, WhileStatement};
use crate::tast::{Definition, FieldDef, FunctionDef, Program};
use crate::tast::{EnumLiteral, Expression, ExpressionKind, Literal, Statement, StatementKind};
use crate::tast::{SlangType, Symbol};
use std::cell::RefCell;
use std::rc::Rc;

pub fn print_ast(program: &mut Program) {
    let mut printer = AstPrinter::new();
    visit_program(&mut printer, program);
}

struct AstPrinter {
    indent_level: usize,
}

impl AstPrinter {
    fn new() -> Self {
        AstPrinter { indent_level: 0 }
    }

    fn print_function(&mut self, function_def: &FunctionDef) {
        println!(
            "{}fn {} location={}",
            self.get_indent(),
            function_def.name,
            function_def.location
        );
        self.indent();

        let signature = function_def.signature.borrow();
        if !signature.parameters.is_empty() {
            println!("{}parameters:", self.get_indent());
            self.indent();
            for parameter in &signature.parameters {
                let parameter = parameter.borrow();
                println!(
                    "{}{} typ={}",
                    self.get_indent(),
                    parameter.name,
                    parameter.typ
                );
            }
            self.dedent();
        }

        if let Some(return_type) = &signature.return_type {
            println!("{}Return type: {}", self.get_indent(), return_type);
        }

        if !function_def.locals.is_empty() {
            println!("{}locals:", self.get_indent());
            self.indent();
            for (index, local_ref) in function_def.locals.iter().enumerate() {
                let local_ref = local_ref.borrow();
                println!(
                    "{}index={} {} typ={}",
                    self.get_indent(),
                    index,
                    local_ref.name,
                    local_ref.typ,
                );
            }
            self.dedent();
        }

        println!("{}code:", self.get_indent());
    }

    fn print_literal(&self, literal: &Literal) {
        match literal {
            Literal::Bool(value) => {
                print!("{}Bool val={}", self.get_indent(), value);
            }
            Literal::Integer(value) => {
                print!("{}Integer val={}", self.get_indent(), value);
            }
            Literal::Float(value) => {
                print!("{}Float val={}", self.get_indent(), value);
            }
            Literal::String(value) => {
                print!("{}String val='{}'", self.get_indent(), value);
            }
        }
    }

    /// Print some additional attributes
    ///
    /*
    fn print_attributes(&self, node_id: NodeId) {
        if self.context.has_location(node_id) {
            let location = self.context.get_location(node_id);
            print!(" location={}:{}", location.row, location.column);
        }

        if self.context.has_name(node_id) {
            let name = self.context.get_name(node_id);
            print!(" name={}", name);
        }

        if self.context.has_type(node_id) {
            let typ = self.context.get_type(node_id);
            print!(" type={:?}", typ);
        }

        println!(" node-id={}", node_id);
    }
    */

    fn get_indent(&self) -> String {
        " ".repeat(self.indent_level * 3)
    }

    fn indent(&mut self) {
        self.indent_level += 1;
    }

    fn dedent(&mut self) {
        self.indent_level -= 1;
    }

    fn pre_definition(&mut self, definition: &Definition) {
        match definition {
            Definition::Function(function_def) => {
                self.print_function(&function_def.borrow());
                self.indent();
            }

            Definition::Class(class_def) => {
                println!("{}class {}", self.get_indent(), class_def.name);
                self.indent();
                self.print_fields(&class_def.fields);
            }
            Definition::Struct(struct_def) => {
                println!("{}struct {}", self.get_indent(), struct_def.name);

                self.indent();
                self.print_fields(&struct_def.fields);
            }
            Definition::Union(union_def) => {
                println!("{}union {}", self.get_indent(), union_def.name);

                self.indent();
                self.print_fields(&union_def.fields);
            }

            // Definition::Field(field_def) => {

            // self.print_attributes(field_def.node_id);
            // }
            Definition::Enum(enum_def) => {
                println!("{}{}", self.get_indent(), enum_def);
                self.indent();
                for variant in &enum_def.variants {
                    let variant = variant.borrow();
                    let mut type_texts = vec![];
                    for t in &variant.data {
                        type_texts.push(format!("{}", t));
                    }
                    println!(
                        "{}variant {}({})",
                        self.get_indent(),
                        variant.name,
                        type_texts.join(", ")
                    );
                }
            }
        }
    }

    fn print_fields(&mut self, fields: &[Rc<RefCell<FieldDef>>]) {
        for field_def in fields {
            let field = field_def.borrow();
            println!(
                "{}field name={} typ={}",
                self.get_indent(),
                field.name,
                field.typ
            );
        }
    }

    fn post_definition(&mut self, definition: &Definition) {
        match definition {
            Definition::Function(_) => {
                self.dedent();
                self.dedent();
            }
            Definition::Class(_) => {
                self.dedent();
            }
            Definition::Struct(_) | Definition::Union(_) => {
                self.dedent();
            }
            Definition::Enum(_) => {
                self.dedent();
            }
        }
    }

    fn pre_stmt(&mut self, statement: &mut Statement) {
        match &statement.kind {
            StatementKind::Break => {
                print!("{}break", self.get_indent());
            }
            StatementKind::Continue => {
                print!("{}continue", self.get_indent());
            }
            StatementKind::Unreachable => {
                print!("{}unreachable", self.get_indent());
            }
            StatementKind::Pass => {
                print!("{}pass", self.get_indent());
            }
            StatementKind::Return { .. } => {
                print!("{}return", self.get_indent());
            }
            StatementKind::If(IfStatement { .. }) => {
                print!("{}if-statement", self.get_indent());
            }
            StatementKind::While(WhileStatement { .. }) => {
                print!("{}while-statement", self.get_indent());
            }
            StatementKind::Loop { .. } => {
                print!("{}loop-statement", self.get_indent());
            }
            StatementKind::Compound(_) => {
                print!("{}compound-statement", self.get_indent());
            }
            StatementKind::For(ForStatement {
                loop_var,
                iterable: _,
                body: _,
            }) => {
                print!(
                    "{}for-statement loop-var-name={}",
                    self.get_indent(),
                    refer(loop_var).borrow().name
                );
            }
            StatementKind::Expression(_) => {
                print!("{}expression-statement", self.get_indent());
            }
            StatementKind::Assignment(AssignmentStatement { .. }) => {
                print!("{}assignment-statement", self.get_indent());
            }
            StatementKind::Case(CaseStatement { .. }) => {
                print!("{}case-statement", self.get_indent());
            }
            StatementKind::Switch { .. } => {
                print!("{}switch-statement", self.get_indent());
            }
            StatementKind::Let {
                local_ref,
                type_hint: _,
                value: _,
            } => {
                print!(
                    "{}let-statement variable-name={}",
                    self.get_indent(),
                    refer(local_ref).borrow().name
                );
            }

            StatementKind::SetAttr {
                base: _,
                attr,
                value: _,
            } => {
                print!("{}set-attr-statement attr={}", self.get_indent(), attr);
            }

            StatementKind::SetIndex { .. } => {
                print!("{}set-index-statement", self.get_indent());
            }

            StatementKind::StoreLocal { local_ref, .. } => {
                print!(
                    "{}store-local-variable({})",
                    self.get_indent(),
                    refer(local_ref).borrow().name,
                );
            }
        }

        println!(" {}", statement.location);

        self.indent();
    }

    fn pre_expr(&mut self, expression: &mut Expression) {
        match &expression.kind {
            ExpressionKind::Undefined => {
                print!("{}undefined", self.get_indent());
            }
            ExpressionKind::Object(_) => {
                print!("{}ref", self.get_indent());
            }
            ExpressionKind::Call { .. } => {
                print!("{}call", self.get_indent());
            }
            /*
            ExpressionKind::MethodCall {
                instance,
                method,
                arguments,
            } => {
                print!("{}method-call method={}", self.get_indent(), method);
            }
            */
            ExpressionKind::Binop { op, .. } => {
                print!("{}Binary operation {:?}", self.get_indent(), op);
            }
            ExpressionKind::TypeCast { to_type, value: _ } => {
                print!("{}Type-cast to {}", self.get_indent(), to_type);
            }
            ExpressionKind::Literal(literal) => {
                self.print_literal(literal);
            }
            ExpressionKind::ObjectInitializer { .. } => {
                print!("{}Object-initializer", self.get_indent());
            }
            ExpressionKind::TupleLiteral { typ: _, values: _ } => {
                print!("{}Tuple-literal", self.get_indent());
            }
            ExpressionKind::UnionLiteral { attr, value: _ } => {
                print!("{}Union-literal: {}", self.get_indent(), attr);
            }
            ExpressionKind::EnumLiteral(EnumLiteral {
                enum_type: _,
                variant,
                arguments: _,
            }) => {
                print!(
                    "{}Enum-literal variant={}",
                    self.get_indent(),
                    variant.upgrade().unwrap().borrow().name
                );
            }
            ExpressionKind::ListLiteral(_values) => {
                print!("{}List-literal", self.get_indent());
            }

            ExpressionKind::LoadSymbol(symbol) => match symbol {
                Symbol::Parameter(param_ref) => {
                    print!(
                        "{}Load-parameter {}",
                        self.get_indent(),
                        refer(param_ref).borrow().name,
                    );
                }
                Symbol::LocalVariable(local_ref) => {
                    print!(
                        "{}Load-local({})",
                        self.get_indent(),
                        refer(local_ref).borrow().name,
                    );
                }
                Symbol::Function(func_ref) => {
                    print!(
                        "{}Load-symbol-function({})",
                        self.get_indent(),
                        refer(func_ref).borrow().name
                    );
                }
                Symbol::ExternFunction { name, typ: _ } => {
                    print!(
                        "{}Load-symbol-extern-function(name={})",
                        self.get_indent(),
                        name
                    );
                }

                Symbol::Typ(typ) => {
                    // SlangType::User(user) => match user {
                    //     UserType::Struct(struct_type) => {
                    //         print!("{}Load struct type {:?}", self.get_indent(), struct_type);
                    //     }
                    //     UserType::Enum(enum_type) => {
                    //         print!("{}Load enum type {:?}", self.get_indent(), enum_type);
                    //     }
                    //     UserType::Class(class_type) => {
                    //         let class_type = class_type.upgrade().unwrap();
                    //         print!(
                    //             "{}Load class type name={}, id={}",
                    //             self.get_indent(),
                    //             class_type.name,
                    //             class_type.id
                    //         );
                    //     }
                    // },
                    // other => {
                    print!("{}Load type {}", self.get_indent(), typ);
                    // }
                }

                other => {
                    print!("{}Load-symbol {}", self.get_indent(), other);
                }
            },
            // ExpressionKind::TypeConstructor(type_constructor) => {
            //     match type_constructor {
            //         other => {
            //             print!("{}type-constructor: {:?}", self.get_indent(), other);
            //         }
            /*
            TypeConstructor::Any(typ) => {
                println!("{}Type constructor (any): {:?}", self.get_indent(), typ);
            }
            TypeConstructor::EnumOption { enum_type, choice } => {
                println!(
                    "{}Type constructor (enum option) choice={} : {:?}",
                    self.get_indent(),
                    choice,
                    enum_type
                );
            }
            */
            //     }
            // }

            // ExpressionKind::Instantiate => {
            //     print!("{}Create instance", self.get_indent(),);
            // }
            // ExpressionKind::ImplicitSelf => {
            //     print!("{}self", self.get_indent());
            // }
            ExpressionKind::GetAttr { attr, .. } => {
                print!("{}get attr={}", self.get_indent(), attr);
            }
            ExpressionKind::GetIndex { .. } => {
                print!("{}get-index", self.get_indent());
            }
        }

        if let SlangType::Undefined = expression.typ {
        } else {
            print!(" type={}", expression.typ);
        }

        println!(" {}", expression.location);

        self.indent();
    }
}

impl VisitorApi for AstPrinter {
    fn pre_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::Program(program) => {
                println!("======== TYPED AST [{}] ============>>", program.name);
                /*
                for type_def in &prog.type_defs {
                    println!(
                        "{}type {} = {:?}",
                        self.get_indent(),
                        type_def.name,
                        type_def.typ
                    );
                }
                for class_def in &prog.class_defs {
                    self.print_class_def(class_def);
                }
                */
            }

            VisitedNode::Definition(definition) => {
                self.pre_definition(definition);
            }
            VisitedNode::Function(function_def) => {
                self.print_function(function_def);
            }
            VisitedNode::Statement(statement) => {
                self.pre_stmt(statement);
            }
            VisitedNode::CaseArm(_) => {
                println!("{}case-arm:", self.get_indent());
                self.indent();
            }
            VisitedNode::Expression(expression) => {
                self.pre_expr(expression);
            }
            VisitedNode::TypeExpr(_expression) => {
                // Does not print that nice:
                // println!("{}type-expr={}", self.get_indent(), expression);
            }
        }
    }

    fn post_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::Program(_) | VisitedNode::TypeExpr(_) => {}

            VisitedNode::Function(_) => {
                self.dedent();
            }
            VisitedNode::Definition(definition) => {
                self.post_definition(definition);
            }
            VisitedNode::Statement(_) => {
                self.dedent();
            }
            VisitedNode::CaseArm(_) => {
                self.dedent();
            }
            VisitedNode::Expression(_) => {
                self.dedent();
            }
        }
    }
}
