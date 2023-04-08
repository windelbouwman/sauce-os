
import std
from std import print
from token import Token, TokenKind, new_token, to_string
from location import Location, new_location
from datatypes import List, Option

class Lexer:
    var indent_level: int = 0
    # Syntax for the list/vector type:
    # backlog: List<Token>
    # backlog: list[Token]
    # backlog: list[Token]
    var at_bol: bool = true
    var spaces: int = 0
    var source: str = ""
    var tok_begin: int = 0
    # var tok_end: int = 0
    var offset: int = 0
    var automaton: Automaton = Automaton()

    fn init(source: str):
        this.source = source
        this.automaton.init_table()

    fn next_token() -> Option[Token]:
        # TODO: detect indentations!
        # let tok = lexer::detect_indentations(lex)
        return this.next_token2()

    fn next_token2() -> Option[Token]:
        this.tok_begin = this.tok_begin + 1

        let n = std.str_len(this.source)
        if this.offset < n:
            this.automaton.reset()
            this.tok_begin = this.offset
            while this.offset < n:
                let c = std.ord(std.str_get(this.source, this.offset))
                this.automaton.next(c)
                
                # Check for error state:
                if this.automaton.state == 1:
                    break
                else:
                    # TODO: this.offset += 1
                    this.offset = this.offset + 1

            if this.automaton.accepts == "":
                print("error!")
                return Option.None()
            else:
                let tok_end = this.tok_begin + this.automaton.length
                let txt = std.str_slice(this.source, this.tok_begin, tok_end)
                let kind = TokenKind::Identifier("?")
                if this.automaton.accepts == "id":
                    kind = TokenKind::Identifier(txt)
                else:
                    # TODO: elif!
                    if this.automaton.accepts == "number":
                        kind = TokenKind::Integer(std.str_to_int(txt))
                    else:
                        if this.automaton.accepts == "space":
                            kind = TokenKind::Space(std.str_len(txt))
                        else:
                            print("TOKEN (len={this.offset})->" + this.automaton.accepts)

                let loc = Location:
                    row: 1
                    column: this.tok_begin

                let tok = Token:
                    location: loc
                    kind: kind  # TODO: kind: kind ==> kind
                return Option.Some(tok)
        else:
            return Option.None()


fn next_token(lexer: Lexer) -> Token:
    # let kind = TokenKind::NewLine()
    let kind = TokenKind::String("foobar")

    let location = new_location(1, 1)
    return new_token(kind, location)

fn detect_indentations(lexer: Lexer) -> Token:
    let tok = next_token(lexer)
    if tok.location.row == 1:  # "fu":
        pass
    else:
        # return tok
        pass
    return tok

class Automaton:
    var state: int = 0
    var offset: int = 0
    var length: int = 0
    var accepts: str = ""
    var states: List[State] = List()

    fn init_table():
        # TODO: call from constructor

        # Example which can handle identifiers, whitespace and numbers.
        # State 0:
        let state0 = State()
        state0.add_range_goto(0, 31, 1)
        state0.add_range_goto(32, 32, 2)
        state0.add_range_goto(33, 47, 1)
        state0.add_range_goto(48, 57, 4)
        state0.add_range_goto(58, 96, 1)
        state0.add_range_goto(97, 122, 3)
        state0.add_range_goto(123, 255, 1)
        this.states.append(state0)

        # State 1:
        let state1 = State()
        state1.add_range_goto(0, 255, 1)
        this.states.append(state1)

        # State 2:
        let state2 = State()
        state2.add_range_goto(0, 31, 1)
        state2.add_range_goto(32, 32, 2)
        state2.add_range_goto(33, 255, 1)
        state2.accept = "space"
        this.states.append(state2)

        # State 3:
        let state3 = State()
        state3.add_range_goto(0, 96, 1)
        state3.add_range_goto(97, 122, 3)
        state3.add_range_goto(123, 255, 1)
        state3.accept = "id"
        this.states.append(state3)

        # State 4:
        let state4 = State()
        state4.add_range_goto(0, 47, 1)
        state4.add_range_goto(48, 57, 4)
        state4.add_range_goto(58, 255, 1)
        state4.accept = "number"
        this.states.append(state4)

        # Display table:
        if false == true:
            for state in this.states:
                print("State")
                for y in state.transitions:
                    print(" * {y.begin}-{y.end} -> {y.goto}")

    fn reset():
        this.state = 0
        this.accepts = ""
        this.offset = 0
        this.length = 0

    fn next(atom: int):
        # Go to next state, depending on current state, and atom.
        # TODO: this.offset += 1
        let state = this.states.get(this.state)
        if state.accept == "":
            pass
        else:
            this.accepts = state.accept
            this.length = this.offset

        # Transition:
        for g in state.transitions:
            if g.begin <= atom and atom <= g.end:
                this.state = g.goto
                # Verbose mode:
                # print("new state {atom} ==> {this.state}")

        this.offset = this.offset + 1

class State:
    var transitions: List[RangeGoto] = List()
    var accept: str = ""

    fn add_range_goto(begin: int, end: int, goto: int):
        let g = RangeGoto:
            begin: begin
            end: end
            goto: goto
        this.transitions.append(g)

struct RangeGoto:
    begin: int
    end: int
    goto: int

# Epsilon generated state machine, based on ranges and regular derivatives
#[example]
#id = [a-z]+
#space = [ ]+
#number = [0-9]+
# 
# example = Automaton(transitions=
    #[
    # 0 [(0, 31, 1), (32, 32, 2), (33, 47, 1), (48, 57, 4), (58, 96, 1), (97, 122, 3), (123, 1114111, 1)],
    # 1 [(0, 1114111, 1)],
    # 2 [(0, 31, 1), (32, 32, 2), (33, 1114111, 1)],
    # 3 [(0, 96, 1), (97, 122, 3), (123, 1114111, 1)],
    # 4 [(0, 47, 1), (48, 57, 4), (58, 1114111, 1)]
    # ],
    # accepts=[[], [], ['space'], ['id'], ['number']], error=1)
