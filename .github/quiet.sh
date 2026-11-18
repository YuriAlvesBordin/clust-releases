#!/usr/bin/env bash
# quiet NAME COMMAND...: runs COMMAND with all of its output in ../logs/NAME.log instead of the
# public job log, because compiler, lint and test output quotes lines of the private source. Prints
# only whether it passed. On failure the seal-logs action encrypts the logs; nothing else does.
set -uo pipefail
name="$1"
shift
mkdir -p ../logs
if "$@" > "../logs/$name.log" 2>&1; then
  echo "$name: ok"
else
  code=$?
  echo "::error::$name failed (exit $code). Its output is in the encrypted logs artifact."
  exit "$code"
fi
