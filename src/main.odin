// odin run src -out:ice-debug.exe -- release
// odin build src -out:ice-debug.exe -define:VERSION=debug
package main
import "base:intrinsics"
import "core:fmt"
import "core:os"
import "core:strings"
import "lib"

VERSION :: #config(VERSION, "0")
IS_DEBUG_VERSION :: VERSION == "debug"

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
RUNNABLE_CONTINUE_CHARS :: "$-:0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz"
when ODIN_OS == .Windows {
  VARIABLE_CHARS :: "$:0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz"
} else {
  VARIABLE_CHARS :: "$0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz"
}
VARIABLE_CONTINUE_CHARS :: VARIABLE_CHARS[1:]
/* Parse string and keep escape characters */
parse_string_keep_escaped :: proc(src: string, i: int) -> (string, int) {
  i := i
  sb: strings.Builder
  start_char := src[i]
  assert(start_char == '"' || start_char == '\'')
  j := i + 1
  i = i + 1
  for j < len(src) {
    char := src[j]
    if char == '\\' {
      if j + 1 < len(src) {
        fmt.sbprint(&sb, src[i:j + 2])
        i = j + 2
        j = j + 2
      }
    } else if char == start_char {
      break
    }
    j += 1
  }
  fmt.sbprint(&sb, src[i:j])
  return strings.to_string(sb), min(j + 1, len(src))
}
parse_string_evaluate_escapes :: proc(src: string, i: int) -> (string, int) {
  i := i
  sb: strings.Builder
  start_char := src[i]
  assert(start_char == '"' || start_char == '\'')
  j := i + 1
  i = i + 1
  for j < len(src) {
    char := src[j]
    if char == '\\' {
      fmt.sbprint(&sb, src[i:j])
      if j + 1 < len(src) {
        next_char := src[j + 1]
        switch next_char {
        case 't':
          fmt.sbprint(&sb, '\t')
        case 'n':
          fmt.sbprint(&sb, '\n')
        case 'v':
          fmt.sbprint(&sb, '\v')
        case 'f':
          fmt.sbprint(&sb, '\f')
        case 'r':
          fmt.sbprint(&sb, '\r')
        case:
          fmt.sbprint(&sb, rune(next_char))
        }
        i = j + 2
        j = j + 2
      } else {
        fmt.sbprint(&sb, "\\\\")
      }
    } else if char == start_char {
      break
    }
    j += 1
  }
  fmt.sbprint(&sb, src[i:j])
  return strings.to_string(sb), min(j + 1, len(src))
}
escape_shell_characters_for_double_quoted_string :: proc(sb: ^strings.Builder, value: string) {
  for char_u32 in value {
    if char_u32 == '"' {
      when ODIN_OS == .Windows {
        fmt.sbprint(sb, '`')
      } else {
        fmt.sbprint(sb, '\\')
      }
    }
    fmt.sbprint(sb, char_u32)
  }
}
escape_shell_characters_for_single_quoted_string :: proc(sb: ^strings.Builder, value: string) {
  for char_u32 in value {
    if char_u32 == '\'' {
      when ODIN_OS == .Windows {
        fmt.sbprint(sb, '\'')
      } else {
        fmt.sbprint(sb, '\\')
      }
    }
    fmt.sbprint(sb, char_u32)
  }
}
parse_ice :: proc(
  parser: ^lib.TreeParser,
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
    token.slice = parser.str[i:]
    if lib.starts_with(token.slice, "//") {
      j := lib.index_newline(parser.str, i + 2)
      token.slice = parser.str[i:j]
      token.type = int(TokenType.SingleLineComment)
      op_type = lib.OpType.Ignore
    } else if lib.starts_with(token.slice, "/*") {
      j := lib.index_after(parser.str, i + 2, "*/")
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
  case '"', '\'':
    string_value: string
    j: int
    if first_char == '"' {
      string_value, j = parse_string_evaluate_escapes(parser.str, i)
    } else {
      string_value, j = parse_string_keep_escaped(parser.str, i)
    }
    token.slice = parser.str[i:j]
    token.type = int(TokenType.String)
    string_slice := new(string)
    string_slice^ = string_value
    token.user_data = uintptr(string_slice)
    op_type = lib.OpType.Value
  case '$', 'A' ..= 'Z', '_', 'a' ..= 'z':
    // try parsing a runnable
    j := lib.index_after_ascii(parser.str, i, RUNNABLE_CONTINUE_CHARS)
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
    j = lib.index_after_ascii(parser.str, i, VARIABLE_CHARS)
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
    if lib.starts_with(token.slice, "? ") {
      token.user_data = 1
    }
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
      if lib.starts_with(token.slice, "? ") {
        token.user_data = 1
      }
    } else {
      lib.report_parser_error(parser, fmt.tprintf("'%v' not implemented yet.", rune(first_char)))
    }
  }
  return
}
assertf :: proc(condition: bool, format: string, args: ..any, loc := #caller_location) {
  when IS_DEBUG_VERSION {
    fmt.assertf(condition, format, ..args, loc = loc)
  } else {
    if intrinsics.expect(!condition, false) {
      fmt.printfln(format, ..args)
      intrinsics.trap()
    }
  }
}

