//! Pass to rewrite classes into structs and functions.
//!
//! Transform class definition.
//!
//! class Foo:
//!     bar: str = "W00t"
//!
//!     fn info():
//!         std::print(this.bar)
//!
//! Becomes:
//!
//! struct Foo:
//!     bar: str
//!
//! fn Foo_ctor() -> Foo:
//!     let this = Foo:
//!         bar = "W00t"
//!     return this
//!
//! fn Foo_info(this: Foo):
//!     std::print(this.bar)
//!

use super::type_system::{SlangType, UserType};
use super::typed_ast;
use super::visitor::{visit_program, VisitedNode, VisitorApi};
use super::{Context, NodeId, Ref, Scope, Symbol};
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::Arc;

pub fn rewrite_classes(program: &mut typed_ast::Program, context: &mut Context) {
    log::info!("Rewriting classes into structs and functions");
    let mut rewriter = ClassRewriter::new(context);
    visit_program(&mut rewriter, program);
}

struct ClassRewriter<'d> {
    context: &'d mut Context,
    new_definitions: Vec<typed_ast::Definition>,

    /// Mapping from enum types to tagged-union types!
    enum_map: HashMap<NodeId, SlangType>,
    ctor_map: HashMap<NodeId, Ref<typed_ast::FunctionDef>>,
}

impl<'d> ClassRewriter<'d> {
    fn new(context: &'d mut Context) -> Self {
        Self {
            context,
            new_definitions: vec![],
            enum_map: HashMap::new(),
            ctor_map: HashMap::new(),
        }
    }

    fn compile_class(&mut self, class_def: Rc<typed_ast::ClassDef>) {
        self.define_struct_type(&class_def);
        self.create_constructor(&class_def);
        self.transform_methods(&class_def);
    }

    fn define_struct_type(&mut self, class_def: &typed_ast::ClassDef) {
        let mut struct_builder =
            typed_ast::StructDefBuilder::new(class_def.name.clone(), self.new_id());

        for field in &class_def.fields {
            let field = field.borrow();
            struct_builder.add_field(&field.name, field.typ.clone());
        }

        let struct_def = struct_builder.finish_struct();

        let struct_def = Rc::new(struct_def);
        let struct_ty = SlangType::User(UserType::Struct(Rc::downgrade(&struct_def)));
        self.new_definitions
            .push(typed_ast::Definition::Struct(struct_def));

        self.enum_map.insert(class_def.id, struct_ty.clone());
    }

    /// Create constructor function
    fn create_constructor(&mut self, class_def: &typed_ast::ClassDef) {
        let struct_ty = self.enum_map.get(&class_def.id).unwrap().clone();

        // let this_param = Rc::new(RefCell::new(typed_ast::Parameter {
        //     name: "this".to_owned(),
        //     id: self.new_id(),
        //     location: Default::default(),
        //     typ: struct_ty.clone(),
        // }));

        let mut init_values = vec![];
        for field in &class_def.fields {
            let mut field = field.borrow_mut();
            if let Some(init_value) = std::mem::take(&mut field.value) {
                init_values.push(init_value);
                // ctor_code.push(
                //     typed_ast::load_parameter(Rc::downgrade(&this_param))
                //         .set_attr(&field.name, init_value),
                // );
            } else {
                panic!("All class fields must initialize! (otherwise no tuple literal!)");
            }
        }
        let ctor_code = vec![typed_ast::return_value(typed_ast::tuple_literal(
            struct_ty.clone(),
            init_values,
        ))];

        let ctor_name = format!("{}_ctor", class_def.name);

        let ctor_func = Rc::new(RefCell::new(typed_ast::FunctionDef {
            name: ctor_name,
            id: self.new_id(),
            location: class_def.location.clone(),
            body: ctor_code,
            scope: Arc::new(Scope::new()),
            parameters: vec![],
            locals: vec![],
            return_type: Some(struct_ty.clone()),
        }));

        self.ctor_map
            .insert(class_def.id, Rc::downgrade(&ctor_func));

        self.new_definitions
            .push(typed_ast::Definition::Function(ctor_func));
    }

