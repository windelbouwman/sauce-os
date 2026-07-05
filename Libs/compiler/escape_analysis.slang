module compiler.escape_analysis
"""Analyze variables, and mark variables that escape"""

from base.logging import log_info
from base.listtype import List
import ast

pub fn escape(module_defs: List[ast.ModuleDef]):
	log_info("Escape analysis")
	let escaper = Escaper(a: 1)
	let escape_visitor: ast.Visitor[Escaper] = ast.Visitor:
		data: escaper
		on_definition: escape_on_definition
		on_type: escape_on_type
		on_statement: escape_on_statement
		on_expression: escape_on_expression
		on_node: escape_on_node
	for module_def in module_defs:
		ast.visit_module(visitor: escape_visitor, module_def)

struct Escaper:
	a: int

fn escape_on_definition(filler: Escaper, definition: ast.Definition, phase: ast.VisitPhase):
	pass

fn escape_on_type(escaper: Escaper, ty: ast.Type, phase: ast.VisitPhase):
	pass

fn escape_on_statement(escaper: Escaper, statement: ast.Statement, phase: ast.VisitPhase):
	case phase:
		Post:
			case statement.kind:
				Assignment(target, op, value):
					case target.kind:
						GetAttr(base, attr):
							mark_escaping_vars(value)
						GetIndex(base, indici):
							mark_escaping_vars(value)
						VariableRef(variable):
							# Only assigning global variable escapes
							mark_escaping_vars(value)
						ParameterRef(parameter_def):
							mark_escaping_vars(value)
					else:
						pass
				Return(value):
					case value:
						Some(value):
							mark_escaping_vars(value)
						None:
							pass
				Expr(value):
					mark_escaping_vars(value)
			else:
				pass
	else:
		pass

fn escape_on_expression(escaper: Escaper, expression: ast.Expression, phase: ast.VisitPhase):
	case phase:
		Post:
			case expression.kind:
				Call(call):
					for argument in call.arguments:
						mark_escaping_vars(argument.value)
			else:
				pass
	else:
		pass

fn escape_on_node(escaper: Escaper, node: ast.VisitNode, phase: ast.VisitPhase):
	pass

fn mark_escaping_vars(value?: ast.Expression):
	"""This expression escapes"""
	case value.kind:
		VariableRef(variable):
			variable.escapes = true
		# TODO: mark GetAttr/base as escaping as well?
	else:
		pass
