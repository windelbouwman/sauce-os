use super::refer;
use super::symbol::Symbol;
use super::type_system::{ArrayType, SlangType, UserType};
use super::typed_ast;
use super::typed_ast::{Expression, ExpressionKind};
use super::Diagnostics;
use crate::errors::CompilationError;
use crate::parsing::ast;
use crate::parsing::Location;
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

/// Check the given program for type correctness.
pub fn check_types(program: &typed_ast::Program) -> Result<(), CompilationError> {
    log::debug!("Type checking!");
    let mut type_checker = TypeChecker::new(&program.path);
    type_checker.check_program(program);
    type_checker.diagnostics.value_or_error(())
}

struct TypeChecker {
    diagnostics: Diagnostics,
}

impl TypeChecker {
    fn new(path: &std::path::Path) -> Self {
        Self {
            diagnostics: Diagnostics::new(path),
        }
    }

    fn check_program(&mut self, program: &typed_ast::Program) {
        for definition in &program.definitions {
            match definition {
                typed_ast::Definition::Class(class_def) => {
                    for field in &class_def.fields {
                        self.check_field(field)
                    }

                    for method in &class_def.methods {
                        let this_var = method.borrow().this_param.as_ref().unwrap().clone();
                        this_var.borrow_mut().typ =
                            SlangType::User(UserType::Class(Rc::downgrade(&class_def)));
                        self.check_function(method);
                    }
                }
                typed_ast::Definition::Struct(struct_def) => {
                    for field in &struct_def.fields {
                        self.check_field(field);
                    }
                }
                typed_ast::Definition::Union(union_def) => {
                    for field in &union_def.fields {
                        self.check_field(field);
                    }
                }
                typed_ast::Definition::Enum(_enum_def) => {
                    // unimplemented!();
                }
                typed_ast::Definition::Function(function_def) => {
                    self.check_function(function_def);
                }
            }
        }
    }

    fn check_field(&mut self, field_def: &Rc<RefCell<typed_ast::FieldDef>>) {
        let mut field = field_def.borrow_mut();
        if let Some(value) = &mut field.value {
            self.check_expression(value).ok();
        }
    }

    fn check_function(&mut self, function_def: &Rc<RefCell<typed_ast::FunctionDef>>) {
        self.check_block(&mut function_def.borrow_mut().body);
    }

    fn check_block(&mut self, block: &mut [typed_ast::Statement]) {
        for statement in block {
            self.check_statement(statement).ok();
        }
    }

