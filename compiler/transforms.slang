
from location import Location
from utils import panic, log_info
from datatypes import Dictionary, List, vec2, Option, option_unwrap_or, option_unwrap
import ast

fn transform(module: ast.Module):
    log_info("Transforming")
    let t = Transformer:
        class_rewriter: ClassRewriter()

    # Phase 1
    let visitor = ast.Visitor[Transformer]:
        data: t
        on_definition: transformer_on_definition
        on_type: transformer_on_type
        on_statement: transformer_on_statement1
        on_expression: transformer_on_expression1
        on_node: transformer_on_node

    ast.visit_module(visitor, module)

    # Filter class-defs:
    let new_defs2: List[ast.Definition] = List()
    for def2 in module.definitions:
        case def2:
            Class(c):
                pass
        else:
            new_defs2.append(def2)

    new_defs2.extend(t.class_rewriter.new_definitions)
    module.definitions = new_defs2

    # Phase 2
    visitor.on_statement = transformer_on_statement2
    visitor.on_expression = transformer_on_expression2
    ast.visit_module(visitor, module)

struct Transformer:
    class_rewriter: ClassRewriter

fn transformer_on_definition(transformer: Transformer, definition: ast.Definition, phase: ast.VisitPhase):
    case phase:
        Post:
            case definition:
                Class(class_def):
                    transformer.class_rewriter.rewrite_class_def(class_def)
            else:
                pass
    else:
        pass


fn transformer_on_type(transformer: Transformer, ty: ast.Type, phase: ast.VisitPhase):
    pass

fn transformer_on_statement1(transformer: Transformer, statement: ast.Statement, phase: ast.VisitPhase):
    case phase:
        Post:
            case statement.kind:
                Loop(loop_statement):
                    let condition = ast.bool_literal(value: true, location: statement.location)
                    let while_statement = ast.WhileStatement(condition, body: loop_statement.body)
                    statement.kind = ast.StatementKind.While(while_statement)
                Case(case_statement):
                    statement.kind = transformer.class_rewriter.transform_case(case_statement).kind
            else:
                pass
    else:
        pass

fn transformer_on_statement2(transformer: Transformer, statement: ast.Statement, phase: ast.VisitPhase):
    case phase:
        Post:
            case statement.kind:
                Switch(switch_statement):
                    statement.kind = transformer.class_rewriter.transform_switch(switch_statement, location: statement.location)
            else:
                pass
    else:
        pass


fn transformer_on_expression1(transformer: Transformer, expression: ast.Expression, phase: ast.VisitPhase):
    case phase:
        Post:
            case expression.kind:
                Call(call):
                    case call.callee.kind:
                        GetAttr(base, name):
                            # Method call!
                            let function_def: ast.FunctionDef = ast.get_method_from_type(ty: base.ty, attr: name)
                            let this_arg = ast.LabeledExpression(location: base.location, name: Option.Some("this"), value: base)
                            let arguments = call.arguments
                            arguments.prepend(this_arg)
                            let ty = ast.undefined_type()
                            call.callee = ast.load_symbol(symbol: ast.Symbol.Function(function_def), ty, location: expression.location)
                    else:
                        pass
            else:
                pass
    else:
        pass

fn transformer_on_expression2(transformer: Transformer, expression: ast.Expression, phase: ast.VisitPhase):
    case phase:
        Post:
            case expression.kind:
                ClassLiteral(ty, arguments):
                    # Call constructor instead!
                    let ctor_call = transformer.class_rewriter.rewrite_class_literal(ty, arguments, location: expression.location)
                    expression.kind = ctor_call.kind
                    expression.ty = ctor_call.ty
            else:
                pass
    else:
        pass

fn transformer_on_node(transformer: Transformer, node: ast.VisitNode, phase: ast.VisitPhase):
    pass


