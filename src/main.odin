// odin run src -out:ice-debug.exe -- release
package main
import "base:intrinsics"
import "core:fmt"
import "core:os"
import "core:strings"
import "lib"

// parser
TokenType :: enum {
	None,
	// binary ops
	Newline,
	Runnable,
	DeclareConstant,
	DeclareAssignment,
	// values
	Int,
	String,
	Name,
	Command,
	// unary ops
	Plus,
	Minus,
	// brackets
	LeftBracket,
	RightBracket,
	// ignore
	Whitespace,
	SingleLineComment,
	MultiLineComment,
}
parse_ice :: proc(
	parser: ^lib.Parser,
	prev_node: ^lib.ASTNode,
) -> (
	token: lib.Token,
	op_type: lib.OpType,
	precedence: int,
	right_associative: bool,
) {
	i := parser.start
	first_char := parser.str[i]
	switch first_char {
	case ' ':
		j := lib.index_after_ascii_char(parser.str, i, ' ')
		token.slice = parser.str[i:j]
		token.type = int(TokenType.Whitespace)
		op_type = lib.OpType.Ignore
	case '/':
		j := lib.index_ascii_char(parser.str, i, ' ')
		token.slice = parser.str[i:j]
		if token.slice == "//" {
			j = lib.index_newline(parser.str, j)
			token.slice = parser.str[i:j]
			token.type = int(TokenType.SingleLineComment)
			op_type = lib.OpType.Ignore
		} else if token.slice == "/*" {
			j = lib.index_after(parser.str, j, "*/")
			token.slice = parser.str[i:j]
			token.type = int(TokenType.MultiLineComment)
			op_type = lib.OpType.Ignore
		} else {
			lib.report_parser_error(parser, fmt.tprintf("'%v' not implemented yet.", rune(first_char)))
		}
	case '0' ..= '9':
		j := lib.index_after_ascii(parser.str, i, "0123456789")
		token.slice = parser.str[i:j]
		token.type = int(TokenType.Int)
		op_type = lib.OpType.Value
	case '"':
		// TODO: parse strings properly
		j := lib.index_ascii_char(parser.str, i + 1, '"') + 1
		token.slice = parser.str[i:j]
		token.type = int(TokenType.String)
		string_value := new([]u8)
		string_value^ = transmute([]u8)(token.slice[1:len(token.slice) - 1])
		token.user_data = uintptr(string_value)
		op_type = lib.OpType.Value
	case '$', 'A' ..= 'Z', '_', 'a' ..= 'z':
		// try parsing a runnable
		j := lib.index_after_ascii(parser.str, i, "$-:0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz")
		if parser.str[j - 1] == ':' {
			token.user_data = uintptr((j - 1) - i)
			j = lib.index_after_newline(parser.str, j)
			token.slice = parser.str[i:j]
			token.type = int(TokenType.Runnable)
			precedence = 1
			right_associative = true
			break
		}
		/* NOTE: most linux shells only allow `[A-Z_a-z][0-9A-Z_a-z]*` */
		j = lib.index_after_ascii(parser.str, i, "$0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz")
		token.slice = parser.str[i:j]
		if token.slice == "if" {
			if true {
				lib.report_parser_error(parser, "TODO: if")
			} else {
				/*condition_end := lib.index_after_ascii_char(parser.str, j, '{')
				if condition_end >= len(parser.str) {
					lib.report_parser_error(parser, "Missing block after if statement")
					return
				}
				condition, condition_error := lib.parse(parser.str[:condition_end], parse_ice, j)
				if len(condition_error) != 0 {
					lib.report_parser_error(parser, condition_error)
					return
				}
				true_block_start := condition_end + 1
				true_block, true_error := lib.parse(parser.str[:condition_end], parse_ice, true_block_start)*/
			}
		}
		if j < len(parser.str) {
			switch parser.str[j] {
			case '(':
				lib.report_parser_error(parser, "TODO: function call")
				return
			}
		}
		j = lib.index_after_ascii_char(parser.str, j, ' ')
		if lib.starts_with(parser.str[j:], "::") || lib.starts_with(parser.str[j:], ":=") {
			token.type = int(TokenType.Name)
			op_type = lib.OpType.Value
			return
		}
		j = lib.index_newline(parser.str, j)
		token.slice = parser.str[i:j]
		token.type = int(TokenType.Command)
		op_type = lib.OpType.Value
		return
	case '\n', '\r':
		j := lib.index_after_newlines(parser.str, i)
		token.slice = parser.str[i:j]
		token.type = int(TokenType.Newline)
		precedence = 2
	case ':':
		j := lib.index_ascii(parser.str, i, "\n\r ")
		token.slice = parser.str[i:j]
		if token.slice == "::" {
			token.type = int(TokenType.DeclareConstant)
			precedence = 3
		} else if token.slice == ":=" {
			token.type = int(TokenType.DeclareAssignment)
			precedence = 3
		} else {
			lib.report_parser_error(parser, fmt.tprintf("Invalid operator '%v'", token.slice))
		}
	case '+':
		token.slice = parser.str[i:i + 1]
		token.type = int(TokenType.Plus)
		precedence = 10
	case '-':
		token.slice = parser.str[i:i + 1]
		token.type = int(TokenType.Minus)
		precedence = 10
	case:
		if prev_node == nil {
			j := lib.index_newline(parser.str, i)
			token.slice = parser.str[i:j]
			token.type = int(TokenType.Command)
			op_type = lib.OpType.Value
		} else {
			lib.report_parser_error(parser, fmt.tprintf("'%v' not implemented yet.", rune(first_char)))
		}
	}
	return
}
IS_RELEASE :: ODIN_OPTIMIZATION_MODE == .Speed
assertf :: proc(condition: bool, format: string, args: ..any, loc := #caller_location) {
	when IS_RELEASE {
		if intrinsics.expect(!condition, false) {
			fmt.printfln(format, ..args)
			intrinsics.trap()
		}
	} else {
		fmt.assertf(condition, format, ..args, loc = loc)
	}
}

