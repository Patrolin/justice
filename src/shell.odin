package main
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"

_build_environment_block :: proc(environment: []string, allocator: runtime.Allocator) -> string {
	builder := strings.builder_make(allocator)
	loop: #reverse for kv, cur_idx in environment {
		eq_idx := strings.index_byte(kv, '=')
		assert(eq_idx >= 0, "Malformed environment string. Expected '=' to separate keys and values")
		key := kv[:eq_idx]
		for old_kv in environment[cur_idx + 1:] {
			old_key := old_kv[:strings.index_byte(old_kv, '=')]
			if key == old_key {
				continue loop
			}
		}
		strings.write_string(&builder, kv)
		strings.write_byte(&builder, 0)
	}
	// Note(flysand): In addition to the NUL-terminator for each string, the
	// environment block itself is NUL-terminated.
	strings.write_byte(&builder, 0)
	return strings.to_string(builder)
}

@(require_results)
execute_command :: proc(command: string, variables: ^Variables) -> int {
	env: [dynamic]string
	for key, variable in variables {
		if key[0] == '$' {
			append(&env, fmt.tprintf("%v=%v", key[1:], variable.value))
		}
	}
	when ODIN_OS == .Windows {
		full_command := []string{"powershell", "-Command", command}
	} else {
		full_command := []string{"sh", "-c", command}
	}
	process, process_create_err := os.process_start({command = full_command, stdout = os.stdout, stderr = os.stderr, env = env[:]})
	fmt.assertf(process_create_err == nil, "create_process_err: %v", process_create_err)
	state, process_wait_err := os.process_wait(process)
	fmt.assertf(process_wait_err == nil, "process_wait_err: %v", process_wait_err)
	return state.exit_code
}
