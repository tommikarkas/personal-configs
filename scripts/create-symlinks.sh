#!/bin/bash
set -e
set -x

PROJECT_DIR="/projects/personal-configs/"
TARGET_DIR="${HOME}${PROJECT_DIR}"
ln -s "${TARGET_DIR}.bashrc" ~/.bashrc 
ln -s "${TARGET_DIR}.bash_aliases" ~/.bash_aliases 
ln -s "${TARGET_DIR}.vimrc" ~/.vimrc 
