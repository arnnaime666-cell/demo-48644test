#!/bin/sh

set -eu

# Prefer a real Git binary over Apple's /usr/bin/git shim, which invokes
# xcrun and writes cache files to locations that are often blocked in
# sandboxed agent sessions.
for developer_bin in \
  "/Applications/Xcode-beta.app/Contents/Developer/usr/bin" \
  "/Applications/Xcode.app/Contents/Developer/usr/bin" \
  "/Library/Developer/CommandLineTools/usr/bin"
do
  if [ -x "$developer_bin/git" ]; then
    case ":$PATH:" in
      *":$developer_bin:"*) ;;
      *) export PATH="$developer_bin:$PATH" ;;
    esac
    break
  fi
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

echo "PATH prefixed with a real Git binary when available."
echo "Current git: $(command -v git)"
