#!/bin/sh

set -e
set -x

# Dependencies: brew

# Config variables
BREW_PACKAGES="git bash bash-completion jenv thefuck"


main () {
    brew install ${BREW_PACKAGES}
}

if brew --version > /dev/null; then
  # The package is installed
  main
else
  # The package is not installed
  echo "Install brew and try running the script again"
fi


