#!/bin/bash
# Run all tests from the project root directory.
# Usage: bash tests/run_tests.sh

cd "$(dirname "$0")/.." || exit 1

PASS=0
FAIL=0

for test_file in tests/test_*.lua; do
    [ "$test_file" = "tests/test_helpers.lua" ] && continue
    echo "=== $test_file ==="
    if lua5.4 "$test_file" 2>&1; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    echo ""
done

echo "==============================="
echo "Test files: $((PASS + FAIL)) total, $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