    /// transform methods
    ///
    /// class Bar:
    ///     fn foo():
    ///         pass
    ///
    /// into:
    ///
    /// fn Bar_foo(this: Bar):   # Bar is struct type
    ///     passs
    fn transform_methods(&mut self, class_def: &typed_ast::ClassDef) {
        let struct_ty = self.enum_map.get(&class_def.id).unwrap().clone();
        for method_ref in &class_def.methods {
            // Create 'this' parameter to refer to struct itself
            let this_param = Rc::new(RefCell::new(typed_ast::Parameter {
                name: "this".to_owned(),
                id: self.new_id(),
                location: Default::default(),
                typ: struct_ty.clone(),
            }));

            // Add first parameter as this:
            let mut method = method_ref.borrow_mut();
            method.parameters.insert(0, this_param.clone());
            method.name = format!("{}_{}", class_def.name, method.name);

            self.new_definitions
                .push(typed_ast::Definition::Function(method_ref.clone()));
        }
    }

    fn lower_expression(&mut self, expression: &mut typed_ast::Expression) {
        match &mut expression.kind {
            typed_ast::ExpressionKind::Call { callee, arguments } => {
                self.transform_method_call(callee, arguments);
                self.transform_constructor_call(callee);
            }
            _ => {}
        }
    }

    /// Transform method call into function call with base as first argument!
    ///
    ///     obj.do_thing(a, b, c)
    ///
    /// becomes:
    ///     do_thing(obj, a, b, c)
    fn transform_method_call(
        &self,
        callee: &mut typed_ast::Expression,
        arguments: &mut Vec<typed_ast::Expression>,
    ) {
        let res: Option<(typed_ast::Expression, typed_ast::Expression)> = match &mut callee.kind {
            typed_ast::ExpressionKind::GetAttr { base, attr } => {
                let obj: typed_ast::Expression =
                    std::mem::replace(base, typed_ast::undefined_value());
                let method = obj.typ.get_method(attr).unwrap();
                let method_func = typed_ast::load_function(Rc::downgrade(&method));
                Some((method_func, obj))
            }
            _ => None,
        };

        if let Some((method_func, obj)) = res {
            arguments.insert(0, obj);
            *callee = method_func;
        }
    }

    /// Transform calls to constructor!
    ///
    fn transform_constructor_call(&self, callee: &mut typed_ast::Expression) {
        match &mut callee.kind {
            typed_ast::ExpressionKind::LoadSymbol(symbol) => {
                let new_sym = match symbol {
                    Symbol::Typ(typ) => {
                        let class_def = typ.as_class();
                        let ctor_func = self.ctor_map.get(&class_def.id).unwrap();
                        Some(Symbol::Function(ctor_func.clone()))
                    }
                    _ => None,
                };

                if let Some(s) = new_sym {
                    *symbol = s;
                }
            }
            _ => {}
        }
    }

    /// Create a new unique ID
    fn new_id(&mut self) -> NodeId {
        self.context.id_generator.gimme()
    }
}

impl<'d> VisitorApi for ClassRewriter<'d> {
    fn pre_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::Program(program) => {
                for definition in &program.definitions {
                    match definition {
                        typed_ast::Definition::Class(class_def) => {
                            self.compile_class(class_def.clone());
                        }
                        _ => {}
                    }
                }
                program.definitions.append(&mut self.new_definitions);
            }
            _ => {}
        }
    }

    fn post_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::Program(program) => {
                // remove all classes from definitions:
                program
                    .definitions
                    .retain(|d| !matches!(d, typed_ast::Definition::Class(_)));
            }
            VisitedNode::Expression(expression) => {
                self.lower_expression(expression);
            }
            _ => {}
        }
    }
}