// interpreter
InterpreterData :: struct {
  variables:         Variables,
  working_directory: string,
}
Variables :: map[string]Variable
Variable :: struct {
  readonly: bool,
  value:    union {
    int,
    string,
  },
}
main :: proc() {
  // read config from `.ice`
  config_file, read_err := os.read_entire_file(".ice", allocator = context.allocator)
  assert(read_err == nil, "Failed to open .ice")
  // parse the config
  ast, parse_err := lib.parse_tree(string(config_file), parse_ice)
  when IS_DEBUG_VERSION {lib.print_ast(ast)}
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
  arg_i := 1
  print_env_vars := false
  fail_on_missing_env_file := false
  env_file_name := ".env"
  selected_runnable_name := ""
  for arg_i < len(os.args) {
    next_arg := os.args[arg_i]
    if strings.starts_with(next_arg, "-env:") {
      env_file_name = strings.concatenate({".env.", next_arg[5:]})
      fail_on_missing_env_file = true
      arg_i += 1
    } else if next_arg == "-p" {
      print_env_vars = true
      arg_i += 1
    } else if selected_runnable_name == "" {
      selected_runnable_name = next_arg
      arg_i += 1
      continue
    } else {
      assertf(false, "Unknown arg: %v", next_arg)
    }
  }
  args: strings.Builder
  if len(os.args) > arg_i {
    fmt.sbprint(&args, os.args[arg_i])
    for arg in os.args[arg_i + 1:] {fmt.sbprintf(&args, " %v", arg)}
  }
  // add builtin constants
  data := InterpreterData{}
  data.variables["ARGS"] = Variable{true, strings.to_string(args)}
  if ODIN_OS == .Windows {data.variables["OS_WINDOWS"] = Variable{true, 1}}
  if ODIN_OS == .Linux {data.variables["OS_LINUX"] = Variable{true, 1}}
  // add environment variables
  default_env, default_env_err := os.environ(context.temp_allocator)
  fmt.assertf(default_env_err == nil, "Failed to get environment")
  for assignment in default_env {
    if len(assignment) == 0 {continue}
    j := lib.index_ascii_char(assignment, 0, '=')
    key := assignment[:j]
    k := j + 1
    value := assignment[k:len(assignment)]
    data.variables[fmt.tprintf("$%v", key)] = Variable{true, value}
  }
  // add `.env` file
  env_file, env_file_err := os.read_entire_file_from_path(env_file_name, allocator = context.allocator)
  if fail_on_missing_env_file {
    assert(env_file_err == nil, fmt.tprintf("Failed to open %v", env_file_name))
  }
  debug_env_file_vars: map[string]string
  if env_file_err == nil {
    env_file := string(env_file)
    i := 0
    j := 0
    for j < len(env_file) {
      for {
        i = lib.index_after_ascii(env_file, i, " \r\n")
        if i < len(env_file) && env_file[i] == '#' {
          i = lib.index_newline(env_file, i)
        } else {
          break
        }
      }
      j = lib.index_ascii(env_file, i, "=#\r\n")
      left := strings.trim(env_file[i:j], " ")
      if j < len(env_file) && env_file[j] == '=' {
        j = min(j + 1, len(env_file))
      }
      j = lib.index_after_ascii_char(env_file, j, ' ')
      right: string
      k: int
      if j < len(env_file) && env_file[j] == '"' {
        right, k = parse_string_evaluate_escapes(env_file, j)
      } else if j < len(env_file) && env_file[j] == '\'' {
        right, k = parse_string_keep_escaped(env_file, j)
      } else {
        k = lib.index_ascii(env_file, j, "#\r\n")
        right = strings.trim(env_file[j:k], " ")
      }
      if len(right) > 0 {
        data.variables[fmt.tprintf("$%v", left)] = Variable{false, right}
        debug_env_file_vars[left] = right
      }
      i = lib.index_newline(env_file, k)
    }
  }
  working_directory, working_directory_err := os.get_working_directory(context.allocator)
  assert(working_directory_err == nil)
  data.working_directory = working_directory
  data.variables["$PWD"] = Variable {
    readonly = true,
    value    = data.working_directory,
  }
  // print help text
  if selected_runnable_name == "" {
    fmt.printfln("ice %v:", VERSION)
    for runnable in runnables_list {fmt.printfln("- ice %v", runnable)}
    if print_env_vars {
      for k, v in debug_env_file_vars {
        fmt.printf("$%v := \"%v\"\n", k, v)
      }
    }
    return
  }
  // run the user setup code
  setup := ast.left
  run_interpreter(setup, &data)
  // run the selected runnable
  selected_runnable, runnable_exists := runnables_map[selected_runnable_name]
  assertf(runnable_exists, "Runnable '%v' does not exist.", selected_runnable_name)
  run_interpreter(selected_runnable, &data)
}
expand_string :: proc(str: string, variables: Variables) -> string {
  sb := strings.builder_make_none()
  i := 0
  for {
    j := lib.index_ascii_char(str, i, '$')
    fmt.sbprint(&sb, str[i:j])
    if j >= len(str) {break}
    get_env_variable :: proc(sb: ^strings.Builder, str: string, j: int, variables: Variables, loc := #caller_location) -> int {
      k := lib.index_after_ascii(str, j + 1, VARIABLE_CONTINUE_CHARS)
      if k == j + 1 {
        fmt.sbprint(sb, rune(str[j]))
        return j + 1
      }
      variable_name := str[j:k]
      _, variable_exists := variables[variable_name]
      if !variable_exists {
        when IS_DEBUG_VERSION {fmt.printfln("str[j:]: '%v'", str[j:])}
        assertf(false, "Error: Undeclared variable '%v'", variable_name, loc = loc)
      }
      when ODIN_OS == .Windows {
        fmt.sbprintf(sb, "$env:%v", variable_name[1:])
      } else {
        fmt.sbprint(sb, variable_name) // NOTE: posix shells already interpret `$var` correctly
      }
      return k
    }
    get_variable :: proc(sb: ^strings.Builder, str: string, j: int, variables: Variables, loc := #caller_location) -> int {
      k := lib.index_after_ascii(str, j, VARIABLE_CONTINUE_CHARS)
      variable_name := str[j:k]
      variable, variable_exists := variables[variable_name]
      assertf(variable_exists, "Error: Undeclared variable '%v'", variable_name, loc = loc)
      fmt.sbprint(sb, variable.value)
      return k
    }
    if j + 1 >= len(str) || str[j + 1] != '$' {
      // env variable
      i = get_env_variable(&sb, str, j, variables)
    } else if j + 2 >= len(str) || str[j + 2] != '$' {
      // variable
      i = get_variable(&sb, str, j + 2, variables)
    } else if j + 3 >= len(str) || str[j + 3] != '$' {
      // escaped variable
      value_sb: strings.Builder
      i = get_variable(&value_sb, str, j + 3, variables)
      value := strings.to_string(value_sb)
      escape_shell_characters_for_double_quoted_string(&sb, value)
    } else if j + 4 >= len(str) || str[j + 4] != '$' {
      // escaped variable
      value_sb: strings.Builder
      i = get_variable(&value_sb, str, j + 4, variables)
      value := strings.to_string(value_sb)
      escape_shell_characters_for_single_quoted_string(&sb, value)
    } else {
      fmt.sbprint(&sb, rune(str[j]))
      i = j + 1
    }
  }
  return strings.to_string(sb)
}
run_interpreter :: proc(parent: ^lib.ASTNode, data: ^InterpreterData) {
  walk_ast_lines(
    parent,
    data,
    proc(node: ^lib.ASTNode, user_data: rawptr) {
      data := (^InterpreterData)(user_data)
      variable_readonly := false
      #partial switch TokenType(node.type) {
      case .DeclareConstant:
        variable_readonly = true
        fallthrough
      case .DeclareAssignment:
        name := node.left.slice
        expression := node.right
        if TokenType(expression.type) != .String {
          when ODIN_DEBUG {lib.print_ast(expression)}
          assertf(false, "Unsupported expression type: %v", TokenType(expression.type))
        }
        string_value := (^string)(expression.user_data)^
        if name in data.variables {
          current_variable := data.variables[name]
          if current_variable.readonly {
            assertf(false, "Error: Cannot redeclare constant '%v'", name)
          }
        }
        data.variables[name] = {variable_readonly, expand_string(string_value, data.variables)}
      case .Command:
        is_optional := node.user_data != 0
        command := is_optional ? node.slice[2:] : node.slice
        command = expand_string(command, data.variables)
        // run the command
        if lib.starts_with(command, "rm ") || lib.starts_with(command, "del ") {
          assertf(false, "Suspicious command: '%v', aborting.", command)
        }
        if command == "cd" || lib.starts_with(command, "cd ") {
          diff := command[3:]
          if lib.starts_with(diff, "/") {
            starting_dir := data.variables["$PWD"].value.(string)
            data.working_directory = diff == "/" ? starting_dir : strings.concatenate({starting_dir, diff})
          } else {
            data.working_directory = strings.concatenate({data.working_directory, "/", diff})
          }
          fmt.printfln("cd %v", data.working_directory)
          return
        }
        fmt.println(command)
        return_code := execute_command(command, is_optional, data)
        if !is_optional {
          assertf(return_code == 0, "Got return code %v, aborting.", return_code)
        }
      case:
        assertf(false, "Unsupported node.type: %v", TokenType(node.type))
      }
    },
  )
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
