//! Transform a typed ast into some byte-code ish format
//!
//! Idea section:
//! - introduce a de-sugar phase, to eliminate wildly complicated contraptions on source level.

use super::bytecode;
use super::bytecode::Instruction;
use super::parsing::ast;
use crate::tast;
use crate::tast::{refer, ArrayType, BasicType, NodeId, SlangType, Symbol, UserType};
use std::collections::HashMap;
use std::rc::Rc;

/// Compile a typed ast into bytecode.
pub fn generate_bytecode(progs: &[Rc<tast::Program>]) -> bytecode::Program {
    log::info!("Generating IR bytecode");
    let mut generator = Generator::new();
    for prog in progs {
        generator.gen_prog(prog)
    }

    generator.take_program()
}

#[derive(Hash, Eq, PartialEq, Clone)]
struct Label {
    name: usize,
}

struct Generator {
    imports: Vec<bytecode::Import>,
    imported: HashMap<String, bool>,
    functions: Vec<bytecode::Function>,
    instructions: Vec<Instruction>,
    id_counter: usize,
    loop_stack: Vec<(Label, Label)>,
    types: Vec<bytecode::TypeDef>,
    type_to_id_map: HashMap<bytecode::TypeDef, usize>,
    type_to_id_map2: HashMap<tast::NodeId, usize>,
    index_map: HashMap<NodeId, usize>,
    label_map: HashMap<Label, usize>,
    relocations: Vec<Relocation>,
}

enum Relocation {
    Jump {
        pc: usize,
        label: Label,
    },
    JumpIf {
        pc: usize,
        true_label: Label,
        false_label: Label,
    },
    JumpSwitch {
        pc: usize,
        default: Label,
        options: Vec<(i64, Label)>,
    },
}

impl Generator {
    fn new() -> Self {
        Generator {
            imports: vec![],
            imported: HashMap::new(),
            functions: vec![],
            instructions: vec![],
            id_counter: 0,
            loop_stack: vec![],
            types: vec![],
            type_to_id_map: HashMap::new(),
            type_to_id_map2: HashMap::new(),
            index_map: HashMap::new(),
            label_map: HashMap::new(),
            relocations: vec![],
        }
    }

    fn gen_prog(&mut self, prog: &tast::Program) {
        // First fill typedefs
        for definition in &prog.definitions {
            match definition {
                tast::Definition::Struct(struct_def) => {
                    self.type_to_id_map2
                        .insert(struct_def.name.id, self.types.len());
                    self.types.push(bytecode::TypeDef::invalid());
                }
                tast::Definition::Union(union_def) => {
                    self.type_to_id_map2
                        .insert(union_def.name.id, self.types.len());
                    self.types.push(bytecode::TypeDef::invalid());
                }
                _ => {}
            }
        }

        for definition in &prog.definitions {
            match definition {
                tast::Definition::Struct(struct_def) => {
                    let mut bytecode_field_types: Vec<bytecode::Typ> = vec![];
                    for field_ref in struct_def.fields.iter() {
                        // self.index_map.insert(*f_id, index);
                        let field_type = self.get_bytecode_typ(&field_ref.borrow().typ);
                        bytecode_field_types.push(field_type);
                    }

                    let name = struct_def.name.name.clone();

                    let typ = bytecode::TypeDef::Struct(bytecode::StructDef {
                        name: Some(name),
                        fields: bytecode_field_types,
                    });

                    self.types[self.type_to_id_map2[&struct_def.name.id]] = typ;
                }
                tast::Definition::Union(union_def) => {
                    let mut choices: Vec<bytecode::Typ> = vec![];
                    for field_ref in union_def.fields.iter() {
                        let field_type = self.get_bytecode_typ(&field_ref.borrow().typ);
                        choices.push(field_type);
                    }
                    let name = union_def.name.name.clone();

                    let union_typ = bytecode::TypeDef::Union(bytecode::UnionDef { name, choices });

                    self.types[self.type_to_id_map2[&union_def.name.id]] = union_typ;
                }
                _ => {}
            }
        }

        for definition in &prog.definitions {
            match definition {
                tast::Definition::Function(function) => {
                    self.gen_func(&function.borrow());
                }
                tast::Definition::Class(class_def) => {
                    panic!(
                        "IR-gen does not support classes, like '{}'. Elimenate those earlier on.",
                        class_def.name
                    );
                }
                tast::Definition::Struct(_struct_def) => {
                    // ?
                }
                tast::Definition::Union(_union_def) => {
                    // ?
                }
                tast::Definition::Enum(enum_def) => {
                    panic!(
                        "IR-gen does not enum types, like '{}'. Elimenate those earlier on.",
                        enum_def.name
                    );
                }
            }
        }
    }

