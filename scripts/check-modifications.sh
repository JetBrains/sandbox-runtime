#!/bin/bash
# Fails when MODIFICATIONS no longer describes this checkout: its upstream base must be the last merged
# upstream release and its file list must equal the upstream files changed since that base.
#
#   scripts/check-modifications.sh
set -euo pipefail

cd "$(dirname "$0")/.."

fail() { echo "Error: $1" >&2; exit 1; }

base_line="$(sed -n 's/^Upstream base: //p' MODIFICATIONS)"
[[ "$base_line" =~ ^v([0-9A-Za-z.-]+)\ \(([0-9a-f]{40})\)$ ]] ||
  fail "MODIFICATIONS needs a line 'Upstream base: v<version> (<full commit sha>)', found '${base_line}'"
base_version="${BASH_REMATCH[1]}"
base="${BASH_REMATCH[2]}"

git cat-file -e "${base}^{commit}" 2>/dev/null ||
  fail "upstream base ${base} is not in this clone; fetch the full history (actions/checkout fetch-depth: 0)"
git merge-base --is-ancestor "$base" HEAD || fail "upstream base ${base} is not an ancestor of HEAD"

read_version() { node -e "process.stdout.write(JSON.parse(require('fs').readFileSync(0, 'utf8')).version)"; }
base_package_version="$(git show "${base}:package.json" | read_version)"
[ "$base_package_version" = "$base_version" ] ||
  fail "upstream base ${base} is package version ${base_package_version}, not v${base_version}"
package_version="$(read_version < package.json)"
[ "$package_version" = "$base_version" ] ||
  fail "package.json is ${package_version}: after merging an upstream release, update 'Upstream base' in MODIFICATIONS"

jb_version="$(tr -d '[:space:]' < JB_VERSION)"
[[ "$jb_version" == "${base_version}-jb."* ]] ||
  fail "JB_VERSION ${jb_version} does not match upstream base v${base_version}; expected ${base_version}-jb.<n>"

listed="$(sed -n '/^Files added by JetBrains/,$ s/^  - //p' MODIFICATIONS)"
expected="$(git diff --name-only --diff-filter=a "$base")"
if [ "$listed" != "$expected" ]; then
  echo "Error: the file list in MODIFICATIONS differs from the upstream files changed since ${base}:" >&2
  diff <(echo "$listed") <(echo "$expected") >&2 || true
  exit 1
fi

echo "MODIFICATIONS matches the delta over upstream v${base_version}"