class ClassRewriter:
    var ctor_map: Dictionary[ast.FunctionDef] = Dictionary()
    var new_definitions: List[ast.Definition] = List()

    fn rewrite_class_def(class_def: ast.ClassDef):
        log_info("Rewriting class def {class_def.id.name}")
        let ctor_parameters: List[ast.ParameterDef] = List()
        let init_values: List[ast.Expression] = List()
        let methods: List[ast.FunctionDef] = List()
        let builder = ast.StructBuilder()
        builder.set_name(name: class_def.id.name)

        let type_arguments: List[ast.Type] = List()
        for type_parameter in class_def.type_parameters:
            let type_parameter_ref = builder.add_type_parameter(name: this.unique_name(hint: type_parameter.id.name), id: 13333, location: type_parameter.location)
            type_arguments.append(type_parameter_ref)
        let m = ast.create_subst_mapping(type_parameters: class_def.type_parameters, type_arguments)

        for definition in class_def.definitions:
            case definition:
                Var(var_def):
                    let ty = ast.subst(ty: var_def.variable.ty, m)
                    builder.add_field(name: var_def.variable.id.name, ty, location: var_def.location)
                    case var_def.value:
                        Some(iv2):
                            init_values.append(iv2)
                            # log_info("Init val")
                        None:
                            # Create a c-tor parameter
                            # log_info("c-tor param")
                            let ctor_param = ast.parameter_def(name: var_def.variable.id.name, id: 13333, label_is_optional: false, ty, location: class_def.location)
                            ctor_parameters.append(ctor_param)
                            let symbol = ast.Symbol.Parameter(ctor_param)
                            let iv2 = ast.load_symbol(symbol, ty, location: class_def.location)
                            init_values.append(iv2)
                Function(function_def):
                    methods.append(function_def)
            else:
                panic("only fields and functions expected")

        let struct_def = builder.finish()
        this.new_definitions.append(ast.Definition.Struct(struct_def))

        # Lift methods:
        for method in methods:
            this.lift_method(method, class_def, struct_def)

        this.create_constructor(class_def, struct_def, parameters: ctor_parameters, init_values)

    fn lift_method(method: ast.FunctionDef, class_def: ast.ClassDef, struct_def: ast.StructDef):
        let type_arguments: List[ast.Type] = List()
        for type_parameter in class_def.type_parameters:
            type_parameter = ast.new_type_parameter(name: type_parameter.id.name, id: this.get_unique_id(), location: type_parameter.location)
            method.type_parameters.append(type_parameter)
            type_arguments.append(ast.type_parameter_ref(type_parameter))
        let struct_type = ast.apply_tycon(tycon: ast.TyCon.Struct(struct_def), type_arguments)
        method.id.name = "{class_def.id.name}_{method.id.name}"
        let this_parameter = option_unwrap(method.this_parameter)
        ast.change_type_to(ty: this_parameter.ty, ty2: struct_type)
        method.parameters.prepend(this_parameter)
        this.new_definitions.append(ast.Definition.Function(method))

    fn create_constructor(class_def: ast.ClassDef, struct_def: ast.StructDef, parameters: List[ast.ParameterDef], init_values: List[ast.Expression]):
        # Create constructor function
        let ctor_name = "{class_def.id.name}_ctor"
        let type_parameters: List[ast.TypeParameter] = List()
        let except_type = ast.void_type()
        let type_arguments: List[ast.Type] = List()
        for type_parameter in class_def.type_parameters:
            type_parameter = ast.new_type_parameter(name: type_parameter.id.name, id: this.get_unique_id(), location: type_parameter.location)
            type_parameters.append(type_parameter)
            type_arguments.append(ast.type_parameter_ref(type_parameter))
        let struct_type = ast.apply_tycon(tycon: ast.TyCon.Struct(struct_def), type_arguments)
        let init_literal = ast.struct_literal(ty: struct_type, values: init_values, location: class_def.location)
        let body = ast.return_statement(value: Option.Some(init_literal), location: class_def.location)
        let ctor_func = ast.function_def(name: ctor_name, id: this.get_unique_id(), type_parameters, this_parameter: Option.None(), parameters, return_type: struct_type, except_type, body, location: class_def.location)
        this.ctor_map.insert(key: ctor_name, value: ctor_func)
        this.new_definitions.append(ast.Definition.Function(ctor_func))

    fn rewrite_class_literal(ty: ast.Type, arguments: List[ast.LabeledExpression], location: Location) -> ast.Expression:
        # TODO: figure out how to store ctor's related to classes
        let class_def = ast.get_class_def_from_type(ty)
        let ctor_name = "{class_def.id.name}_ctor"
        let ctor_func_def: ast.FunctionDef = option_unwrap(this.ctor_map.get(key: ctor_name))
        let symbol = ast.Symbol.Function(ctor_func_def)
        let ctor_func_ref = ast.load_symbol(symbol, ty: ast.get_function_type(function_def: ctor_func_def), location)
        let struct_ty: ast.Type = ast.undefined_type()
        let ctor_call = ast.call(callee: ctor_func_ref, arguments, ty: struct_ty, location)
        return ctor_call

    fn unique_name(hint: str) -> str:
        # TODO: figure out unique name
        # TODO: get unique ID!
        return hint
    
    fn get_unique_id() -> int:
        # TODO, create unique ID
        return 133
    
    fn new_variable(name: str, ty: ast.Type) -> ast.Variable:
        # Create a new variable with unique id
        let id = this.get_unique_id()
        return ast.variable(name: this.unique_name(hint: name), id, ty)

    fn transform_switch(switch_statement: ast.SwitchStatement, location: Location) -> ast.StatementKind:
        # Turn switch into sequence of if-else
        let x_var = this.new_variable(name: "x", ty: ast.int_type())
        let let_x = ast.let_statement(variable: x_var, type_hint: Option.None(), value: switch_statement.value, location)

        let else_clause = switch_statement.default_body
        for arm in switch_statement.arms:
            let x_ref = ast.var_ref(variable: x_var, location: arm.location)
            let eq_op = ast.BinaryOperator.Equals()
            let eq_ty = ast.bool_type()
            let condition = ast.binop(lhs: x_ref, op: eq_op, rhs: arm.value, ty: eq_ty, location: arm.location)
            else_clause = ast.if_statement(condition, body: arm.body, false_body: else_clause, location: arm.location)
        
        return ast.StatementKind.Compound(vec2(let_x, else_clause))

    fn transform_case(case_statement: ast.CaseStatement) -> ast.Statement:
        # TODO: support doc strings
        # """ Transform case statement into switch case over tagged unions. """
        let location = case_statement.value.location
        let x_var = this.new_variable(name: "x", ty: ast.undefined_type())
        let store_tagged_union = ast.let_statement(variable: x_var, type_hint: Option.None(), value: case_statement.value, location)

        let switch_arms: List[ast.SwitchArm] = List()
        for arm in case_statement.arms:
            let arm_tag = 1337
            let switch_arm_value = ast.integer_literal(value: arm_tag, location: arm.location)
            let switch_arm_body: List[ast.Statement] = List()

            # Unpack payload:
            if arm.variables.len() == 1:
                let payload_value1: ast.Expression = ast.var_ref(variable: x_var, location: arm.location)
                # ast.get_attr()
                let store_var1 = ast.let_statement(variable: arm.variables.first(), type_hint: Option.None(), value: payload_value1, location: arm.location)
                switch_arm_body.append(store_var1)
            elif arm.variables.len() > 1:
                for variable in arm.variables:
                    let payload_value2: ast.Expression = ast.var_ref(variable: x_var, location: arm.location)
                    let store_var2 = ast.let_statement(variable, type_hint: Option.None(), value: payload_value2, location: arm.location)
                    switch_arm_body.append(store_var2)

            switch_arm_body.append(arm.body)
            let switch_arm = ast.SwitchArm:
                location: arm.location
                value: switch_arm_value
                body: ast.compound(inner: switch_arm_body, location: arm.location)
            switch_arms.append(switch_arm)
        
        let switch_default_code: ast.Statement = option_unwrap_or(option: case_statement.else_clause, default: ast.pass_statement(location))

        let switch_value = ast.var_ref(variable: x_var, location)
        let switch_on_tag = ast.switch_statement(value: switch_value, arms: switch_arms, default_body: switch_default_code, location)

        return ast.compound(inner: vec2(store_tagged_union, switch_on_tag), location)