    fn take_program(&mut self) -> bytecode::Program {
        self.imported.clear();

        bytecode::Program {
            imports: std::mem::take(&mut self.imports),
            types: std::mem::take(&mut self.types),
            functions: std::mem::take(&mut self.functions),
        }
    }

    fn import_external(&mut self, func_name: String, import_typ: SlangType) {
        if self.imported.contains_key(&func_name) {
            return;
        } else {
            self.imported.insert(func_name.clone(), true);
        }

        match import_typ {
            SlangType::User(UserType::Function(signature)) => {
                let signature = signature.borrow();
                let bc_import = bytecode::Import {
                    name: func_name,
                    parameter_types: signature
                        .parameters
                        .iter()
                        .map(|p| self.get_bytecode_typ(&p.borrow().typ))
                        .collect(),
                    return_type: signature
                        .return_type
                        .as_ref()
                        .map(|t| self.get_bytecode_typ(t)),
                };
                self.imports.push(bc_import);
            }
            other => {
                unimplemented!("Not implemented: {}", other);
            }
        }
    }

    fn gen_func(&mut self, func: &tast::FunctionDef) {
        log::debug!("Gen code for {}", func.name);

        self.label_map.clear();

        // Create parameter space
        let signature = func.signature.borrow();
        let mut parameters: Vec<bytecode::Parameter> = vec![];
        for (index, parameter) in signature.parameters.iter().enumerate() {
            let typ = parameter.borrow().typ.clone();
            let name = parameter.borrow().name.name.clone();
            self.index_map.insert(parameter.borrow().name.id, index);
            parameters.push(bytecode::Parameter {
                name,
                typ: self.get_bytecode_typ(&typ),
            });
        }

        // let f_typ = func.get_type().clone().into_function_type();
        let return_type = signature
            .return_type
            .as_ref()
            .map(|t| self.get_bytecode_typ(t));

        // Create local space:
        let mut locals = vec![];
        for (index, local_ref) in func.locals.iter().enumerate() {
            let typ = local_ref.borrow().typ.clone();
            let name = local_ref.borrow().name.name.clone();
            self.index_map.insert(local_ref.borrow().name.id, index);
            locals.push(bytecode::Local {
                name,
                typ: self.get_bytecode_typ(&typ),
            });
        }

        self.gen_block(&func.body);

        // Hmm, a bit of a hack, to inject a void return here ..
        // If either:
        // - no instructions
        // - last instruction is not a terminator
        if self
            .instructions
            .last()
            .map(|i| !i.is_terminator())
            .unwrap_or(true)
        {
            self.emit(Instruction::Return(0));
        }

        self.resolve_relocations();

        let instructions = std::mem::take(&mut self.instructions);
        self.functions.push(bytecode::Function {
            name: func.name.name.clone(),
            parameters,
            return_type,
            locals,
            code: instructions,
        })
    }

    fn gen_block(&mut self, block: &tast::Block) {
        for statement in block {
            self.gen_statement(statement);
        }
    }

