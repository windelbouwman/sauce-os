//! Transform a typed ast into some byte-code ish format
//!
//! Idea section:
//! - introduce a de-sugar phase, to eliminate wildly complicated contraptions on source level.

use super::bytecode;
use super::bytecode::Instruction;
use super::parsing::ast;
use super::semantics::type_system::{
    EnumOption, EnumType, FunctionType, MyType, StructType, UnionType,
};
use super::semantics::typed_ast;
use super::simple_ast;
use std::collections::HashMap;

pub fn gen(prog: simple_ast::Program) -> bytecode::Program {
    log::info!("Generating IR bytecode");
    let mut g = Generator::new();
    g.gen_prog(prog)
}

#[derive(Hash, Eq, PartialEq, Clone)]
struct Label {
    name: usize,
}

struct Generator {
    functions: Vec<bytecode::Function>,
    instructions: Vec<Instruction>,
    id_counter: usize,
    loop_stack: Vec<(Label, Label)>,
    types: Vec<bytecode::TypeDef>,
    type_to_id_map: HashMap<bytecode::TypeDef, usize>,
    label_map: HashMap<Label, usize>,
    relocations: Vec<Relocation>,
}

enum Relocation {
    Jump(usize, Label),
    JumpIf(usize, Label, Label),
    JumpTable(usize, Vec<Label>),
}

impl Generator {
    fn new() -> Self {
        Generator {
            functions: vec![],
            instructions: vec![],
            id_counter: 0,
            loop_stack: vec![],
            types: vec![],
            type_to_id_map: HashMap::new(),
            label_map: HashMap::new(),
            relocations: vec![],
        }
    }

    fn gen_prog(&mut self, prog: simple_ast::Program) -> bytecode::Program {
        let mut imports = vec![];
        for imp in prog.imports {
            match imp.typ {
                MyType::Function(FunctionType {
                    argument_types,
                    return_type,
                }) => {
                    let bc_import = bytecode::Import {
                        name: imp.name,
                        parameter_types: argument_types
                            .iter()
                            .map(|t| self.get_bytecode_typ(t))
                            .collect(),
                        return_type: return_type.as_ref().map(|t| self.get_bytecode_typ(t)),
                    };
                    imports.push(bc_import);
                }
                other => {
                    unimplemented!("Not implemented: {:?}", other);
                }
            }
        }

        for function in prog.functions {
            self.gen_func(function);
        }

        bytecode::Program {
            imports,
            types: std::mem::take(&mut self.types),
            functions: std::mem::take(&mut self.functions),
        }
    }

    fn gen_func(&mut self, func: simple_ast::FunctionDef) {
        log::debug!("Gen code for {}", func.name);

        self.label_map.clear();

        let parameters: Vec<bytecode::Parameter> = func
            .parameters
            .into_iter()
            .map(|p| bytecode::Parameter {
                name: p.name,
                typ: self.get_bytecode_typ(&p.typ),
            })
            .collect();

        let return_type = func.return_type.as_ref().map(|t| self.get_bytecode_typ(t));

        let locals = func
            .locals
            .into_iter()
            .map(|v| bytecode::Local {
                name: v.name,
                typ: self.get_bytecode_typ(&v.typ),
            })
            .collect();

        self.gen_block(func.body);

        // Hmm, a bit of a hack, to inject a void return here ..
        if !self.instructions.last().unwrap().is_terminator() {
            self.emit(Instruction::Return(0));
        }

        self.resolve_relocations();

        let instructions = std::mem::take(&mut self.instructions);
        self.functions.push(bytecode::Function {
            name: func.name,
            parameters,
            return_type,
            locals,
            code: instructions,
        })
    }

    /// Get a new label we can jump to!
    fn new_label(&mut self) -> Label {
        let x = self.id_counter;
        self.id_counter += 1;
        Label { name: x }
    }

    fn set_label(&mut self, label: Label) {
        let current_pc = self.instructions.len();
        assert!(!self.label_map.contains_key(&label));
        self.label_map.insert(label, current_pc);
    }