    fn check_statement(&mut self, statement: &mut typed_ast::Statement) -> Result<(), ()> {
        match &mut statement.kind {
            typed_ast::StatementKind::Let {
                local_ref,
                type_hint,
                value,
            } => {
                let typ = if let Some(type_hint) = type_hint {
                    self.coerce(type_hint, value)?;
                    type_hint.clone()
                } else {
                    self.check_expression(value)?;
                    self.get_type(value)?
                };
                refer(local_ref).borrow_mut().typ = typ;
                Ok(())
            }
            typed_ast::StatementKind::StoreLocal { local_ref, value } => {
                self.check_expression(value)?;
                let typ = self.get_type(value)?;
                // TODO: do we want to annotate the local or check against the type?
                refer(local_ref).borrow_mut().typ = typ;
                Ok(())
            }
            typed_ast::StatementKind::Assignment(typed_ast::AssignmentStatement {
                target,
                value,
            }) => {
                self.check_expression(target)?;
                let target_type = self.get_type(target)?;
                self.coerce(&target_type, value)?;
                Ok(())
            }
            typed_ast::StatementKind::SetAttr {
                base,
                attr: _,
                value,
            } => {
                self.check_expression(base)?;
                self.check_expression(value)?;
                Ok(())
            }
            typed_ast::StatementKind::SetIndex { base, index, value } => {
                self.check_expression(base)?;
                self.check_expression(index)?;
                self.check_expression(value)?;
                Ok(())
            }
            typed_ast::StatementKind::Pass => Ok(()),
            typed_ast::StatementKind::Unreachable => Ok(()),
            typed_ast::StatementKind::Break | typed_ast::StatementKind::Continue => Ok(()),
            typed_ast::StatementKind::Return { value } => {
                if let Some(value) = value {
                    self.check_expression(value)?;
                }
                // TODO: check return type
                Ok(())
            }
            typed_ast::StatementKind::For(typed_ast::ForStatement {
                iterable,
                loop_var,
                body,
            }) => {
                self.check_expression(iterable)?;
                match &iterable.typ {
                    SlangType::Array(array_type) => {
                        let iterated_typ = *array_type.element_type.clone();
                        loop_var.upgrade().unwrap().borrow_mut().typ = iterated_typ;
                    }
                    other => {
                        self.error(&statement.location, format!("Cannot loop over {}", other));
                        return Err(());
                    }
                };
                self.check_block(body);
                Ok(())
            }

            typed_ast::StatementKind::If(typed_ast::IfStatement {
                condition,
                if_true,
                if_false,
            }) => {
                self.check_condition(condition)?;
                self.check_block(if_true);
                if let Some(if_false) = if_false {
                    self.check_block(if_false);
                }
                Ok(())
            }
            typed_ast::StatementKind::Loop { body } => {
                self.check_block(body);
                Ok(())
            }
            typed_ast::StatementKind::Compound(block) => {
                self.check_block(block);
                Ok(())
            }
            typed_ast::StatementKind::While(typed_ast::WhileStatement { condition, body }) => {
                self.check_condition(condition)?;
                self.check_block(body);
                Ok(())
            }
            typed_ast::StatementKind::Switch(typed_ast::SwitchStatement {
                value,
                arms,
                default,
            }) => {
                self.coerce(&SlangType::Int, value)?;
                for arm in arms {
                    self.coerce(&SlangType::Int, &mut arm.value)?;
                    self.check_block(&mut arm.body);
                }
                self.check_block(default);
                Ok(())
            }
            typed_ast::StatementKind::Case(case_statement) => {
                self.check_case_statement(&statement.location, case_statement)?;
                Ok(())
            }

            typed_ast::StatementKind::Expression(expression) => {
                // TBD: check for VOID value now?
                self.check_expression(expression)?;
                Ok(())
            }
        }
    }

    /// Check a case-statement.
    ///
    /// This construct should match all variants of the enum.
    fn check_case_statement(
        &mut self,
        location: &Location,
        case_statement: &mut typed_ast::CaseStatement,
    ) -> Result<(), ()> {
        self.check_expression(&mut case_statement.value)?;

        // Check if the case type is an enum type:
        let enum_type = self.use_as_enum_type(&case_statement.value)?;

        // Check for:
        // - duplicate arms
        // - and for missing arms
        // - correct amount of constructor arguments
        let mut value_map: HashMap<usize, bool> = HashMap::new();

        for arm in &mut case_statement.arms {
            // Ensure we referred to an enum constructor
            match &arm.constructor.kind {
                // ExpressionKind::TypeConstructor(
                //     typed_ast::TypeConstructor::EnumVariant(variant),
                // )
                ExpressionKind::LoadSymbol(Symbol::EnumVariant(variant)) => {
                    let variant_ref = variant.upgrade().unwrap();
                    let variant = variant_ref.borrow();

                    // Check for arm compatibility:
                    self.check_equal_types(
                        &arm.location,
                        &case_statement.value.typ,
                        &variant.get_parent_type(),
                    )?;

                    // Check for duplicate arms:
                    if value_map.contains_key(&variant.index) {
                        self.error(&arm.location, format!("Duplicate field: {}", variant.name));
                    } else {
                        value_map.insert(variant.index, true);

                        let arg_types: Vec<SlangType> = variant.data.clone();

                        // Check for number of payload variables:
                        if arg_types.len() == arm.local_refs.len() {
                            for (arg_typ, local_ref) in
                                arg_types.into_iter().zip(arm.local_refs.iter())
                            {
                                local_ref.upgrade().unwrap().borrow_mut().typ = arg_typ;
                            }
                        } else {
                            self.error(
                                &arm.location,
                                format!(
                                    "Got {} constructor arguments, but expected {}",
                                    arm.local_refs.len(),
                                    arg_types.len()
                                ),
                            );
                        }
                    }
                }
                other => {
                    // Err!
                    self.error(
                        &arm.location,
                        format!("Expected enum variant constructor, not {:?}", other),
                    );
                }
            }

            self.check_block(&mut arm.body);
        }

        // Check if all cases are covered:
        let mut missed_variants = vec![];
        for variant in &enum_type.variants {
            if !value_map.contains_key(&variant.borrow().index) {
                missed_variants.push(variant.borrow().name.clone());
            }
        }
        if !missed_variants.is_empty() {
            self.error(
                location,
                format!("Enum case '{:?}' not covered", missed_variants),
            );
        }

        Ok(())
    }

