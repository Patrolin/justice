// odin run src -out:ice-debug.exe
package main
import "core:fmt"
import "core:os"
import "lib"

TokenType :: enum {
	None,
	// ignore
	Whitespace,
	// brackets
	LeftBracket,
	RightBracket,
	// values
	Command,
	String,
	Int,
	// unary ops
	Plus,
	Minus,
	// binary ops
	Newline,
	Runnable,
}
parse_ice :: proc(parser: ^lib.Parser, prev_node: ^lib.ASTNode) -> (token: lib.Token, operator_precedence: int) {
	i := parser.start
	first_char := parser.str[i]
	switch first_char {
	case ' ':
		j := lib.index_not_ascii_char(parser.str, i, ' ')
		token.slice = parser.str[i:j]
		token.type = int(TokenType.Whitespace)
		operator_precedence = int(lib.OpType.Ignore)
	case '\n', '\r':
		j := lib.index_ignore_newline(parser.str, i)
		token.slice = parser.str[i:j]
		token.type = int(TokenType.Newline)
		operator_precedence = 2
	case '0' ..= '9':
		j := lib.index_not_ascii(parser.str, i, "0123456789")
		token.slice = parser.str[i:j]
		token.type = int(TokenType.Int)
		operator_precedence = int(lib.OpType.Value)
	case '$', 'A' ..= 'Z', '_', 'a' ..= 'z':
		j := lib.index_not_ascii(parser.str, i, "$ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz")
		token.slice = parser.str[i:j]
		if token.slice == "if" {
			lib.report_parser_error(parser, "TODO: if")
			return
		}
		if j < len(parser.str) {
			switch parser.str[j] {
			case '(':
				lib.report_parser_error(parser, "TODO: function call")
				return
			case ':':
				token.user_data = uintptr(j - i)
				j = lib.index_ignore_newline(parser.str, j + 1)
				token.slice = parser.str[i:j]
				token.type = int(TokenType.Runnable)
				operator_precedence = 1
				return
			}
		}
		j = lib.index_newline(parser.str, j)
		token.slice = parser.str[i:j]
		token.type = int(TokenType.Command)
		operator_precedence = int(lib.OpType.Value)
		return
	case '+':
		token.slice = parser.str[i:i + 1]
		token.type = int(TokenType.Plus)
		operator_precedence = 10
	case '-':
		token.slice = parser.str[i:i + 1]
		token.type = int(TokenType.Minus)
		operator_precedence = 10
	case:
		lib.report_parser_error(parser, fmt.tprintf("'%v' not implemented yet.", rune(first_char)))
	}
	return
}
main :: proc() {
	// read config from `.ice`
	config_file, read_err := os.read_entire_file(".ice", allocator = context.allocator)
	assert(read_err == nil, "Failed to open .ice")
	// parse the config
	ast, parse_err := lib.parse(string(config_file), parse_ice)
	/*lib.print_ast(ast)*/
	assert(len(parse_err) == 0, parse_err)
	// find runnable options
	runnables_map: map[string]^lib.ASTNode
	runnables_list_reverse: [dynamic]string
	for curr := ast; curr != nil && curr.type == int(TokenType.Runnable); curr = curr.left {
		name := curr.slice[:curr.user_data]
		runnables_map[name] = curr.right
		append(&runnables_list_reverse, name)
	}
	// parse the args
	if len(os.args) < 2 {
		fmt.println("Options:")
		for i := len(runnables_list_reverse) - 1; i >= 0; i -= 1 {
			fmt.printfln("- %v", runnables_list_reverse[i])
		}
		return
	}
	selected_name := os.args[1]
	// run the selected runnable
	selected_runnable := runnables_map[selected_name]
	walk_ast(selected_runnable, proc(node: ^lib.ASTNode) {
		command_to_run := node.slice
		fmt.println(command_to_run)
		execute_command(command_to_run)
	})
}
walk_ast :: proc(node: ^lib.ASTNode, callback: proc(_: ^lib.ASTNode)) {
	if node == nil {return}
	if node.type == int(TokenType.Newline) {
		walk_ast(node.left, callback)
		walk_ast(node.right, callback)
	} else {
		callback(node)
	}
}
