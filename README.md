# ice
Ice is an OS-agnostic build system with basic scripting funcionality.

## Usage
Create a `.ice` file in your project root with some runnable options:
```yaml
run:
  odin run src -out:ice-debug.exe
release:
  odin build src -vet -o:speed -out:ice.exe
  wsl sh -c "odin build src -vet -o:speed -out:ice-linux-x64"
```

- `ice` - list runnable options
- `ice <option_name>` - run the selected option

## Todo list
- Support `CONSTANT :: "value"`
- `args += "-foo -bar"` to append arguments into a variable with implicit spaces
- `if` conditions
- builtin `OS_WINDOWS`, ...
- builtin functions for cleaning dirs safely
