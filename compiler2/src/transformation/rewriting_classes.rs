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

use crate::semantics::Context;
use crate::tast::{
    load_function, return_value, tuple_literal, undefined_value, Expression, ExpressionKind,
};
use crate::tast::{visit_program, VisitedNode, VisitorApi};
use crate::tast::{ClassDef, Definition, FunctionDef, FunctionSignature, Program};
use crate::tast::{NameNodeId, NodeId, Ref, Scope, Symbol};
use crate::tast::{SlangType, StructDefBuilder};
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::Arc;

pub fn rewrite_classes(program: &mut Program, context: &mut Context) {
    log::info!("Rewriting classes into structs and functions");
    let mut rewriter = ClassRewriter::new(context);
    visit_program(&mut rewriter, program);
}

struct ClassRewriter<'d> {
    context: &'d mut Context,
    new_definitions: Vec<Definition>,

    /// Mapping from enum types to tagged-union types!
    class_map: HashMap<NodeId, SlangType>,
    ctor_map: HashMap<NodeId, Ref<FunctionDef>>,
}

impl<'d> ClassRewriter<'d> {
    fn new(context: &'d mut Context) -> Self {
        Self {
            context,
            new_definitions: vec![],
            class_map: HashMap::new(),
            ctor_map: HashMap::new(),
        }
    }

    fn compile_class(&mut self, class_def: Rc<ClassDef>) {
        self.define_struct_type(&class_def);
        self.create_constructor(&class_def);
        self.transform_methods(&class_def);
    }

    fn define_struct_type(&mut self, class_def: &ClassDef) {
        let mut struct_builder = StructDefBuilder::new(class_def.name.name.clone(), self.new_id());

        for field in &class_def.fields {
            let field = field.borrow();
            struct_builder.add_field(&field.name, field.typ.clone());
        }

        let struct_def = struct_builder.finish();

        let struct_def = struct_def.into_def();
        let struct_ty = struct_def.create_type(vec![]);
        self.new_definitions.push(struct_def);

        self.class_map.insert(class_def.name.id, struct_ty);
    }

    /// Create constructor function
    fn create_constructor(&mut self, class_def: &ClassDef) {
        let struct_ty = self.class_map.get(&class_def.name.id).unwrap().clone();

        // let this_param = Rc::new(RefCell::new(Parameter {
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
                //     load_parameter(Rc::downgrade(&this_param))
                //         .set_attr(&field.name, init_value),
                // );
            } else {
                panic!("All class fields must initialize! (otherwise no tuple literal!)");
            }
        }
        let ctor_code = vec![return_value(tuple_literal(struct_ty.clone(), init_values))];

        let ctor_name = format!("{}_ctor", class_def.name.name);

        let signature = Rc::new(RefCell::new(FunctionSignature {
            parameters: vec![],
            return_type: Some(struct_ty.clone()),
        }));

        // TODO: fill something here:
        let type_parameters = vec![];

        let ctor_func = Rc::new(RefCell::new(FunctionDef {
            name: NameNodeId {
                name: ctor_name,
                id: self.new_id(),
            },
            location: class_def.location.clone(),
            type_parameters,
            this_param: None,
            body: ctor_code,
            scope: Arc::new(Scope::new()),
            signature,
            locals: vec![],
        }));

        self.ctor_map
            .insert(class_def.name.id, Rc::downgrade(&ctor_func));

        self.new_definitions.push(Definition::Function(ctor_func));
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
    fn transform_methods(&mut self, class_def: &ClassDef) {
        let struct_ty = self.class_map.get(&class_def.name.id).unwrap().clone();
        for method_ref in &class_def.methods {
            let mut method = method_ref.borrow_mut();

            // Take 'this' parameter and refer to struct instead of class
            let this_param = std::mem::take(&mut method.this_param).unwrap();
            this_param.borrow_mut().typ = struct_ty.clone();

            // Add first parameter as this:
            method
                .signature
                .borrow_mut()
                .parameters
                .insert(0, this_param);

            // Rename method:
            method.name.name = format!("{}_{}", class_def.name.name, method.name.name);

            self.new_definitions
                .push(Definition::Function(method_ref.clone()));
        }
    }

    fn lower_expression(&mut self, expression: &mut Expression) {
        match &mut expression.kind {
            ExpressionKind::Call { callee, arguments } => {
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
    fn transform_method_call(&self, callee: &mut Expression, arguments: &mut Vec<Expression>) {
        match &mut callee.kind {
            ExpressionKind::GetAttr { base, attr } => {
                let obj: Expression = std::mem::replace(base, undefined_value());
                let method = obj.typ.get_method(attr).unwrap();
                let method_func = load_function(Rc::downgrade(&method));

                arguments.insert(0, obj);
                *callee = method_func;
            }
            _ => {}
        }
    }

    /// Transform calls to constructor!
    ///
    fn transform_constructor_call(&self, callee: &mut Expression) {
        match &mut callee.kind {
            ExpressionKind::LoadSymbol(symbol) => match symbol {
                Symbol::Typ(typ) => {
                    let class_type = typ.as_class();
                    let class_def = class_type.class_ref.upgrade().unwrap();
                    let ctor_func = self.ctor_map.get(&class_def.name.id).unwrap();
                    *symbol = Symbol::Function(ctor_func.clone());
                }
                _ => {}
            },
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
                        Definition::Class(class_def) => {
                            self.compile_class(class_def.clone());
                        }
                        _ => {}
                    }
                }
                program.definitions.append(&mut self.new_definitions);
            }
            VisitedNode::TypeExpr(type_expr) => {
                if type_expr.is_class() {
                    let class_type = type_expr.as_class();
                    let class_def = class_type.class_ref.upgrade().unwrap();
                    let struct_type = self.class_map.get(&class_def.name.id).unwrap().clone();
                    *type_expr = struct_type;
                }
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
                    .retain(|d| !matches!(d, Definition::Class(_)));
            }
            VisitedNode::Expression(expression) => {
                self.lower_expression(expression);
            }
            _ => {}
        }
    }
}
