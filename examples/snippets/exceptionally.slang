
# Ideas about exceptions
from std import print

pub fn main() -> int:
	try:
		let y: int = foo(x: false)
		try:
			raise "Ai"
		except (ex2: str):
			print("Inner raise = {ex2}!")
		try:
			print("y1 = {y}")
		except (ex3: str):
			print("Inner raise 2 = {ex3}!")
		y = foo(x: true)
		print("y2 = {y}")
	except(err_val: str):
		print("ERROR: {err_val}")

	# Demo a return from within a try statement:
	try:
		return_in_try()
		raise "fooo"
	except(err: str):
		print("main handler: {err}")

	# Demo a break inside a loop:
	try:
		loop:
			try:
				break
			except(err: str):
				print("loop handler: {err}")
		raise "Moi"
	except(err2: str):
		print("non-loop handler: {err2}")
	
	# Demo exception in an exception handler
	try:
		try:
			raise 1337
		except(err4: int):
			raise "Oh my: {err4}"

	except(err3: str):
		print("outer handler: {err3}")

	0

fn foo(x: bool) -> int except str:
	let x1 = may_bork(do_bork: false)
	let x2 = may_bork(do_bork: x)
	x1 + x2

fn may_bork(do_bork: bool) -> int except str:
	print("We might bork!")
	if do_bork:
		raise "Oh noes"
	else:
		42


fn return_in_try():
	try:
		return
	except(err: str):
		print("return_in_try handler: {err}")
