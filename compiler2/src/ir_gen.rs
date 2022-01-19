//! Transform a typed ast into some byte-code ish format
//!
//! Idea section:
//! - introduce a de-sugar phase, to eliminate wildly complicated contraptions on source level.

use super::bytecode;
use super::bytecode::Instruction;
use super::parsing::ast;
use super::semantics::type_system::{ClassType, FunctionType, MyType, StructType};
use super::semantics::typed_ast;
use std::collections::HashMap;

pub fn gen(prog: typed_ast::Program) -> bytecode::Program {
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
    struct_types: Vec<bytecode::StructDef>,
    struct_id_map: HashMap<bytecode::StructDef, usize>,
    label_map: HashMap<Label, usize>,
    relocations: Vec<Relocation>,
}

enum Relocation {
    Jump(usize, Label),
    JumpIf(usize, Label, Label),
}

impl Generator {
    fn new() -> Self {
        Generator {
            functions: vec![],
            instructions: vec![],
            id_counter: 0,
            loop_stack: vec![],
            struct_types: vec![],
            struct_id_map: HashMap::new(),
            label_map: HashMap::new(),
            relocations: vec![],
        }
    }

    fn gen_prog(&mut self, prog: typed_ast::Program) -> bytecode::Program {
        for typedef in prog.type_defs {
            match &typedef.typ {
                MyType::Struct(struct_type) => {
                    self.get_struct_index(struct_type);
                }
                MyType::Generic { .. } => {
                    // Safely ignoring.
                }
                MyType::Class(class_type) => {
                    // TODO: what now?
                    // self.gen_class(class_type),
                }
                MyType::Enum(enum_type) => {
                    // Hmm, what to do?
                }
                other => {
                    unimplemented!("Not doing this: {:?}", other);
                }
            }
        }

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

        for class_def in prog.class_defs {
            self.gen_class_def(class_def);
        }

        for function in prog.functions {
            self.gen_func(None, function);
        }

        bytecode::Program {
            imports,
            struct_types: std::mem::take(&mut self.struct_types),
            functions: std::mem::take(&mut self.functions),
        }
    }

    fn gen_class_def(&mut self, class_def: typed_ast::ClassDef) {
        // Be smart about it, and create default constructor function!
        let ctor_name = class_def.typ.inner.ctor_func_name();
        let class_typ = self.get_bytecode_class_typ(&class_def.typ.inner);

        if let bytecode::Typ::Ptr(struct_typ) = class_typ.clone() {
            self.emit(Instruction::Malloc(*struct_typ));
        } else {
            panic!("Assumed class type is pointer to struct.");
        }

        // Initialize functions:
        for field in class_def.field_defs {
            // ehm, store attr!
            self.emit(bytecode::Instruction::Duplicate);
            self.gen_expression(field.value);
            self.emit(bytecode::Instruction::SetAttr { index: field.index });
        }

        self.emit(bytecode::Instruction::Return(1));
        let instructions = std::mem::take(&mut self.instructions);
        self.functions.push(bytecode::Function {
            name: ctor_name,
            parameters: vec![],
            return_type: Some(class_typ.clone()),
            locals: vec![],
            code: instructions,
        });

        // Generate member functions:
        for function in class_def.function_defs {
            self.gen_func(Some(class_typ.clone()), function);
        }
    }

