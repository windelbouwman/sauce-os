
# Available transformations:
# - Turn for-loops into while-loops
# - Turn classes into structs with functions
# - Turn enums into tagged unions
# - Turn switch-statement into chain of if-statements

# Ideas for transformations:
# - Transform try/except into something else

from location import Location
# from std import print
from utils import panic, log_info, log_debug, assert
from basepass import IdGen
from typechecking import type_check_modules
from datatypes import Dictionary, List, vec1, vec2, vec3, Option, option_unwrap_or, option_unwrap
from errors import CompilationError
import ast

fn transform(module_set: ast.ModuleSet, id_gen: IdGen, rt_module: ast.Module) except CompilationError:
    # log_info("Transforming {module.name}")
    let transformer = Transformer:
        class_rewriter: ClassRewriter(id_gen, rt_module)

    let visitor = ast.Visitor[Transformer]:
        data: transformer
        on_definition: transformer_on_definition0
        on_type: transformer_on_type0
        on_statement: transformer_on_statement0
        on_expression: transformer_on_expression0
        on_node: transformer_on_node0

    # Phase 1-a:
    # - Rewrite for-loops into while loops
    # - Rewrite loops into while loops
    # - Rewrite ToString contraptions
    visitor.on_definition = transformer_on_definition0
    visitor.on_type = transformer_on_type0
    visitor.on_statement = transformer_on_statement1
    visitor.on_expression = transformer_on_expression1
    visitor.on_node = transformer_on_node0
    ast.visit_module_set(visitor, module_set)

    # Phase 1-b:
    # - Rewrite for-loops into while loops
    # - Rewrite loops into while loops
    # - Rewrite enum definitions into struct definitions
    # - Rewrite classes into structs with functions
    # - Rewrite ToString contraptions
    visitor.on_definition = transformer_on_definition1
    visitor.on_type = transformer_on_type0
    visitor.on_statement = transformer_on_statement0
    visitor.on_expression = transformer_on_expression0
    visitor.on_node = transformer_on_node0

    for module in module_set.modules:
        ast.visit_module(visitor, module)

        # Filter class-defs:
        let new_defs2: List[ast.Definition] = List()
        for def2 in module.definitions:
            case def2:
                Class(c):
                    pass
                Enum(e):
                    pass
            else:
                new_defs2.append(def2)

        new_defs2.extend(transformer.class_rewriter.new_definitions)
        module.definitions = new_defs2

    # ast.print_ast(module)

    # Phase 2:
    # - Rewrite call to get-attr into call with base as first argument
    visitor.on_definition = transformer_on_definition0
    visitor.on_type = transformer_on_type0
    visitor.on_statement = transformer_on_statement0
    visitor.on_expression = transformer_on_expression2
    visitor.on_node = transformer_on_node0
    ast.visit_module_set(visitor, module_set)

    # Phase 3:
    # - Rewrite case statement into switch statement
    # - Rewrite class literal into call to constructor
    # - Rewrite enum literal into struct literal
    visitor.on_definition = transformer_on_definition0
    visitor.on_type = transformer_on_type0
    visitor.on_statement = transformer_on_statement3
    visitor.on_expression = transformer_on_expression3
    visitor.on_node = transformer_on_node0
    ast.visit_module_set(visitor, module_set)

    # Phase 5:
    # - Change enum types into corresponding struct types
    # - Change class types into corresponding struct types
    # - Rewrite switch statement into chain of if statements
    visitor.on_definition = transformer_on_definition0
    visitor.on_type = transformer_on_type5
    visitor.on_statement = transformer_on_statement5
    visitor.on_expression = transformer_on_expression0
    visitor.on_node = transformer_on_node0
    ast.visit_module_set(visitor, module_set)

    # TBD:
    # Optionally check types in between?
    type_check_modules(module_set)

    log_info("Type erasure")

    # Phase 7a: apply type erasure (part 1), this involves:
    # - Apply cast to opaque pointer for generic parameters when calling a function
    visitor.on_definition = transformer_on_definition0
    visitor.on_type = transformer_on_type0
    visitor.on_statement = transformer_on_statement7
    visitor.on_expression = transformer_on_expression7
    visitor.on_node = transformer_on_node7
    ast.visit_module_set(visitor, module_set)

    # Phase 7b: apply type erasure (part 2), this involves:
    # - Remove type parameters from structs and functions
    # - Remove type arguments from type applications
    visitor.on_definition = transformer_on_definition7
    visitor.on_type = transformer_on_type7
    visitor.on_statement = transformer_on_statement0
    visitor.on_expression = transformer_on_expression0
    visitor.on_node = transformer_on_node0
    ast.visit_module_set(visitor, module_set)


struct Transformer:
    class_rewriter: ClassRewriter

fn transformer_on_definition0(transformer: Transformer, definition: ast.Definition, phase: ast.VisitPhase):
    pass