    fn use_as_enum_type(&mut self, value: &Expression) -> Result<Rc<typed_ast::EnumDef>, ()> {
        if let SlangType::User(UserType::Enum(enum_type)) = &value.typ {
            Ok(enum_type.upgrade().unwrap())
        } else {
            self.error(
                &value.location,
                format!("Expected enum type, not {}", value.typ),
            );
            Err(())
        }
    }

    /// Type check the given expression.
    ///
    /// Annotate the given expression with a type
    fn check_expression(&mut self, expression: &mut Expression) -> Result<(), ()> {
        match &mut expression.kind {
            ExpressionKind::Call { callee, arguments } => {
                self.check_expression(callee)?;
                let callee_type = self.get_type(callee)?;
                match callee_type {
                    SlangType::Function(function_type) => {
                        self.check_call_arguments(
                            &expression.location,
                            &function_type.argument_types,
                            arguments,
                        )?;
                        let return_type: SlangType = function_type
                            .return_type
                            .map(|t| *t)
                            .unwrap_or(SlangType::Void);
                        expression.typ = return_type;
                        Ok(())
                    }

                    SlangType::TypeConstructor => {
                        match &callee.kind {
                            // ExpressionKind::TypeConstructor(type_constructor) => {
                            //     unimplemented!("{:?}", type_constructor);
                            // match type_constructor {
                            //     typed_ast::TypeConstructor::ClassRef(class_node_id) => {
                            // let typ = SlangType::Class(*class_node_id);
                            // Ok(typ)
                            //     }
                            // }
                            // }
                            ExpressionKind::LoadSymbol(Symbol::Typ(typ)) => match typ {
                                SlangType::User(UserType::Class(_)) => {
                                    expression.typ = typ.clone();
                                    Ok(())
                                }
                                other => {
                                    self.error(
                                        &expression.location,
                                        format!("Cannot call type: {}", other),
                                    );
                                    Err(())
                                }
                            },
                            ExpressionKind::LoadSymbol(Symbol::EnumVariant(variant)) => {
                                let variant_rc = variant.upgrade().unwrap();
                                let variant = variant_rc.borrow();
                                self.check_call_arguments(
                                    &expression.location,
                                    &variant.data,
                                    arguments,
                                )?;

                                // std::mem::replace(
                                expression.kind =
                                    ExpressionKind::EnumLiteral(typed_ast::EnumLiteral {
                                        variant: Rc::downgrade(&variant_rc),
                                        arguments: std::mem::take(arguments),
                                    });
                                // );
                                expression.typ = variant.get_parent_type();

                                Ok(())
                            }
                            other => {
                                panic!("No go: {:?}", other);
                            }
                        }
                    }

                    other => {
                        self.error(&expression.location, format!("Cannot call: {} ", other));
                        Err(())
                    }
                }
            }
            // ExpressionKind::MethodCall {
            //     instance,
            //     method,
            //     arguments,
            // } => self.check_method_call(&expression.location, instance, method, arguments),
            ExpressionKind::Undefined => {
                // panic!("Should not happen!");
                // Ehh, what now?
                Ok(())
            }
            ExpressionKind::Object(_) => {
                panic!("Should be resolved before type checking.");
            }
            ExpressionKind::Binop { lhs, op, rhs } => {
                expression.typ = match &op {
                    ast::BinaryOperator::Comparison(_compare_op) => {
                        self.check_expression(lhs)?;
                        self.check_expression(rhs)?;
                        let lhs_typ = self.get_type(lhs)?;
                        let rhs_typ = self.get_type(rhs)?;
                        self.check_equal_types(&expression.location, &lhs_typ, &rhs_typ)?;
                        SlangType::Bool
                    }
                    ast::BinaryOperator::Math(math_op) => {
                        self.check_expression(lhs)?;
                        self.check_expression(rhs)?;

                        let lhs_typ = self.get_type(lhs)?;
                        let rhs_typ = self.get_type(rhs)?;
                        let mut common_type =
                            self.common_sub_type(&expression.location, &lhs_typ, &rhs_typ)?;

                        let is_div = matches!(math_op, ast::MathOperator::Div);
                        if is_div && common_type.is_int() {
                            common_type = SlangType::Float;
                        }
                        Self::autoconv(lhs, &common_type);
                        Self::autoconv(rhs, &common_type);
                        common_type
                    }
                    ast::BinaryOperator::Logic(_logic_op) => {
                        self.check_condition(lhs)?;
                        self.check_condition(rhs)?;
                        SlangType::Bool
                    }
                    ast::BinaryOperator::Bit(_op) => {
                        unimplemented!();
                    }
                };
                Ok(())
            }
            ExpressionKind::TypeCast(_value) => {
                // TODO: Check for some valid castings.
                Ok(())
            }
            ExpressionKind::Literal(value) => {
                expression.typ = match value {
                    typed_ast::Literal::Bool(_) => SlangType::Bool,
                    typed_ast::Literal::Integer(_) => SlangType::Int,
                    typed_ast::Literal::String(_) => SlangType::String,
                    typed_ast::Literal::Float(_) => SlangType::Float,
                };
                Ok(())
            }

            ExpressionKind::ObjectInitializer { typ, fields } => {
                self.check_struct_literal(&expression.location, typ, fields)?;
                // struct_literal_to_tuple
                expression.typ = typ.clone();
                Ok(())
            }
            ExpressionKind::TupleLiteral(values) => {
                let struct_ref = expression.typ.as_struct();
                assert_eq!(values.len(), struct_ref.fields.len());
                for (field, value) in struct_ref.fields.iter().zip(values.iter_mut()) {
                    let field = field.borrow();
                    self.coerce(&field.typ, value)?;
                }
                Ok(())
            }

            ExpressionKind::UnionLiteral { attr, value } => {
                let union_ref = expression.typ.as_union();
                if let Some(field) = union_ref.get_field(attr) {
                    let field = field.borrow();
                    self.coerce(&field.typ, value)?;
                    Ok(())
                } else {
                    self.error(
                        &expression.location,
                        format!("Union has no attribute '{}'", attr),
                    );
                    Err(())
                }
            }

            ExpressionKind::ListLiteral(values) => {
                assert!(!values.is_empty());

                let mut value_iter = values.iter_mut();
                let first_value = value_iter.next().unwrap();
                self.check_expression(first_value)?;
                let element_typ = self.get_type(first_value)?;
                for value in value_iter {
                    self.coerce(&element_typ, value)?;
                }
                expression.typ = SlangType::Array(ArrayType {
                    element_type: Box::new(element_typ),
                    size: values.len(),
                });

                Ok(())
            }

            ExpressionKind::EnumLiteral(enum_literal) => {
                let enum_variant_ref = enum_literal.variant.upgrade().unwrap();
                self.check_call_arguments(
                    &expression.location,
                    &enum_variant_ref.borrow().data,
                    &mut enum_literal.arguments,
                )?;
                Ok(())
            }

            ExpressionKind::LoadSymbol(symbol) => match symbol {
                Symbol::ExternFunction { name: _, typ } => {
                    expression.typ = typ.clone();
                    Ok(())
                }
                Symbol::Parameter(param_ref) => {
                    expression.typ = refer(param_ref).borrow().typ.clone();
                    Ok(())
                }
                Symbol::LocalVariable(local_ref) => {
                    expression.typ = refer(local_ref).borrow().typ.clone();
                    Ok(())
                }
                Symbol::Function(func_ref) => {
                    // TODO: function type might not be super nice to use ..
                    let function_type = refer(func_ref).borrow().get_type();
                    expression.typ = function_type;
                    Ok(())
                }
                Symbol::Typ(_typ) => {
                    expression.typ = SlangType::TypeConstructor;
                    Ok(())
                }
                Symbol::Module(_) => {
                    self.error(&expression.location, "cannot load module".to_string());
                    Err(())
                }
                Symbol::Generic(_) => {
                    self.error(
                        &expression.location,
                        "cannot load type template / generic".to_string(),
                    );
                    Err(())
                }
                Symbol::Field(_) => {
                    unimplemented!("Load field: Unlikely that this will ever happen.");
                }
                Symbol::EnumVariant(_variant) => {
                    expression.typ = SlangType::TypeConstructor;
                    Ok(())
                }
            },

            // ExpressionKind::TypeConstructor(_type_constructor) => {
            //     unimplemented!("Type-con?");
            // type_constructor
            // let typ = SlangType::TypeConstructor;
            // Ok(typ)
            // }
            ExpressionKind::GetIndex { base, index } => {
                self.check_expression(base)?;
                match &base.typ {
                    SlangType::Array(array_type) => {
                        self.coerce(&SlangType::Int, index)?;
                        expression.typ = *array_type.element_type.clone();
                        Ok(())
                    }
                    other => {
                        self.error(
                            &expression.location,
                            format!("Cannot array-index non-array '{}' type.", other),
                        );
                        Err(())
                    }
                }
            }

            ExpressionKind::GetAttr { base, attr } => {
                self.check_expression(base)?;
                if let Some(symbol) = base.typ.get_attr(attr) {
                    expression.typ = match symbol {
                        Symbol::Field(field_ref) => {
                            field_ref.upgrade().unwrap().borrow().typ.clone()
                        }
                        Symbol::Function(func_ref) => {
                            func_ref.upgrade().unwrap().borrow().get_type()
                        }
                        other => {
                            panic!("Unexpected user-type member: {}", other);
                        }
                    };
                    Ok(())
                } else {
                    self.error(
                        &expression.location,
                        format!("Type '{}' has no attribute '{}'", base.typ, attr),
                    );
                    Err(())
                }
            }
        }
    }