    fn gen_func(&mut self, self_param: Option<bytecode::Typ>, func: typed_ast::FunctionDef) {
        log::debug!("Gen code for {}", func.name);

        self.label_map.clear();

        let mut parameters: Vec<bytecode::Parameter> = func
            .parameters
            .into_iter()
            .map(|p| bytecode::Parameter {
                name: p.name,
                typ: self.get_bytecode_typ(&p.typ),
            })
            .collect();
        if let Some(p) = self_param {
            parameters.insert(
                0,
                bytecode::Parameter {
                    name: "self".to_owned(),
                    typ: p,
                },
            );
        }

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
            }
        }
        self.relocations.clear();
    }

    fn gen_block(&mut self, block: typed_ast::Block) {
        for statement in block {
            self.gen_statement(statement);
        }
    }

    fn gen_statement(&mut self, statement: typed_ast::Statement) {
        match statement {
            typed_ast::Statement::Let {
                name: _,
                index,
                value,
            } => {
                // let typ = Self::get_bytecode_typ(&value.typ);
                self.gen_expression(value);
                // store value in local variable:
                self.emit(Instruction::StoreLocal { index });
            }
            typed_ast::Statement::Assignment(assignment) => {
                self.gen_assignment(assignment);
            }
            typed_ast::Statement::Break => {
                let target_label = self.loop_stack.last().unwrap().1.clone();
                self.jump(target_label);
            }
            typed_ast::Statement::Continue => {
                let target_label = self.loop_stack.last().unwrap().0.clone();
                self.jump(target_label);
            }
            typed_ast::Statement::Pass => {}
            typed_ast::Statement::Return { value } => {
                if let Some(value) = value {
                    self.gen_expression(value);
                    self.emit(Instruction::Return(1));
                } else {
                    self.emit(Instruction::Return(0));
                }
                // TBD: generate a new label here?
            }
            typed_ast::Statement::Match { value, arms } => {
                self.gen_expression(value);
                for arm in arms {
                    self.gen_block(arm.body);
                }
                unimplemented!("Ehm, what now?");
            }

            typed_ast::Statement::If(if_statement) => self.gen_if_statement(if_statement),
            typed_ast::Statement::Loop { body } => {
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
            typed_ast::Statement::While(while_statement) => {
                self.gen_while_statement(while_statement)
            }
            typed_ast::Statement::Expression(e) => {
                self.gen_expression(e);
            }
        }
    }

    fn gen_assignment(&mut self, assignment: typed_ast::AssignmentStatement) {
        match assignment.target {
            typed_ast::Expression {
                typ: _,
                kind: typed_ast::ExpressionType::GetAttr { base, attr },
            } => match &base.typ {
                MyType::Struct(struct_typ) => {
                    let index = struct_typ.index_of(&attr).expect("Field must be present");
                    self.gen_expression(*base);
                    self.gen_expression(assignment.value);
                    self.emit(Instruction::SetAttr { index });
                }
                MyType::Class(class_typ) => {
                    let index = class_typ
                        .inner
                        .index_of(&attr)
                        .expect("Field must be present");
                    self.gen_expression(*base);
                    self.gen_expression(assignment.value);
                    self.emit(Instruction::SetAttr { index });
                }
                other => {
                    panic!("Base type must be structured type, not {:?}.", other);
                }
            },
            typed_ast::Expression {
                typ: _,
                kind: typed_ast::ExpressionType::LoadLocal { name: _, index },
            } => {
                self.gen_expression(assignment.value);
                self.emit(Instruction::StoreLocal { index });
            }
            _other => {
                unimplemented!("TODO");
            }
        }
    }

    fn gen_if_statement(&mut self, if_statement: typed_ast::IfStatement) {
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

    fn gen_while_statement(&mut self, while_statement: typed_ast::WhileStatement) {
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
        expression: typed_ast::Expression,
        true_label: Label,
        false_label: Label,
    ) {
        // Implement short-circuit logic for 'or' and 'and'
        // TODO: add 'not' operator
        match expression.kind {
            typed_ast::ExpressionType::Binop {
                lhs,
                op: ast::BinaryOperator::Logic(op2),
                rhs,
            } => {
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

    /// Insert struct in de-duplicating manner
    fn inject_struct(&mut self, name: Option<String>, fields: Vec<bytecode::Typ>) -> usize {
        let struct_def = bytecode::StructDef { name, fields };
        if self.struct_id_map.contains_key(&struct_def) {
            *self.struct_id_map.get(&struct_def).unwrap()
        } else {
            let idx = self.struct_types.len();
            self.struct_types.push(struct_def.clone());
            self.struct_id_map.insert(struct_def, idx);
            idx
        }
    }

    fn get_struct_index(&mut self, struct_type: &StructType) -> usize {
        let fields: Vec<bytecode::Typ> = struct_type
            .fields
            .iter()
            .map(|f| self.get_bytecode_typ(&f.typ))
            .collect();
        self.inject_struct(struct_type.name.clone(), fields)
    }

    fn get_bytecode_class_typ(&mut self, class_type: &ClassType) -> bytecode::Typ {
        // Map class into a struct type!
        let fields: Vec<bytecode::Typ> = class_type
            .fields
            .iter()
            .map(|f| self.get_bytecode_typ(&f.typ))
            .collect();
        let idx = self.inject_struct(Some(class_type.name.clone()), fields);
        bytecode::Typ::Ptr(Box::new(bytecode::Typ::Struct(idx)))
    }

    fn get_bytecode_typ(&mut self, ty: &MyType) -> bytecode::Typ {
        match ty {
            MyType::Bool => bytecode::Typ::Bool,
            MyType::Int => bytecode::Typ::Int,
            MyType::Float => bytecode::Typ::Float,
            MyType::String => bytecode::Typ::String,
            MyType::Struct(struct_type) => bytecode::Typ::Ptr(Box::new(bytecode::Typ::Struct(
                self.get_struct_index(struct_type),
            ))),
            MyType::Enum(enum_type) => {
                // Hmm, what to do!
                unimplemented!("TODO!");
            }
            MyType::Class(class_type) => self.get_bytecode_class_typ(&class_type.inner),
            other => {
                unimplemented!("{:?}", other);
            }
        }
    }

    fn gen_expression(&mut self, expression: typed_ast::Expression) {
        match expression.kind {
            typed_ast::ExpressionType::Bool(value) => {
                self.emit(Instruction::BoolLiteral(value));
            }
            typed_ast::ExpressionType::Integer(value) => {
                self.emit(Instruction::IntLiteral(value));
            }
            typed_ast::ExpressionType::Float(value) => {
                self.emit(Instruction::FloatLiteral(value));
            }
            typed_ast::ExpressionType::String(value) => {
                self.emit(Instruction::StringLiteral(value));
            }
            typed_ast::ExpressionType::StructLiteral(values) => {
                let typ = self.get_bytecode_typ(&expression.typ);
                if let bytecode::Typ::Ptr(typ) = typ {
                    self.emit(Instruction::Malloc(*typ));
                } else {
                    panic!("Assumed struct literal is pointer to thing.");
                }
                for (index, value) in values.into_iter().enumerate() {
                    self.emit(Instruction::Duplicate);
                    self.gen_expression(value);
                    self.emit(Instruction::SetAttr { index });
                }
            }
            typed_ast::ExpressionType::EnumLiteral { choice, arguments } => {
                unimplemented!("?");
            }
            typed_ast::ExpressionType::Binop { lhs, op, rhs } => {
                self.gen_binop(expression.typ, *lhs, op, *rhs);
            }
            typed_ast::ExpressionType::Call { callee, arguments } => match &callee.typ {
                MyType::Function(function_type) => {
                    let return_type = function_type
                        .return_type
                        .as_ref()
                        .map(|t| self.get_bytecode_typ(t));

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
                other => {
                    panic!("Can only call function types, not {:?}", other);
                }
            },
            typed_ast::ExpressionType::MethodCall {
                instance,
                method,
                arguments,
            } => {
                self.emit(Instruction::LoadGlobalName(method));
                // 'self' is implicit first argument!
                let n_args = arguments.len() + 1;
                self.gen_expression(*instance);
                for argument in arguments {
                    self.gen_expression(argument);
                }
                // let return_type = self.get_bytecode_typ(&expression.typ);
                let return_type = None; // TODO!
                self.emit(Instruction::Call {
                    n_args,
                    typ: return_type,
                });
            }
            typed_ast::ExpressionType::GetAttr { base, attr } => match &base.typ {
                MyType::Struct(struct_typ) => {
                    let index = struct_typ.index_of(&attr).expect("Field must be present");
                    let typ = self.get_bytecode_typ(&struct_typ.fields[index].typ);
                    self.gen_expression(*base);
                    self.emit(Instruction::GetAttr { index, typ });
                }
                MyType::Class(class_type_ref) => {
                    let index = class_type_ref
                        .inner
                        .index_of(&attr)
                        .expect("Field must be present");
                    let typ = self.get_bytecode_typ(&expression.typ);
                    self.gen_expression(*base);
                    self.emit(Instruction::GetAttr { index, typ });
                }
                other => {
                    panic!("base type must be struct, not {:?}", other);
                }
            },
            typed_ast::ExpressionType::LoadFunction(name) => {
                self.emit(Instruction::LoadGlobalName(name));
            }
            typed_ast::ExpressionType::Typ(_) => {
                // TBD: maybe allowing a type as an expression is wrong.
                panic!("Cannot evaluate type!");
            }
            typed_ast::ExpressionType::Instantiate => {
                if let MyType::Class(class_type) = &expression.typ {
                    // Call class constructor auto-contrapted function!
                    let name = class_type.inner.ctor_func_name();
                    self.emit(Instruction::LoadGlobalName(name));
                    let typ = Some(self.get_bytecode_class_typ(&class_type.inner));
                    self.emit(Instruction::Call { n_args: 0, typ });
                } else {
                    panic!("Instantiation requires class type");
                }
            }
            typed_ast::ExpressionType::LoadParameter { name: _, index } => {
                // TBD: use name as a hint?
                self.emit(Instruction::LoadParameter { index });
            }
            typed_ast::ExpressionType::LoadLocal { name: _, index } => {
                let typ = self.get_bytecode_typ(&expression.typ);
                self.emit(Instruction::LoadLocal { index, typ });
            }
            typed_ast::ExpressionType::ImplicitSelf => {
                // Load 'self':
                self.emit(Instruction::LoadParameter { index: 0 });
            }
        }
    }

    fn gen_binop(
        &mut self,
        typ: MyType,
        lhs: typed_ast::Expression,
        op: ast::BinaryOperator,
        rhs: typed_ast::Expression,
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
            ast::BinaryOperator::Logic(op) => {
                let true_label = self.new_label();
                let false_label = self.new_label();
                let final_label = self.new_label();
                let recreated_expression = typed_ast::Expression {
                    typ,
                    kind: typed_ast::ExpressionType::Binop {
                        lhs: Box::new(lhs),
                        op: ast::BinaryOperator::Logic(op),
                        rhs: Box::new(rhs),
                    },
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
