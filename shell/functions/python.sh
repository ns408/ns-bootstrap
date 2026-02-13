#!/usr/bin/env bash
# Python environment setup
# Note: Python version management handled by mise (see .zprofile)

# Python startup file
[[ -f "${HOME}/.pythonstartup.py" ]] && export PYTHONSTARTUP="${HOME}/.pythonstartup.py"