    /*
    fn check_method_call(
        &mut self,
        location: &Location,
        instance: &Expression,
        method: &str,
        arguments: &[Expression],
    ) -> Result<SlangType, ()> {
        unimplemented!();
        let instance_type = self.get_type(instance)?;
        match instance_type {
            SlangType::Class(class_node_id) => {
                let method = self.get_class_attr(node_id, class_node_id, method)?;
                match method {
                    Symbol::Function {
                        name: _,
                        node_id: function_node_id,
                    } => {
                        let method_type: FunctionType = self
                            .context
                            .get_type(function_node_id)
                            .clone()
                            .into_function_type();

                        self.check_call_arguments(
                            location,
                            &method_type.argument_types,
                            arguments,
                        )?;
                        let return_type: SlangType = method_type
                            .return_type
                            .map(|t| *t)
                            .unwrap_or(SlangType::Void);
                        Ok(return_type)
                    }
                    other => {
                        self.error(location, format!("Cannot call: {:?}", other));
                        Err(())
                    }
                }
            }
            other => {
                self.error(location, format!("Cannot call method on: {:?} ", other));
                Err(())
            }
        }
    }
    */
    /// Check number of arguments and type of each argument.
    fn check_call_arguments(
        &mut self,
        location: &Location,
        argument_types: &[SlangType],
        arguments: &mut [Expression],
    ) -> Result<(), ()> {
        if argument_types.len() == arguments.len() {
            for (arg_typ, argument) in argument_types.iter().zip(arguments.iter_mut()) {
                self.coerce(arg_typ, argument).ok();
            }
            Ok(())
        } else {
            self.error(
                location,
                format!(
                    "Expected {}, but got {} arguments ",
                    argument_types.len(),
                    arguments.len()
                ),
            );
            Err(())
        }
    }

