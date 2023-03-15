""" Spit out LLVM module.

This is some nifty reference: https://mapping-high-level-constructs-to-llvm-ir.readthedocs.io

TODO: other backends for:
- WASM?
- own bytecode VM which we can emulate later?
"""

from .ast import FunctionCall, IfStatement, Let, While
from .ast import StringConstant, NameRef, Binop, NumericConstant
from .ast import DotOperator, NewOp, Parameter
from .ast import Return, Break, Continue
from .ast import StructDef
from .types import StructType, VoidType, BaseType
from .analyze import Variable

import logging
logger = logging.getLogger('codegen')


def gencode(mod, output_filename):
    logger.info(f"Writing output to {output_filename}")
    try:
        with open(output_filename, 'w') as f:
            CodeGenerator(f).gen_mod(mod)
    except:
        print('Horror!')
        import os
        os.remove(output_filename)
        raise


class CodeGenerator:
    def __init__(self, f):
        self.f = f
        self.string_constants = []
        self._counter = 1
        self._indent = 0
        self._var_map = {}
        self._type_map = {}
        self.func_names = {
            'std_print': 'puts'
        }

    def gen_mod(self, mod):
        self.emit()
        self.emit(r'declare i32 @puts(i8* nocapture) nounwind')
        self.emit(r'declare i8* @malloc(i64) nounwind')
        self.emit()
        self.emit('; Funky type section:')
        for ty in mod.types:
            self.gen_typ(ty)

        # for function in mod.functions:
        # self.func_names[function.name] = function.name

        self.emit()
        self.emit('; Funky functions:')
        self.emit()
        for function in mod.functions:
            self.gen_func(function)

        self.emit()
        self.emit('; some funky string literals:')
        for line in self.string_constants:
            self.emit(line)

    def gen_typ(self, ty):
        if isinstance(ty, StructDef):
            ty_name = self.new_local(ty.name + "Type")
            self.emit(f'{ty_name} = type {{')
            self.indent()
            field_types = []
            for _, field_ty in ty.ty.fields:
                field_ty = self.get_type(field_ty)
                field_types.append(field_ty)
            self.emit(', '.join(field_types))
            self.dedent()
            self.emit('}')
            self._type_map[ty.ty] = ty_name
        else:
            raise NotImplementedError(str(ty))

    def new_id(self):
        n = self._counter
        self._counter += 1
        return n

    def new_local(self, hint='val'):
        n = self.new_id()
        return f'%{hint}{n}'

    def new_global(self, hint='gval'):
        n = self.new_id()
        return f'@{hint}{n}'

    def new_label(self, hint='block'):
        n = self.new_id()
        return f'{hint}{n}'

    def gen_func(self, func):
        self.emit()
        self.emit(f'; Code for function "{func.name}"')
        ret_type = self.get_type(func.ty.return_type)
        if func.ty.return_type.is_reftype():
            ret_type += '*'
        params = []

        for p in func.parameters:
            param_name = self.new_local(p.name)
            param_ty = self.get_type(p.ty)
            ptr_suffix = "*" if p.ty.is_reftype() else ""
            params.append(f'{param_ty}{ptr_suffix} {param_name}')
            self._var_map[p] = (param_name, param_ty)

        params_txt = ', '.join(params)
        self.emit(f'define {ret_type} @{func.name}({params_txt}) {{')
        self.indent()
        for statement in func.statements:
            self.gen_statement(statement)
        # TODO: provide some ready set return value?
        # self.emit('ret i32 0')
        self.emit('ret void')
        self.dedent()
        self.emit('}')

    def gen_statement(self, statement):
        # logger.info(f'Generating code for {statement}')
        if isinstance(statement, IfStatement):
            self.gen_if_statement(statement)
        elif isinstance(statement, While):
            self.gen_while_statement(statement)

        elif isinstance(statement, FunctionCall):
            self.gen_function_call(statement)
        elif isinstance(statement, list):
            for s in statement:
                self.gen_statement(s)
        elif isinstance(statement, Let):
            self.gen_let_statement(statement)
        elif statement is None:
            pass
        elif isinstance(statement, Return):
            self.gen_return_statement(statement)
        else:
            raise NotImplementedError(str(statement))

    def get_sizeof(self, ty) -> int:
        if ty is None or isinstance(ty, VoidType):
            raise NotImplementedError('sizeof-void')
        elif isinstance(ty, StructType):
            size = 0
            for field_name, field_type in ty.fields:
                size += self.get_sizeof(field_type)
            return size
        elif isinstance(ty, BaseType):
            m = {
                'str': 8,
                'int': 4,
                'bool': 1,
            }
            return m[ty.name]
        else:
            raise NotImplementedError(str(ty))

    def get_type(self, ty, as_ref=False):
        if ty is None or isinstance(ty, VoidType):
            return 'void'
        elif isinstance(ty, StructType):
            if ty in self._type_map:
                ty2 = self._type_map[ty]
                if as_ref:
                    ty2 += '*'
            else:
                raise NotImplementedError()
                self._type_map[ty] = ty2
            return ty2
        elif isinstance(ty, BaseType):
            m = {
                'str': 'i8*',  # str maps to i8* llvm type
                'int': 'i32',
                'bool': 'i1',
            }
            return m[ty.name]
        else:
            raise NotImplementedError(str(ty))

    def gen_function_call(self, call):
        args = []
        for arg in call.args:
            a, ty = self.gen_expression(arg)
            if arg.ty.is_reftype():
                ty += '*'
            args.append((ty, a))

        args = ', '.join(f'{ty} {a}' for ty, a in args)

        funcname = self.func_names.get(call.target.name, call.target.name)

        if call.target.ty.return_type.is_void():
            self.emit(f'call void @{funcname}({args})')
        else:
            retval = self.new_local('retval')
            ret_ty = self.get_type(call.target.ty.return_type)
            ret_ty_suffix = '*' if call.target.ty.return_type.is_reftype() else ''
            self.emit(
                f'{retval} = call {ret_ty}{ret_ty_suffix} @{funcname}({args})')
            return retval, ret_ty

    def gen_return_statement(self, statement):
        val, ty = self.gen_expression(statement.value)
        self.emit(f'ret {val}')

    def gen_let_statement(self, statement):
        value, ty = self.gen_expression(statement.value)
        # target = self.new_local(statement.target)
        self._var_map[statement.variable] = value, ty
        # self.emit(f'{target} = {val}')

    def gen_if_statement(self, statement):
        true_label = self.new_label()
        false_label = self.new_label()
        self.gen_condition(statement.condition, true_label, false_label)
        self.emit(f'{true_label}:')
        self.gen_statement(statement.true_statement)
        if statement.false_statement:
            final_label = self.new_label()
            self.emit(f'br label %{final_label}')
            self.emit(f'{false_label}:')
            self.gen_statement(statement.false_statement)
            self.emit(f'br label %{final_label}')
            self.emit(f'{final_label}:')
        else:
            self.emit(f'br label %{false_label}')
            self.emit(f'{false_label}:')

    def gen_while_statement(self, statement):
        true_label = self.new_label()
        false_label = self.new_label()
        test_label = self.new_label()
        self.emit(f'br label %{test_label}')
        self.emit(f'{test_label}:')
        self.gen_condition(statement.condition, true_label, false_label)
        self.emit(f'{true_label}:')
        self.gen_statement(statement.false_statement)
        self.emit(f'br label %{test_label}')
        self.emit(f'{false_label}:')

    def gen_condition(self, condition, true_label, false_label):
        # Implement short circuit logic here
        if isinstance(condition, Binop) and condition.op == 'or':
            maybe_label = self.new_label()
            self.gen_condition(condition.lhs, true_label, maybe_label)
            self.emit(f'{maybe_label}:')
            self.gen_condition(condition.rhs, true_label, false_label)
        elif isinstance(condition, Binop) and condition.op == 'and':
            maybe_label = self.new_label()
            self.gen_condition(condition.lhs, maybe_label, false_label)
            self.emit(f'{maybe_label}:')
            self.gen_condition(condition.rhs, true_label, false_label)
        else:
            condition, ty = self.gen_expression(condition)
            self.emit(
                f'br {ty} {condition}, label %{true_label}, label %{false_label}')

    def gen_malloc(self, size):
        val = self.new_local('malloc')
        self.emit(f"{val} = call i8* @malloc(i64 {size}) nounwind")
        return val

    def gen_expression(self, expression):
        if isinstance(expression, StringConstant):
            val = self.gen_string_constant(expression.text)
            ty = self.get_type(expression.ty)
            # print(expression, ty)
        # elif isinstance(expression, NameRef):
        #     logger.info(f'TODO generating code for {expression}')
        #     print('TODO', expression)
        #     val = expression.name
        elif isinstance(expression, Binop):
            val, ty = self.gen_binop(expression)
        elif isinstance(expression, NumericConstant):
            # val = self.new_local('val')
            # self.emit(f'{val} = {expression.value}')
            val = f'{expression.value}'
            ty = 'i32'
        elif isinstance(expression, FunctionCall):
            val, ty = self.gen_function_call(expression)
        elif isinstance(expression, DotOperator):
            val = self.new_local('field')
            ty = self.get_type(expression.ty)
            if isinstance(expression.base.ty, StructType):
                val_ptr = self.new_local('field_ptr')
                base, base_ty = self.gen_expression(expression.base)
                field_index = expression.base.ty.index_of(expression.field)
                self.emit(
                    f'{val_ptr} = getelementptr {base_ty}, {base_ty}* {base}, i32 0, i32 {field_index}')
                self.emit(f"{val} = load {ty}, {ty}* {val_ptr}")
            else:
                raise NotImplementedError(str(expression))
        elif isinstance(expression, Variable):
            #val = self.new_local('var_ref')
            addr, ty = self._var_map[expression]
            # TODO: determine if we must load a value from memory?
            #self.emit(f'{val} = load {ty}, {ty}* {addr}')
            val = addr
        elif isinstance(expression, Parameter):
            val, ty = self._var_map[expression]
        elif isinstance(expression, NewOp):
            val, ty = self.gen_new_op(expression)
        else:
            raise NotImplementedError(f'TODO: {expression}')
        return val, ty

    def gen_string_constant(self, txt):
        size = len(txt) + 1
        valname = self.new_local('cast')
        str_name = self.new_global('.str')
        self.emit(
            f'{valname} = getelementptr [{size} x i8], [{size} x i8]* {str_name}, i64 0, i64 0')
        self.string_constants.append(
            f'{str_name} = private unnamed_addr constant [{size} x i8] c"{txt}\\00"')
        return valname

    def gen_new_op(self, expression):
        ty = self.get_type(expression.new_ty)
        size = self.get_sizeof(expression.new_ty)
        new_data = self.gen_malloc(size)
        new_val = self.new_local('new_op')
        self.emit(f"{new_val} = bitcast i8* {new_data} to {ty}*")
        for field in expression.fields:
            field_val, field_ty = self.gen_expression(field.value)
            field_addr = self.new_local('addr')
            index = expression.new_ty.index_of(field.name)
            self.emit(
                f'{field_addr} = getelementptr {ty}, {ty}* {new_val}, i32 0, i32 {index}')
            self.gen_store(field_ty, field_val, field_addr)
        return new_val, ty

    def gen_load(self, ty, addr):
        pass

    def gen_store(self, ty, value, addr):
        self.emit(f'store {ty} {value}, {ty}* {addr}')

    def gen_binop(self, expression):
        lhs, lhs_ty = self.gen_expression(expression.lhs)
        rhs, _rhs_ty = self.gen_expression(expression.rhs)
        val = self.new_local('binop')
        cmp_ops = {
            '<': 'slt',
            '<=': 'sle',
            '>': 'sgt',
            '>=': 'sge',
            '!=': 'ne',
            '==': 'eq',
        }
        basic_ops = {
            '+': 'add',
            '-': 'sub',
            '*': 'mul',
            '/': 'sdiv',
        }
        if expression.op in cmp_ops:
            op = cmp_ops[expression.op]
            self.emit(f'{val} = icmp {op} {lhs_ty} {lhs}, {rhs}')
            ty = 'i1'
        elif expression.op in basic_ops:
            op = basic_ops[expression.op]
            self.emit(f'{val} = {op} {lhs_ty} {lhs}, {rhs}')
            ty = lhs_ty
        else:
            raise NotImplementedError(expression.op)
        return val, ty

    def indent(self):
        self._indent += 2

    def dedent(self):
        self._indent -= 2

    def emit(self, line=''):
        indent = ' ' * self._indent
        print(indent + line, file=self.f)
