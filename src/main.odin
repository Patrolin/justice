// odin run src -out:ice-debug.exe
package main
import "core:fmt"
import "lib"

TokenType :: enum {
	None,
	// ignore
	Whitespace,
	// brackets
	LeftBracket,
	RightBracket,
	// values
	String,
	Int,
	// unary ops
	Plus,
	Minus,
}
parse_ice :: proc(
	parser: ^lib.Parser,
	prev_node: ^lib.ASTNode,
) -> (
	token: lib.Token,
	operator_precedence: int,
) {
	i := parser.start
	first_char := parser.str[i]
	switch first_char {
	case ' ':
		j := lib.index_not_ascii_char(parser.str, i, ' ')
		token.slice = parser.str[i:j]
		token.type = int(TokenType.Whitespace)
		operator_precedence = int(lib.OpType.Ignore)
	case '0' ..= '9':
		j := lib.index_not_ascii(parser.str, i, "0123456789")
		token.slice = parser.str[i:j]
		token.type = int(TokenType.Int)
		operator_precedence = int(lib.OpType.Value)
	case '+':
		token.slice = parser.str[i:i + 1]
		token.type = int(TokenType.Plus)
		operator_precedence = 0
	case '-':
		token.slice = parser.str[i:i + 1]
		token.type = int(TokenType.Minus)
		operator_precedence = 0
	case:
		lib.report_parser_error(parser, fmt.tprintf("'%v' not implemented yet.", rune(first_char)))
	}
	return
}
main :: proc() {
	ast, error := lib.parse("12 + 3", parse_ice)
	lib.print_ast(ast)
	assert(error == "", error)
}
