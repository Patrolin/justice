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
- `ice <option_name> -env:<env_name>` - run the selected option with env variables from the `.env.<env_name>` file
- `ice -p` - print variables from the default `.env` file
- `ice -p -env:<env_name>` - print variables from the `.env.<env_name>` file

## Features
```
COMMAND :: "echo"   // declare a constant
values := "foo bar" // declare a variable
$var := "0.3"       // set an environment variable
bar:                // declare a runnable
  echo "var: $var"   // run a command using an environment variable
  echo $$ARGS        // run a command using the rest of the commandline arguments
  $$COMMAND $$values // run a command using variables
  ? command          // run a command, and continue even if it fails
  FOO :: "hello\nworld" // declare a string, evaluating escape chars (\t\n\v\f\r)
  BAR :: 'hello\nworld' // declare a string, preserving escape chars
  echo $var             // paste the environment variable directly
  echo "$"var"          // format the name of an environment variable for " strings
  echo '$'var'          // format the environment variable for ' strings
  echo $$var            // paste the variable directly
  echo "$$"var"         // format the variable for " strings
  echo '$$'var'         // format the variable for ' strings
  VAR_ESCAPED :: "$'var"            // escape for inner ' string
  echo "$$$"VAR = '$$"VAR_ESCAPED'" // print name and value and escape for outer " string
  if (OS_WINDOWS) echo "Windows!"   // execute command only on Windows
  if (OS_LINUX) echo "Linux!"       // execute command only on Linux
```

## Todo list (do we need any of these?)
- Print error line on error
- builtin `EXE(string)` -> add ".exe" suffix on windows?
- `params()` builtin for bools
- `args += "-foo -bar"` to append arguments into a variable with implicit spaces
- ability to run substeps via `! step`
- builtin functions for cleaning dirs safely
