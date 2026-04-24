// foobar
/* boo */
BUILD_RELEASE :: "odin build src -vet -o:speed"

run:
  odin run src -out:ice-debug.exe -- $$ARGS
release:
  $$BUILD_RELEASE -out:ice.exe
  wsl sh -c "$$BUILD_RELEASE -out:ice-linux-x64"
