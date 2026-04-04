RELEASE_BUILD := "odin build src -vet -o:speed"

run:
  odin run src -out:ice-debug.exe
release:
  $$RELEASE_BUILD -out:ice.exe
  wsl sh -c "$$RELEASE_BUILD -out:ice-linux-x64"
