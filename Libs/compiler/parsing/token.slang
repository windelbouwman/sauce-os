
from location import Location, location_default

pub fn default_token() -> Token:
	Token:
		location: location_default()
		kind: TokenKind.None()

pub struct Token:
	location: Location
	kind: TokenKind

pub enum TokenKind:
	Identifier(id: str)

	# Keywords:
	KwAnd
	KwBreak
	KwCase
	KwClass
	KwContinue
	KwElse
	KwElif
	KwEnum
	KwExcept
	KwExtern
	KwFn
	KwFor
	KwFrom
	KwIf
	KwImport
	KwImpl
	KwIn
	KwInterface
	KwLet
	KwLoop
	KwMacro
	KwNot
	KwOr
	KwPass
	KwPub
	KwRaise
	KwReturn
	KwStruct
	KwSwitch
	KwTry
	KwType
	KwVar
	KwWhile
	KwUnreachable
	KwBox
	KwUnbox
	KwNull

	# Literals:
	Float(value: float)
	Integer(value: int)
	Char(value: char)
	Bool(value: bool)

	StringStart
	StringContent(value: str)
	StringEnd
	DocString(value: str)

	# Punctuation:
	Colon
	Comma
	Dot
	Arrow
	Question
	ParenthesisOpen
	ParenthesisClose
	BracketOpen
	BracketClose
	BraceOpen
	BraceClose

	Plus
	Minus
	Slash
	Asterix
	Less
	Greater
	LessEquals
	GreaterEquals
	Equals
	EqualsEquals
	ShiftRight
	ShiftLeft
	BitOr
	BitAnd
	BitXor
	NotEquals
	PlusEquals
	MinusEquals
	AsterixEquals
	SlashEquals

	# White-space:
	Space(amount: int)
	Tab(amount: int)
	NewLine
	Comment(comment: str)
	Indent
	Dedent

	Eof
	None
	Error(message: str)

pub fn token_to_string(tok: Token) -> str:
	# """ Convert token to txt """
	case tok.kind:
		KwAnd:
			"AND"
		KwBreak:
			"BREAK"
		KwCase:
			"CASE"
		KwClass:
			"CLASS"
		KwContinue:
			"CONTINUE"
		KwElse:
			"ELSE"
		KwElif:
			"ELIF"
		KwEnum:
			"ENUM"
		KwExcept:
			"EXCEPT"
		KwExtern:
			"EXTERN"
		KwFn:
			"FN"
		KwFor:
			"FOR"
		KwFrom:
			"FROM"
		KwIf:
			"IF"
		KwImport:
			"IMPORT"
		KwImpl:
			"IMPL"
		KwIn:
			"IN"
		KwInterface:
			"INTERFACE"
		KwLet:
			"LET"
		KwLoop:
			"LOOP"
		KwMacro:
			"MACRO"
		KwNot:
			"NOT"
		KwOr:
			"OR"
		KwPass:
			"PASS"
		KwPub:
			"PUB"
		KwRaise:
			"RAISE"
		KwReturn:
			"RETURN"
		KwStruct:
			"STRUCT"
		KwSwitch:
			"SWITCH"
		KwTry:
			"TRY"
		KwType:
			"TYPE"
		KwVar:
			"VAR"
		KwWhile:
			"WHILE"
		KwUnreachable:
			"UNREACHABLE"
		KwBox:
			"BOX"
		KwUnbox:
			"UNBOX"
		KwNull:
			"NULL"
		Identifier(id):
			"ID({id})"
		StringStart:
			"STRING_START"
		StringContent(content):
			"STRING_CONTENT({content})"
		StringEnd:
			"STRING_END"
		DocString(value):
			"DOC_STRING({value})"
		Char(value):
			"CHAR({value})"
		Integer(value):
			"INT({value})"
		Float(v):
			"FLOAT(...)"
		Bool(value):
			if value:
				"BOOL(yes)"
			else:
				"BOOL(no)"
		Space(amount):
			"SPACE({amount})"
		Tab(amount):
			"TAB({amount})"
		Comment(comment):
			"COMMENT({comment})"
		NewLine:
			"NEWLINE"
		Indent:
			"INDENT"
		Dedent:
			"DEDENT"
		Colon:
			"COLON"
		Arrow:
			"ARROW"
		Question:
			"QUESTION"
		Comma:
			"COMMA"
		Dot:
			"DOT"
		Plus:
			"+"
		Minus:
			"-"
		Slash:
			"/"
		Asterix:
			"*"
		Equals:
			"="
		EqualsEquals:
			"=="
		NotEquals:
			"!="
		PlusEquals:
			"+="
		MinusEquals:
			"-="
		AsterixEquals:
			"*="
		SlashEquals:
			"/="
		Less:
			"<"
		LessEquals:
			"<="
		Greater:
			">"
		GreaterEquals:
			">="
		ShiftRight:
			"shr"
		ShiftLeft:
			"shl"
		BitOr:
			"bitor"
		BitAnd:
			"bitand"
		BitXor:
			"bitxor"
		ParenthesisOpen:
			"("
		ParenthesisClose:
			")"
		BracketOpen:
			"["
		BracketClose:
			"]"
		BraceOpen:
			"\{"
		BraceClose:
			"}"
		Error(message):
			"LEX-ERROR({message})"
		Eof:
			"EOF"
		None:
			"None"
