package lib
import "base:intrinsics"
import "core:fmt"
import "core:strings"

TokenType :: int
OpType :: enum {
	Ignore       = -1,
	Value        = -2,
	Unary        = -3,
	LeftBracket  = -4,
	RightBracket = -5,
}

Parser :: struct {
	str:           string,
	start:         int,
	parser_proc:   ParserProc `fmt:"-"`,
	keep_going:    bool,
	error:         string,
	bracket_count: int,
}
ASTNode :: struct {
	using token: Token,
	left, right: ^ASTNode,
}
#assert(size_of(ASTNode) == 48)

Token :: struct {
	slice:     string,
	type:      TokenType,
	user_data: uintptr `fmt:"-"`,
}
#assert(size_of(Token) == 32)

ParserProc :: proc(parser: ^Parser, prev_node: ^ASTNode) -> (token: Token, operator_precedence: int)

@(private = "file")
_parser_eat_token :: #force_inline proc(parser: ^Parser, token: Token) {
	parser.start += len(token.slice)
	parser.keep_going = parser.start < len(parser.str)
}
// TODO: add `file:line:column` prefix to the error
report_parser_error :: proc(parser: ^Parser, error: string) {
	parser.keep_going = false
	if len(parser.error) == 0 {parser.error = error}
}
@(private = "file")
_parse_recursively :: proc(parser: ^Parser, min_precedence: int, allocator := context.temp_allocator) -> (prev_node: ^ASTNode) {
	for parser.keep_going {
		unary_tail := prev_node
		unary_tail_is_value := false
		for parser.keep_going {
			token, operator_precedence := parser.parser_proc(parser, prev_node)
			fmt.assertf(operator_precedence != 0 || parser.error != "", "token: %v, operator_precedence: %v", token, operator_precedence)
			if intrinsics.expect(len(token.slice) == 0 || !parser.keep_going, false) {
				report_parser_error(parser, fmt.tprintf("Cannot have token of length 0: %v", token))
				break
			}
			switch OpType(operator_precedence) {
			case OpType.Ignore:
				_parser_eat_token(parser, token)
			case OpType.Value, OpType.Unary, OpType.LeftBracket:
				if unary_tail_is_value {
					report_parser_error(parser, fmt.tprintf("Cannot have two values in a row: %v, %v", prev_node.token, token))
					break
				}
				_parser_eat_token(parser, token)
				node: ^ASTNode = ---
				if OpType(operator_precedence) == .LeftBracket {
					// left bracket
					parser.bracket_count += 1
					node = _parse_recursively(parser, -1, allocator = allocator)
					// right bracket
					next_token, next_operator_precedence := parser.parser_proc(parser, prev_node)
					if OpType(next_operator_precedence) != .RightBracket {
						report_parser_error(parser, "Unclosed left bracket")
						break
					}
					parser.bracket_count -= 1
					_parser_eat_token(parser, next_token)
				} else {
					node = new(ASTNode, allocator = allocator)
					node.token = token
				}
				if prev_node == nil {prev_node = node} else {unary_tail.left = node}
				unary_tail = node
				unary_tail_is_value = OpType(operator_precedence) != .Unary
			case OpType.RightBracket:
				if parser.bracket_count == 0 {
					report_parser_error(parser, "Unclosed right bracket")
				}
				// close until we find the matching left bracket
				parser.keep_going = false
				break
			case:
				// binary
				/* NOTE: The full algorithm would be:
				`if operator_precedence < min_precedence || (operator_precedence == min_precedence && operator_is_right_associative(...)) {}`
				however right-associativity is confusing, so we're not doing it */
				if operator_precedence < min_precedence {
					parser.keep_going = false
					break
				}
				_parser_eat_token(parser, token)
				node := new(ASTNode, allocator = allocator)
				node.token = token
				node.left = prev_node
				node.right = _parse_recursively(parser, operator_precedence, allocator = allocator)
				prev_node = node
			}
		}
	}
	/* NOTE: reset after right bracket, or binary op with lower precedence */
	parser.keep_going = len(parser.error) == 0 && parser.start < len(parser.str)
	return prev_node
}
parse :: proc(str: string, parser_proc: ParserProc, allocator := context.temp_allocator) -> (node: ^ASTNode, error: string) {
	parser := Parser {
		str         = str,
		start       = 0,
		parser_proc = parser_proc,
		keep_going  = true,
		error       = "",
	}
	result := _parse_recursively(&parser, -1, allocator = allocator)
	return result, parser.error
}

repeat :: proc(str: string, count: int, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make_none(allocator = allocator)
	for _ in 0 ..< count {
		fmt.sbprint(&sb, str)
	}
	return strings.to_string(sb)
}
print_ast :: proc(node: ^ASTNode, indent: int = 0) {
	indent_str := repeat(" ", indent)
	fmt.printfln("%v", node.token)
	if node == nil || node.type < 0 {return} /* NOTE: negative node types are used for unary ops and custom data */
	if node.left != nil {
		fmt.printf("%v. ", indent_str)
		print_ast(node.left, indent + 1)
	}
	if node.right != nil {
		fmt.printf("%v- ", indent_str)
		print_ast(node.right, indent + 1)
	}
}
