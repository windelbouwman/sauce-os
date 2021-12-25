/// Spit out LLVM IR text form
use super::bytecode;

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
    stack: Vec<(String, String)>,
    id_counter: usize,
    string_literals: Vec<String>,
}

impl<W> LLVMWriter<W>
where
    W: std::io::Write,
{
    fn new(w: W) -> Self {
        LLVMWriter {
            w,
            stack: vec![],
            id_counter: 0,
            string_literals: vec![],
        }
    }

    fn gen(&mut self, prog: bytecode::Program) -> Result<(), std::io::Error> {
        writeln!(self.w)?;
        writeln!(self.w, r"; Text generated!!")?;
        writeln!(self.w)?;
        // UGH: TODO: handle imports!
        writeln!(self.w, r"declare void @std_print(i8* nocapture) nounwind")?;
        writeln!(self.w)?;
        for function in prog.functions {
            self.gen_function(function)?;
        }

        for literal in &self.string_literals {
            writeln!(self.w, "{}", literal)?;
        }
        writeln!(self.w)?;

        Ok(())
    }

    fn new_id(&mut self) -> usize {
        let new_id = self.id_counter;
        self.id_counter += 1;
        new_id
    }
    fn new_local(&mut self) -> String {
        let new_id = self.new_id();
        format!("%fuu{}", new_id)
    }

    fn new_global(&mut self) -> String {
        let new_id = self.new_id();
        format!("@baz{}", new_id)
    }

    fn get_llvm_typ(ty: &bytecode::Typ) -> String {
        match ty {
            bytecode::Typ::Bool => "i1".to_owned(),
            bytecode::Typ::Int => "i64".to_owned(),
            bytecode::Typ::Float => "f64".to_owned(),
            bytecode::Typ::Ptr => "i8*".to_owned(),
            bytecode::Typ::Struct(_) => "i8*".to_owned(),
        }
    }

    fn gen_function(&mut self, func: bytecode::Function) -> Result<(), std::io::Error> {
        log::debug!("Generating function: {}", func.name);
        self.stack.clear();
        let parameters: Vec<String> = func
            .parameters
            .iter()
            .map(|p| format!("{} %{}", Self::get_llvm_typ(&p.typ), p.name))
            .collect();
        let p_text = parameters.join(", ");
        let return_type = "void";
        writeln!(
            self.w,
            "define {} @{}({}) {{",
            return_type, func.name, p_text
        )?;
        for instruction in func.code {
            self.gen_instruction(instruction)?;
        }
        writeln!(self.w, "    ret void")?;
        writeln!(self.w, "}}")?;
        writeln!(self.w)?;

        Ok(())
    }

    fn gen_instruction(
        &mut self,
        instruction: bytecode::Instruction,
    ) -> Result<(), std::io::Error> {
        use bytecode::Instruction;
        match instruction {
            Instruction::Operator { op, typ } => {
                let op: String = match op {
                    bytecode::Operator::Add => "add".to_owned(),
                    bytecode::Operator::Sub => "sub".to_owned(),
                    bytecode::Operator::Mul => "mul".to_owned(),
                    bytecode::Operator::Div => "div".to_owned(),
                };
                let typ = Self::get_llvm_typ(&typ);
                let rhs = self.pop_untyped();
                let lhs = self.pop_untyped();
                let new_var = self.new_local();
                writeln!(self.w, "    {} = {} {} {}, {};", new_var, op, typ, lhs, rhs)?;
                self.push(typ, new_var);
            }
            // Instruction::Nop => {
            // Easy, nothing to do here!!
            // }
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
                self.push("f64".to_owned(), format!("{}", value));
            }
            Instruction::Comparison { op, typ } => {
                let rhs = self.pop_untyped();
                let lhs = self.pop_untyped();
                let op: String = match op {
                    bytecode::Comparison::Lt => "icmp slt".to_owned(),
                    bytecode::Comparison::LtEqual => "icmp sle".to_owned(),
                    bytecode::Comparison::Gt => "icmp sgt".to_owned(),
                    bytecode::Comparison::GtEqual => "icmp sge".to_owned(),
                    bytecode::Comparison::Equal => "icmp eq".to_owned(),
                    bytecode::Comparison::NotEqual => {
                        unimplemented!("TODO!");
                    }
                };
                let typ = Self::get_llvm_typ(&typ);
                let new_var = self.new_local();
                // %binop10 = icmp slt i32 %a5, %b6
                writeln!(self.w, "    {} = {} {} {}, {}", new_var, op, typ, lhs, rhs)?;
                self.push("i1".to_owned(), new_var);
            }
            Instruction::Call { n_args, typ } => {
                self.gen_call(n_args, typ)?;
            }
            Instruction::GetAttr(index) => {
                let base = self.pop_untyped();
                let new_var = self.new_local();
                writeln!(self.w, "    {} = getelementptr {} {}", new_var, base, index)?;
                self.push("i1".to_owned(), new_var);
            }
            Instruction::SetAttr(index) => {
                let base = self.pop_untyped();
                let value = self.pop_untyped();
                writeln!(self.w, "    store {} {} {}", base, index, value)?;
            }
            Instruction::LoadName { name, typ } => {
                let typ = Self::get_llvm_typ(&typ);
                self.push(typ, format!("%{}", name));
            }
            Instruction::LoadGlobalName(name) => {
                self.push("".to_owned(), format!("@{}", name));
            }
            Instruction::StoreLocal { name, typ } => {
                let typ = Self::get_llvm_typ(&typ);
                let value = self.pop_untyped();
                writeln!(self.w, "    store {} = {} {}", name, typ, value)?;
            }
            Instruction::Label(label) => {
                writeln!(self.w, "  block{}:", label)?;
            }
            Instruction::Jump(label) => {
                writeln!(self.w, "    br label %block{}", label)?;
            }
            Instruction::JumpIf(label, else_label) => {
                let condition = self.pop_untyped();
                writeln!(
                    self.w,
                    "    br i1 {}, label %block{}, label %block{}",
                    condition, label, else_label
                )?;
            }
        };
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
        // TODO
        let (_, callee) = self.pop();
        if let Some(typ) = typ {
            let res_var = self.new_local();
            let typ = Self::get_llvm_typ(&typ);
            writeln!(self.w, "    res_var = call {} {}({})", typ, callee, args)?;
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
        let new_var = self.new_local();
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
