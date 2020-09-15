#!/bin/sh

set -e
set -x

# Dependencies: brew

# Config variables
BREW_PACKAGES="git git-gui bash bash-completion jenv thefuck cowsay"
CASK_PACKAGES="docker google-chrome iterm2 slack"

PROJECT_DIR="/Projects/Personal/personal-configs/mac/"
TARGET_DIR="${HOME}${PROJECT_DIR}"

installBrewPackages () {
    brew install ${BREW_PACKAGES}
}

installBrewCaskPackages () {
    brew cask install ${CASK_PACKAGES}
}
setBashProfile () {
    ln -fs "${TARGET_DIR}.bash_profile" ~/.bash_profile 
}

changeBackToBash () {
    chsh -s /bin/bash
}

if brew --version > /dev/null; then
  # The package is installed
  installBrewPackages
  installBrewCaskPackages
else
  # The package is not installed
  echo "Install brew and try running the script again"
fi

setBashProfile
changeBackToBash

