
from listtype import List
from lexer import Lexer
from token import token_to_string
from std import read_file, print, get_n_args, get_arg
from hashmap import HashMap, new_hashmap_str
from sorting import sort_list

pub fn main() -> int:
	let filenames: List[str] = List()
	let stats: HashMap[str,int] = new_hashmap_str()

	var i = 0
	let n = get_n_args()
	while i < n:
		let argument = get_arg(arg: i)
		filenames.append(argument)
		i += 1

	for filename in filenames:
		let source = read_file(filename)
		let lex = Lexer()
		lex.init(source)
		loop:
			let token = lex.next_token()
			let category = case token.kind:
				Eof:
					break
				Identifier(name):
					"ID"
				Integer(value):
					"INT"
				Char(value):
					"CHAR"
				StringContent(content):
					"STRING_CONTENT"
				DocString(value):
					"DOCSTRING"
			else:
				token_to_string(tok: token)

			let count = stats.get_or_else(key: category, default: 0) + 1
			stats.insert(key: category, value: count)

	let records: List[Record] = List()
	for key in stats:
		let count = stats.get(key)
		records.append(Record(count, category: key))

	let records2 = sort_list(records, cmp: cmp_records)
	for record in records2:
		print("- {record.count}: {record.category}")

	0

struct Record:
	count: int
	category: str

fn cmp_records(a?: Record, b?: Record) -> bool:
	a.count > b.count