    fn gen_statement(&mut self, statement: &tast::Statement) {
        match &statement.kind {
            tast::StatementKind::SetAttr { base, attr, value } => match &base.typ {
                SlangType::User(UserType::Struct(struct_type)) => {
                    let field2 = struct_type
                        .struct_ref
                        .upgrade()
                        .unwrap()
                        .get_field(attr)
                        .unwrap();
                    let field = field2.borrow();
                    self.gen_expression(base);
                    self.gen_expression(value);
                    self.emit(Instruction::SetAttr { index: field.index });
                }
                other => {
                    panic!("Base type must be structured type, not {}.", other);
                }
            },

            tast::StatementKind::SetIndex { base, index, value } => {
                self.gen_expression(base);
                self.gen_expression(index);
                self.gen_expression(value);
                self.emit(Instruction::SetElement);
            }

            tast::StatementKind::StoreLocal { local_ref, value } => {
                self.gen_expression(value);
                let index: usize = *self
                    .index_map
                    .get(&refer(local_ref).borrow().name.id)
                    .unwrap();
                self.emit(Instruction::StoreLocal { index });
            }
            tast::StatementKind::Let { .. } => {
                unimplemented!("let-statement not supported, please use store-local");
            }
            tast::StatementKind::Assignment(_) => {
                unimplemented!("assignment not supported, please use store-local or set-attr");
            }
            tast::StatementKind::Break => {
                let target_label = self.loop_stack.last().unwrap().1.clone();
                self.jump(target_label);
            }
            tast::StatementKind::Continue => {
                let target_label = self.loop_stack.last().unwrap().0.clone();
                self.jump(target_label);
            }
            tast::StatementKind::Pass => {}
            tast::StatementKind::Unreachable => {
                // TODO: think about unreachable code?
            }
            tast::StatementKind::Return { value } => self.gen_return_statement(value),
            tast::StatementKind::Case(_case_statement) => {
                // self.gen_case_statement(case_statement)
                unimplemented!("case statements must be rewritten into switch statements before reaching this phase.");
            }
            tast::StatementKind::Switch(switch_statement) => {
                self.gen_switch_statement(switch_statement);
            }
            tast::StatementKind::For(_) => {
                unimplemented!(
                    "for-loops not supported, please rewrite into something else, like a while loop."
                );
            }
            tast::StatementKind::If(if_statement) => self.gen_if_statement(if_statement),
            tast::StatementKind::Loop { body } => self.gen_loop(body),
            tast::StatementKind::Compound(block) => {
                self.gen_block(block);
            }
            tast::StatementKind::While(while_statement) => {
                self.gen_while_statement(while_statement)
            }
            tast::StatementKind::Expression(expression) => {
                self.gen_expression(expression);
            }
        }
    }

    fn gen_return_statement(&mut self, value: &Option<tast::Expression>) {
        if let Some(value) = value {
            self.gen_expression(value);
            self.emit(Instruction::Return(1));
        } else {
            self.emit(Instruction::Return(0));
        }
        // TBD: generate a new label here?
    }

    fn gen_switch_statement(&mut self, switch_statement: &tast::SwitchStatement) {
        let final_label = self.new_label();
        let default_label = self.new_label();

        let mut options: Vec<(i64, Label)> = vec![];
        let mut arm_labels: Vec<Label> = vec![];
        for arm in &switch_statement.arms {
            let arm_label = self.new_label();
            // Many assumptions here:
            // - value is constant
            // - value has no duplicate in other arms
            let arm_value: i64 = arm.value.eval().into_i64();
            options.push((arm_value, arm_label.clone()));
            arm_labels.push(arm_label);
        }

        // Emit switch jump based upon stack value.
        self.gen_expression(&switch_statement.value);
        self.jump_table(default_label.clone(), options);

        // Generate code for each arm
        for (arm_label, arm) in arm_labels.into_iter().zip(switch_statement.arms.iter()) {
            self.set_label(arm_label);
            self.gen_block(&arm.body);
            self.jump(final_label.clone());
        }

        // default case:
        self.set_label(default_label);
        self.gen_block(&switch_statement.default);
        self.jump(final_label.clone());

        self.set_label(final_label);
        self.emit(Instruction::Nop);
    }