fn transformer_on_definition1(transformer: Transformer, definition: ast.Definition, phase: ast.VisitPhase):
    case phase:
        Post:
            case definition:
                Class(class_def):
                    transformer.class_rewriter.rewrite_class_def(class_def)
                Enum(enum_def):
                    transformer.class_rewriter.rewrite_enum_def(enum_def)
            else:
                pass
    else:
        pass

fn transformer_on_definition7(transformer: Transformer, definition: ast.Definition, phase: ast.VisitPhase):
    case phase:
        Post:
            # Remove type parameters. They are all opaque pointers now.
            case definition:
                Struct(struct_def):
                    struct_def.type_parameters.clear()
                Function(function_def):
                    function_def.type_parameters.clear()
                ExternFunction(extern_function_def):
                    pass
                Var(var_def):
                    pass
            else:
                panic("Only structs and functions supported during type erasure!")
    else:
        pass

fn transformer_on_type0(transformer: Transformer, ty: ast.Type, phase: ast.VisitPhase):
    pass

fn transformer_on_type5(transformer: Transformer, ty: ast.Type, phase: ast.VisitPhase):
    case phase:
        Post:
            case ty.kind:
                App(tycon, type_arguments):
                    case tycon:
                        Class(class_def):
                            let struct_def = option_unwrap(transformer.class_rewriter.struct_map.get(key: ast.node_id_to_string(class_def.id)))
                            ty.kind = ast.TypeKind.App(ast.TyCon.Struct(struct_def), type_arguments)
                        Enum(enum_def):
                            let struct_def = option_unwrap(transformer.class_rewriter.struct_map.get(key: ast.node_id_to_string(enum_def.id)))
                            ty.kind = ast.TypeKind.App(ast.TyCon.Struct(struct_def), type_arguments)
                    else:
                        pass
            else:
                pass
    else:
        pass

fn transformer_on_type7(transformer: Transformer, ty: ast.Type, phase: ast.VisitPhase):
    case phase:
        Post:
            if ast.is_type_parameter_type(ty):
                ast.change_type_to(ty, ty2: ast.opaque_type())
            elif ast.is_tycon_app_type(ty):
                let type_arguments = ast.get_type_arguments_from_type(ty)
                type_arguments.clear()
    else:
        pass



fn transformer_on_statement0(transformer: Transformer, statement: ast.Statement, phase: ast.VisitPhase):
    pass

fn transformer_on_statement1(transformer: Transformer, statement: ast.Statement, phase: ast.VisitPhase):
    case phase:
        Post:
            case statement.kind:
                Loop(loop_statement):
                    let condition = ast.bool_literal(value: true, location: statement.location)
                    let while_statement = ast.WhileStatement(condition, block: loop_statement.block)
                    statement.kind = ast.StatementKind.While(while_statement)
                For(for_statement):
                    statement.kind = transformer.class_rewriter.transform_for_loop(for_statement, location: statement.location).kind
            else:
                pass
    else:
        pass

fn transformer_on_statement3(transformer: Transformer, statement: ast.Statement, phase: ast.VisitPhase):
    case phase:
        Post:
            case statement.kind:
                Case(case_statement):
                    statement.kind = transformer.class_rewriter.transform_case(case_statement).kind
            else:
                pass
    else:
        pass

fn transformer_on_statement5(transformer: Transformer, statement: ast.Statement, phase: ast.VisitPhase):
    case phase:
        Post:
            case statement.kind:
                Switch(switch_statement):
                    statement.kind = transformer.class_rewriter.transform_switch(switch_statement, location: statement.location)
            else:
                pass
    else:
        pass

fn transformer_on_statement7(transformer: Transformer, statement: ast.Statement, phase: ast.VisitPhase):
    case phase:
        Post:
            case statement.kind:
                Assignment(target, op, expr):
                    # Check if we must do type erasure:
                    transformer.class_rewriter.erase_type(ft: target.ty, value: expr, assign: true)

                    # If we cast to a value, we must move the cast to the value side

                    case target.kind:
                        TypeCast(typ, value):
                            if ast.is_opaque_type(value.ty) or ast.is_type_parameter_type(value.ty):
                                ast.change_expression_to(expression: target, to: value)
                            else:
                                panic("Only supported type cast from opaque as assignment target (not {ast.type_to_string(value.ty)})")
                    else:
                        pass

            else:
                pass
    else:
        pass

fn transformer_on_expression0(transformer: Transformer, expression: ast.Expression, phase: ast.VisitPhase):
    pass

