#!/bin/sh
# Runs every fuzzer/brute-force oracle in this directory in --release mode.
# These are too slow for `crystal spec`; run them before releases or nightly.
#
# Failure detection is by output pattern: each program reports counters like
# "bugs=0" / "0 failures" / "FAIL ..." rather than exit codes.
set -u
cd "$(dirname "$0")" || exit 1

status=0
for f in *.cr; do
  echo "=== $f ==="
  out=$(crystal run --release "$f" 2>&1) || { echo "$out"; status=1; continue; }
  echo "$out" | tail -5
  if echo "$out" | grep -qE 'FAIL|bugs=[1-9]|(^|[^0-9])[1-9][0-9]* (failures|violations)|fails: [1-9]'; then
    echo ">>> $f REPORTED FAILURES"
    status=1
  fi
done

exit $status