    /// Generate code to jump to the given label.
    fn jump(&mut self, target_label: Label) {
        // Check if the label is known, otherwise emit nop and resolve later.
        if let Some(dest) = self.label_map.get(&target_label).cloned() {
            self.emit(Instruction::Jump(dest));
        } else {
            let pc = self.instructions.len();
            self.emit(Instruction::Nop);
            self.relocations.push(Relocation::Jump(pc, target_label));
        }
    }

    fn jump_if(&mut self, true_label: Label, false_label: Label) {
        let pc = self.instructions.len();
        // Emit NOP, fixup at the end.
        // TODO: we might check if the labels are defined here
        // and emit jump right away.
        self.emit(Instruction::Nop);
        // self.emit(Instruction::JumpIf(true_label, false_label));
        self.relocations
            .push(Relocation::JumpIf(pc, true_label, false_label));
    }

    fn jump_table(&mut self, targets: Vec<Label>) {
        let pc = self.instructions.len();
        self.emit(Instruction::Nop);
        self.relocations.push(Relocation::JumpTable(pc, targets));
    }

    fn resolve_relocations(&mut self) {
        for relocation in &self.relocations {
            match relocation {
                Relocation::Jump(pc, target) => {
                    let target = self.label_map.get(target).unwrap();
                    self.instructions[*pc] = bytecode::Instruction::Jump(*target);
                }
                Relocation::JumpIf(pc, true_target, false_target) => {
                    let true_index: usize = *self.label_map.get(true_target).unwrap();
                    let false_index: usize = *self.label_map.get(false_target).unwrap();
                    self.instructions[*pc] = bytecode::Instruction::JumpIf(true_index, false_index);
                }
                Relocation::JumpTable(pc, targets) => {
                    let resolved_target: Vec<usize> = targets
                        .iter()
                        .map(|t| *self.label_map.get(t).unwrap())
                        .collect();
                    self.instructions[*pc] = bytecode::Instruction::JumpTable(resolved_target);
                }
            }
        }
        self.relocations.clear();
    }

    fn gen_block(&mut self, block: simple_ast::Block) {
        for statement in block {
            self.gen_statement(statement);
        }
    }

    fn gen_statement(&mut self, statement: simple_ast::Statement) {
        match statement {
            simple_ast::Statement::Let {
                name: _,
                index,
                value,
            } => {
                // let typ = Self::get_bytecode_typ(&value.typ);
                self.gen_expression(value);
                // store value in local variable:
                self.emit(Instruction::StoreLocal { index });
            }
            simple_ast::Statement::SetAttr {
                base,
                base_typ,
                index,
                value,
            } => match &base_typ {
                MyType::Struct(_struct_typ) => {
                    self.gen_expression(base);
                    self.gen_expression(value);
                    self.emit(Instruction::SetAttr { index });
                }
                other => {
                    panic!("Base type must be structured type, not {:?}.", other);
                }
            },
            simple_ast::Statement::StoreLocal { index, value } => {
                self.gen_expression(value);
                self.emit(Instruction::StoreLocal { index });
            }
            simple_ast::Statement::Break => {
                let target_label = self.loop_stack.last().unwrap().1.clone();
                self.jump(target_label);
            }
            simple_ast::Statement::Continue => {
                let target_label = self.loop_stack.last().unwrap().0.clone();
                self.jump(target_label);
            }
            simple_ast::Statement::Pass => {}
            simple_ast::Statement::Return { value } => self.gen_return_statement(value),
            simple_ast::Statement::Case(case_statement) => self.gen_case_statement(case_statement),
            simple_ast::Statement::If(if_statement) => self.gen_if_statement(if_statement),
            simple_ast::Statement::Loop { body } => self.gen_loop(body),
            simple_ast::Statement::While(while_statement) => {
                self.gen_while_statement(while_statement)
            }
            simple_ast::Statement::Expression(e) => {
                self.gen_expression(e);
            }
        }
    }

    fn gen_return_statement(&mut self, value: Option<simple_ast::Expression>) {
        if let Some(value) = value {
            self.gen_expression(value);
            self.emit(Instruction::Return(1));
        } else {
            self.emit(Instruction::Return(0));
        }
        // TBD: generate a new label here?
    }