fn transformer_on_expression1(transformer: Transformer, expression: ast.Expression, phase: ast.VisitPhase):
    case phase:
        Post:
            case expression.kind:
                ToString(value):
                    # Rewrite To String
                    # log_info("Rewrite to-string")
                    if ast.is_str_type(value.ty):
                        ast.change_expression_to(expression, to: value)
                    elif ast.is_int_type(value.ty):
                        # call int-to-str
                        let int_to_str_func = transformer.class_rewriter.load_std_function(name: "int_to_str", location: expression.location)
                        let arg1 = ast.LabeledExpression(name: Option.Some("value"), value, location: expression.location)
                        let arguments = vec1(arg1)
                        let call = ast.call(callee: int_to_str_func, arguments, ty: ast.str_type(), location: expression.location)
                        ast.change_expression_to(expression, to: call)
                    elif ast.is_char_type(value.ty):
                        # call char-to-str
                        let char_to_str_func = transformer.class_rewriter.load_std_function(name: "char_to_str", location: expression.location)
                        let arg1 = ast.LabeledExpression(name: Option.Some("value"), value, location: expression.location)
                        let arguments = vec1(arg1)
                        let call = ast.call(callee: char_to_str_func, arguments, ty: ast.str_type(), location: expression.location)
                        ast.change_expression_to(expression, to: call)
                    else:
                        panic("Invalid type for to-string")
            else:
                pass
    else:
        pass

fn transformer_on_expression2(transformer: Transformer, expression: ast.Expression, phase: ast.VisitPhase):
    case phase:
        Post:
            case expression.kind:
                Call(call):
                    case call.callee.kind:
                        GetAttr(base, name):
                            if ast.is_class_type(base.ty):
                                # Rewrite method call
                                # log_info("Rewrite method call")
                                let function_def: ast.FunctionDef = ast.get_method_from_type(ty: base.ty, attr: name)
                                let this_arg = ast.LabeledExpression(location: base.location, name: Option.Some("this"), value: base)
                                let arguments = call.arguments
                                arguments.prepend(this_arg)
                                let type_arguments = ast.get_type_arguments_from_type(base.ty)
                                call.callee = ast.function_ref(function_def, type_arguments, location: expression.location)
                    else:
                        pass
                Binop(op):
                    if ast.is_str_type(op.lhs.ty):
                        case op.op:
                            Add:
                                # Rewrite adding of strings by calling a runtime str_concat function
                                let str_concat_func = transformer.class_rewriter.load_std_function(name: "str_concat", location: expression.location)
                                let lhs_arg = ast.LabeledExpression(name: Option.None(), value: op.lhs, location: op.lhs.location)
                                let rhs_arg = ast.LabeledExpression(name: Option.None(), value: op.rhs, location: op.rhs.location)
                                let arguments = vec2(lhs_arg, rhs_arg)
                                let call = ast.call(callee: str_concat_func, arguments, ty: ast.str_type(), location: expression.location)
                                ast.change_expression_to(expression, to: call)

                            Equals:
                                # Rewrite '==' for strings into call to runtime function.
                                let str_compare_func = transformer.class_rewriter.load_std_function(name: "str_compare", location: expression.location)
                                let lhs_arg = ast.LabeledExpression(name: Option.None(), value: op.lhs, location: op.lhs.location)
                                let rhs_arg = ast.LabeledExpression(name: Option.None(), value: op.rhs, location: op.rhs.location)
                                let arguments = vec2(lhs_arg, rhs_arg)
                                let call = ast.call(callee: str_compare_func, arguments, ty: ast.bool_type(), location: expression.location)
                                ast.change_expression_to(expression, to: call)

                        else:
                            panic("Can only add or compare str types.")
            else:
                pass
    else:
        pass

fn transformer_on_expression3(transformer: Transformer, expression: ast.Expression, phase: ast.VisitPhase):
    case phase:
        Post:
            case expression.kind:
                ClassLiteral(ty, arguments):
                    # Call constructor instead!
                    let ctor_call = transformer.class_rewriter.rewrite_class_literal(ty, arguments, location: expression.location)
                    ast.change_expression_to(expression, to: ctor_call)
                EnumLiteral(ty, variant, values):
                    let struct_literal = transformer.class_rewriter.rewrite_enum_literal(enum_ty: ty, variant, values, location: expression.location)
                    ast.change_expression_to(expression, to: struct_literal)
            else:
                pass
    else:
        pass

