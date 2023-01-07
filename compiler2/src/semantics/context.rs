use super::id_generator::IdGenerator;
use crate::tast::Scope;
use std::sync::Arc;

pub struct Context {
    pub id_generator: IdGenerator,
    pub builtin_scope: Arc<Scope>,
    pub modules_scope: Scope,
}

impl Context {
    pub fn new(builtin_scope: Scope) -> Self {
        let id_generator = IdGenerator::new();
        let modules_scope = Scope::new();
        Self {
            id_generator,
            builtin_scope: Arc::new(builtin_scope),
            modules_scope,
        }
    }
}
