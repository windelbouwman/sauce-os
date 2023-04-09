
import std
from std import print
from token import Token, TokenKind, new_token, to_string
from location import Location, new_location
from datatypes import List, Option

struct IndentLevel:
    level: int

fn new_indent_level(level: int) -> IndentLevel:
    let i = IndentLevel:
        level: level
    return i

class Lexer:
    var indent_level: int = 0
    var pending: List[Token] = List()
    var indent_stack: List[IndentLevel] = List()  # TODO: list of integers! (can only make list of non-basic types..)
    var at_bol: bool = true
    var at_end: bool = false
    var spaces: int = 0
    var source: str = ""

    var tok_begin: int = 0
    var offset: int = 0
    var row: int = 1
    var automaton: Automaton = Automaton()

    fn init(source: str):
        this.source = source
        this.indent_stack.append(new_indent_level(0))
        this.automaton.init_table()

    fn next_token() -> Option[Token]:
        # TODO: detect indentations!
        # let tok = lexer::detect_indentations(lex)
        # return this.next_token2()
        while this.pending.is_empty() == true:
            if this.at_end == false:
                this.work_some()
            else:
                break
        
        if this.pending.is_empty() == true:
            return Option.None()
        else:
            return Option.Some(this.pending.pop_front())
    
    fn work_some():
        let tok2 = this.next_token2()
        case tok2:
            None:
                this.at_end = true
                # Dedent to top level!

                while this.indent_stack.len() > 1:
                    let tmp = this.indent_stack.pop_front()
                    # Arg, drop use: ...
                    if tmp.level == 0:
                        pass
                    let location = Location:
                        row: 999
                        column: 999
                    this.emit(new_token(TokenKind::Dedent(), location))

            Some(tok):
                case tok.kind:
                    Space(x):
                        if this.at_bol == true:
                            this.spaces += x
                        else:
                            pass
                    NewLine:
                        this.on_newline(tok)
                    Comment(x):
                        # TODO: only use x, since we must ??
                        if x == x:
                            pass
                        tok.kind = TokenKind::NewLine()
                        this.on_newline(tok)
                else:
                    if this.at_bol == true:
                        this.at_bol = false
                        if this.spaces > this.indent_stack.last().level:
                            # 1x indent!
                            this.indent_stack.append(new_indent_level(this.spaces))

                            this.emit(new_token(TokenKind::Indent(), tok.location))
                        while this.spaces < this.indent_stack.last().level:
                            # n times dedent!
                            let tmp = this.indent_stack.pop_last().level
                            if tmp < this.spaces:
                                print("Indentation error")
                                pass
                            this.emit(new_token(TokenKind::Dedent(), tok.location))
                            # pass

                    # print("ehhh -> " + to_string(tok))
                    this.emit(tok)
                

    fn on_newline(tok: Token):
        if this.at_bol == false:
            this.emit(tok)
        this.at_bol = true
        this.spaces = 0
        this.row += 1
    
    fn emit(tok: Token):
        this.pending.append(tok)

    fn next_token2() -> Option[Token]:
        let n = std.str_len(this.source)
        if this.offset < n:
            this.automaton.reset()
            this.tok_begin = this.offset
            while this.offset < n:
                let c = std.ord(std.str_get(this.source, this.offset))
                this.automaton.next(c)
                
                # Check for error state:
                if this.automaton.state == 12:
                    break
                else:
                    this.offset += 1

            if this.automaton.accepts == "":
                print("error!")
                return Option.None()
            else:
                let tok_end = this.tok_begin + this.automaton.length
                let txt = std.str_slice(this.source, this.tok_begin, tok_end)
                let kind = TokenKind::Error()
                if this.automaton.accepts == "id":
                    kind = TokenKind::Identifier(txt)
                # TODO: elif!
                if this.automaton.accepts == "number":
                    kind = TokenKind::Integer(std.str_to_int(txt))
                if this.automaton.accepts == "space":
                    kind = TokenKind::Space(std.str_len(txt))
                if this.automaton.accepts == "newline":
                    kind = TokenKind::NewLine()
                if this.automaton.accepts == "comment":
                    kind = TokenKind::Comment(txt)
                if this.automaton.accepts == "string":
                    kind = TokenKind::String(txt)
                #else:
                #    print("TOKEN (len={this.offset})->" + this.automaton.accepts)

                let loc = Location:
                    row: this.row
                    column: this.tok_begin

                let tok = new_token(kind, loc)
                return Option.Some(tok)
        else:
            return Option.None()


