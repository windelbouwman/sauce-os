//! Transform a typed ast into some byte-code ish format
//!
//! Idea section:
//! - introduce a de-sugar phase, to eliminate wildly complicated contraptions on source level.

use super::bytecode;
use super::bytecode::Instruction;
use super::parsing::ast;
use super::semantics::type_system::{ArrayType, FunctionType, SlangType, UserType};
use super::semantics::typed_ast;
use crate::semantics::NodeId;
use crate::semantics::{refer, Symbol};
use std::collections::HashMap;
use std::rc::Rc;

/// Compile a typed ast into bytecode.
pub fn gen(progs: &[Rc<typed_ast::Program>]) -> bytecode::Program {
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
            index_map: HashMap::new(),
            label_map: HashMap::new(),
            relocations: vec![],
        }
    }

    fn gen_prog(&mut self, prog: &typed_ast::Program) {
        for definition in &prog.definitions {
            match definition {
                typed_ast::Definition::Function(function) => {
                    self.gen_func(&function.borrow());
                }
                typed_ast::Definition::Class(_) => {
                    panic!("IR-gen does not support classes. Elimenate those earlier on.");
                }
                typed_ast::Definition::Struct(_struct_def) => {
                    // ?
                }
                typed_ast::Definition::Union(_union_def) => {
                    // ?
                }
                typed_ast::Definition::Enum(_) => {}
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
            SlangType::Function(FunctionType {
                argument_types,
                return_type,
            }) => {
                let bc_import = bytecode::Import {
                    name: func_name,
                    parameter_types: argument_types
                        .iter()
                        .map(|t| self.get_bytecode_typ(t))
                        .collect(),
                    return_type: return_type.as_ref().map(|t| self.get_bytecode_typ(t)),
                };
                self.imports.push(bc_import);
            }
            other => {
                unimplemented!("Not implemented: {:?}", other);
            }
        }
    }

    fn gen_func(&mut self, func: &typed_ast::FunctionDef) {
        log::debug!("Gen code for {}", func.name);

        self.label_map.clear();

        // Create parameter space
        let mut parameters: Vec<bytecode::Parameter> = vec![];
        for (index, parameter) in func.parameters.iter().enumerate() {
            let typ = parameter.borrow().typ.clone();
            let name = parameter.borrow().name.clone();
            self.index_map.insert(parameter.borrow().id, index);
            parameters.push(bytecode::Parameter {
                name,
                typ: self.get_bytecode_typ(&typ),
            });
        }

        let f_typ = func.get_type().clone().into_function_type();
        let return_type = f_typ.return_type.as_ref().map(|t| self.get_bytecode_typ(t));

        // Create local space:
        let mut locals = vec![];
        for (index, local_ref) in func.locals.iter().enumerate() {
            let typ = local_ref.borrow().typ.clone();
            let name = local_ref.borrow().name.clone();
            self.index_map.insert(local_ref.borrow().id, index);
            locals.push(bytecode::Local {
                name,
                typ: self.get_bytecode_typ(&typ),
            });
        }

        self.gen_block(&func.body);

        // Sort of a hack, insert NOP so we can jump this no-op..
        self.emit(Instruction::Nop);

        // Hmm, a bit of a hack, to inject a void return here ..
        if !self.instructions.last().unwrap().is_terminator() {
            self.emit(Instruction::Return(0));
        }

        self.resolve_relocations();

        let instructions = std::mem::take(&mut self.instructions);
        self.functions.push(bytecode::Function {
            name: func.name.clone(),
            parameters,
            return_type,
            locals,
            code: instructions,
        })
    }

    fn gen_block(&mut self, block: &typed_ast::Block) {
        for statement in block {
            self.gen_statement(statement);
        }
    }

    fn gen_statement(&mut self, statement: &typed_ast::Statement) {
        match &statement.kind {
            typed_ast::StatementKind::SetAttr { base, attr, value } => match &base.typ {
                SlangType::User(UserType::Struct(struct_ref)) => {
                    let field2 = struct_ref.upgrade().unwrap().get_field(attr).unwrap();
                    let field = field2.borrow();
                    self.gen_expression(base);
                    self.gen_expression(value);
                    self.emit(Instruction::SetAttr { index: field.index });
                }
                other => {
                    panic!("Base type must be structured type, not {:?}.", other);
                }
            },

            typed_ast::StatementKind::SetIndex { base, index, value } => {
                self.gen_expression(base);
                self.gen_expression(index);
                self.gen_expression(value);
                self.emit(Instruction::SetElement);
            }

            typed_ast::StatementKind::StoreLocal { local_ref, value } => {
                self.gen_expression(value);
                let index: usize = *self.index_map.get(&refer(local_ref).borrow().id).unwrap();
                self.emit(Instruction::StoreLocal { index });
            }
            typed_ast::StatementKind::Let { .. } => {
                unimplemented!("let-statement not supported, please use store-local");
            }
            typed_ast::StatementKind::Assignment(_) => {
                unimplemented!("assignment not supported, please use store-local or set-attr");
            }
            typed_ast::StatementKind::Break => {
                let target_label = self.loop_stack.last().unwrap().1.clone();
                self.jump(target_label);
            }
            typed_ast::StatementKind::Continue => {
                let target_label = self.loop_stack.last().unwrap().0.clone();
                self.jump(target_label);
            }
            typed_ast::StatementKind::Pass => {}
            typed_ast::StatementKind::Unreachable => {
                // TODO: think about unreachable code?
            }
            typed_ast::StatementKind::Return { value } => self.gen_return_statement(value),
            typed_ast::StatementKind::Case(_case_statement) => {
                // self.gen_case_statement(case_statement)
                unimplemented!("case statements must be rewritten into switch statements before reaching this phase.");
            }
            typed_ast::StatementKind::Switch(switch_statement) => {
                self.gen_switch_statement(switch_statement);
            }
            typed_ast::StatementKind::For(_) => {
                unimplemented!(
                    "for-loops not supported, please rewrite into something else, like a while loop."
                );
            }
            typed_ast::StatementKind::If(if_statement) => self.gen_if_statement(if_statement),
            typed_ast::StatementKind::Loop { body } => self.gen_loop(body),
            typed_ast::StatementKind::Compound(block) => {
                self.gen_block(block);
            }
            typed_ast::StatementKind::While(while_statement) => {
                self.gen_while_statement(while_statement)
            }
            typed_ast::StatementKind::Expression(expression) => {
                self.gen_expression(expression);
            }
        }
    }

    fn gen_return_statement(&mut self, value: &Option<typed_ast::Expression>) {
        if let Some(value) = value {
            self.gen_expression(value);
            self.emit(Instruction::Return(1));
        } else {
            self.emit(Instruction::Return(0));
        }
        // TBD: generate a new label here?
    }

    fn gen_switch_statement(&mut self, switch_statement: &typed_ast::SwitchStatement) {
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
    }

    fn gen_if_statement(&mut self, if_statement: &typed_ast::IfStatement) {
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
            self.gen_block(&if_false);
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
    }

    fn gen_loop(&mut self, body: &typed_ast::Block) {
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
    }

    fn gen_while_statement(&mut self, while_statement: &typed_ast::WhileStatement) {
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
    }

    /// Generate bytecode for condition statement.
    fn gen_condition(
        &mut self,
        expression: &typed_ast::Expression,
        true_label: Label,
        false_label: Label,
    ) {
        // TODO: add 'not' operator
        match &expression.kind {
            typed_ast::ExpressionKind::Binop {
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

    fn get_struct_index(&mut self, struct_def: Rc<typed_ast::StructDef>) -> usize {
        // *self
        // .type_to_id_map
        // .get(&struct_type.upgrade().unwrap().id)
        // .unwrap()
        // unimplemented!();

        // let struct_name = self.context.get_name(struct_type_node_id);
        let mut bytecode_field_types: Vec<bytecode::Typ> = vec![];
        for (_index, field_ref) in struct_def.fields.iter().enumerate() {
            // self.index_map.insert(*f_id, index);
            let field_type = self.get_bytecode_typ(&field_ref.borrow().typ);
            bytecode_field_types.push(field_type);
        }

        let name = struct_def.name.clone();

        let typ = bytecode::TypeDef::Struct(bytecode::StructDef {
            name: Some(name),
            fields: bytecode_field_types,
        });
        self.inject_type(typ)
    }

    fn get_union_index(&mut self, union_def: Rc<typed_ast::UnionDef>) -> usize {
        let mut choices: Vec<bytecode::Typ> = vec![];
        for field_ref in union_def.fields.iter() {
            let field_type = self.get_bytecode_typ(&field_ref.borrow().typ);
            choices.push(field_type);
        }
        let name = union_def.name.clone();

        let union_typ = bytecode::TypeDef::Union(bytecode::UnionDef { name, choices });

        self.inject_type(union_typ)
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
            SlangType::Bool => bytecode::Typ::Bool,
            SlangType::Int => bytecode::Typ::Int,
            SlangType::Float => bytecode::Typ::Float,
            SlangType::String => bytecode::Typ::String,
            SlangType::Undefined => {
                panic!("Undefined type");
            }
            SlangType::Unresolved(_) => {
                panic!("AARG");
            }
            SlangType::User(user_type) => {
                let composite_id: usize = match user_type {
                    UserType::Struct(struct_type) => {
                        self.get_struct_index(struct_type.upgrade().unwrap())
                    }
                    UserType::Union(union_type) => {
                        self.get_union_index(union_type.upgrade().unwrap())
                    }
                    UserType::Enum(_) => {
                        panic!("Cannot handle enum-types, please rewrite in tagged unions");
                    }
                    UserType::Class(_) => {
                        panic!("Cannot handle class-types");
                    }
                };

                bytecode::Typ::Ptr(Box::new(bytecode::Typ::Composite(composite_id)))
            }
            SlangType::Array(array_type) => bytecode::Typ::Ptr(Box::new(bytecode::Typ::Composite(
                self.get_array_index(array_type),
            ))),
            // SlangType::Generic { .. } => {
            //     panic!("Cannot compile generic type");
            // }
            SlangType::TypeConstructor => {
                panic!("Cannot compile type constructor");
            }
            SlangType::Void => bytecode::Typ::Void,
            // SlangType::TypeVar(_) => {
            //     panic!("Cannot compile type variable");
            // }
            SlangType::Function(_) => {
                unimplemented!("function-type");
            }
        }
    }

    fn gen_expression(&mut self, expression: &typed_ast::Expression) {
        match &expression.kind {
            typed_ast::ExpressionKind::Literal(literal) => self.gen_literal(literal),
            typed_ast::ExpressionKind::StructLiteral { .. } => {
                unimplemented!("Struct literal, please use tuple literal instead.");
            }
            typed_ast::ExpressionKind::TupleLiteral(values) => {
                self.gen_tuple_literal(&expression.typ, values);
            }
            typed_ast::ExpressionKind::UnionLiteral { attr, value } => {
                self.gen_union_literal(&expression.typ, attr, value);
            }
            /*
            typed_ast::ExpressionKind::VoidLiteral => {
                // TBD: do something?
            }
            */
            typed_ast::ExpressionKind::Undefined => {
                // TBD: now what? Push undefined value onto the stack!
                self.emit(Instruction::UndefinedLiteral);
            }
            typed_ast::ExpressionKind::ListLiteral(values) => {
                self.gen_array_literal(&expression.typ, values);
            }
            typed_ast::ExpressionKind::Binop { lhs, op, rhs } => {
                self.gen_binop(lhs, op, rhs);
            }

            typed_ast::ExpressionKind::Call { callee, arguments } => {
                self.gen_call(callee, arguments);
            }

            typed_ast::ExpressionKind::GetAttr { base, attr } => match &base.typ {
                SlangType::User(user_type) => {
                    let field2 = user_type.get_field(attr).unwrap();
                    let field = field2.borrow();
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

            typed_ast::ExpressionKind::GetIndex { base, index } => {
                let typ = self.get_bytecode_typ(&expression.typ);
                self.gen_expression(base);
                self.gen_expression(index);
                self.emit(Instruction::GetElement { typ });
            }

            typed_ast::ExpressionKind::LoadSymbol(symbol) => match symbol {
                Symbol::ExternFunction { name, typ } => {
                    // TODO: Gross hack! Not all functions are imported from std::!
                    let full_name = format!("std_{}", name);
                    self.import_external(full_name.clone(), typ.clone());
                    self.emit(Instruction::LoadGlobalName(full_name));
                }
                Symbol::Function(func_ref) => {
                    let name = refer(func_ref).borrow().name.clone();
                    self.emit(Instruction::LoadGlobalName(name));
                }
                Symbol::LocalVariable(local_ref) => {
                    // TBD: use name + id as hint?
                    let index: usize = *self.index_map.get(&refer(local_ref).borrow().id).unwrap();
                    self.emit(Instruction::LoadLocal { index });
                }
                Symbol::Parameter(param_ref) => {
                    // TBD: use name as a hint?
                    let index: usize = *self.index_map.get(&refer(param_ref).borrow().id).unwrap();
                    self.emit(Instruction::LoadParameter { index });
                }
                other => {
                    unimplemented!("Loading {}", other);
                }
            },
            other => {
                unimplemented!("EXPR {:?}", other);
            }
        }
    }

    /// Generate code for a literal value.
    fn gen_literal(&mut self, literal: &typed_ast::Literal) {
        match literal {
            typed_ast::Literal::Bool(value) => {
                self.emit(Instruction::BoolLiteral(*value));
            }
            typed_ast::Literal::Integer(value) => {
                self.emit(Instruction::IntLiteral(*value));
            }
            typed_ast::Literal::Float(value) => {
                self.emit(Instruction::FloatLiteral(*value));
            }
            typed_ast::Literal::String(value) => {
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
    fn gen_array_literal(&mut self, typ: &SlangType, values: &[typed_ast::Expression]) {
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
    fn gen_tuple_literal(&mut self, typ: &SlangType, values: &[typed_ast::Expression]) {
        self.allocate_composite_type(typ);

        for (index, value) in values.iter().enumerate() {
            self.emit(Instruction::Duplicate);
            self.gen_expression(value);
            self.emit(Instruction::SetAttr { index });
        }
    }

    fn gen_union_literal(&mut self, typ: &SlangType, attr: &str, value: &typed_ast::Expression) {
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
    fn gen_call(&mut self, callee: &typed_ast::Expression, arguments: &Vec<typed_ast::Expression>) {
        let typ = callee.typ.clone().into_function_type().return_type.clone();
        let return_type = typ.map(|t| self.get_bytecode_typ(&t));
        // let return_type = if typ.is_void() {
        //     None
        // } else {
        //     Some(self.get_bytecode_typ(&typ))
        // };

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
        lhs: &typed_ast::Expression,
        op: &ast::BinaryOperator,
        rhs: &typed_ast::Expression,
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
                    let target = self.label_map.get(label).unwrap();
                    self.instructions[*pc] = bytecode::Instruction::Jump(*target);
                }
                Relocation::JumpIf {
                    pc,
                    true_label,
                    false_label,
                } => {
                    let true_index: usize = *self.label_map.get(true_label).unwrap();
                    let false_index: usize = *self.label_map.get(false_label).unwrap();
                    self.instructions[*pc] = bytecode::Instruction::JumpIf(true_index, false_index);
                }
                Relocation::JumpSwitch {
                    pc,
                    default,
                    options,
                } => {
                    let default: usize = *self.label_map.get(default).unwrap();
                    let options: Vec<(i64, usize)> = options
                        .iter()
                        .map(|(v, t)| (*v, *self.label_map.get(t).unwrap()))
                        .collect();
                    self.instructions[*pc] = bytecode::Instruction::JumpSwitch { default, options };
                }
            }
        }
        self.relocations.clear();
    }

    /// Emit single instruction
    fn emit(&mut self, instruction: Instruction) {
        self.instructions.push(instruction);
    }
}