fn transformer_on_expression7(transformer: Transformer, expression: ast.Expression, phase: ast.VisitPhase):
    case phase:
        Post:
            case expression.kind:
                Call(call):
                    # Perform type erasure on function call arguments if required.
                    let parameter_types = ast.get_parameter_types_from_type(call.callee.ty)
                    
                    assert(condition: call.arguments.len() == parameter_types.len(), message: "arguments and parameters types must be the same length")
                    let pti = parameter_types.iter()
                    for argument in call.arguments:
                        let pt = option_unwrap(pti.next())
                        transformer.class_rewriter.erase_type(ft: pt, value: argument.value, assign: false)

                    upcast_type(expression)

                FunctionRef(function_def, type_arguments):
                    # Remove type arguments:
                    type_arguments.clear()

                StructLiteral(ty, values):
                    # Perform type erasure on struct literal values
                    let field_types = ast.get_field_types(ty)
                    assert(condition: values.len() == field_types.len(), message: "values and field-types must be the same length")
                    let fti = field_types.iter()
                    for value in values:
                        let ft = option_unwrap(fti.next())
                        transformer.class_rewriter.erase_type(ft, value, assign: false)

                UnionLiteral(ty, attr, value):
                    # Perform type erasure on union literal value
                    let ft = option_unwrap(ast.get_field_type(ty, attr))
                    transformer.class_rewriter.erase_type(ft, value, assign: false)

                GetAttr(base, attr):
                    upcast_type(expression)
            else:
                pass
    else:
        pass



fn upcast_type(expression: ast.Expression):
    # Perform type promotion, when this type was a generic
    if expression.ty.was_generic:
        let old_expression = ast.clone_expression(value: expression)
        let new_expression = ast.cast(value: old_expression, to_type: expression.ty, location: expression.location)
        ast.change_expression_to(expression: expression, to: new_expression)

fn transformer_on_node0(transformer: Transformer, node: ast.VisitNode, phase: ast.VisitPhase):
    pass

fn transformer_on_node7(transformer: Transformer, node: ast.VisitNode, phase: ast.VisitPhase):
    case phase:
        Post:
            case node:
                ModuleNode(module):
                    module.definitions.extend(transformer.class_rewriter.new_definitions)
            else:
                pass
    else:
        pass