    fn gen_if_statement(&mut self, if_statement: &tast::IfStatement) {
        let true_label = self.new_label();
        let final_label = self.new_label();
        if let Some(if_false) = &if_statement.if_false {
            let false_label = self.new_label();
            self.gen_condition(
                &if_statement.condition,
                true_label.clone(),
                false_label.clone(),
            );

            self.set_label(true_label);
            self.gen_block(&if_statement.if_true);
            self.jump(final_label.clone());

            self.set_label(false_label);
            self.gen_block(if_false);
        } else {
            self.gen_condition(
                &if_statement.condition,
                true_label.clone(),
                final_label.clone(),
            );

            self.set_label(true_label);
            self.gen_block(&if_statement.if_true);
        }
        self.jump(final_label.clone());
        self.set_label(final_label);
        self.emit(Instruction::Nop);
    }

    fn gen_loop(&mut self, body: &tast::Block) {
        let loop_start_label = self.new_label();
        let final_label = self.new_label();
        self.jump(loop_start_label.clone());
        self.set_label(loop_start_label.clone());
        self.loop_stack
            .push((loop_start_label.clone(), final_label.clone()));
        self.gen_block(body);
        self.loop_stack.pop();
        self.jump(loop_start_label);
        self.set_label(final_label);
        self.emit(Instruction::Nop);
    }

    fn gen_while_statement(&mut self, while_statement: &tast::WhileStatement) {
        let loop_start_label = self.new_label();
        let true_label = self.new_label();
        let final_label = self.new_label();
        self.jump(loop_start_label.clone());
        self.set_label(loop_start_label.clone());
        self.gen_condition(
            &while_statement.condition,
            true_label.clone(),
            final_label.clone(),
        );
        self.set_label(true_label);
        self.loop_stack
            .push((loop_start_label.clone(), final_label.clone()));
        self.gen_block(&while_statement.body);
        self.loop_stack.pop();
        self.jump(loop_start_label);
        self.set_label(final_label);
        self.emit(Instruction::Nop);
    }

    /// Generate bytecode for condition statement.
    fn gen_condition(
        &mut self,
        expression: &tast::Expression,
        true_label: Label,
        false_label: Label,
    ) {
        // TODO: add 'not' operator
        match &expression.kind {
            tast::ExpressionKind::Binop {
                lhs,
                op: ast::BinaryOperator::Logic(op2),
                rhs,
            } => {
                // Implement short-circuit logic for 'or' and 'and'
                let middle_label = self.new_label();
                match op2 {
                    ast::LogicOperator::And => {
                        self.gen_condition(lhs, middle_label.clone(), false_label.clone());
                        self.set_label(middle_label);
                        self.gen_condition(rhs, true_label, false_label);
                    }
                    ast::LogicOperator::Or => {
                        self.gen_condition(lhs, true_label.clone(), middle_label.clone());
                        self.set_label(middle_label);
                        self.gen_condition(rhs, true_label, false_label);
                    }
                }
            }
            _ => {
                // Fall back to evaluation an expression!
                self.gen_expression(expression);
                self.jump_if(true_label, false_label);
            }
        }
    }

    /// Insert type into the type table in de-duplicating manner
    fn inject_type(&mut self, typ: bytecode::TypeDef) -> usize {
        if self.type_to_id_map.contains_key(&typ) {
            *self.type_to_id_map.get(&typ).unwrap()
        } else {
            let idx = self.types.len();
            self.types.push(typ.clone());
            self.type_to_id_map.insert(typ, idx);
            idx
        }
    }

    fn get_struct_index(&self, struct_def: Rc<tast::StructDef>) -> usize {
        *self.type_to_id_map2.get(&struct_def.name.id).unwrap()
    }

    fn get_union_index(&self, union_def: Rc<tast::UnionDef>) -> usize {
        *self.type_to_id_map2.get(&union_def.name.id).unwrap()
    }

    fn get_array_index(&mut self, array_type: &ArrayType) -> usize {
        let element_type = self.get_bytecode_typ(&array_type.element_type);
        let array_typ = bytecode::TypeDef::Array {
            size: array_type.size,
            element_type,
        };

        self.inject_type(array_typ)
    }

