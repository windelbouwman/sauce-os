use super::refer;
use super::type_system::SlangType;
use super::typed_ast;
use super::visitor::{visit_program, VisitedNode, VisitorApi};
use super::Symbol;
use std::cell::RefCell;
use std::rc::Rc;

pub fn print_ast(program: &mut typed_ast::Program) {
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

    fn print_function(&mut self, function_def: &typed_ast::FunctionDef) {
        println!(
            "{}fn name={} id={} location={}",
            self.get_indent(),
            function_def.name,
            function_def.id,
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
                    "{}name={} id={} typ={}",
                    self.get_indent(),
                    parameter.name,
                    parameter.id,
                    parameter.typ
                );
            }
            self.dedent();
        }

        if let Some(return_type) = &signature.return_type {
            println!("{}Return type: {:?}", self.get_indent(), return_type);
        }

        if !function_def.locals.is_empty() {
            println!("{}locals:", self.get_indent());
            self.indent();
            for (index, local_ref) in function_def.locals.iter().enumerate() {
                let local_ref = local_ref.borrow();
                println!(
                    "{}index={} name={} id={} typ={}",
                    self.get_indent(),
                    index,
                    local_ref.name,
                    local_ref.id,
                    local_ref.typ,
                );
            }
            self.dedent();
        }

        println!("{}code:", self.get_indent());
    }

    fn print_literal(&self, literal: &typed_ast::Literal) {
        match literal {
            typed_ast::Literal::Bool(value) => {
                print!("{}Bool val={}", self.get_indent(), value);
            }
            typed_ast::Literal::Integer(value) => {
                print!("{}Integer val={}", self.get_indent(), value);
            }
            typed_ast::Literal::Float(value) => {
                print!("{}Float val={}", self.get_indent(), value);
            }
            typed_ast::Literal::String(value) => {
                print!("{}String val='{}'", self.get_indent(), value);
            }
        }
    }

    /// Print some additional attributes
    ///
    /*
    fn print_attributes(&self, node_id: typed_ast::NodeId) {
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

    fn pre_definition(&mut self, definition: &typed_ast::Definition) {
        match definition {
            typed_ast::Definition::Function(function_def) => {
                self.print_function(&function_def.borrow());
                self.indent();
            }

            typed_ast::Definition::Class(class_def) => {
                println!(
                    "{}class name={} id={}",
                    self.get_indent(),
                    class_def.name,
                    class_def.id
                );
                self.indent();
                self.print_fields(&class_def.fields);
            }
            typed_ast::Definition::Struct(struct_def) => {
                println!(
                    "{}struct name={} id={}",
                    self.get_indent(),
                    struct_def.name,
                    struct_def.id
                );

                self.indent();
                self.print_fields(&struct_def.fields);
            }
            typed_ast::Definition::Union(union_def) => {
                println!(
                    "{}union name={} id={}",
                    self.get_indent(),
                    union_def.name,
                    union_def.id
                );

                self.indent();
                self.print_fields(&union_def.fields);
            }

            // typed_ast::Definition::Field(field_def) => {

            // self.print_attributes(field_def.node_id);
            // }
            typed_ast::Definition::Enum(enum_def) => {
                println!(
                    "{}enum name={} id={}",
                    self.get_indent(),
                    enum_def.name,
                    enum_def.id
                );
                self.indent();
                for variant in &enum_def.variants {
                    let variant = variant.borrow();
                    println!("{}variant name={}", self.get_indent(), variant.name,);
                }
            }
        }
    }

    fn print_fields(&mut self, fields: &[Rc<RefCell<typed_ast::FieldDef>>]) {
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

    fn post_definition(&mut self, definition: &typed_ast::Definition) {
        match definition {
            typed_ast::Definition::Function(_) => {
                self.dedent();
                self.dedent();
            }
            typed_ast::Definition::Class(_) => {
                self.dedent();
            }
            typed_ast::Definition::Struct(_) | typed_ast::Definition::Union(_) => {
                self.dedent();
            }
            typed_ast::Definition::Enum(_) => {
                self.dedent();
            }
        }
    }

    fn pre_stmt(&mut self, statement: &mut typed_ast::Statement) {
        match &statement.kind {
            typed_ast::StatementKind::Break => {
                print!("{}break", self.get_indent());
            }
            typed_ast::StatementKind::Continue => {
                print!("{}continue", self.get_indent());
            }
            typed_ast::StatementKind::Unreachable => {
                print!("{}unreachable", self.get_indent());
            }
            typed_ast::StatementKind::Pass => {
                print!("{}pass", self.get_indent());
            }
            typed_ast::StatementKind::Return { .. } => {
                print!("{}return", self.get_indent());
            }
            typed_ast::StatementKind::If(typed_ast::IfStatement { .. }) => {
                print!("{}if-statement", self.get_indent());
            }
            typed_ast::StatementKind::While(typed_ast::WhileStatement { .. }) => {
                print!("{}while-statement", self.get_indent());
            }
            typed_ast::StatementKind::Loop { .. } => {
                print!("{}loop-statement", self.get_indent());
            }
            typed_ast::StatementKind::Compound(_) => {
                print!("{}compound-statement", self.get_indent());
            }
            typed_ast::StatementKind::For(typed_ast::ForStatement {
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
            typed_ast::StatementKind::Expression(_) => {
                print!("{}expression-statement", self.get_indent());
            }
            typed_ast::StatementKind::Assignment(typed_ast::AssignmentStatement { .. }) => {
                print!("{}assignment-statement", self.get_indent());
            }
            typed_ast::StatementKind::Case(typed_ast::CaseStatement { .. }) => {
                print!("{}case-statement", self.get_indent());
            }
            typed_ast::StatementKind::Switch { .. } => {
                print!("{}switch-statement", self.get_indent());
            }
            typed_ast::StatementKind::Let {
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

            typed_ast::StatementKind::SetAttr {
                base: _,
                attr,
                value: _,
            } => {
                print!("{}set-attr-statement attr={}", self.get_indent(), attr);
            }

            typed_ast::StatementKind::SetIndex { .. } => {
                print!("{}set-index-statement", self.get_indent());
            }

            typed_ast::StatementKind::StoreLocal { local_ref, .. } => {
                print!(
                    "{}store-local-variable(name={}, id={})",
                    self.get_indent(),
                    refer(local_ref).borrow().name,
                    refer(local_ref).borrow().id
                );
            }
        }

        println!(" {}", statement.location);

        self.indent();
    }

    fn pre_expr(&mut self, expression: &mut typed_ast::Expression) {
        match &expression.kind {
            typed_ast::ExpressionKind::Undefined => {
                print!("{}undefined", self.get_indent());
            }
            typed_ast::ExpressionKind::Object(_) => {
                print!("{}ref", self.get_indent());
            }
            typed_ast::ExpressionKind::Call { .. } => {
                print!("{}call", self.get_indent());
            }
            /*
            typed_ast::ExpressionKind::MethodCall {
                instance,
                method,
                arguments,
            } => {
                print!("{}method-call method={}", self.get_indent(), method);
            }
            */
            typed_ast::ExpressionKind::Binop { op, .. } => {
                print!("{}Binary operation {:?}", self.get_indent(), op);
            }
            typed_ast::ExpressionKind::TypeCast(_) => {
                print!("{}Type-cast", self.get_indent());
            }
            typed_ast::ExpressionKind::Literal(literal) => {
                self.print_literal(literal);
            }
            typed_ast::ExpressionKind::ObjectInitializer { .. } => {
                print!("{}Object-initializer", self.get_indent());
            }
            typed_ast::ExpressionKind::TupleLiteral(_values) => {
                print!("{}Tuple-literal", self.get_indent());
            }
            typed_ast::ExpressionKind::UnionLiteral { attr, value: _ } => {
                print!("{}Union-literal: {}", self.get_indent(), attr);
            }
            typed_ast::ExpressionKind::EnumLiteral(typed_ast::EnumLiteral {
                variant,
                arguments: _,
            }) => {
                print!(
                    "{}Enum-literal variant={}",
                    self.get_indent(),
                    variant.upgrade().unwrap().borrow().name
                );
            }
            typed_ast::ExpressionKind::ListLiteral(_values) => {
                print!("{}List-literal", self.get_indent());
            }

            typed_ast::ExpressionKind::LoadSymbol(symbol) => match symbol {
                Symbol::Parameter(param_ref) => {
                    print!(
                        "{}Load-parameter name={} id={}",
                        self.get_indent(),
                        refer(param_ref).borrow().name,
                        refer(param_ref).borrow().id
                    );
                }
                Symbol::LocalVariable(local_ref) => {
                    print!(
                        "{}Load-local(name={}, id={})",
                        self.get_indent(),
                        refer(local_ref).borrow().name,
                        refer(local_ref).borrow().id
                    );
                }
                Symbol::Function(func_ref) => {
                    print!(
                        "{}Load-symbol-function(name={}, id={})",
                        self.get_indent(),
                        refer(func_ref).borrow().name,
                        refer(func_ref).borrow().id
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
            // typed_ast::ExpressionKind::TypeConstructor(type_constructor) => {
            //     match type_constructor {
            //         other => {
            //             print!("{}type-constructor: {:?}", self.get_indent(), other);
            //         }
            /*
            typed_ast::TypeConstructor::Any(typ) => {
                println!("{}Type constructor (any): {:?}", self.get_indent(), typ);
            }
            typed_ast::TypeConstructor::EnumOption { enum_type, choice } => {
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

            // typed_ast::ExpressionKind::Instantiate => {
            //     print!("{}Create instance", self.get_indent(),);
            // }
            // typed_ast::ExpressionKind::ImplicitSelf => {
            //     print!("{}self", self.get_indent());
            // }
            typed_ast::ExpressionKind::GetAttr { attr, .. } => {
                print!("{}get attr={}", self.get_indent(), attr);
            }
            typed_ast::ExpressionKind::GetIndex { .. } => {
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
            VisitedNode::Generic(generic) => {
                // Ehm?
                let type_parameters: Vec<String> = generic
                    .type_parameters
                    .iter()
                    .map(|p| format!("{}", p))
                    .collect();
                println!(
                    "{}generic {} ({}):",
                    self.get_indent(),
                    generic.name,
                    type_parameters.join(",")
                );
                self.indent();
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
            VisitedNode::Generic(_) => {
                self.dedent();
            }

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