class Automaton:
    var state: int = 0
    var offset: int = 0
    var length: int = 0
    var accepts: str = ""
    var states: List[State] = List()

    fn init_table():
        # TODO: call from constructor

        # Below table is constructed by this python code:
        # ================
        # for index, state in enumerate(transitions):
        #     print(f"let state{index} = State()")
        #     for t in state:
        #         print(f"state{index}.add_range_goto{t}")
        #     if accepts[index]:
        #         print(f'state{index}.accept = "{accepts[index][0]}"')
        #     print(f"this.states.append(state{index})")
        #     print()
        # ================

        let state0 = State()
        state0.add_range_goto(0, 9, 12)
        state0.add_range_goto(10, 10, 10)
        state0.add_range_goto(11, 31, 12)
        state0.add_range_goto(32, 32, 2)
        state0.add_range_goto(33, 33, 12)
        state0.add_range_goto(34, 34, 13)
        state0.add_range_goto(35, 35, 14)
        state0.add_range_goto(36, 39, 12)
        state0.add_range_goto(40, 40, 4)
        state0.add_range_goto(41, 41, 3)
        state0.add_range_goto(42, 42, 12)
        state0.add_range_goto(43, 43, 7)
        state0.add_range_goto(44, 44, 12)
        state0.add_range_goto(45, 45, 9)
        state0.add_range_goto(46, 46, 1)
        state0.add_range_goto(47, 47, 12)
        state0.add_range_goto(48, 57, 6)
        state0.add_range_goto(58, 58, 11)
        state0.add_range_goto(59, 60, 12)
        state0.add_range_goto(61, 61, 5)
        state0.add_range_goto(62, 64, 12)
        state0.add_range_goto(65, 90, 8)
        state0.add_range_goto(91, 96, 12)
        state0.add_range_goto(97, 122, 8)
        state0.add_range_goto(123, 1114111, 12)
        this.states.append(state0)

        let state1 = State()
        state1.add_range_goto(0, 1114111, 12)
        state1.accept = "dot"
        this.states.append(state1)

        let state2 = State()
        state2.add_range_goto(0, 31, 12)
        state2.add_range_goto(32, 32, 2)
        state2.add_range_goto(33, 1114111, 12)
        state2.accept = "space"
        this.states.append(state2)

        let state3 = State()
        state3.add_range_goto(0, 1114111, 12)
        state3.accept = "brace_close"
        this.states.append(state3)

        let state4 = State()
        state4.add_range_goto(0, 1114111, 12)
        state4.accept = "brace_open"
        this.states.append(state4)

        let state5 = State()
        state5.add_range_goto(0, 1114111, 12)
        state5.accept = "equals"
        this.states.append(state5)

        let state6 = State()
        state6.add_range_goto(0, 47, 12)
        state6.add_range_goto(48, 57, 6)
        state6.add_range_goto(58, 1114111, 12)
        state6.accept = "number"
        this.states.append(state6)

        let state7 = State()
        state7.add_range_goto(0, 1114111, 12)
        state7.accept = "plus"
        this.states.append(state7)

        let state8 = State()
        state8.add_range_goto(0, 47, 12)
        state8.add_range_goto(48, 57, 8)
        state8.add_range_goto(58, 64, 12)
        state8.add_range_goto(65, 90, 8)
        state8.add_range_goto(91, 94, 12)
        state8.add_range_goto(95, 95, 8)
        state8.add_range_goto(96, 96, 12)
        state8.add_range_goto(97, 122, 8)
        state8.add_range_goto(123, 1114111, 12)
        state8.accept = "id"
        this.states.append(state8)

        let state9 = State()
        state9.add_range_goto(0, 61, 12)
        state9.add_range_goto(62, 62, 18)
        state9.add_range_goto(63, 1114111, 12)
        state9.accept = "minus"
        this.states.append(state9)

        let state10 = State()
        state10.add_range_goto(0, 1114111, 12)
        state10.accept = "newline"
        this.states.append(state10)

        let state11 = State()
        state11.add_range_goto(0, 57, 12)
        state11.add_range_goto(58, 58, 17)
        state11.add_range_goto(59, 1114111, 12)
        state11.accept = "colon"
        this.states.append(state11)

        let state12 = State()
        state12.add_range_goto(0, 1114111, 12)
        this.states.append(state12)

        let state13 = State()
        state13.add_range_goto(0, 9, 13)
        state13.add_range_goto(10, 10, 12)
        state13.add_range_goto(11, 33, 13)
        state13.add_range_goto(34, 34, 16)
        state13.add_range_goto(35, 1114111, 13)
        this.states.append(state13)

        let state14 = State()
        state14.add_range_goto(0, 9, 14)
        state14.add_range_goto(10, 10, 15)
        state14.add_range_goto(11, 1114111, 14)
        this.states.append(state14)

        let state15 = State()
        state15.add_range_goto(0, 1114111, 12)
        state15.accept = "comment"
        this.states.append(state15)

        let state16 = State()
        state16.add_range_goto(0, 1114111, 12)
        state16.accept = "string"
        this.states.append(state16)

        let state17 = State()
        state17.add_range_goto(0, 1114111, 12)
        state17.accept = "coloncolon"
        this.states.append(state17)

        let state18 = State()
        state18.add_range_goto(0, 1114111, 12)
        state18.accept = "arrow"
        this.states.append(state18)




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

        this.offset += 1

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

