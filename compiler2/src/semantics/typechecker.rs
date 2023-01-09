use super::Diagnostics;
use crate::errors::CompilationError;
use crate::parsing::{ast, Location};
use crate::tast::{refer, undefined_value, Literal};
use crate::tast::{ArrayType, BasicType, ClassType, SlangType, UserType};
use crate::tast::{
    AssignmentStatement, CaseStatement, ForStatement, IfStatement, SwitchStatement, WhileStatement,
};
use crate::tast::{Definition, FieldDef, FunctionDef, FunctionSignature, Program, Symbol};
use crate::tast::{Expression, ExpressionKind, Statement, StatementKind, VariantRef};
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

/// Check the given program for type correctness.
pub fn check_types(program: &Program) -> Result<(), CompilationError> {
    log::debug!("Type checking!");
    let mut type_checker = TypeChecker::new(&program.path);
    type_checker.check_program(program);
    type_checker.diagnostics.value_or_error(())
}

struct TypeChecker {
    diagnostics: Diagnostics,
    function_signatures: Vec<Rc<RefCell<FunctionSignature>>>,
}

impl TypeChecker {
    fn new(path: &std::path::Path) -> Self {
        Self {
            diagnostics: Diagnostics::new(path),
            function_signatures: vec![],
        }
    }

    fn check_program(&mut self, program: &Program) {
        for definition in &program.definitions {
            match definition {
                Definition::Class(class_def) => {
                    for field in &class_def.fields {
                        self.check_field(field)
                    }

                    let class_typ = SlangType::User(UserType::Class(ClassType {
                        class_ref: Rc::downgrade(class_def),
                        type_arguments: vec![],
                    }));

                    for method in &class_def.methods {
                        let this_var = method.borrow().this_param.as_ref().unwrap().clone();
                        this_var.borrow_mut().typ = class_typ.clone();
                        self.check_function(method);
                    }
                }
                Definition::Struct(struct_def) => {
                    for field in &struct_def.fields {
                        self.check_field(field);
                    }
                }
                Definition::Enum(enum_def) => {
                    for variant in &enum_def.variants {
                        let variant = variant.borrow();
                        for payload_type in &variant.data {
                            self.check_type(&variant.location, payload_type);
                        }
                    }
                }
                Definition::Function(function_def) => {
                    self.check_function(function_def);
                }
            }
        }
    }

    fn check_type(&mut self, _location: &Location, _typ: &SlangType) {}

    fn check_field(&mut self, field_def: &Rc<RefCell<FieldDef>>) {
        let mut field = field_def.borrow_mut();
        self.check_type(&field.location, &field.typ);
        if let Some(value) = &mut field.value {
            self.check_expression(value).ok();
        }
    }

    fn check_function(&mut self, function_def: &Rc<RefCell<FunctionDef>>) {
        self.function_signatures
            .push(function_def.borrow().signature.clone());
        self.check_block(&mut function_def.borrow_mut().body);
        self.function_signatures.pop();
    }

    fn check_block(&mut self, block: &mut [Statement]) {
        for statement in block {
            self.check_statement(statement).ok();
        }
    }