// interpreter
Variable :: struct {
	readonly: bool,
	value:    union {
		int,
		string,
	},
}
Variables :: map[string]Variable
main :: proc() {
	// read config from `.ice`
	config_file, read_err := os.read_entire_file(".ice", allocator = context.allocator)
	assert(read_err == nil, "Failed to open .ice")
	// parse the config
	ast, parse_err := lib.parse(string(config_file), parse_ice)
	when !IS_RELEASE {lib.print_ast(ast)}
	assert(len(parse_err) == 0, parse_err)
	// find runnable options
	runnables_map: map[string]^lib.ASTNode
	runnables_list: [dynamic]string
	for curr := ast; curr != nil && curr.type == int(TokenType.Runnable); curr = curr.right {
		name := curr.slice[:curr.user_data]
		code := curr.right
		if TokenType(code.type) == .Runnable {code = code.left}
		runnables_map[name] = code
		append(&runnables_list, name)
	}
	// parse the args
	if len(os.args) < 2 {
		fmt.println("Usage:")
		for runnable in runnables_list {fmt.printfln("- ice %v", runnable)}
		return
	}
	selected_runnable_name := os.args[1]
	args: strings.Builder
	if (len(os.args) >= 3) {
		fmt.sbprint(&args, os.args[2])
		for arg in os.args[3:] {fmt.sbprintf(&args, " %v", arg)}
	}
	// add builtin constants
	variables := Variables{}
	variables["ARGS"] = Variable{true, strings.to_string(args)}
	if ODIN_OS == .Windows {variables["OS_WINDOWS"] = Variable{true, 1}}
	if ODIN_OS == .Linux {variables["OS_LINUX"] = Variable{true, 1}}
	// run the user setup code
	setup := ast.left
	run_interpreter(setup, &variables)
	// run the selected runnable
	selected_runnable := runnables_map[selected_runnable_name]
	run_interpreter(selected_runnable, &variables)
}
run_interpreter :: proc(parent: ^lib.ASTNode, variables: ^Variables) {
	walk_ast_lines(parent, variables, proc(node: ^lib.ASTNode, user_data: rawptr) {
		variables := (^Variables)(user_data)
		variable_readonly := false
		#partial switch TokenType(node.type) {
		case .DeclareConstant:
			variable_readonly = true
			fallthrough
		case .DeclareAssignment:
			name := node.left.slice
			expression := node.right
			assertf(TokenType(expression.type) == .String, "Unsupported expression type: %v", TokenType(expression.type))
			string_value := (^string)(expression.user_data)^
			if name in variables {
				current_variable := variables[name]
				assertf(false, "Cannot redeclare %v '%v'", current_variable.readonly ? "constant" : "variable", name)
			}
			variables[name] = {variable_readonly, string_value}
		case .Command:
			source_command := node.slice
			i := 0
			sb := strings.builder_make()
			for {
				j := lib.index(source_command, i, "$$")
				fmt.sbprint(&sb, source_command[i:j])
				i = j
				if i >= len(source_command) {break}
				k := lib.index_after_ascii(source_command, j + 2, "ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz")
				variable_name := source_command[j + 2:k]
				variable, variable_exists := variables[variable_name]
				assertf(variable_exists, "Undeclared variable '%v'", variable_name)
				switch v in variable.value {
				case int:
					fmt.sbprint(&sb, v)
				case string:
					fmt.sbprint(&sb, v)
				}
				i = k
			}
			command_to_run := strings.to_string(sb)
			if lib.starts_with(command_to_run, "rm ") || lib.starts_with(command_to_run, "del ") {
				fmt.printfln("Suspicious command: '%v', aborting.", command_to_run)
				return
			}
			fmt.println(command_to_run)
			return_code := execute_command(command_to_run)
			assertf(return_code == 0, "Got return code %v, aborting.", return_code)
		case:
			assertf(false, "Unsupported node.type: %v", TokenType(node.type))
		}
	})
}
walk_ast_lines :: proc(node: ^lib.ASTNode, user_data: rawptr, callback: proc(node: ^lib.ASTNode, user_data: rawptr)) {
	if node == nil {return}
	if node.type == int(TokenType.Newline) {
		walk_ast_lines(node.left, user_data, callback)
		walk_ast_lines(node.right, user_data, callback)
	} else {
		callback(node, user_data)
	}
}