    fn get_bytecode_typ(&mut self, ty: &SlangType) -> bytecode::Typ {
        match ty {
            SlangType::Basic(basic_type) => match basic_type {
                BasicType::Bool => bytecode::Typ::Bool,
                BasicType::Int => bytecode::Typ::Int,
                BasicType::Float => bytecode::Typ::Float,
                BasicType::String => bytecode::Typ::String,
            },
            SlangType::Undefined => {
                panic!("Undefined type");
            }
            SlangType::Unresolved(_) => {
                panic!("AARG");
            }
            SlangType::User(user_type) => self.get_bytecode_typ_for_user_type(user_type),
            SlangType::Array(array_type) => bytecode::Typ::Ptr(Box::new(bytecode::Typ::Composite(
                self.get_array_index(array_type),
            ))),
            // SlangType::Generic { .. } => {
            //     panic!("Cannot compile generic type");
            // }
            SlangType::TypeConstructor(typ) => {
                panic!("Cannot compile type constructor:{}", typ);
            }
            SlangType::Opaque => {
                // A "void*" type
                bytecode::Typ::Ptr(Box::new(bytecode::Typ::Void))
            }
            SlangType::Void => bytecode::Typ::Void,
            SlangType::TypeVar(v) => {
                panic!("Cannot compile type variable {}", v);
            }
        }
    }

    /// Get bytecode type for the given user type
    fn get_bytecode_typ_for_user_type(&mut self, user_type: &UserType) -> bytecode::Typ {
        match user_type {
            UserType::Struct(struct_type) => {
                let composite_id: usize =
                    self.get_struct_index(struct_type.struct_ref.upgrade().unwrap());
                bytecode::Typ::Ptr(Box::new(bytecode::Typ::Composite(composite_id)))
            }
            UserType::Union(union_type) => {
                let composite_id: usize =
                    self.get_union_index(union_type.union_ref.upgrade().unwrap());
                bytecode::Typ::Ptr(Box::new(bytecode::Typ::Composite(composite_id)))
            }
            UserType::Enum(_) => {
                panic!("Cannot handle enum-types, please rewrite in tagged unions");
            }
            UserType::Class(_) => {
                panic!("Cannot handle class-types");
            }
            UserType::Function(signature) => {
                let signature = signature.borrow();

                let mut parameters = vec![];
                for parameter in &signature.parameters {
                    parameters.push(self.get_bytecode_typ(&parameter.borrow().typ));
                }
                let result = if let Some(t) = &signature.return_type {
                    Some(Box::new(self.get_bytecode_typ(t)))
                } else {
                    None
                };
                // TBD: we might want to store this as a forward definition, and refer by ID.
                bytecode::Typ::Function { parameters, result }
            }
        }
    }

