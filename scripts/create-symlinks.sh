#!/bin/bash
set -e
set -x

source shared-vars.sh

ln -fs "${TARGET_DIR}.bashrc" ~/.bashrc
ln -fs "${TARGET_DIR}.bash_aliases" ~/.bash_aliases
ln -fs "${TARGET_DIR}.vimrc" ~/.vimrc
ln -fs "${TARGET_DIR}.env_vars" ~/.env_vars
ln -fs "${TARGET_DIR}.gitconfig" ~/.gitconfig
