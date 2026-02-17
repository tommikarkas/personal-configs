# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a personal dotfiles repository containing shell configurations, aliases, git settings, and system setup scripts for macOS and Linux environments. The configurations are meant to be symlinked to the home directory.

## Repository Structure

- **Root dotfiles**: `.bashrc`, `.bash_aliases`, `.env_vars`, `.gitconfig`, `.vimrc` - Core configuration files meant to be symlinked to `~/`
- **scripts/**: Contains utilities for managing symlinks
  - `create-symlinks.sh` - Creates symlinks for all dotfiles to home directory
  - `delete-symlinks.sh` - Removes the symlinks created by create-symlinks.sh
  - `shared-vars.sh` - Defines project path variables used by other scripts
- **mac/**: macOS-specific configurations
  - `.bash_profile` - macOS login shell configuration (sources .bashrc, sets up jenv, nvm, rvm, chruby)
  - `mac-init-scripts.sh` - Initial macOS setup script for installing brew packages
- **Brewfile**: Homebrew bundle file listing all installed packages and casks

## Key Configuration Files

### .bashrc
Main bash configuration that includes:
- Custom PS1 prompt with git branch display via `parse_git_branch()`
- `mark` function for bookmarking directories
- Integrations: thefuck, pyenv, kubectl completion, rvm
- PATH additions for various tools (Redis, MongoDB, Elasticsearch, IntelliJ IDEA)

### .bash_aliases
Quick command shortcuts including:
- `k` for kubectl
- `g` for git
- `resume` for `tmux attach -t 0`
- `openvault` for Vault login with GPG-encrypted token
- `aws-login-payments` for AWS Vault login

### .env_vars
Contains environment variables (note: currently blocked from reading due to permission settings, likely contains sensitive credentials)

### .gitconfig
Git configuration with:
- GPG commit signing enabled
- Git LFS filter configuration
- Vim as default editor

## Setup Commands

### Initial Setup (macOS)
```bash
# Install Homebrew packages from Brewfile
brew bundle install

# Run macOS initialization script
./mac/mac-init-scripts.sh
```

### Managing Symlinks
```bash
# Create symlinks for all dotfiles
cd scripts/
./create-symlinks.sh

# Remove symlinks (to revert)
./delete-symlinks.sh
```

Note: The symlink scripts use `shared-vars.sh` which defines `TARGET_DIR` as `${HOME}/Projects/Personal/personal-configs/`

## Important Notes

- The `.bashrc` and `mac/.bash_profile` contain hardcoded credentials and tokens that should NOT be committed to version control. When making changes, ensure sensitive data is moved to a separate, git-ignored file.
- The repository tracks modified but uncommitted changes to `.bash_aliases`, `.bashrc`, `.env_vars`, `.gitconfig`, and `mac/.bash_profile`
- Untracked files: `.bashrc-e` (likely backup) and `Brewfile`
