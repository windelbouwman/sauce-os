
from location import Location
from utils import panic
from datatypes import Dictionary, List, vec2, Option, option_unwrap_or, option_unwrap
import ast

fn transform(module: ast.Module):
    let t = Transformer:
        counter: 42
        class_rewriter: ClassRewriter()

    let t_visitor = ast.Visitor[Transformer]:
        data: t
        on_definition: transformer_on_definition
        on_type: transformer_on_type
        on_statement: transformer_on_statement
        on_expression: transformer_on_expression
        on_node: transformer_on_node

    ast.visit_module(t_visitor, module)

    t_visitor.on_statement = transformer_on_statement2

    ast.visit_module(t_visitor, module)

struct Transformer:
    counter: int
    class_rewriter: ClassRewriter

fn transformer_on_definition(transformer: Transformer, definition: ast.Definition, phase: ast.VisitPhase):
    pass

fn transformer_on_type(transformer: Transformer, ty: ast.MyType, phase: ast.VisitPhase):
    pass

fn transformer_on_statement(transformer: Transformer, statement: ast.Statement, phase: ast.VisitPhase):
    case phase:
        Post:
            case statement.kind:
                Loop(x):
                    let condition = ast.bool_literal(true, statement.location)
                    let w = ast.WhileStatement:
                        condition: condition
                        body: x.body
                    statement.kind = ast.StatementKind.While(w)
                Case(case_statement):
                    statement.kind = transform_case(case_statement).kind
            else:
                pass
    else:
        pass

fn transformer_on_statement2(transformer: Transformer, statement: ast.Statement, phase: ast.VisitPhase):
    case phase:
        Post:
            transform_statement2(statement)
    else:
        pass

fn transformer_on_expression(transformer: Transformer, expression: ast.Expression, phase: ast.VisitPhase):
    case phase:
        Post:
            case expression.kind:
                ClassLiteral(ty):
                    # Call constructor instead!
                    # rewrite_class_literal
                    
                    # expression.kind = ctor_call.kind
                    pass
            else:
                pass
    else:
        pass

fn transformer_on_node(transformer: Transformer, node: ast.VisitNode, phase: ast.VisitPhase):
    pass


fn transform_statement2(statement: ast.Statement):
    case statement.kind:
        Switch(switch_statement):
            statement.kind = transform_switch(switch_statement, statement.location)
    else:
        pass

class ClassRewriter:
    var ctor_map: Dictionary[ast.FunctionDef] = Dictionary()
    var new_definitions: List[ast.Definition] = List()

    fn rewrite_class_def(class_def: ast.ClassDef):
        let init_values: List[ast.Expression] = List()
        let methods: List[ast.FunctionDef] = List()
        let builder = ast.StructBuilder()

        let type_arguments: List[ast.MyType] = List()
        for type_parameter in class_def.type_parameters:
            let type_parameter_ref = builder.add_type_parameter(this.unique_name(type_parameter.node_id.name), 13333, type_parameter.location)
            type_arguments.append(type_parameter_ref)
        let m = ast.create_subst_mapping(class_def.type_parameters, type_arguments)

        for definition in class_def.definitions:
            case definition:
                Var(var_def):
                    builder.add_field(var_def.variable.name, ast.subst(var_def.variable.ty, m), var_def.location)
                    init_values.append(var_def.value)
                Function(function_def):
                    methods.append(function_def)
            else:
                panic("only fields and functions expected")

        let struct_def = builder.finish()
        this.new_definitions.append(ast.Definition.Struct(struct_def))

        # Lift methods:
        for method in methods:
            this.lift_method(method, class_def, struct_def)

        this.create_constructor(class_def, struct_def, init_values)

    fn lift_method(method: ast.FunctionDef, class_def: ast.ClassDef, struct_def: ast.StructDef):
        let type_arguments: List[ast.MyType] = List()
        for type_parameter in class_def.type_parameters:
            type_parameter = ast.type_parameter(type_parameter.node_id.name, 1337, type_parameter.location)
            method.type_parameters.append(type_parameter)
            type_arguments.append(ast.type_parameter_ref(type_parameter))
        let struct_type = ast.apply_tycon(ast.TyCon.Struct(struct_def), type_arguments)
        let this_param = ast.parameter_def("this2", struct_type, method.location)
        method.parameters.prepend(this_param)
        this.new_definitions.append(ast.Definition.Function(method))

    fn create_constructor(class_def: ast.ClassDef, struct_def: ast.StructDef, init_values: List[ast.Expression]):
        # Create constructor function
        let ctor_name = "{class_def.node_id.name}_ctor"
        let type_parameters: List[ast.TypeParameter] = List()
        let except_type = ast.void_type()
        let parameters: List[ast.ParameterDef] = List()
        let type_arguments: List[ast.MyType] = List()
        for type_parameter in class_def.type_parameters:
            type_parameter = ast.type_parameter(type_parameter.node_id.name, 1337, type_parameter.location)
            type_parameters.append(type_parameter)
            type_arguments.append(ast.type_parameter_ref(type_parameter))
        let struct_type = ast.apply_tycon(ast.TyCon.Struct(struct_def), type_arguments)
        let init_literal = ast.struct_literal(struct_type, init_values, class_def.location)
        let body = ast.return_statement(Option.Some(init_literal), class_def.location)
        let ctor_func = ast.function_def(ctor_name, type_parameters, parameters, struct_type, except_type, body, class_def.location)
        this.new_definitions.append(ast.Definition.Function(ctor_func))

    fn rewrite_class_literal(ty: ast.MyType, location: Location):
        # TODO: figure out how to store ctor's related to classes
        let ctor_func_def: ast.FunctionDef = option_unwrap(this.ctor_map.get("??"))
        let symbol = ast.Symbol.Function(ctor_func_def)
        let ctor_func_ref = ast.load_symbol(symbol, ast.get_function_type(ctor_func_def), location)
        let struct_ty: ast.MyType = ast.undefined_type()
        let ctor_call = ast.call(ctor_func_ref, List(), struct_ty, location)
    
    fn unique_name(hint: str) -> str:
        # TODO: figure out unique name
        return hint

