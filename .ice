// bootstrap:
/* odin run src -out:ice-debug.exe -define:VERSION=debug -- release */
run:
  odin run src -out:ice-debug.exe -define:VERSION=debug -- $$ARGS
release:
  BUILD :: "odin build src -vet -o:speed -define:VERSION=$version"
  $$BUILD -out:ice.exe
  wsl sh -c "$$BUILD -out:ice-linux-x64"