    fn check_statement(&mut self, statement: &mut Statement) -> Result<(), ()> {
        match &mut statement.kind {
            StatementKind::Let {
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
            StatementKind::StoreLocal { local_ref, value } => {
                self.check_expression(value)?;
                let typ = self.get_type(value)?;
                // TODO: do we want to annotate the local or check against the type?
                refer(local_ref).borrow_mut().typ = typ;
                Ok(())
            }
            StatementKind::Assignment(AssignmentStatement { target, value }) => {
                self.check_expression(target)?;
                let target_type = self.get_type(target)?;
                self.coerce(&target_type, value)?;
                Ok(())
            }
            StatementKind::SetAttr {
                base,
                attr: _,
                value,
            } => {
                self.check_expression(base)?;
                self.check_expression(value)?;
                Ok(())
            }
            StatementKind::SetIndex { base, index, value } => {
                self.check_expression(base)?;
                self.check_expression(index)?;
                self.check_expression(value)?;
                Ok(())
            }
            StatementKind::Pass => Ok(()),
            StatementKind::Unreachable => Ok(()),
            StatementKind::Break | StatementKind::Continue => Ok(()),
            StatementKind::Return { value } => {
                let sig_ref = self.function_signatures.last().unwrap().clone();
                let signature = sig_ref.borrow();

                // Check return type:
                if let Some(value) = value {
                    self.check_expression(value)?;
                    if let Some(typ) = &signature.return_type {
                        self.check_equal_types(&statement.location, typ, &value.typ)?;
                    } else {
                        self.error(
                            &statement.location,
                            "Function does not return anything".to_owned(),
                        );
                    }
                } else if let Some(typ) = &signature.return_type {
                    self.error(
                        &statement.location,
                        format!("Return nothing, but expected: {}", typ),
                    );
                }

                Ok(())
            }
            StatementKind::For(ForStatement {
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

            StatementKind::If(IfStatement {
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
            StatementKind::Loop { body } => {
                self.check_block(body);
                Ok(())
            }
            StatementKind::Compound(block) => {
                self.check_block(block);
                Ok(())
            }
            StatementKind::While(WhileStatement { condition, body }) => {
                self.check_condition(condition)?;
                self.check_block(body);
                Ok(())
            }
            StatementKind::Switch(SwitchStatement {
                value,
                arms,
                default,
            }) => {
                self.coerce(&SlangType::int(), value)?;
                for arm in arms {
                    self.coerce(&SlangType::int(), &mut arm.value)?;
                    self.check_block(&mut arm.body);
                }
                self.check_block(default);
                Ok(())
            }
            StatementKind::Case(case_statement) => {
                self.check_case_statement(&statement.location, case_statement)?;
                Ok(())
            }

            StatementKind::Expression(expression) => {
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
        case_statement: &mut CaseStatement,
    ) -> Result<(), ()> {
        self.check_expression(&mut case_statement.value)?;

        let value_type = &case_statement.value.typ;
        // Check if the case type is an enum type:
        // let enum_type = self.use_as_enum_type(&case_statement.value)?;
        if !value_type.is_enum() {
            self.error(
                &case_statement.value.location,
                format!("Expected enum type, not {}", value_type),
            );
            return Err(());
        }

        let enum_type = value_type.as_enum();

        // Check for:
        // - duplicate arms
        // - and for missing arms
        // - correct amount of constructor arguments
        let mut value_map: HashMap<usize, bool> = HashMap::new();

        for arm in &mut case_statement.arms {
            // Ensure we referred to an enum constructor
            let variant_ref = match &arm.variant {
                VariantRef::Variant(variant) => {
                    let variant_ref = variant.upgrade().unwrap();
                    variant_ref
                }
                VariantRef::Name(variant_name) => {
                    // We refer to the enum variant by name, lookup the name in the enum.
                    let variant_ref = enum_type.lookup_variant(variant_name);
                    if let Some(variant_ref) = variant_ref {
                        arm.variant = VariantRef::Variant(Rc::downgrade(&variant_ref));
                        variant_ref
                    } else {
                        self.error(
                            &arm.location,
                            format!("Enum has no variant named: {}", variant_name),
                        );
                        continue;
                    }
                }
            };

            let variant = variant_ref.borrow();

            // Check for arm compatibility:
            // self.check_equal_types(
            //     &arm.location,
            //     &case_statement.value.typ,
            //     &variant.get_parent_type(),
            // )?;

            // Check for duplicate arms:
            if value_map.contains_key(&variant.index) {
                self.error(&arm.location, format!("Duplicate field: {}", variant.name));
                continue;
            } else {
                value_map.insert(variant.index, true);
            }

            let arg_types: Vec<SlangType> = enum_type.get_variant_data_types(variant.index);

            // Check for number of payload variables:
            if arg_types.len() == arm.local_refs.len() {
                for (arg_typ, local_ref) in arg_types.into_iter().zip(arm.local_refs.iter()) {
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

            self.check_block(&mut arm.body);
        }

        // Check if all cases are covered:
        let mut missed_variants = vec![];
        for variant in enum_type.get_variants() {
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

    /*
    fn use_as_enum_type(&mut self, value: &Expression) -> Result<Rc<EnumDef>, ()> {
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
    */

    /// Type check the given expression.
    ///
    /// Annotate the given expression with a type
    fn check_expression(&mut self, expression: &mut Expression) -> Result<(), ()> {
        match &mut expression.kind {
            ExpressionKind::Call { callee, arguments } => {
                self.check_expression(callee)?;
                let callee_type = self.get_type(callee)?;
                match callee_type {
                    SlangType::User(UserType::Function(function_type)) => {
                        let function_type = function_type.borrow();
                        let parameter_types: Vec<SlangType> = function_type
                            .parameters
                            .iter()
                            .map(|p| p.borrow().typ.clone())
                            .collect();
                        self.check_call_arguments(
                            &expression.location,
                            &parameter_types,
                            arguments,
                        )?;

                        let return_type: SlangType = function_type
                            .return_type
                            .as_ref()
                            .cloned()
                            .unwrap_or(SlangType::Void);
                        expression.typ = return_type;
                        Ok(())
                    }

                    SlangType::TypeConstructor(_t) => {
                        match &callee.kind {
                            // ExpressionKind::TypeConstructor(type_constructor) => {
                            //     unimplemented!("{:?}", type_constructor);
                            // match type_constructor {
                            //     TypeConstructor::ClassRef(class_node_id) => {
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
                            ExpressionKind::LoadSymbol(Symbol::EnumVariant(_variant)) => {
                                /*
                                let variant_rc = variant.upgrade().unwrap();
                                let variant = variant_rc.borrow();
                                self.check_call_arguments(
                                    &expression.location,
                                    &variant.data,
                                    arguments,
                                )?;

                                // std::mem::replace(
                                expression.kind =
                                    ExpressionKind::EnumLiteral(EnumLiteral {
                                        variant: Rc::downgrade(&variant_rc),
                                        arguments: std::mem::take(arguments),
                                    });
                                    // );
                                    expression.typ = variant.get_parent_type();

                                    Ok(())
                                    */
                                panic!("Should not reach this point!");
                            }
                            _other => {
                                panic!("No go");
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
                        SlangType::bool()
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
                            common_type = SlangType::float();
                        }
                        Self::autoconv(lhs, &common_type);
                        Self::autoconv(rhs, &common_type);
                        common_type
                    }
                    ast::BinaryOperator::Logic(_logic_op) => {
                        self.check_condition(lhs)?;
                        self.check_condition(rhs)?;
                        SlangType::bool()
                    }
                    ast::BinaryOperator::Bit(_op) => {
                        unimplemented!();
                    }
                };
                Ok(())
            }
            ExpressionKind::TypeCast { value, to_type } => {
                // TODO: Check for some valid castings.
                self.check_expression(value)?;
                expression.typ = to_type.clone();
                Ok(())
            }
            ExpressionKind::Literal(value) => {
                expression.typ = SlangType::Basic(match value {
                    Literal::Bool(_) => BasicType::Bool,
                    Literal::Integer(_) => BasicType::Int,
                    Literal::String(_) => BasicType::String,
                    Literal::Float(_) => BasicType::Float,
                });
                Ok(())
            }

            ExpressionKind::ObjectInitializer { typ: _, fields: _ } => {
                panic!("Object initializer should be squashed before.");
            }
            ExpressionKind::TupleLiteral { typ, values } => {
                let struct_type = typ.as_struct();
                let fields = struct_type.get_struct_fields();
                assert_eq!(values.len(), fields.len());
                for (field, value) in fields.iter().zip(values.iter_mut()) {
                    self.coerce(&field.1, value)?;
                }
                expression.typ = typ.clone();
                Ok(())
            }

            ExpressionKind::UnionLiteral { typ, attr, value } => {
                let union_type = expression.typ.as_struct();
                assert!(union_type.is_union());
                if let Some(wanted_typ) = union_type.get_attr_type(attr) {
                    self.coerce(&wanted_typ, value)?;
                    expression.typ = typ.clone();
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
                let data_types = enum_literal
                    .enum_type
                    .get_variant_data_types(enum_variant_ref.borrow().index);
                self.check_call_arguments(
                    &expression.location,
                    &data_types,
                    &mut enum_literal.arguments,
                )?;
                expression.typ = enum_literal.enum_type.clone().into();
                Ok(())
            }

            ExpressionKind::LoadSymbol(symbol) => match symbol {
                Symbol::LocalVariable(_)
                | Symbol::Parameter(_)
                | Symbol::Function(_)
                | Symbol::ExternFunction { .. } => {
                    expression.typ = symbol.get_type();
                    Ok(())
                }
                Symbol::Typ(typ) => {
                    expression.typ = SlangType::TypeConstructor(Box::new(typ.clone()));
                    Ok(())
                }
                Symbol::Module(_) => {
                    self.error(&expression.location, "cannot load module".to_string());
                    Err(())
                }
                Symbol::Definition(_) => {
                    self.error(&expression.location, "cannot load definition".to_string());
                    Err(())
                }
                Symbol::Field(_) => {
                    unimplemented!("Load field: Unlikely that this will ever happen.");
                }
                Symbol::EnumVariant(_variant) => {
                    // expression.typ = SlangType::TypeConstructor(Box::new(
                    //     variant.upgrade().unwrap().borrow().get_parent_type(),
                    // ));
                    // Ok(())
                    unimplemented!("Ehm, now what?");
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
                        self.coerce(&SlangType::int(), index)?;
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
                if let Some(typ) = base.typ.get_attr_type(attr) {
                    expression.typ = typ;
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

    /// Check if a condition is boolean type.
    fn check_condition(&mut self, condition: &mut Expression) -> Result<(), ()> {
        self.check_expression(condition)?;
        let actual_type = self.get_type(condition)?;
        self.check_equal_types(&condition.location, &SlangType::bool(), &actual_type)
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
            let old_value = std::mem::replace(value, undefined_value());
            *value = old_value.cast(wanted_typ.clone());
            value.typ = wanted_typ.clone();
        }
    }

    fn common_sub_type(
        &mut self,
        location: &Location,
        type1: &SlangType,
        type2: &SlangType,
    ) -> Result<SlangType, ()> {
        match (type1, type2) {
            (SlangType::Basic(BasicType::Float), SlangType::Basic(BasicType::Int)) => {
                Ok(SlangType::float())
            }
            (SlangType::Basic(BasicType::Int), SlangType::Basic(BasicType::Float)) => {
                Ok(SlangType::float())
            }
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