fn transform_switch(switch_statement: ast.SwitchStatement, location: Location) -> ast.StatementKind:
    # Turn switch into sequence of if-else
    # TODO: get unique ID!
    let x_var = ast.variable("x", ast.int_type())
    let let_x = ast.let_statement(x_var, Option.None(), switch_statement.value, location)

    let else_clause = switch_statement.default_body
    for arm in switch_statement.arms:
        let x_ref = ast.var_ref(x_var, arm.location)
        let eq_op = ast.BinaryOperator.Equals()
        let eq_ty = ast.bool_type()
        let condition = ast.binop(x_ref, eq_op, arm.value, eq_ty, arm.location)
        else_clause = ast.if_statement(condition, arm.body, else_clause, arm.location)
    
    return ast.StatementKind.Compound(vec2(let_x, else_clause))

fn transform_case(case_statement: ast.CaseStatement) -> ast.Statement:
    # TODO: support doc strings
    # """ Transform case statement into switch case over tagged unions. """
    let location = case_statement.value.location
    # TODO: unique name for x.
    let x_var = ast.variable("x", ast.undefined_type())
    let store_tagged_union = ast.let_statement(x_var, Option.None(), case_statement.value, location)

    let switch_arms: List[ast.SwitchArm] = List()
    for arm in case_statement.arms:
        let arm_tag = 1337
        let switch_arm_value = ast.integer_literal(arm_tag, arm.location)
        let switch_arm_body: List[ast.Statement] = List()

        # Unpack payload:
        if arm.variables.len() == 1:
            let payload_value1: ast.Expression = ast.var_ref(x_var, arm.location)
            # ast.get_attr()
            let store_var1 = ast.let_statement(arm.variables.first(), Option.None(), payload_value1, arm.location)
            switch_arm_body.append(store_var1)
        elif arm.variables.len() > 1:
            for variable in arm.variables:
                let payload_value2: ast.Expression = ast.var_ref(x_var, arm.location)
                let store_var2 = ast.let_statement(variable, Option.None(), payload_value2, arm.location)
                switch_arm_body.append(store_var2)

        switch_arm_body.append(arm.body)
        let switch_arm = ast.SwitchArm:
            location: arm.location
            value: switch_arm_value
            body: ast.compound(switch_arm_body, arm.location)
        switch_arms.append(switch_arm)
    
    let switch_default_code: ast.Statement = option_unwrap_or(case_statement.else_clause, ast.pass_statement(location))

    let switch_value = ast.var_ref(x_var, location)
    let switch_on_tag = ast.switch_statement(switch_value, switch_arms, switch_default_code, location)

    return ast.compound(vec2(store_tagged_union, switch_on_tag), location)