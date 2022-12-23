use crate::semantics::type_system::SlangType;
use crate::semantics::typed_ast;
use crate::semantics::{Context, Scope, Symbol};

use std::rc::Rc;
use std::sync::Arc;

pub fn define_builtins(scope: &mut Scope) {
    // Built in types:
    // let location: Location = Default::default();
    scope.define("str".to_owned(), Symbol::Typ(SlangType::String));
    scope.define("int".to_owned(), Symbol::Typ(SlangType::Int));
    scope.define("float".to_owned(), Symbol::Typ(SlangType::Float));
    scope.define("bool".to_owned(), Symbol::Typ(SlangType::Bool));
    /*
    let list_class_typ = ClassTypeRef::new(ClassType {
        name: "List".to_owned(),
        fields: vec![],
        methods: vec![],
    });

    let list_generic_type: SlangType = SlangType::Generic {
        base: Box::new(SlangType::Class(list_class_typ)),
        type_parameters: vec!["x".to_string()],
    };
    self.define("list", Symbol::Typ(list_generic_type), &location);
    */
}

/// Define functions provided by 'std' module.
pub fn load_std_module(context: &mut Context) {
    let mut std_scope = Scope::new();

    // TODO: these could be loaded from interface/header like file?
    std_scope.define_func(
        context,
        "putc",
        vec![("char".to_owned(), SlangType::String)],
        None,
    );
    std_scope.define_func(
        context,
        "print",
        vec![("message".to_owned(), SlangType::String)],
        None,
    );
    std_scope.define_func(
        context,
        "read_file",
        vec![("filename".to_owned(), SlangType::String)],
        Some(SlangType::String),
    );
    std_scope.define_func(
        context,
        "int_to_str",
        vec![("value".to_owned(), SlangType::Int)],
        Some(SlangType::String),
    );
    std_scope.define_func(
        context,
        "float_to_str",
        vec![("value".to_owned(), SlangType::Float)],
        Some(SlangType::String),
    );
    let name = "std".to_owned();

    let std_module = typed_ast::Program {
        name: name.clone(),
        path: Default::default(),
        generics: vec![],
        definitions: vec![],
        scope: Arc::new(std_scope),
    };

    context
        .modules_scope
        .define(name, Symbol::Module(Rc::new(std_module)));
}
