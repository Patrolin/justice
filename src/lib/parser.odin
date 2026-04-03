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
	using _:     struct #raw_union {
		user_data: rawptr,
		int:       int,
		str:       string,
		value:     ^ASTNode,
		using _:   struct {
			left, right: ^ASTNode,
		},
	},
}
#assert(size_of(ASTNode) == 40)

Token :: struct {
	slice: string,
	type:  TokenType,
}
#assert(size_of(Token) == 24)

ParserProc :: proc(
	parser: ^Parser,
	prev_node: ^ASTNode,
) -> (
	token: Token,
	operator_precedence: int,
)

@(private = "file")
_parser_eat_token :: #force_inline proc(parser: ^Parser, token: Token) {
	parser.start += len(token.slice)
	parser.keep_going = parser.start < len(parser.str)
}
report_parser_error :: proc(parser: ^Parser, error: string) {
	parser.keep_going = false
	if parser.error == "" {parser.error = error}
}

/* parse `A + B * ...` as `A + [B * ...]` */
@(private = "file")
_parse_downwards :: proc(
	parser: ^Parser,
	prev_node: ^ASTNode,
	min_precedence: int,
	allocator := context.temp_allocator,
) -> (
	node: ^ASTNode,
) {
	/* NOTE: unary head or binary op */
	prev_node := prev_node
	prev_node_unary_tail := prev_node
	prev_node_unary_tail_is_value := false
	for parser.keep_going {
		token, operator_precedence := parser.parser_proc(parser, prev_node)
		//fmt.printfln("_parse_downwards: %v, %v", token, operator_precedence)
		if intrinsics.expect(len(token.slice) == 0 || !parser.keep_going, false) {
			report_parser_error(parser, "Cannot have token of length 0")
			break
		}
		switch OpType(operator_precedence) {
		case OpType.Ignore:
			_parser_eat_token(parser, token)
		case OpType.Value, OpType.Unary, OpType.LeftBracket:
			if prev_node_unary_tail_is_value {
				report_parser_error(parser, "Cannot have two values in a row")
				break
			}
			_parser_eat_token(parser, token)
			if OpType(operator_precedence) == .LeftBracket {
				// left bracket
				parser.bracket_count += 1
				node = _parse_upwards(parser, -1, allocator = allocator)
				// right bracket
				token, operator_precedence := parser.parser_proc(parser, prev_node)
				if OpType(operator_precedence) != .RightBracket {
					report_parser_error(parser, "Unclosed left bracket")
					break
				}
				parser.bracket_count -= 1
				_parser_eat_token(parser, token)
			} else {
				node = new(ASTNode, allocator = allocator)
				node.token = token
			}
			if prev_node == nil {
				prev_node = node
			} else {
				prev_node_unary_tail.left = node
			}
			prev_node_unary_tail = node
			prev_node_unary_tail_is_value = OpType(operator_precedence) != .Unary
		case OpType.RightBracket:
			if parser.bracket_count == 0 {
				report_parser_error(parser, "Unclosed right bracket")
			}
			// close until we find the matching left bracket
			parser.keep_going = false
			break
		case:
			// binary
			if prev_node == nil {
				report_parser_error(parser, "Cannot have binary op without a value")
				break
			}
			/* NOTE: The full algorithm would be:
				`if operator_precedence < min_precedence || (operator_precedence == min_precedence && operator_is_left_associative(...)) {}`
				however right-to-left associativity is confusing, so we're not doing it */
			if operator_precedence <= min_precedence {
				parser.keep_going = false
				break
			}
			_parser_eat_token(parser, token)
			node = new(ASTNode, allocator = allocator)
			node.token = token
			node.left = prev_node
			node.right = _parse_upwards(parser, operator_precedence, allocator = allocator)
			prev_node = node
		}
	}
	return prev_node
}
/* parse `A * B + ...` as `[A * B] + ...` */
@(private = "file")
_parse_upwards :: proc(
	parser: ^Parser,
	min_precedence: int,
	allocator := context.temp_allocator,
) -> (
	prev_node: ^ASTNode,
) {
	for parser.keep_going {
		//fmt.printfln("_parse_upwards: '%v', %v, %v", parser.str[parser.start:], min_precedence, prev_node)
		prev_node = _parse_downwards(parser, prev_node, min_precedence, allocator = allocator)
	}
	/* NOTE: reset after right bracket, or binary op with lower precedence */
	parser.keep_going = parser.error == "" && parser.start < len(parser.str)
	return prev_node
}
parse :: proc(
	str: string,
	parser_proc: ParserProc,
	allocator := context.temp_allocator,
) -> (
	node: ^ASTNode,
	error: string,
) {
	parser := Parser {
		str         = str,
		start       = 0,
		parser_proc = parser_proc,
		keep_going  = true,
		error       = "",
	}
	result := _parse_upwards(&parser, -1, allocator = allocator)
	return result, parser.error
}

repeat :: proc(str: string, count: int, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make_none(allocator = allocator)
	for i in 0 ..< count {
		fmt.sbprint(&sb, str)
	}
	return strings.to_string(sb)
}
print_ast :: proc(node: ^ASTNode, indent: int = 0) {
	indent_str := repeat(" ", indent)
	fmt.printfln("%v", node.token)
	if node.type < 0 {return} /* NOTE: negative node types are used for custom data */
	if node.left != nil {
		fmt.printf("%v- ", indent_str)
		print_ast(node.left, indent + 1)
	}
	if node.right != nil {
		fmt.printf("%v- ", indent_str)
		print_ast(node.right, indent + 1)
	}
}
