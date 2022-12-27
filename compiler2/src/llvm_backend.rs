/// Spit out LLVM IR text form
use super::bytecode;
use std::collections::HashMap;

pub fn create_llvm_text_code<W>(prog: bytecode::Program, writer: &mut W)
where
    W: std::io::Write,
{
    log::info!("Attempting to contrapt LLVM IR-code");
    let buffered_writer = std::io::BufWriter::new(writer);
    let mut llvm_writer = LLVMWriter::new(buffered_writer);
    llvm_writer.gen(prog).unwrap();
}

struct LLVMWriter<W: std::io::Write> {
    w: W,

    // List of name / size pairs
    type_names: Vec<(String, usize)>,
    stack: Vec<(String, String)>,
    parameter_names_and_types: Vec<(String, String)>,
    local_names: Vec<(String, String)>,
    id_counter: usize,
    string_literals: Vec<String>,
    label_map: HashMap<usize, String>,
}

impl<W> LLVMWriter<W>
where
    W: std::io::Write,
{
    fn new(w: W) -> Self {
        LLVMWriter {
            w,
            type_names: vec![],
            stack: vec![],
            parameter_names_and_types: vec![],
            local_names: vec![],
            id_counter: 0,
            string_literals: vec![],
            label_map: HashMap::new(),
        }
    }

    fn gen(&mut self, program: bytecode::Program) -> Result<(), std::io::Error> {
        writeln!(self.w)?;
        writeln!(self.w, r"declare i8* @malloc(i64) nounwind")?;
        writeln!(self.w, r"declare i8* @rt_str_concat(i8*, i8*) nounwind")?;
        writeln!(self.w, r"declare i1 @rt_str_compare(i8*, i8*) nounwind")?;
        writeln!(self.w)?;

        self.gen_types(program.types)?;
        self.gen_imports(program.imports)?;

        writeln!(self.w)?;
        for function in program.functions {
            self.gen_function(function)?;
        }

        for literal in &self.string_literals {
            writeln!(self.w, "{}", literal)?;
        }
        writeln!(self.w)?;

        Ok(())
    }

    fn gen_types(&mut self, typedefs: Vec<bytecode::TypeDef>) -> Result<(), std::io::Error> {
        // Create forward declarations first:
        for typedef in &typedefs {
            match typedef {
                bytecode::TypeDef::Struct(struct_def) => {
                    let type_name = self.new_local(Some(
                        struct_def
                            .name
                            .as_ref()
                            .map(|n| format!("{}Type", n))
                            .unwrap_or("DaType".to_owned()),
                    ));
                    let type_size = 1337;
                    // writeln!(self.w, r"{} = type opaque", type_name)?;
                    self.type_names.push((type_name, type_size));
                }
                bytecode::TypeDef::Union(union_def) => {
                    let type_name = self.new_local(Some(format!("{}Type", union_def.name)));
                    let type_size = 1334;

                    // writeln!(self.w, r"{} = type opaque", type_name)?;
                    self.type_names.push((type_name, type_size));
                }
                bytecode::TypeDef::Array {
                    size,
                    element_type: _,
                } => {
                    // let type_name = self.new_local(Some("ArrayType".to_owned()));
                    let type_name = format!("[{} x ?]", size);
                    let type_size = 1334;
                    self.type_names.push((type_name, type_size));
                }
            }
        }

        for (index, typedef) in typedefs.iter().enumerate() {
            let type_name: String = self.type_names[index].0.clone();
            match typedef {
                bytecode::TypeDef::Struct(struct_def) => {
                    let mut type_size = 0;
                    for field_type in &struct_def.fields {
                        type_size += self.get_sizeof(field_type);
                    }

                    self.type_names[index].1 = type_size;
                    let fields: Vec<String> = struct_def
                        .fields
                        .iter()
                        .map(|f| self.get_llvm_typ(f))
                        .collect();
                    writeln!(self.w, r"{} = type {{ {} }}", type_name, fields.join(", "))?;
                }
                bytecode::TypeDef::Union(union_def) => {
                    let type_size = 1334;
                    self.type_names[index].1 = type_size;

                    let mut fields: Vec<String> = vec![];
                    for subtype in &union_def.choices {
                        fields.push(self.get_llvm_typ(subtype));
                    }
                    writeln!(self.w, r"{} = type {{ {} }}", type_name, fields.join(", "))?;
                }
                bytecode::TypeDef::Array { size, element_type } => {
                    let element_type = self.get_llvm_typ(&element_type);
                    let type_name = format!("[{} x {}]", size, element_type);
                    let type_size = 1334;
                    self.type_names[index] = (type_name.clone(), type_size);
                }
            }
        }
        Ok(())
    }

    // Handle imports!
    fn gen_imports(&mut self, imports: Vec<bytecode::Import>) -> Result<(), std::io::Error> {
        for import in imports {
            let p_text = import
                .parameter_types
                .iter()
                .map(|typ| self.get_llvm_typ(typ))
                .collect::<Vec<String>>()
                .join(", ");

            let return_type = import
                .return_type
                .as_ref()
                .map(|t| self.get_llvm_typ(t))
                .unwrap_or("void".to_owned());

            writeln!(
                self.w,
                r"declare {} @{}({}) nounwind",
                return_type, import.name, p_text
            )?;
        }
        writeln!(self.w)?;
        Ok(())
    }

    fn new_id(&mut self) -> usize {
        let new_id = self.id_counter;
        self.id_counter += 1;
        new_id
    }

    /// Construct a new local value, optionally give
    /// a hint to how it's to be named.
    fn new_local(&mut self, hint: Option<String>) -> String {
        let new_id = self.new_id();
        let hint = hint.unwrap_or("fuu".to_owned());
        format!("%{}_{}", hint, new_id)
    }

    fn new_global(&mut self) -> String {
        let new_id = self.new_id();
        format!("@baz{}", new_id)
    }

    fn get_llvm_typ(&self, ty: &bytecode::Typ) -> String {
        match ty {
            bytecode::Typ::Bool => "i1".to_owned(),
            bytecode::Typ::Int => "i64".to_owned(),
            bytecode::Typ::Float => "double".to_owned(),
            bytecode::Typ::String => "i8*".to_owned(),
            bytecode::Typ::Ptr(pointed_type) => match pointed_type.as_ref() {
                bytecode::Typ::Void => "i8*".to_owned(),
                other => {
                    format!("{}*", self.get_llvm_typ(other))
                }
            },
            bytecode::Typ::Composite(index) => self.type_names[*index].0.clone(),
            bytecode::Typ::Function { parameters, result } => {
                // function: f64(i32, i32)*
                // function returning i32 from float: 'i32(f32,f64)*'
                let mut parameter_types = vec![];
                for parameter in parameters {
                    parameter_types.push(self.get_llvm_typ(parameter));
                }
                let llvm_return_type: String = if let Some(typ) = result {
                    self.get_llvm_typ(typ)
                } else {
                    "void".to_owned()
                };
                // Assume function type are always pointers.
                let type_name = format!("{}({})*", llvm_return_type, parameter_types.join(","));
                type_name
            }
            bytecode::Typ::Void => {
                unimplemented!("TODO");
            }
        }
    }

    /// Poor-man size of function
    fn get_sizeof(&self, ty: &bytecode::Typ) -> usize {
        match ty {
            bytecode::Typ::Bool => 8,   // Conservative, estimate as i64
            bytecode::Typ::Int => 8,    // Conservative, estimate as i64
            bytecode::Typ::Float => 8,  // Conservative, estimate as f64
            bytecode::Typ::String => 8, // assume pointer to u8
            bytecode::Typ::Ptr(_) => 8, // assume 64 bit
            bytecode::Typ::Composite(index) => self.type_names[*index].1,
            bytecode::Typ::Function { .. } => 8, // assume 64 bit
            bytecode::Typ::Void => {
                unimplemented!("TODO");
            }
        }
    }

    fn gen_function(&mut self, func: bytecode::Function) -> Result<(), std::io::Error> {
        log::debug!("Generating function: {}", func.name);
        self.stack.clear();
        self.parameter_names_and_types.clear();
        let mut parameters: Vec<String> = vec![];

        for parameter in func.parameters {
            let parameter_name = format!("%{}", parameter.name);
            let parameter_type = self.get_llvm_typ(&parameter.typ);
            parameters.push(format!("{} {}", parameter_type, parameter_name));
            self.parameter_names_and_types
                .push((parameter_name, parameter_type));
        }

        let p_text = parameters.join(", ");

        let return_type = func
            .return_type
            .as_ref()
            .map(|t| self.get_llvm_typ(t))
            .unwrap_or("void".to_owned());

        writeln!(
            self.w,
            "define {} @{}({}) {{",
            return_type, func.name, p_text
        )?;

        // Allocate room for local variables!
        self.local_names.clear();
        for local in func.locals {
            // Contrapt a sort of unique name:
            // let loc_name = format!("{}_{}", local.name, self.new_id());
            let local_name = self.new_local(Some(local.name));
            let local_typ = self.get_llvm_typ(&local.typ);
            writeln!(self.w, "    {} = alloca {}", local_name, local_typ)?;
            // let local_alloc_type = format!("{}*", local_typ);
            self.local_names.push((local_typ, local_name));
        }

        // Determine jump targets:
        self.determine_jump_targets(&func.code);

        for (index, instruction) in func.code.into_iter().enumerate() {
            if let Some(label_name) = self.label_map.get(&index) {
                writeln!(self.w, "  {}:", label_name)?;
            }
            self.gen_instruction(instruction)?;
        }

        writeln!(self.w, "}}")?;
        writeln!(self.w)?;

        Ok(())
    }

    fn determine_jump_targets(&mut self, code: &[bytecode::Instruction]) {
        self.label_map.clear();
        for instruction in code {
            match instruction {
                bytecode::Instruction::Jump(label) => {
                    self.get_label(*label);
                }
                bytecode::Instruction::JumpIf(label1, label2) => {
                    self.get_label(*label1);
                    self.get_label(*label2);
                }
                bytecode::Instruction::JumpSwitch { default, options } => {
                    self.get_label(*default);
                    for (_, label) in options {
                        self.get_label(*label);
                    }
                }
                _other => {}
            }
        }
    }

    fn get_label(&mut self, label: usize) -> String {
        if self.label_map.contains_key(&label) {
            self.label_map
                .get(&label)
                .expect("Contains the key, we checked above")
                .clone()
        } else {
            let new_label = format!("block{}", label);
            self.label_map.insert(label, new_label.clone());
            new_label
        }
    }

    fn get_label_ref(&self, label: usize) -> String {
        format!("label %{}", self.label_map.get(&label).unwrap())
    }

    fn gen_instruction(
        &mut self,
        instruction: bytecode::Instruction,
    ) -> Result<(), std::io::Error> {
        use bytecode::Instruction;
        log::trace!("Generating code for: {:?}", instruction);
        match instruction {
            Instruction::Nop => {
                log::warn!("Bytecode could be improved, by removing NOPs");
            }
            Instruction::Operator { op, typ } => match typ {
                bytecode::Typ::Int => {
                    let op: String = match op {
                        bytecode::Operator::Add => "add".to_owned(),
                        bytecode::Operator::Sub => "sub".to_owned(),
                        bytecode::Operator::Mul => "mul".to_owned(),
                        bytecode::Operator::Div => "sdiv".to_owned(),
                    };
                    let typ = self.get_llvm_typ(&typ);
                    let rhs = self.pop_untyped();
                    let lhs = self.pop_untyped();
                    let new_var = self.new_local(None);
                    writeln!(self.w, "    {} = {} {} {}, {}", new_var, op, typ, lhs, rhs)?;
                    self.push(typ, new_var);
                }
                bytecode::Typ::Float => {
                    let op: String = match op {
                        bytecode::Operator::Add => "fadd".to_owned(),
                        bytecode::Operator::Sub => "fsub".to_owned(),
                        bytecode::Operator::Mul => "fmul".to_owned(),
                        bytecode::Operator::Div => "fdiv".to_owned(),
                    };
                    let typ = self.get_llvm_typ(&typ);
                    let rhs = self.pop_untyped();
                    let lhs = self.pop_untyped();
                    let new_var = self.new_local(None);
                    writeln!(self.w, "    {} = {} {} {}, {}", new_var, op, typ, lhs, rhs)?;
                    self.push(typ, new_var);
                }
                bytecode::Typ::String => {
                    match op {
                        bytecode::Operator::Add => {
                            let typ = self.get_llvm_typ(&typ);
                            let rhs = self.pop_untyped();
                            let lhs = self.pop_untyped();
                            let new_var = self.new_local(None);
                            // "    {} = call i8* @malloc(i64 {}) nounwind",
                            writeln!(
                                self.w,
                                "    {} = call {} @rt_str_concat({} {}, {} {}) nounwind",
                                new_var, typ, typ, lhs, typ, rhs
                            )?;
                            self.push(typ, new_var);
                        }
                        other => {
                            panic!("Can only add strings, not {:?}", other);
                        }
                    };
                }
                other => {
                    unimplemented!("Binary op for: {:?}", other);
                }
            },
            Instruction::TypeConvert(_conversion) => {
                let new_var = self.new_local(None);
                let (typ, val) = self.pop();
                let (opcode, to_typ) = match _conversion {
                    bytecode::TypeConversion::FloatToInt => ("fptosi", bytecode::Typ::Int),
                    bytecode::TypeConversion::IntToFloat => ("sitofp", bytecode::Typ::Float),
                    bytecode::TypeConversion::UserToOpaque => {
                        ("bitcast", bytecode::Typ::Ptr(Box::new(bytecode::Typ::Void)))
                    }
                    bytecode::TypeConversion::OpaqueToUser(to_typ) => ("bitcast", to_typ),
                };
                let to_typ = self.get_llvm_typ(&to_typ);

                writeln!(
                    self.w,
                    "    {} = {} {} {} to {}",
                    new_var, opcode, typ, val, to_typ
                )?;
                self.push(to_typ, new_var);
            }
            Instruction::BoolLiteral(value) => {
                self.push("i1".to_owned(), format!("{}", if value { 1 } else { 0 }));
            }
            Instruction::IntLiteral(value) => {
                self.push("i64".to_owned(), format!("{}", value));
            }
            Instruction::StringLiteral(value) => {
                self.gen_string_literal(value)?;
            }
            Instruction::FloatLiteral(value) => {
                self.push("double".to_owned(), format!("{:.30}", value));
            }
            Instruction::UndefinedLiteral => {
                self.push("undefined".to_owned(), "undefined".to_owned());
            }
            Instruction::Malloc(typ) => {
                //  TBD: use heap malloc or alloca on stack?

                // Example LLVM code snippet:
                // %malloc2 = call i8* @malloc(i64 16) nounwind
                // %new_op3 = bitcast i8* %malloc2 to %HolderType1*
                let raw_ptr_var = self.new_local(None);
                let typed_ptr_var = self.new_local(None);

                // TBD: use getelementptr hack to determine size?
                let byte_size = self.get_sizeof(&typ);

                // let var_typ = self.get_llvm_typ(&typ);
                let var_typ = format!("{}*", self.get_llvm_typ(&typ));

                writeln!(
                    self.w,
                    "    {} = call i8* @malloc(i64 {}) nounwind",
                    raw_ptr_var, byte_size
                )?;
                writeln!(
                    self.w,
                    "    {} = bitcast i8* {} to {}",
                    typed_ptr_var, raw_ptr_var, var_typ
                )?;
                // writeln!(self.w, "    {} = alloca {}", new_var, typ)?;
                self.push(var_typ, typed_ptr_var);
            }
            Instruction::Duplicate => {
                let (typ, val) = self.pop();
                self.push(typ.clone(), val.clone());
                self.push(typ, val);
            }
            // Instruction::DropTop => {
            //     self.pop();
            // }
            Instruction::Comparison { op, typ } => {
                match typ {
                    bytecode::Typ::Int => {
                        let rhs = self.pop_untyped();
                        let lhs = self.pop_untyped();
                        let op: String = match op {
                            bytecode::Comparison::Lt => "icmp slt".to_owned(),
                            bytecode::Comparison::LtEqual => "icmp sle".to_owned(),
                            bytecode::Comparison::Gt => "icmp sgt".to_owned(),
                            bytecode::Comparison::GtEqual => "icmp sge".to_owned(),
                            bytecode::Comparison::Equal => "icmp eq".to_owned(),
                            bytecode::Comparison::NotEqual => "icmp ne".to_owned(),
                        };
                        let typ = self.get_llvm_typ(&typ);
                        let new_var = self.new_local(None);
                        // %binop10 = icmp slt i32 %a5, %b6
                        writeln!(self.w, "    {} = {} {} {}, {}", new_var, op, typ, lhs, rhs)?;
                        self.push("i1".to_owned(), new_var);
                    }
                    bytecode::Typ::Float => {
                        let rhs = self.pop_untyped();
                        let lhs = self.pop_untyped();
                        let op: String = match op {
                            bytecode::Comparison::Lt => "fcmp olt".to_owned(),
                            bytecode::Comparison::LtEqual => "fcmp ole".to_owned(),
                            bytecode::Comparison::Gt => "fcmp ogt".to_owned(),
                            bytecode::Comparison::GtEqual => "fcmp oge".to_owned(),
                            bytecode::Comparison::Equal => "fcmp oeq".to_owned(),
                            bytecode::Comparison::NotEqual => "fcmp one".to_owned(),
                        };
                        let typ = self.get_llvm_typ(&typ);
                        let new_var = self.new_local(None);
                        // %binop10 = icmp slt i32 %a5, %b6
                        writeln!(self.w, "    {} = {} {} {}, {}", new_var, op, typ, lhs, rhs)?;
                        self.push("i1".to_owned(), new_var);
                    }
                    bytecode::Typ::String => {
                        let rhs = self.pop_typed();
                        let lhs = self.pop_typed();

                        match op {
                            bytecode::Comparison::Equal => {
                                // Call run time
                                let new_var = self.new_local(None);
                                writeln!(
                                    self.w,
                                    "    {} = call i1 @rt_str_compare({}, {})",
                                    new_var, lhs, rhs
                                )?;
                                self.push("i1".to_owned(), new_var);
                            }
                            other => {
                                panic!("Cannot compare string by: {:?}", other);
                            }
                        }
                    }
                    other => {
                        unimplemented!("Comparison not implemented for: {:?}", other);
                    }
                }
            }
            Instruction::Call { n_args, typ } => {
                self.gen_call(n_args, typ)?;
            }
            Instruction::GetAttr { index, typ } => {
                let (base_type, base) = self.pop();

                let index = format!("{}", index);
                // Determine element pointer:
                let element_ptr = self.get_element_ptr(&base_type, &base, "i32", &index)?;
                let element_ptr_type = self.get_llvm_typ(&typ);

                // Example:
                // %field_ptr15 = getelementptr %HolderType1, %HolderType1* %messages10, i32 0, i32 1
                // %field14 = load i8*, i8** %field_ptr15
                // load value:
                let loaded_value = self.emit_load(&element_ptr_type, &element_ptr, None)?;
                self.push(element_ptr_type, loaded_value);
            }
            Instruction::SetAttr { index } => {
                let (value_type, value) = self.pop();
                let (base_type, base) = self.pop();

                let index = format!("{}", index);
                let element_ptr = self.get_element_ptr(&base_type, &base, "i32", &index)?;

                // Example:
                // %HolderType1 = type { i8*, i8* }
                // %addr6 = getelementptr %HolderType1, %HolderType1* %new_op3, i32 0, i32 0
                // store i8* %cast4, i8** %addr6
                self.emit_store(&value_type, &value, &element_ptr)?;
            }
            Instruction::GetElement { typ } => {
                let (index_type, index) = self.pop();
                let (base_type, base) = self.pop();

                let element_ptr_type = self.get_llvm_typ(&typ);

                // %field_ptr15 = getelementptr %HolderType1, %HolderType1* %messages10, i32 0, i32 1
                // %field14 = load i8*, i8** %field_ptr15
                let element_ptr = self.get_element_ptr(&base_type, &base, &index_type, &index)?;
                let loaded_value = self.emit_load(&element_ptr_type, &element_ptr, None)?;
                self.push(element_ptr_type, loaded_value);
            }
            Instruction::SetElement => {
                let (value_type, value) = self.pop();
                let (index_type, index) = self.pop();
                let (base_type, base) = self.pop();

                let element_ptr = self.get_element_ptr(&base_type, &base, &index_type, &index)?;
                self.emit_store(&value_type, &value, &element_ptr)?;
            }
            Instruction::LoadParameter { index } => {
                let (name, typ) = self.parameter_names_and_types[index].clone();
                self.push(typ, name);
            }
            Instruction::LoadGlobalName { name, typ } => {
                let typ = self.get_llvm_typ(&typ);
                self.push(typ, format!("@{}", name));
            }
            Instruction::StoreLocal { index } => {
                let (value_type, value) = self.pop();
                let (local_type, local_name) = self.local_names[index].clone();
                log::info!(
                    "Local type = {} <<= value type = {}",
                    local_type,
                    value_type
                );
                // assert!(value_type == local_type);
                // Generate something like: store i64 %fuu_8, i64* %z_2
                self.emit_store(&value_type, &value, &local_name)?;
            }
            Instruction::LoadLocal { index } => {
                let (local_type, local_name) = self.local_names[index].clone();
                let new_var = self.emit_load(&local_type, &local_name, None)?;
                self.push(local_type, new_var);
            }
            Instruction::Jump(label) => {
                let label = self.get_label_ref(label);
                writeln!(self.w, "    br {}", label)?;
            }
            Instruction::JumpIf(label, else_label) => {
                let condition = self.pop_untyped();
                let label = self.get_label_ref(label);
                let else_label = self.get_label_ref(else_label);
                writeln!(self.w, "    br i1 {}, {}, {}", condition, label, else_label)?;
            }
            Instruction::JumpSwitch { default, options } => {
                // TODO: when using jump table with a value on the stack,
                // the stack must be saved somehow...

                // Integer to choose lives on stack now.
                let (typ, value) = self.pop();

                assert!(typ == "i64");

                let default_label = self.get_label_ref(default);

                assert!(!options.is_empty());
                let options: Vec<String> = options
                    .into_iter()
                    .map(|(value, label)| format!("i64 {}, {}", value, self.get_label_ref(label)))
                    .collect();

                writeln!(
                    self.w,
                    "    switch {} {}, {} [ {} ]",
                    typ,
                    value,
                    default_label,
                    options.join(" ")
                )?;
            }
            Instruction::Return(amount) => match amount {
                0 => {
                    writeln!(self.w, "    ret void")?;
                }
                1 => {
                    let (typ, value) = self.pop();
                    writeln!(self.w, "    ret {} {}", typ, value)?;
                }
                other => {
                    unimplemented!("Return {} values", other);
                }
            },
        };
        Ok(())
    }

    fn get_element_ptr(
        &mut self,
        base_type: &str,
        base: &str,
        index_type: &str,
        index: &str,
    ) -> Result<String, std::io::Error> {
        // let base_type2 = "%HolderType1";
        let element_ptr = self.new_local(None);
        // let element_typ = "u8*";
        log::info!("Base type = {}", base_type);

        // Example:
        // %HolderType1 = type { i8*, i8* }
        // %addr6 = getelementptr %HolderType1, %HolderType1* %new_op3, i32 0, i32 0
        // store i8* %cast4, i8** %addr6
        // assert!(base_type)
        assert!(is_pointer(base_type));
        writeln!(
            self.w,
            "    {} = getelementptr {}, {} {}, i32 0, {} {}",
            element_ptr,
            un_pointerize(base_type),
            base_type,
            base,
            index_type,
            index
        )?;

        Ok(element_ptr)
    }

    /// Emit LLVM load instruction
    ///
    /// Generate something like: %fuu_3 = load i64, i64* %x_0
    fn emit_load(
        &mut self,
        var_typ: &str,
        var_name: &str,
        hint: Option<String>,
    ) -> Result<String, std::io::Error> {
        let new_var = self.new_local(hint);
        writeln!(
            self.w,
            "    {} = load {}, {}* {}",
            new_var, var_typ, var_typ, var_name
        )?;

        Ok(new_var)
    }

    fn emit_store(
        &mut self,
        value_type: &str,
        value: &str,
        element_ptr: &str,
    ) -> Result<(), std::io::Error> {
        // Example:
        // %HolderType1 = type { i8*, i8* }
        // %addr6 = getelementptr %HolderType1, %HolderType1* %new_op3, i32 0, i32 0
        // store i8* %cast4, i8** %addr6
        writeln!(
            self.w,
            "    store {} {}, {}* {}",
            value_type, value, value_type, element_ptr
        )?;

        Ok(())
    }

    /// Generate LLVM code for a function call
    fn gen_call(
        &mut self,
        n_args: usize,
        typ: Option<bytecode::Typ>,
    ) -> Result<(), std::io::Error> {
        let mut args = vec![];
        for _ in 0..n_args {
            args.push(self.pop_typed());
        }
        args.reverse();

        let args = args.join(", ");
        let callee = self.pop_untyped();
        if let Some(typ) = typ {
            let res_var = self.new_local(None);
            let typ = self.get_llvm_typ(&typ);
            writeln!(
                self.w,
                "    {} = call {} {}({})",
                res_var, typ, callee, args
            )?;
            self.push(typ, res_var);
        } else {
            writeln!(self.w, "    call void {}({})", callee, args)?;
        }
        Ok(())
    }

    /// Contrapt a string literal in LLVM speak.
    fn gen_string_literal(&mut self, value: String) -> Result<(), std::io::Error> {
        // Add string to string literal pool!
        let literal_name = self.new_global();
        let literal_size = value.len() + 1;
        let literal = format!(
            r#"{} = private unnamed_addr constant [{} x i8] c"{}\00""#,
            literal_name, literal_size, value
        );
        self.string_literals.push(literal);
        let new_var = self.new_local(Some("str".to_owned()));
        writeln!(
            self.w,
            "    {} = getelementptr [{} x i8], [{} x i8]* {}, i64 0, i64 0",
            new_var, literal_size, literal_size, literal_name
        )?;
        self.push("i8*".to_owned(), new_var);
        Ok(())
    }

    fn push(&mut self, typ: String, name: String) {
        self.stack.push((typ, name));
    }

    fn pop(&mut self) -> (String, String) {
        self.stack.pop().unwrap()
    }

    fn pop_typed(&mut self) -> String {
        let (arg_ty, arg_name) = self.pop();
        format!("{} {}", arg_ty, arg_name)
    }

    fn pop_untyped(&mut self) -> String {
        let (_, arg_name) = self.pop();
        arg_name
    }
}

/// Remove trailing asterix from string
fn un_pointerize(llvm_type: &str) -> &str {
    let mut x = llvm_type.chars();
    // assert!(x.last().unwrap() == '*');
    let last_char = x.next_back().unwrap();
    assert!(last_char == '*');
    x.as_str()
}

fn is_pointer(llvm_type: &str) -> bool {
    let x = llvm_type.chars();
    x.last().unwrap() == '*'
}