    fn gen_expression(&mut self, expression: &tast::Expression) {
        match &expression.kind {
            tast::ExpressionKind::Literal(literal) => self.gen_literal(literal),
            tast::ExpressionKind::ObjectInitializer { .. } => {
                unimplemented!("Object initializer, please use tuple literal instead.");
            }
            tast::ExpressionKind::EnumLiteral(_) => {
                unimplemented!("Enum literal, please rewrite into tagged union.");
            }
            tast::ExpressionKind::TupleLiteral { typ, values } => {
                self.gen_tuple_literal(typ, values);
            }
            tast::ExpressionKind::UnionLiteral { attr, value } => {
                self.gen_union_literal(&expression.typ, attr, value);
            }
            /*
            tast::ExpressionKind::VoidLiteral => {
                // TBD: do something?
            }
            */
            tast::ExpressionKind::Undefined => {
                // TBD: now what? Push undefined value onto the stack!
                self.emit(Instruction::UndefinedLiteral);
            }
            tast::ExpressionKind::Object(_) => {
                panic!("Please resolve symbols before embarking into bytecode");
            }
            tast::ExpressionKind::ListLiteral(values) => {
                self.gen_array_literal(&expression.typ, values);
            }
            tast::ExpressionKind::Binop { lhs, op, rhs } => {
                self.gen_binop(lhs, op, rhs);
            }
            tast::ExpressionKind::TypeCast { to_type: _, value } => {
                self.gen_expression(value);
                let cast_operation = match (&value.typ, &expression.typ) {
                    (SlangType::Basic(from_type), SlangType::Basic(to_type)) => {
                        match (from_type, to_type) {
                            (BasicType::Int, BasicType::Float) => {
                                bytecode::TypeConversion::IntToFloat
                            }
                            (BasicType::Float, BasicType::Int) => {
                                bytecode::TypeConversion::FloatToInt
                            }
                            (a, b) => {
                                panic!("Unsupported type casting: {} -> {}", a, b);
                            }
                        }
                    }
                    (SlangType::User(_user_type), SlangType::Opaque) => {
                        bytecode::TypeConversion::UserToOpaque
                    }
                    (SlangType::Opaque, SlangType::User(user_type)) => {
                        bytecode::TypeConversion::OpaqueToUser(
                            self.get_bytecode_typ_for_user_type(user_type),
                        )
                    }
                    (a, b) => {
                        panic!("Unsupported type casting: {} -> {}", a, b);
                    }
                };
                self.emit(Instruction::TypeConvert(cast_operation));
            }
            tast::ExpressionKind::Call { callee, arguments } => {
                self.gen_call(callee, arguments);
            }

            tast::ExpressionKind::GetAttr { base, attr } => match &base.typ {
                SlangType::User(user_type) => {
                    let field_ref = user_type.get_field(attr).unwrap();
                    let field = field_ref.borrow();
                    let typ = self.get_bytecode_typ(&field.typ);
                    self.gen_expression(base);
                    self.emit(Instruction::GetAttr {
                        index: field.index,
                        typ,
                    });
                }
                other => {
                    panic!("base type must be user-type, not {}", other);
                }
            },

            tast::ExpressionKind::GetIndex { base, index } => {
                let typ = self.get_bytecode_typ(&expression.typ);
                self.gen_expression(base);
                self.gen_expression(index);
                self.emit(Instruction::GetElement { typ });
            }

            tast::ExpressionKind::LoadSymbol(symbol) => match symbol {
                Symbol::ExternFunction { name, typ } => {
                    // TODO: Gross hack! Not all functions are imported from std::!
                    let full_name = format!("std_{}", name);
                    self.import_external(full_name.clone(), typ.clone());
                    let typ = self.get_bytecode_typ(typ);
                    self.emit(Instruction::LoadGlobalName {
                        name: full_name,
                        typ,
                    });
                }
                Symbol::Function(func_ref) => {
                    let func_ref1 = refer(func_ref);
                    let func_ref = func_ref1.borrow();
                    let name = func_ref.name.name.clone();
                    let typ = self.get_bytecode_typ(&func_ref.get_type());
                    self.emit(Instruction::LoadGlobalName { name, typ });
                }
                Symbol::LocalVariable(local_ref) => {
                    // TBD: use name + id as hint?
                    let index: usize = *self
                        .index_map
                        .get(&refer(local_ref).borrow().name.id)
                        .unwrap();
                    self.emit(Instruction::LoadLocal { index });
                }
                Symbol::Parameter(param_ref) => {
                    // TBD: use name as a hint?
                    let index: usize = *self
                        .index_map
                        .get(&refer(param_ref).borrow().name.id)
                        .unwrap();
                    self.emit(Instruction::LoadParameter { index });
                }
                other => {
                    unimplemented!("Loading {}", other);
                }
            },
        }
    }

    /// Generate code for a literal value.
    fn gen_literal(&mut self, literal: &tast::Literal) {
        match literal {
            tast::Literal::Bool(value) => {
                self.emit(Instruction::BoolLiteral(*value));
            }
            tast::Literal::Integer(value) => {
                self.emit(Instruction::IntLiteral(*value));
            }
            tast::Literal::Float(value) => {
                self.emit(Instruction::FloatLiteral(*value));
            }
            tast::Literal::String(value) => {
                self.emit(Instruction::StringLiteral(value.clone()));
            }
        }
    }

