# ice
Ice is an OS-agnostic build system with basic scripting funcionality.

## Usage
Create a `.ice` file in your project root with some runnable options:
```yaml
BUILD_RELEASE :: "odin build src -vet -o:speed"

run:
  odin run src -out:ice-debug.exe
release:
  $$BUILD_RELEASE -out:ice.exe
  wsl sh -c "$$BUILD_RELEASE -out:ice-linux-x64"
```

- `ice` - list runnable options
- `ice <option_name>` - run the selected option

## Features
```
FOO :: "foo"   // declare a constant
foo :: "foo"   // declare a variable
bar:           // declare a runnable
  echo "hello" // run a command
  echo $$foo   // run a command using the value of foo
```

## Todo list
- Print error line from config on error
- `if` conditions
- builtin `EXE(string)` -> add ".exe" suffix on windows?
- `params()` builtin for bools
- `args += "-foo -bar"` to append arguments into a variable with implicit spaces
- ability to run substeps via `step()`
- builtin `ARGS` from `ice run -- ..ARGS`
- builtin `$var` from environment variables
- builtin functions for cleaning dirs safely
