# ice
Ice is an OS-agnostic build system with basic scripting funcionality.

## Usage
Create a `.ice` file in your project root with some runnable options:
```yaml
run:
  odin run src -out:ice-debug.exe -- $$ARGS
release:
  BUILD :: "odin build src -vet -o:speed"
  $$BUILD -out:ice.exe
  wsl sh -c "$$BUILD -out:ice-linux-x64"
```

- `ice` - print version and runnable options
- `ice <option_name>` - run the selected option

## Features
```
COMMAND :: "echo"   // declare a constant
values := "foo bar" // declare a variable
$var := "0.3"       // set an environment variable
bar:                // declare a runnable
  echo "var: $var"   // run a command using an environment variable
  echo $$ARGS        // run a command using the rest of the commandline arguments
  $$COMMAND $$values // run a command using variables
```

## Todo list
- Print error line from config on error
- escape strings in `$$$var`
- `if` conditions
- builtin `EXE(string)` -> add ".exe" suffix on windows?
- `params()` builtin for bools
- `args += "-foo -bar"` to append arguments into a variable with implicit spaces
- ability to run substeps via `step()`
- builtin functions for cleaning dirs safely
