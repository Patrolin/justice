package main
import "core:fmt"
import "core:os"

execute_command :: proc(command: string) -> int {
	when ODIN_OS == .Windows {
		process, process_create_err := os.process_start(
			{command = {"powershell", "-Command", command}, stdout = os.stdout, stderr = os.stderr},
		)
	} else {
		process, process_create_err := os.process_start({command = {"sh", "-c", command}, stdout = os.stdout, stderr = os.stderr})
	}
	fmt.assertf(process_create_err == nil, "create_process_err: %v", process_create_err)
	state, process_wait_err := os.process_wait(process)
	fmt.assertf(process_wait_err == nil, "process_wait_err: %v", process_wait_err)
	return state.exit_code
}