class ClassRewriter:
    var ctor_map: Dictionary[ast.FunctionDef] = Dictionary()
    var struct_map: Dictionary[ast.StructDef] = Dictionary()
    var new_definitions: List[ast.Definition] = List()
    var id_gen: IdGen
    var rt_module: ast.Module

    fn rewrite_class_def(class_def: ast.ClassDef):
        log_info("Rewriting class def {class_def.id.name}")
        let ctor_parameters: List[ast.ParameterDef] = List()
        let init_values: List[ast.Expression] = List()
        let methods: List[ast.FunctionDef] = List()
        let builder = ast.StructBuilder()
        builder.set_name(name: class_def.id.name)
        builder.set_id(id: get_unique_id())

        let type_arguments: List[ast.Type] = List()
        for type_parameter in class_def.type_parameters:
            let type_parameter_ref = builder.add_type_parameter(name: type_parameter.id.name, id: get_unique_id(), location: type_parameter.location)
            type_arguments.append(type_parameter_ref)
        let m = ast.create_subst_mapping(type_parameters: class_def.type_parameters, type_arguments)

        for definition in class_def.definitions:
            case definition:
                Var(var_def):
                    let ty = ast.subst(ty: var_def.variable.ty, m)
                    builder.add_field(name: var_def.variable.id.name, ty, location: var_def.variable.location)
                    case var_def.value:
                        Some(iv2):
                            init_values.append(iv2)
                            # log_info("Init val")
                        None:
                            # Create a c-tor parameter
                            # log_info("c-tor param")
                            let ctor_param = ast.parameter_def(name: var_def.variable.id.name, id: get_unique_id(), label_is_optional: false, ty, location: class_def.location)
                            ctor_parameters.append(ctor_param)
                            let iv2 = ast.parameter_ref(parameter_def: ctor_param, location: class_def.location)
                            init_values.append(iv2)
                Function(function_def):
                    methods.append(function_def)
            else:
                panic("only fields and functions expected")

        let struct_def = builder.finish()
        new_definitions.append(ast.Definition.Struct(struct_def))
        struct_map.insert(key: ast.node_id_to_string(class_def.id), value: struct_def)

        # Lift methods:
        for method in methods:
            lift_method(method, class_def, struct_def)

        create_constructor(class_def, struct_def, parameters: ctor_parameters, init_values)

    fn lift_method(method: ast.FunctionDef, class_def: ast.ClassDef, struct_def: ast.StructDef):
        let type_arguments: List[ast.Type] = List()
        for type_parameter in class_def.type_parameters:
            type_parameter = ast.new_type_parameter(name: type_parameter.id.name, id: get_unique_id(), location: type_parameter.location)
            method.type_parameters.append(type_parameter)
            type_arguments.append(ast.type_parameter_ref(type_parameter))
        let struct_type = ast.apply_tycon(tycon: ast.TyCon.Struct(struct_def), type_arguments)
        method.id.name = "{class_def.id.name}_{method.id.name}"
        let this_parameter = option_unwrap(method.this_parameter)
        method.this_parameter = Option.None()
        # ast.change_type_to(ty: this_parameter.ty, ty2: struct_type)
        method.parameters.prepend(this_parameter)
        new_definitions.append(ast.Definition.Function(method))

    fn create_constructor(class_def: ast.ClassDef, struct_def: ast.StructDef, parameters: List[ast.ParameterDef], init_values: List[ast.Expression]):
        # Create constructor function
        let ctor_name = "{class_def.id.name}_ctor"
        let type_parameters: List[ast.TypeParameter] = List()
        let except_type = ast.void_type()
        let type_arguments: List[ast.Type] = List()
        for type_parameter in class_def.type_parameters:
            type_parameter = ast.new_type_parameter(name: type_parameter.id.name, id: get_unique_id(), location: type_parameter.location)
            type_parameters.append(type_parameter)
            type_arguments.append(ast.type_parameter_ref(type_parameter))
        let struct_type = ast.apply_tycon(tycon: ast.TyCon.Struct(struct_def), type_arguments)
        let init_literal = ast.struct_literal(ty: struct_type, values: init_values, location: class_def.location)
        let body = ast.return_statement(value: Option.Some(init_literal), location: class_def.location)
        let ctor_func = ast.function_def(name: ctor_name, id: get_unique_id(), type_parameters, this_parameter: Option.None(), parameters, return_type: struct_type, except_type, body, location: class_def.location)

        # Use node-id to store constructor:
        ctor_map.insert(key: ast.node_id_to_string(class_def.id), value: ctor_func)
        new_definitions.append(ast.Definition.Function(ctor_func))

    #fn rewrite_method_call():
    #    pass

    fn rewrite_class_literal(ty: ast.Type, arguments: List[ast.LabeledExpression], location: Location) -> ast.Expression:
        let class_def = ast.get_class_def_from_type(ty)
        let ctor_func_def: ast.FunctionDef = option_unwrap(ctor_map.get(key: ast.node_id_to_string(class_def.id)))
        let type_arguments = ast.get_type_arguments_from_type(ty)
        let ctor_func_ref = ast.function_ref(function_def: ctor_func_def, type_arguments, location)
        let struct_ty: ast.Type = ast.undefined_type()
        let ctor_call = ast.call(callee: ctor_func_ref, arguments, ty: struct_ty, location)
        return ctor_call

    fn get_unique_id() -> int:
        return id_gen.new_id()
    
    fn new_variable(name: str, ty: ast.Type, location: Location) -> ast.Variable:
        # Create a new variable with unique id
        let id = get_unique_id()
        return ast.variable(name, id, ty, location)

    fn get_struct_def_for_id(id: ast.NodeId) -> ast.StructDef:
        return option_unwrap(struct_map.get(key: ast.node_id_to_string(id)))
    
    fn get_struct_type_for_id(id: ast.NodeId, type_arguments: List[ast.Type]) -> ast.Type:
        let struct_def = get_struct_def_for_id(id)
        return ast.apply_tycon(tycon: ast.TyCon.Struct(struct_def), type_arguments)

    fn load_std_function(name: str, location: Location) -> ast.Expression:
        # Get expression that loads a builtin runtime function.
        let symbol = option_unwrap(rt_module.scope.lookup(name))
        return ast.load_symbol(symbol, ty: ast.undefined_type(), location)

    fn transform_for_loop(for_statement: ast.ForStatement, location: ast.Location) -> ast.Statement:
        log_debug("Rewrite for loop")
        # Turn for loop into iterator and while loop

        if ast.is_array_type(for_statement.iter_value.ty):
            return transform_for_loop_over_array(for_statement, location)
        else:
            return transform_for_loop_over_iterator(for_statement, location)

    fn transform_for_loop_over_iterator(for_statement: ast.ForStatement, location: ast.Location) -> ast.Statement:
        # Implement loop over 'iter' method:
        # log_info(".... {ast.type_to_string(for_statement.iter_value.ty)}")
        let iter_val = ast.call_method(base: for_statement.iter_value, method: "iter", location)
        let iter_var = new_variable(name: "it", ty: iter_val.ty, location)
        let let_it_var = ast.let_statement(variable: iter_var, type_hint: Option.None(), value: iter_val, location)

        # log_info("....>>> {ast.type_to_string(iter_var.ty)}")
        let opt_val = ast.call_method(base: ast.var_ref(variable: iter_var, location), method: "next", location)
        let opt_var = new_variable(name: "opt", ty: opt_val.ty, location)
        let let_opt_var = ast.let_statement(variable: opt_var, type_hint: Option.None(), value: opt_val, location)

        let arm1 = ast.CaseArm:
            location
            name: "None"
            variables: List()
            block: ast.scoped_block(body: ast.break_statement(location))
        let arm2 = ast.CaseArm:
            location
            name: "Some"
            variables: vec1(for_statement.iter_var)
            block: for_statement.block
        let arms: List[ast.CaseArm] = vec2(arm1, arm2)

        let case_statement = ast.case_statement(value: ast.var_ref(variable: opt_var, location), arms, else_clause: Option.None(), location)
        let true_value = ast.bool_literal(value: true, location)
        let loop_body = ast.compound(inner: vec2(let_opt_var, case_statement), location)
        let loop_statement = ast.while_statement(condition: true_value, body: loop_body, location)

        return ast.compound(inner: vec2(let_it_var, loop_statement), location)

    fn transform_for_loop_over_array(for_statement: ast.ForStatement, location: ast.Location) -> ast.Statement:
        # Turn for loop into index / while loop
        let array_type = for_statement.iter_value.ty

        # let arr = iter_value
        let x_var = new_variable(name: "x", ty: array_type, location)
        let let_x = ast.let_statement(variable: x_var, type_hint: Option.None(), value: for_statement.iter_value, location)

        # index = 0
        let index_var = new_variable(name: "index", ty: ast.int_type(), location)
        let zero = ast.integer_literal(value: 0, location)
        let let_index = ast.let_statement(variable: index_var, type_hint: Option.None(), value: zero, location)

        # index < len(array)
        let array_size = ast.integer_literal(value: ast.get_array_size_from_type(array_type), location)
        let index_ref1 = ast.var_ref(variable: index_var, location)
        let condition = ast.binop(lhs: index_ref1, op: ast.BinaryOperator.Less(), rhs: array_size, ty: ast.bool_type(), location)

        # v = x[index]
        let x_ref1 = ast.var_ref(variable: x_var, location)
        let index_ref2 = ast.var_ref(variable: index_var, location)
        let x_indexed = ast.subscript(base: x_ref1, indici: vec1(index_ref2), ty: ast.get_element_type_from_type(array_type), location)
        let let_v = ast.let_statement(variable: for_statement.iter_var, type_hint: Option.None(), value: x_indexed, location)

        # index = index + 1
        let index_ref3 = ast.var_ref(variable: index_var, location)
        let index_ref4 = ast.var_ref(variable: index_var, location)
        let one = ast.integer_literal(value: 1, location)
        let index_plus_1 = ast.binop(lhs: index_ref4, op: ast.BinaryOperator.Add(), rhs: one, ty: ast.int_type(), location)
        let inc_index = ast.assignment_statement(target: index_ref3, op: Option.None(), value: index_plus_1, location)

        # While loop:
        let loop_body1 = ast.compound(inner: vec3(let_v, for_statement.block.body, inc_index), location)
        let while_loop = ast.while_statement(condition, body: loop_body1, location)

        return ast.compound(inner: vec3(let_x, let_index, while_loop), location)

    fn transform_switch(switch_statement: ast.SwitchStatement, location: Location) -> ast.StatementKind:
        # Turn switch into sequence of if-else
        let x_var = new_variable(name: "x", ty: ast.int_type(), location)
        let let_x = ast.let_statement(variable: x_var, type_hint: Option.None(), value: switch_statement.value, location)

        let else_clause = switch_statement.default_block.body
        for arm in switch_statement.arms:
            let x_ref = ast.var_ref(variable: x_var, location: arm.location)
            let eq_op = ast.BinaryOperator.Equals()
            let eq_ty = ast.bool_type()
            let condition = ast.binop(lhs: x_ref, op: eq_op, rhs: arm.value, ty: eq_ty, location: arm.location)
            else_clause = ast.if_statement(condition, body: arm.block.body, false_body: else_clause, location: arm.location)
        
        return ast.StatementKind.Compound(vec2(let_x, else_clause))

    fn rewrite_enum_def(enum_def: ast.EnumDef):
        log_info("Rewriting enum def {enum_def.id.name}")

        let builder2 = ast.StructBuilder()
        builder2.set_name(name: "{enum_def.id.name}Data")
        builder2.set_id(get_unique_id())
        builder2.set_is_union(true)

        let type_arguments2: List[ast.Type] = List()
        for type_parameter in enum_def.type_parameters:
            let type_parameter_ref2 = builder2.add_type_parameter(name: type_parameter.id.name, id: get_unique_id(), location: type_parameter.location)
            type_arguments2.append(type_parameter_ref2)

        for variant in enum_def.variants:
            let t3 = ast.int_type()
            if variant.payload.len() == 1:
                t3 = variant.payload.first()
            elif variant.payload.len() > 1:
                let builder3 = ast.StructBuilder()
                builder3.set_name(name: "{enum_def.id.name}{variant.name}Data")
                builder3.set_id(id: get_unique_id())

                let idx = 0
                for payload_type in variant.payload:
                    builder3.add_field(name: "f_{idx}", ty: payload_type, location: variant.location)
                    idx += 1

                let struct_def3 = builder3.finish()
                new_definitions.append(ast.Definition.Struct(struct_def3))
                t3 = ast.apply_tycon(tycon: ast.TyCon.Struct(struct_def3), type_arguments: type_arguments2)

            builder2.add_field(name: variant.name, ty: t3, location: variant.location)

        let union_def = builder2.finish()
        new_definitions.append(ast.Definition.Struct(union_def))

        let builder = ast.StructBuilder()
        builder.set_name(name: enum_def.id.name)
        builder.set_id(get_unique_id())

        let type_arguments: List[ast.Type] = List()
        for type_parameter in enum_def.type_parameters:
            let type_parameter_ref = builder.add_type_parameter(name: type_parameter.id.name, id: get_unique_id(), location: type_parameter.location)
            type_arguments.append(type_parameter_ref)

        builder.add_field(name: "tag", ty: ast.int_type(), location: enum_def.location)
        let union_type = ast.apply_tycon(tycon: ast.TyCon.Struct(union_def), type_arguments)
        builder.add_field(name: "data", ty: union_type, location: enum_def.location)
        let struct_def = builder.finish()
        # let m = ast.create_subst_mapping(type_parameters: enum_def.type_parameters, type_arguments)

        new_definitions.append(ast.Definition.Struct(struct_def))
        struct_map.insert(key: ast.node_id_to_string(enum_def.id), value: struct_def)

    fn transform_case(case_statement: ast.CaseStatement) -> ast.Statement:
        # TODO: support doc strings
        # """ Transform case statement into switch case over tagged unions. """
        let location = case_statement.value.location
        let enum_def = ast.get_enum_def_from_type(case_statement.value.ty)
        let struct_def = get_struct_def_for_id(id: enum_def.id)
        let type_arguments = ast.get_type_arguments_from_type(case_statement.value.ty)
        let struct_type = ast.apply_tycon(tycon: ast.TyCon.Struct(struct_def), type_arguments)

        let x_var = new_variable(name: "x", ty: struct_type, location)
        let store_tagged_union = ast.let_statement(variable: x_var, type_hint: Option.None(), value: case_statement.value, location)

        let switch_arms: List[ast.SwitchArm] = List()
        for arm in case_statement.arms:
            let arm_tag = option_unwrap(ast.get_enum_variant(enum_def, attr: arm.name)).tag_value
            let switch_arm_value = ast.integer_literal(value: arm_tag, location: arm.location)
            let switch_arm_body: List[ast.Statement] = List()

            # Unpack payload:
            if arm.variables.len() == 1:
                let x_var_ref = ast.var_ref(variable: x_var, location: arm.location)
                let payload_value = ast.get_attr_typed(value: x_var_ref, attr: "data", location: arm.location)
                let union_val = ast.get_attr_typed(value: payload_value, attr: arm.name, location: arm.location)
                let store_var = ast.let_statement(variable: arm.variables.first(), type_hint: Option.None(), value: union_val, location: arm.location)
                switch_arm_body.append(store_var)
            elif arm.variables.len() > 1:
                let idx = 0
                for variable in arm.variables:
                    let x_var_ref = ast.var_ref(variable: x_var, location: arm.location)
                    let payload_value = ast.get_attr_typed(value: x_var_ref, attr: "data", location: arm.location)
                    let union_val = ast.get_attr_typed(value: payload_value, attr: arm.name, location: arm.location)
                    let actual_val = ast.get_attr_typed(value: union_val, attr: "f_{idx}", location: arm.location)
                    let store_var = ast.let_statement(variable, type_hint: Option.None(), value: actual_val, location: arm.location)
                    switch_arm_body.append(store_var)
                    idx += 1

            switch_arm_body.append(arm.block.body)
            let switch_arm = ast.SwitchArm:
                location: arm.location
                value: switch_arm_value
                block: ast.scoped_block(body: ast.compound(inner: switch_arm_body, location: arm.location))
            switch_arms.append(switch_arm)
        
        let switch_default_code: ast.Statement = ast.pass_statement(location)
        case case_statement.else_block:
            None:
                switch_default_code = ast.unreachable_statement(location)
            Some(else_block):
                switch_default_code = else_block.body

        let x_var_ref0 = ast.var_ref(variable: x_var, location)
        let switch_value = ast.get_attr_typed(value: x_var_ref0, attr: "tag", location)
        let switch_on_tag = ast.switch_statement(value: switch_value, arms: switch_arms, default_body: switch_default_code, location)

        return ast.compound(inner: vec2(store_tagged_union, switch_on_tag), location)

    fn rewrite_enum_literal(enum_ty: ast.Type, variant: ast.EnumVariant, values: List[ast.Expression], location: Location) -> ast.Expression:
        # log_info("Rewrite enum literal")
        let enum_def = ast.get_enum_def_from_type(enum_ty)
        let struct_def = get_struct_def_for_id(id: enum_def.id)
        let type_arguments = ast.get_type_arguments_from_type(enum_ty)
        let struct_type = ast.apply_tycon(tycon: ast.TyCon.Struct(struct_def), type_arguments)
        let union_type = option_unwrap(ast.get_field_type(ty: struct_type, attr: "data"))

        let union_value = ast.undefined_value()
        if values.len() == 0:
            union_value = ast.integer_literal(value: 0, location)
        elif values.len() == 1:
            union_value = values.first()
        elif values.len() > 1:
            let struct_type2 = option_unwrap(ast.get_field_type(ty: union_type, attr: variant.name))
            union_value = ast.struct_literal(ty: struct_type2, values, location)

        let payload = ast.union_literal(ty: union_type, field: variant.name, value: union_value, location)
        let tag_value = variant.tag_value
        let tag = ast.integer_literal(value: tag_value, location)
        return ast.struct_literal(ty: struct_type, values: vec2(tag, payload), location)

    fn erase_type(ft: ast.Type, value: ast.Expression, assign: bool):
        if ft.was_generic and not assign:
            let old_value = ast.clone_expression(value)
            let new_value = ast.cast(value: old_value, to_type: ast.opaque_type(), location: value.location)
            ast.change_expression_to(expression: value, to: new_value)
        elif ast.is_function_type(ft):
            let parameter_types = ast.get_parameter_types_from_type(ft)
            let return_type = ast.get_return_type_from_type(ft)

            # Check if we need a bridge function:
            let opaq = false
            for pt in parameter_types:
                if needs_opaque_cast(pt):
                    opaq = true
            if needs_opaque_cast(return_type):
                opaq = true

            if opaq:
                log_info("We need a bridge function for {ast.type_to_string(ft)} {ast.expression_to_string(value)}")
                case value.kind:
                    FunctionRef(function_def, type_arguments):
                        # TODO: check for existing bridge functions!
                        let bridge_function = create_bridge_function(function_def, parameter_types, return_type)
                        value.kind = ast.ExpressionKind.FunctionRef(bridge_function, type_arguments: List())
                else:
                    panic("Can only bridge a function reference")

    fn create_bridge_function(function_def: ast.FunctionDef, parameter_types: List[ast.Type], return_type: ast.Type) -> ast.FunctionDef:
        # Create a bridge function which takes potential opaque parameters
        # and calls the specific function with opaque types casted.
        let location = function_def.location
        let bridge_function_name = "bridge_to_{function_def.id.name}"
        let type_parameters: List[ast.TypeParameter] = List()
        let parameters: List[ast.ParameterDef] = List()
        let arguments: List[ast.LabeledExpression] = List()
        let return_type2 = function_def.return_type
        assert(condition: ast.is_void_type(function_def.except_type), message: "Bridge function only supports non-throwing functions")
        let except_type = ast.void_type()
        let pti = parameter_types.iter()
        for parameter in function_def.parameters:
            let pt = option_unwrap(pti.next())
            let needs_cast = needs_opaque_cast(pt)

            let ty = parameter.ty
            if needs_cast:
                ty = ast.opaque_type()
            else:
                ty = parameter.ty
            let bridge_function_parameter = ast.parameter_def(name: parameter.id.name, id: get_unique_id(), label_is_optional: true, ty, location)
            parameters.append(bridge_function_parameter)

            let parameter_ref = ast.parameter_ref(parameter_def: bridge_function_parameter, location)
            let argument = ast.LabeledExpression(name: Option.Some(parameter.id.name), value: parameter_ref, location)
            if needs_cast:
                # Introduce cast from opaque to specific type here.
                argument.value = ast.cast(value: argument.value, to_type: parameter.ty, location)
            arguments.append(argument)

        let function_ref = ast.function_ref(function_def, type_arguments: List(), location)
        let function_call = ast.call(callee: function_ref, arguments, ty: ast.void_type(), location)
        let body = ast.pass_statement(location)
        if ast.is_void_type(return_type2):
            body = ast.expression_statement(expr: function_call)
        else:
            # Check if we need to introduce a cast to opaque value
            let value = function_call
            if needs_opaque_cast(return_type):
                return_type2 = ast.opaque_type()
                value = ast.cast(value, to_type: return_type2, location)
            body = ast.return_statement(value: Option.Some(value), location)

        let bridge_function = ast.function_def(name: bridge_function_name, id: get_unique_id(), type_parameters, this_parameter: Option.None(), parameters, return_type: return_type2, except_type, body, location)
        # TODO: we could insert duplicate bridge functions.
        # TODO: check for duplicate bridge functions.
        new_definitions.append(ast.Definition.Function(bridge_function))
        return bridge_function

fn needs_opaque_cast(ty?: ast.Type) -> bool:
    if ty.was_generic:
        if ast.is_type_parameter_type(ty):
            return false
        else:
            return true
    else:
        return false
