/*
Rewrite generics using type erasure, and insert type casting at the proper
places.

Basically there is two ways to implement generics:
- Templates / code expansion: (example languages: C++)
- type erasure: Java, C#

Tasks involved in type erasure:
- replace generic struct with

 */

// use super::type_system::{SlangType, UserType};
use super::generics::get_substitution_map;
use super::type_system::SlangType;
use super::typed_ast::{self, Definition, FunctionDef, Program};
use super::visitor::{visit_program, VisitedNode, VisitorApi};
use super::{Context, NodeId};
use std::collections::HashMap;

pub fn rewrite_generics(program: &mut Program, context: &mut Context) {
    log::info!("Erasing types, where generics are involved");
    let mut rewriter = GenericRewriter::new(context);
    visit_program(&mut rewriter, program);
}

struct GenericRewriter<'d> {
    context: &'d mut Context,
    new_definitions: Vec<Definition>,
    type_map: HashMap<NodeId, SlangType>,
}

impl<'d> GenericRewriter<'d> {
    fn new(context: &'d mut Context) -> Self {
        Self {
            context,
            new_definitions: vec![],
            type_map: HashMap::new(),
        }
    }

    /// Modify definitions and rewrite types used
    fn update_definition(&self, definition: &Definition) {
        match definition {
            Definition::Struct(struct_def) => {
                for field in &struct_def.fields {
                    self.update_type(&mut field.borrow_mut().typ);
                }
            }
            Definition::Function(function_def) => {
                self.update_function(&function_def.borrow());
            }
            _ => {}
        }
    }

    fn update_function(&self, function_def: &FunctionDef) {
        log::trace!(
            "Rewrite types in function parameters: {}",
            function_def.name
        );
        let signature = function_def.signature.borrow();
        for parameter in &signature.parameters {
            self.update_type(&mut parameter.borrow_mut().typ);
        }
    }

    /// Look at several constructs:
    ///
    /// - Get-attr:
    ///     check if we get an attribute of a bound-generic
    ///     and upcast the opaque pointer
    /// - Object initializer:
    ///     Check if we initialize a bound generic
    ///     Cast specifics to opaque pointers.
    fn update_expression(&self, expression: &mut typed_ast::Expression) {
        match &mut expression.kind {
            typed_ast::ExpressionKind::GetAttr { base, attr } => {
                if let SlangType::GenericInstance(generic_instance) = &base.typ {
                    // If we get an attribute which is a type var
                    // Introduce a cast from opaque, to the concrete type.

                    // Store original type with generic info, this is required for later get-attrs..
                    // A bit lame to do it like this ..
                    let original_expr_type = expression.typ.clone();

                    let generic = generic_instance.get_def();
                    let attr_typ = generic.get_attr(attr).expect("We checked this").get_type();

                    if let SlangType::TypeVar(type_var) = attr_typ {
                        let type_var_map = generic_instance.get_substitution_map();
                        let mut typ = type_var_map
                            .get(&type_var.ptr.upgrade().unwrap().name)
                            .cloned()
                            .expect("We checked!");
                        self.update_type(&mut typ);

                        // Patch expression!
                        let expr2 = std::mem::take(expression);
                        *expression = expr2.cast(typ);
                        expression.typ = original_expr_type;
                    }
                }
            }
            typed_ast::ExpressionKind::TupleLiteral(_) => {
                // self.update_type(&mut expression.typ);
            }
            typed_ast::ExpressionKind::ObjectInitializer { typ, fields } => {
                // Initialization of an object, by a set of named fields!
                if let SlangType::GenericInstance(generic_instance) = typ {
                    // If we initialize a bound generic, we need to do something.
                    // let base_struct = generic.get_def().base.as_struct();

                    // let target_type = typ.get_struct_fields().unwrap();

                    // Insert type-casts of some field values.
                    // println!("On object init: {:?}", typ);
                    for field in fields {
                        // println!("Field: {} = {:?}", field.name, field.value);
                        let attr_type = generic_instance.get_attr(&field.name).unwrap().get_type();
                        if let SlangType::TypeVar(_var_type_ref) = attr_type {
                            // If we initialize a field whose type is a type variable
                            // Transform this initial value into an opaque pointer.
                            let old_value = *std::mem::take(&mut field.value);
                            field.value = Box::new(old_value.cast(SlangType::Opaque));
                        }
                    }
                }

                self.update_type(typ);
            }
            _ => {}
        }
    }

    /// Do two things:
    ///
    /// - Replace type variable by an opaque type (void*)
    /// - Replace Generic instances, by the concrete type for this generic.
    fn update_type(&self, typ: &mut SlangType) {
        match typ {
            SlangType::GenericInstance(generic_instance) => {
                // Okay, if we refer to a generic instance, replace with opaque generic type!
                *typ = self
                    .type_map
                    .get(&generic_instance.get_def().id)
                    .unwrap()
                    .clone();
            }
            SlangType::TypeVar(_) => {
                // Replace type variables with opaque pointers!
                *typ = SlangType::Opaque;
            }
            _ => {}
        }
    }

    #[allow(dead_code)]
    fn new_id(&mut self) -> NodeId {
        self.context.id_generator.gimme()
    }
}

impl<'d> VisitorApi for GenericRewriter<'d> {
    fn pre_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::Program(program) => {
                // Promote internal definitions from generics to
                // top level definition
                for generic in &program.generics {
                    // Take each generic, and move it up a notch:
                    let new_def = generic.base.clone();
                    let new_type = new_def.create_type();
                    self.type_map.insert(generic.id, new_type);
                    self.new_definitions.push(new_def);
                }

                program.definitions.append(&mut self.new_definitions);
            }
            VisitedNode::Definition(_definition) => {
                // match definition {
                // typed_ast::Definition::
                // }
            }
            VisitedNode::Expression(expression) => {
                // Update own type:
                // self.update_type(&mut expression.typ);
            }
            VisitedNode::TypeExpr(_type_expr) => {
                // self.update_type(type_expr);
            }
            VisitedNode::Statement(statement) => match &statement.kind {
                typed_ast::StatementKind::Case(_case_statement) => {
                    panic!("Unsupported, case statements must be rewritten first.");
                }
                _ => {}
            },
            _ => {}
        }
    }

    fn post_node(&mut self, node: VisitedNode) {
        match node {
            VisitedNode::Program(program) => {
                for definition in &program.definitions {
                    self.update_definition(definition);
                }

                // Strip out all generics!
                // program.generics.clear();
            }
            VisitedNode::Expression(expression) => {
                self.update_expression(expression);
            }
            VisitedNode::Function(function_def) => {
                self.update_function(function_def);
            }
            _ => {}
        }
    }
}