    fn gen_case_statement(&mut self, case_statement: simple_ast::CaseStatement) {
        let enum_type: EnumType = case_statement.enum_type;
        self.gen_expression(case_statement.value);

        // Duplicate enum struct pointer, so we can later retrieve eventual contents
        self.emit(bytecode::Instruction::Duplicate);

        // Retrieve enum descriminator:
        let int_typ = self.get_bytecode_typ(&MyType::Int);
        self.emit(bytecode::Instruction::GetAttr {
            index: 0,
            typ: int_typ,
        });

        let mut arms = case_statement.arms;
        // Sort the arm, such that we can use the choice index into a jump table:
        arms.sort_by_key(|a| a.choice);
        let final_label = self.new_label();
        let arm_labels: Vec<Label> = arms.iter().map(|_| self.new_label()).collect();
        // choose between arms by means of a jump table:
        self.jump_table(arm_labels.clone());
        for (arm_label, arm) in arm_labels.into_iter().zip(arms.into_iter()) {
            self.set_label(arm_label);

            let bytecode_union_typ = self.get_bytecode_typ(&enum_type.get_data_union_type());
            // Get the union with the data:
            self.emit(bytecode::Instruction::GetAttr {
                index: 1,
                typ: bytecode_union_typ,
            });

            self.gen_unpack_enum_into_locals(
                &enum_type.choices[arm.choice],
                arm.choice,
                arm.local_ids,
            );

            // Execute arm body:
            self.gen_block(arm.body);
            self.jump(final_label.clone());
        }
        self.set_label(final_label);
    }

    fn gen_unpack_enum_into_locals(
        &mut self,
        enum_option: &EnumOption,
        choice: usize,
        local_ids: Vec<usize>,
    ) {
        // Fill enum optional values:
        if enum_option.data.is_empty() {
            self.emit(bytecode::Instruction::DropTop);
        } else {
            if enum_option.data.len() == 1 {
                // 1 argument enum
                let data_typ = self.get_bytecode_typ(&enum_option.data[0]);
                self.emit(bytecode::Instruction::GetAttr {
                    index: choice,
                    typ: data_typ,
                });
                self.emit(bytecode::Instruction::StoreLocal {
                    index: local_ids[0],
                });
            } else {
                // n argument enum
                let struct_type = enum_option.get_payload_type();
                let data_typ = self.get_bytecode_typ(&struct_type);
                self.emit(bytecode::Instruction::GetAttr {
                    index: choice,
                    typ: data_typ,
                });
                let struct_type = struct_type.into_struct();
                assert_eq!(struct_type.fields.len(), local_ids.len());
                for (index, local_id_field_pair) in local_ids
                    .into_iter()
                    .zip(struct_type.fields.iter())
                    .enumerate()
                {
                    let (local_index, field) = local_id_field_pair;
                    self.emit(bytecode::Instruction::Duplicate);
                    let typ = self.get_bytecode_typ(&field.typ);
                    self.emit(bytecode::Instruction::GetAttr { index, typ });
                    self.emit(bytecode::Instruction::StoreLocal { index: local_index });
                }
                self.emit(bytecode::Instruction::DropTop);
            }
        }
    }

    fn gen_if_statement(&mut self, if_statement: simple_ast::IfStatement) {
        let true_label = self.new_label();
        let final_label = self.new_label();
        if let Some(if_false) = if_statement.if_false {
            let false_label = self.new_label();
            self.gen_condition(
                if_statement.condition,
                true_label.clone(),
                false_label.clone(),
            );

            self.set_label(true_label);
            self.gen_block(if_statement.if_true);
            self.jump(final_label.clone());

            self.set_label(false_label);
            self.gen_block(if_false);
        } else {
            self.gen_condition(
                if_statement.condition,
                true_label.clone(),
                final_label.clone(),
            );

            self.set_label(true_label);
            self.gen_block(if_statement.if_true);
        }
        self.jump(final_label.clone());
        self.set_label(final_label);
    }