    fn allocate_composite_type(&mut self, typ: &SlangType) {
        let typ = self.get_bytecode_typ(&typ);
        if let bytecode::Typ::Ptr(array_typ) = typ {
            self.emit(Instruction::Malloc(*array_typ));
        } else {
            panic!("Assumed composite literal is pointer to thing.");
        }
    }

    /// Generate code for an array literal value
    fn gen_array_literal(&mut self, typ: &SlangType, values: &[tast::Expression]) {
        self.allocate_composite_type(typ);

        // Generate a sequence of set-element operations:
        for (index, value) in values.iter().enumerate() {
            self.emit(Instruction::Duplicate);
            self.emit(Instruction::IntLiteral(index as i64));
            self.gen_expression(value);
            self.emit(Instruction::SetElement);
        }
    }

    /// Generate a struct literal, and fill all it's values!
    fn gen_tuple_literal(&mut self, typ: &SlangType, values: &[tast::Expression]) {
        self.allocate_composite_type(typ);

        for (index, value) in values.iter().enumerate() {
            self.emit(Instruction::Duplicate);
            self.gen_expression(value);
            self.emit(Instruction::SetAttr { index });
        }
    }

    fn gen_union_literal(&mut self, typ: &SlangType, attr: &str, value: &tast::Expression) {
        let union_def = typ.as_union();

        let typ = self.get_bytecode_typ(&typ);
        if let bytecode::Typ::Ptr(union_typ) = typ {
            self.emit(Instruction::Malloc(*union_typ));
        } else {
            panic!("Assumed union literal is pointer to thing.");
        }

        let field = union_def.get_field(attr).unwrap();
        let index = field.borrow().index;

        self.emit(Instruction::Duplicate);
        self.gen_expression(value);
        self.emit(Instruction::SetAttr { index });
    }

    /// Generate bytecode for a function call.
    fn gen_call(&mut self, callee: &tast::Expression, arguments: &Vec<tast::Expression>) {
        let typ = callee
            .typ
            .clone()
            .into_function_type()
            .borrow()
            .return_type
            .clone();
        let return_type = typ.map(|t| self.get_bytecode_typ(&t));

        self.gen_expression(callee);
        let n_args = arguments.len();
        for argument in arguments {
            self.gen_expression(argument);
        }
        self.emit(Instruction::Call {
            n_args,
            typ: return_type,
        });
    }

    fn gen_binop(
        &mut self,
        lhs: &tast::Expression,
        op: &ast::BinaryOperator,
        rhs: &tast::Expression,
    ) {
        match op {
            ast::BinaryOperator::Math(op2) => {
                let typ = self.get_bytecode_typ(&lhs.typ);
                self.gen_expression(lhs);
                self.gen_expression(rhs);
                let op = match op2 {
                    ast::MathOperator::Add => bytecode::Operator::Add,
                    ast::MathOperator::Sub => bytecode::Operator::Sub,
                    ast::MathOperator::Mul => bytecode::Operator::Mul,
                    ast::MathOperator::Div => bytecode::Operator::Div,
                };
                self.emit(Instruction::Operator { op, typ });
            }
            ast::BinaryOperator::Comparison(op2) => {
                let typ = self.get_bytecode_typ(&lhs.typ);
                self.gen_expression(lhs);
                self.gen_expression(rhs);
                // TBD: we could simplify by swapping lhs and rhs and using Lt instead of GtEqual
                let op = match op2 {
                    ast::ComparisonOperator::Equal => bytecode::Comparison::Equal,
                    ast::ComparisonOperator::NotEqual => bytecode::Comparison::NotEqual,
                    ast::ComparisonOperator::Gt => bytecode::Comparison::Gt,
                    ast::ComparisonOperator::GtEqual => bytecode::Comparison::GtEqual,
                    ast::ComparisonOperator::Lt => bytecode::Comparison::Lt,
                    ast::ComparisonOperator::LtEqual => bytecode::Comparison::LtEqual,
                };

                self.emit(Instruction::Comparison { op, typ });
            }
            ast::BinaryOperator::Logic(_op) => {
                unimplemented!();
                /*
                let true_label = self.new_label();
                let false_label = self.new_label();
                let final_label = self.new_label();
                let recreated_expression = simple_ast::Expression::Binop {
                    typ,
                    op_typ,
                    lhs: Box::new(lhs),
                    op: ast::BinaryOperator::Logic(op),
                    rhs: Box::new(rhs),
                };
                self.gen_condition(
                    recreated_expression,
                    true_label.clone(),
                    false_label.clone(),
                );
                self.set_label(true_label);
                self.emit(Instruction::BoolLiteral(true));
                self.jump(final_label.clone());
                self.set_label(false_label);
                self.emit(Instruction::BoolLiteral(false));
                self.jump(final_label.clone());
                self.set_label(final_label);
                */
            }
            ast::BinaryOperator::Bit(_) => {
                unimplemented!();
            }
        }
    }

