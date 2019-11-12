#!/bin/bash
PWD=$(pwd)
PROJECT_DIR=projects/personal-configs/"
TARGET_DIR="${PWD}${PROJECT_DIR}"
ln -s ~/.bashrc "$TARGET_DIR/.bashrc"
ln -s ~/.bash_aliases "$TARGET_DIR/.bash_aliases"
ln -s ~/.vimrc "$TARGET_DIR/.vimrc"