    fn gen_loop(&mut self, body: simple_ast::Block) {
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

    fn gen_while_statement(&mut self, while_statement: simple_ast::WhileStatement) {
        let loop_start_label = self.new_label();
        let true_label = self.new_label();
        let final_label = self.new_label();
        self.jump(loop_start_label.clone());
        self.set_label(loop_start_label.clone());
        self.gen_condition(
            while_statement.condition,
            true_label.clone(),
            final_label.clone(),
        );
        self.set_label(true_label);
        self.loop_stack
            .push((loop_start_label.clone(), final_label.clone()));
        self.gen_block(while_statement.body);
        self.loop_stack.pop();
        self.jump(loop_start_label);
        self.set_label(final_label);
    }

    /// Generate bytecode for condition statement.
    fn gen_condition(
        &mut self,
        expression: simple_ast::Expression,
        true_label: Label,
        false_label: Label,
    ) {
        // TODO: add 'not' operator
        match expression {
            simple_ast::Expression::Binop {
                lhs,
                op: ast::BinaryOperator::Logic(op2),
                rhs,
                typ: _,
                op_typ: _,
            } => {
                // Implement short-circuit logic for 'or' and 'and'
                let middle_label = self.new_label();
                match op2 {
                    ast::LogicOperator::And => {
                        self.gen_condition(*lhs, middle_label.clone(), false_label.clone());
                        self.set_label(middle_label);
                        self.gen_condition(*rhs, true_label, false_label);
                    }
                    ast::LogicOperator::Or => {
                        self.gen_condition(*lhs, true_label.clone(), middle_label.clone());
                        self.set_label(middle_label);
                        self.gen_condition(*rhs, true_label, false_label);
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

    fn get_struct_index(&mut self, struct_type: &StructType) -> usize {
        let fields: Vec<bytecode::Typ> = struct_type
            .fields
            .iter()
            .map(|f| self.get_bytecode_typ(&f.typ))
            .collect();
        let typ = bytecode::TypeDef::Struct(bytecode::StructDef {
            name: struct_type.name.clone(),
            fields,
        });
        self.inject_type(typ)
    }

    fn get_union_index(&mut self, union_type: &UnionType) -> usize {
        let choices: Vec<bytecode::Typ> = union_type
            .fields
            .iter()
            .map(|choice| self.get_bytecode_typ(choice))
            .collect();
        let union_typ = bytecode::TypeDef::Union(bytecode::UnionDef {
            name: format!("{}_data", union_type.name),
            choices,
        });

        self.inject_type(union_typ)
    }

    fn get_bytecode_typ(&mut self, ty: &MyType) -> bytecode::Typ {
        match ty {
            MyType::Bool => bytecode::Typ::Bool,
            MyType::Int => bytecode::Typ::Int,
            MyType::Float => bytecode::Typ::Float,
            MyType::String => bytecode::Typ::String,
            MyType::Struct(struct_type) => bytecode::Typ::Ptr(Box::new(bytecode::Typ::Composite(
                self.get_struct_index(struct_type),
            ))),
            MyType::Union(union_type) => bytecode::Typ::Ptr(Box::new(bytecode::Typ::Composite(
                self.get_union_index(union_type),
            ))),
            MyType::Enum(enum_type) => self.get_bytecode_typ(&enum_type.get_struct_type()),
            MyType::Class(_) => {
                panic!("Cannot handle class-types");
            }
            MyType::Generic { .. } => {
                panic!("Cannot compile generic type");
            }
            MyType::TypeConstructor => {
                panic!("Cannot compile type constructor");
            }
            MyType::Void => bytecode::Typ::Void,
            MyType::TypeVar(_) => {
                panic!("Cannot compile type variable");
            }
            MyType::Function(_) => {
                unimplemented!("function-type");
            }
        }
    }

    /// Generate a struct literal, and fill all it's values!
    fn gen_tuple_literal(&mut self, typ: bytecode::Typ, values: Vec<simple_ast::Expression>) {
        // Alloc room for struct:
        if let bytecode::Typ::Ptr(struct_typ) = typ {
            self.emit(Instruction::Malloc(*struct_typ));
        } else {
            panic!("Assumed struct literal is pointer to thing.");
        }

        for (index, value) in values.into_iter().enumerate() {
            self.emit(Instruction::Duplicate);
            self.gen_expression(value);
            self.emit(Instruction::SetAttr { index });
        }
    }

    fn gen_expression(&mut self, expression: simple_ast::Expression) {
        match expression {
            simple_ast::Expression::Literal(literal) => self.gen_literal(literal),
            simple_ast::Expression::StructLiteral { typ, values } => {
                let typ = self.get_bytecode_typ(&typ);
                self.gen_tuple_literal(typ, values);
            }
            simple_ast::Expression::UnionLiteral { typ, index, value } => {
                let typ = self.get_bytecode_typ(&typ);
                if let bytecode::Typ::Ptr(union_typ) = typ {
                    self.emit(Instruction::Malloc(*union_typ));
                } else {
                    panic!("Assumed union literal is pointer to thing.");
                }
                match *value {
                    simple_ast::Expression::VoidLiteral => {}
                    other => {
                        self.emit(Instruction::Duplicate);
                        self.gen_expression(other);
                        self.emit(Instruction::SetAttr { index });
                    }
                }
            }
            simple_ast::Expression::VoidLiteral => {
                // TBD: do something?
            }
            simple_ast::Expression::Binop {
                lhs,
                op,
                rhs,
                typ,
                op_typ,
            } => {
                self.gen_binop(typ, op_typ, *lhs, op, *rhs);
            }
            simple_ast::Expression::Call {
                callee,
                arguments,
                typ,
            } => {
                // let return_type = function_type
                //     .return_type
                //     .as_ref()
                //     .map(|t| self.get_bytecode_typ(t));
                let return_type = if typ.is_void() {
                    None
                } else {
                    Some(self.get_bytecode_typ(&typ))
                };

                self.gen_expression(*callee);
                let n_args = arguments.len();
                for argument in arguments {
                    self.gen_expression(argument);
                }
                self.emit(Instruction::Call {
                    n_args,
                    typ: return_type,
                });
            }
            simple_ast::Expression::GetAttr {
                base,
                base_typ,
                index,
            } => match &base_typ {
                MyType::Struct(struct_typ) => {
                    let typ = self.get_bytecode_typ(&struct_typ.fields[index].typ);
                    self.gen_expression(*base);
                    self.emit(Instruction::GetAttr { index, typ });
                }
                other => {
                    panic!("base type must be struct, not {:?}", other);
                }
            },
            simple_ast::Expression::LoadFunction(name) => {
                self.emit(Instruction::LoadGlobalName(name));
            }
            simple_ast::Expression::LoadParameter { index } => {
                // TBD: use name as a hint?
                self.emit(Instruction::LoadParameter { index });
            }
            simple_ast::Expression::LoadLocal { index, typ } => {
                let typ = self.get_bytecode_typ(&typ);
                self.emit(Instruction::LoadLocal { index, typ });
            }
        }
    }

    fn gen_literal(&mut self, literal: typed_ast::Literal) {
        match literal {
            typed_ast::Literal::Bool(value) => {
                self.emit(Instruction::BoolLiteral(value));
            }
            typed_ast::Literal::Integer(value) => {
                self.emit(Instruction::IntLiteral(value));
            }
            typed_ast::Literal::Float(value) => {
                self.emit(Instruction::FloatLiteral(value));
            }
            typed_ast::Literal::String(value) => {
                self.emit(Instruction::StringLiteral(value));
            }
        }
    }

    fn gen_binop(
        &mut self,
        typ: MyType,
        op_typ: MyType,
        lhs: simple_ast::Expression,
        op: ast::BinaryOperator,
        rhs: simple_ast::Expression,
    ) {
        match op {
            ast::BinaryOperator::Math(op2) => {
                let typ = self.get_bytecode_typ(&op_typ);
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
                let typ = self.get_bytecode_typ(&op_typ);
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
            ast::BinaryOperator::Logic(op) => {
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
            }
        }
    }

    fn emit(&mut self, instruction: Instruction) {
        self.instructions.push(instruction);
    }
}
