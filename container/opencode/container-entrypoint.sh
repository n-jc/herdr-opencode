#!/bin/sh
set -eu

export TERM="${TERM:-xterm-256color}"
export LANG="${LANG:-C.UTF-8}"

exec opencode "$@"
