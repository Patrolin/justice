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
test-env: // ice test-env -env:example
  echo $version
  echo $foo
  echo $bar
  echo $baz
test-constant:
  x :: "1"
  x :: "$$x 2" // Error: Cannot redeclare constant 'x'
  echo "$$x"
test-variable:
  x := "1"
  x := "$$x 2" // redeclare to update the variable
  echo "$$x"
test-unicode:
  echo "á"
test-string:
  // parsing
  FOO := "evaluate\nescapes"
  echo "$$FOO"
  FOO := 'preserve\nescapes'
  echo "$$FOO"
  // formatting
  $BAR := 'hello" $(pwd)'
  echo 'env-dq: $BAR'
  echo "env-dq: $"BAR"
  echo 'env-dq: $'BAR'
  $BAR := "hello' $(pwd)"
  echo "env-sq: $BAR"
  echo "env-sq: $"BAR"
  echo 'env-sq: $'BAR'
  FOO := 'hello" $(pwd)'
  echo 'var-sq: $$FOO'
  echo "var-sq: $$"FOO"
  echo 'var-sq: $$'FOO'
  FOO := "hello' $(pwd)"
  echo "var-dq: $$FOO"
  echo "var-dq: $$"FOO"
  echo 'var-dq: $$'FOO'
  $BAR := "e'v\"il"
  BAR_ESCAPED :: "$'BAR"
  echo "$$$"BAR = '$$"BAR_ESCAPED'"
test-pwd:
  echo $(pwd).Path
  echo $PWD
  cd src
  echo $(pwd).Path
  echo $PWD
  cd /
  echo $(pwd).Path
  echo $PWD
test-powershell-vars:
  $foo :: "1"
  echo $foo
  $foo:bar :: "2"
  echo $foo:bar
test-os:
  echo "OS_WINDOWS: $$OS_WINDOWS"
  echo "OS_LINUX: $$OS_LINUX"
  echo "OS_MAC: $$OS_MAC"
  echo "OS_BSD: $$OS_BSD"
  OS_UNIX :: OS_LINUX | OS_MAC | OS_BSD
  echo "OS_UNIX: $$OS_UNIX"