    /// Check struct initialization.
    ///
    /// Checks:
    /// - missing fields
    /// - extra fields
    /// - duplicate fields
    /// - field types
    fn check_struct_literal(
        &mut self,
        location: &Location,
        typ: &SlangType,
        fields: &mut [typed_ast::LabeledField],
    ) -> Result<(), ()> {
        match typ {
            SlangType::User(UserType::Struct(struct_ref)) => {
                // Get a firm hold to the struct type:
                let struct_ref = struct_ref.upgrade().unwrap();
                // List if fields that must be filled:
                let mut required_fields: HashMap<String, SlangType> = HashMap::new();

                for field in &struct_ref.fields {
                    let field_name = field.borrow().name.clone();
                    let field_type = field.borrow().typ.clone();
                    required_fields.insert(field_name, field_type);
                }

                let mut ok = true;

                for field in fields {
                    if required_fields.contains_key(&field.name) {
                        let wanted_typ = required_fields
                            .remove(&field.name)
                            .expect("Has this key, we checked above");
                        self.coerce(&wanted_typ, &mut field.value)?;
                    } else {
                        // Error here on duplicate and non-existing fields
                        self.error(
                            &field.location,
                            format!("Superfluous field: {}", field.name),
                        );
                        ok = false;
                    }
                }

                // Check missed fields:
                for field in required_fields.keys() {
                    self.error(location, format!("Missing field: {}", field));
                    ok = false;
                }

                if ok {
                    Ok(())
                } else {
                    Err(())
                }
            }
            other => {
                self.error(location, format!("Must be struct type, not {}", other));
                Err(())
            }
        }
    }

