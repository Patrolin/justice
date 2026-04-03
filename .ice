run:
  odin run src -out:ice-debug.exe
release:
  odin build src -vet -o:speed -out:ice.exe
  wsl sh -c "odin build src -vet -o:speed -out:ice-linux-x64"
