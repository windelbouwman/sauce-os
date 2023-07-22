"""
Data flow check.

Check if a variable is defined before usage.

"""

import logging
import networkx as nx
from .location import Location
from .basepass import BasePass
from . import ast

logger = logging.getLogger("flowcheck")


def flow_check(modules: list[ast.Module]):
    for module in modules:
        FlowCheck().run(module)


class FlowCheck(BasePass):
    name = "flow-check"
    write_to_dot_file = False

    def __init__(self):
        super().__init__()
        self._count = 0

        self._g = nx.DiGraph()

        # Is this 'abstract interpretation'??:
        self._pc = 0  # Program counter
        self._loops = []
        self._variables = []

    def visit_definition(self, definition: ast.Definition):
        if isinstance(definition, ast.FunctionDef):
            logger.debug(f"flow check on function '{definition.name}'")
            self._g = nx.DiGraph()
            self._variables = []
            func_entry = self.new_label()
            func_exit = self.new_label()
            self.set_label(func_entry)
            super().visit_definition(definition)
            self.jump_to([func_exit])
            self.set_label(func_exit)

            if self.write_to_dot_file:
                nx.drawing.nx_pydot.write_dot(self._g, f"blabla_{definition.name}.dot")
            logger.debug(f"Flow graph {self._g}")

            dom = nx.algorithms.immediate_dominators(self._g, func_entry)
            # print('dominators', dom)

            # Check that each var use is dominated by a definition
            for variable in self._variables:
                if hasattr(variable, "use_points"):
                    for use_point, use_location in variable.use_points:
                        if not is_dominated(dom, use_point, variable.def_point):
                            self.error(
                                use_location,
                                f"Variable {variable.name} not always defined",
                            )
                else:
                    # TBD: this check may be too annoying:
                    # self.error(variable.location, f"'{variable.name}' was never used")
                    warn_about_unused = False
                    if warn_about_unused:
                        self.warning(
                            variable.location, f"'{variable.name}' was never used"
                        )

        else:
            super().visit_definition(definition)

    def visit_statement(self, statement: ast.Statement):
        kind = statement.kind
        if isinstance(kind, ast.LetStatement):
            self.visit_expression(kind.value)
            self.var_def(kind.variable)
        elif isinstance(kind, ast.IfStatement):
            yes_target = self.new_label()
            no_target = self.new_label()
            final_target = self.new_label()

            self.visit_expression(kind.condition)
            self.jump_to([yes_target, no_target])

            self.set_label(yes_target)
            self.visit_statement(kind.true_statement)
            self.jump_to([final_target])

            self.set_label(no_target)
            self.visit_statement(kind.false_statement)
            self.jump_to([final_target])

            self.set_label(final_target)
        elif isinstance(kind, ast.SwitchStatement):
            final_target = self.new_label()
            default_target = self.new_label()
            arm_targets = [self.new_label() for _ in range(len(kind.arms))]
            self.visit_expression(kind.value)
            self.jump_to(arm_targets + [default_target])

            for arm_target, arm in zip(arm_targets, kind.arms):
                self.set_label(arm_target)
                self.visit_expression(arm.value)
                self.visit_statement(arm.body)
                self.jump_to([final_target])

            self.set_label(default_target)
            self.visit_statement(kind.default_body)
            self.jump_to([final_target])

            self.set_label(final_target)
        elif isinstance(kind, ast.LoopStatement):
            raise NotImplementedError("loop-statement")
        elif isinstance(kind, ast.ForStatement):
            raise NotImplementedError("for-statement")
        elif isinstance(kind, ast.BreakStatement):
            self.jump_to([self._loops[-1][1]])
            unreachable_target = self.new_label()
            self.set_label(unreachable_target)
        elif isinstance(kind, ast.ContinueStatement):
            self.jump_to([self._loops[-1][0]])
            unreachable_target = self.new_label()
            self.set_label(unreachable_target)
        elif isinstance(kind, ast.WhileStatement):
            test_target = self.new_label()
            yes_target = self.new_label()
            final_target = self.new_label()
            self.jump_to([test_target])

            self.set_label(test_target)
            self.visit_expression(kind.condition)
            self.jump_to([yes_target, final_target])

            self._loops.append((test_target, final_target))

            self.set_label(yes_target)
            self.visit_statement(kind.inner)
            self.jump_to([test_target])

            self._loops.pop()

            self.set_label(final_target)
        else:
            super().visit_statement(statement)

    def visit_expression(self, expression: ast.Expression):
        super().visit_expression(expression)
        kind = expression.kind
        if isinstance(kind, ast.ObjRef):
            if isinstance(kind.obj, ast.Variable):
                self.var_use(kind.obj, expression.location)

    def var_use(self, variable: ast.Variable, location: Location):
        # print(f'use: {variable.name}')
        # Hack-in an additional field, use points:
        if not hasattr(variable, "use_points"):
            variable.use_points = []
        x = f"use{self.new_id()} {variable.name}"
        variable.use_points.append((x, location))
        self.execute(x)

    def var_def(self, variable: ast.Variable):
        # print(f'def: {variable.name}')
        self._variables.append(variable)
        x = f"def{self.new_id()} {variable.name}"
        assert not hasattr(variable, "def_point")
        variable.def_point = x
        self.execute(x)

    def execute(self, inst):
        """Add operation in execution graph"""
        # logger.debug(f'EXE> {inst}')
        self._g.add_edge(self._pc, inst)
        self._pc = inst

    def jump_to(self, targets: list[int]):
        """Jump to many targets.

        Do not actually jump, but indicate we might go here.
        """
        # logger.debug(f'JMP TO {targets}')
        for target in targets:
            self._g.add_edge(self._pc, target)

    def new_label(self) -> int:
        return self.new_id()

    def set_label(self, target: int):
        # logger.debug(f'Label {target}')
        self._pc = target

    def new_id(self) -> int:
        self._count += 1
        return self._count


def is_dominated(dom, a, b) -> bool:
    """Test if a is dominated by b"""
    while a != dom[a]:
        a = dom[a]
        if a == b:
            return True
    return False
