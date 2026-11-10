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
test-env:
  echo $version
test-constant:
  x :: "1"
  x :: "$$x 2" // Error: Cannot redeclare constant 'x'
  echo "$$x"
test-variable:
  x := "1"
  x := "$$x 2" // redeclare to update the variable
  echo "$$x"
test-pwd:
  echo $(pwd).Path
  echo $PWD
  cd src
  echo $(pwd).Path
  echo $PWD
test-powershell-vars:
  $foo :: "1"
  echo $foo
  $foo:bar :: "2"
  echo $foo:bar
