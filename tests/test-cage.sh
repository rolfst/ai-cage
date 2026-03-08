#!/usr/bin/env bash
set -euo pipefail

echo "=== ai-cage security tests ==="

# Resolve coreutils and bash from Nix store for use inside the sandbox
COREUTILS_BIN="$(dirname "$(command -v ls)")"
BASH_BIN="$(command -v bash)"

echo -n "Test 1: SSH key files blocked... "
if landrun --rox "$COREUTILS_BIN" --rox /nix/store --ro /etc --connect-tcp 443 \
   -- "$COREUTILS_BIN/cat" ~/.ssh/id_ed25519 2>/dev/null; then
  echo "FAIL (could read SSH key!)"
  exit 1
else
  echo "PASS"
fi

echo -n "Test 2: Home directory blocked... "
if landrun --rox "$COREUTILS_BIN" --rox /nix/store --ro /etc \
   -- "$COREUTILS_BIN/ls" ~/Documents 2>/dev/null; then
  echo "FAIL"
  exit 1
else
  echo "PASS"
fi

echo -n "Test 3: Nix store readable... "
if landrun --rox "$COREUTILS_BIN" --rox /nix/store --ro /etc \
   -- "$COREUTILS_BIN/ls" /nix/store/ >/dev/null 2>&1; then
  echo "PASS"
else
  echo "FAIL (cannot read nix store)"
  exit 1
fi

echo -n "Test 4: Unauthorized port blocked... "
if landrun --rox "$COREUTILS_BIN" --rox "$(dirname "$BASH_BIN")" --rox /nix/store --ro /etc --connect-tcp 443 \
   -- "$BASH_BIN" -c 'echo test > /dev/tcp/127.0.0.1/8888' 2>/dev/null; then
  echo "FAIL"
  exit 1
else
  echo "PASS"
fi

echo "=== All tests passed ==="
