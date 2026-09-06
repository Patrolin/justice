// bootstrap:
/* odin run src -out:ice-debug.exe -define:VERSION=debug -- release */
FLAGS :: "-o:size"
run:
  odin run src -out:ice-debug.exe -define:VERSION=debug $$FLAGS -- $$ARGS
release:
  BUILD :: "odin build src -define:VERSION=$version -vet $$FLAGS"
  $$BUILD -out:ice.exe
  wsl sh -c "$$BUILD -out:ice-linux-x64"
test-fail:
  ./fail.ps1
  echo "not reachable"
test-continue:
  ? ./fail.ps1
  echo "continued"