    /// Get a new label we can jump to!
    fn new_label(&mut self) -> Label {
        let x = self.id_counter;
        self.id_counter += 1;
        Label { name: x }
    }

    /// Mark the current point with the given label.
    fn set_label(&mut self, label: Label) {
        let current_pc = self.instructions.len();
        assert!(!self.label_map.contains_key(&label));
        self.label_map.insert(label, current_pc);
    }

    /// Generate code to jump to the given label.
    fn jump(&mut self, label: Label) {
        // Check if the label is known, otherwise emit nop and resolve later.
        if let Some(dest) = self.label_map.get(&label).cloned() {
            self.emit(Instruction::Jump(dest));
        } else {
            let pc = self.instructions.len();
            self.emit(Instruction::Nop);
            self.relocations.push(Relocation::Jump { pc, label });
        }
    }

    /// Conditionally jump to either the true or the false label.
    fn jump_if(&mut self, true_label: Label, false_label: Label) {
        // TODO: we might check if the labels are defined here
        // self.emit(Instruction::JumpIf(true_label, false_label));

        let pc = self.instructions.len();
        // Emit NOP, fixup at the end.
        // and emit jump right away.
        self.emit(Instruction::Nop);
        self.relocations.push(Relocation::JumpIf {
            pc,
            true_label,
            false_label,
        });
    }

    fn jump_table(&mut self, default: Label, options: Vec<(i64, Label)>) {
        let pc = self.instructions.len();
        self.emit(Instruction::Nop);
        self.relocations.push(Relocation::JumpSwitch {
            pc,
            default,
            options,
        });
    }

    fn resolve_relocations(&mut self) {
        for relocation in &self.relocations {
            match relocation {
                Relocation::Jump { pc, label } => {
                    let target = self.get_jump_dest(label);
                    self.instructions[*pc] = bytecode::Instruction::Jump(target);
                }
                Relocation::JumpIf {
                    pc,
                    true_label,
                    false_label,
                } => {
                    let true_index: usize = self.get_jump_dest(true_label);
                    let false_index: usize = self.get_jump_dest(false_label);
                    self.instructions[*pc] = bytecode::Instruction::JumpIf(true_index, false_index);
                }
                Relocation::JumpSwitch {
                    pc,
                    default,
                    options,
                } => {
                    let default: usize = self.get_jump_dest(default);
                    let options: Vec<(i64, usize)> = options
                        .iter()
                        .map(|(v, t)| (*v, self.get_jump_dest(t)))
                        .collect();
                    self.instructions[*pc] = bytecode::Instruction::JumpSwitch { default, options };
                }
            }
        }
        self.relocations.clear();
    }

    // fn patch_code(&mut self, pc: usize, instruction: Instruction) {
    //     self.instructions[pc] = instruction;
    // }

    fn get_jump_dest(&self, label: &Label) -> usize {
        let dst = *self.label_map.get(label).unwrap();
        assert!(dst < self.instructions.len());
        // if dst == self.instructions.len() - 1 {
        // Append NOP when jump target is last instruction!
        // self.emit(Instruction::Nop);
        // }
        dst
    }

    /// Emit single instruction
    fn emit(&mut self, instruction: Instruction) {
        self.instructions.push(instruction);
    }
}