    /// Check if a condition is boolean type.
    fn check_condition(&mut self, condition: &mut Expression) -> Result<(), ()> {
        self.check_expression(condition)?;
        let actual_type = self.get_type(condition)?;
        self.check_equal_types(&condition.location, &SlangType::Bool, &actual_type)
    }

    /// Get the type of an expression.
    fn get_type(&self, expression: &Expression) -> Result<SlangType, ()> {
        if let SlangType::Undefined = &expression.typ {
            Err(())
        } else {
            Ok(expression.typ.clone())
        }
    }

    /// Try to fit an expression onto the given type.
    ///
    /// Also determine the type of the expression after coercion.
    ///
    /// Future: insert automatic conversion
    fn coerce(&mut self, wanted_typ: &SlangType, value: &mut Expression) -> Result<(), ()> {
        self.check_expression(value)?;

        // Insert automatic conversion:
        if wanted_typ.is_float() && value.typ.is_int() {
            Self::autoconv(value, wanted_typ);
        }

        self.check_equal_types(&value.location, wanted_typ, &value.typ)?;
        Ok(())
    }

    /// Auto convert!
    fn autoconv(value: &mut Expression, wanted_typ: &SlangType) {
        if &value.typ != wanted_typ {
            log::trace!("Autoconving! {} -> {}", value.typ, wanted_typ);
            let old_value = std::mem::replace(value, typed_ast::undefined_value());
            *value = old_value.cast(wanted_typ.clone());
        }
    }

    fn common_sub_type(
        &mut self,
        location: &Location,
        type1: &SlangType,
        type2: &SlangType,
    ) -> Result<SlangType, ()> {
        match (type1, type2) {
            (SlangType::Float, SlangType::Int) => Ok(SlangType::Float),
            (SlangType::Int, SlangType::Float) => Ok(SlangType::Float),
            _ => {
                self.check_equal_types(location, type1, type2)?;
                Ok(type1.clone())
            }
        }
    }

    /// Check if two types are equal, and if not, emit an error message.
    fn check_equal_types(
        &mut self,
        location: &Location,
        expected: &SlangType,
        actual: &SlangType,
    ) -> Result<(), ()> {
        if expected == actual {
            Ok(())
        } else {
            self.error(
                location,
                format!("Expected {}, but got {}", expected, actual),
            );
            Err(())
        }
    }

    /// Emit given error message for this node.
    fn error(&mut self, location: &Location, message: String) {
        self.diagnostics.error(location.clone(), message);
    }
}
