#!/bin/bash
# Assembles THIRD-PARTY from the license of the Bun runtime `bun build --compile` embeds and the
# licenses of the npm packages it inlines into the binary. MIT's "all copies or substantial portions"
# clause has no escape hatch, so this file must ship next to the binary. Run it with the same `bun`
# that compiles the release: the Bun notice is taken from that exact version.
#
#   npm ci && scripts/collect-third-party-licenses.sh
set -euo pipefail

cd "$(dirname "$0")/.."

OUTPUT="THIRD-PARTY"
PACKAGES="commander zod @pondwader/socks5-server node-forge"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

bun build src/cli.ts --target=bun --outdir "${work}/bundle" --metafile="${work}/meta.json" > /dev/null
bundled="$(node -e '
  const inputs = Object.keys(require(process.argv[1]).inputs)
  const names = inputs.map(p => p.match(/.*node_modules\/((?:@[^/]+\/)?[^/]+)\//)?.[1]).filter(Boolean)
  console.log([...new Set(names)].sort().join("\n"))
' "${work}/meta.json")"
declared="$(printf '%s\n' $PACKAGES | sort)"
if [ "$bundled" != "$declared" ]; then
  echo "Error: the binary bundles different npm packages than PACKAGES lists; review their licenses and update PACKAGES:" >&2
  diff <(echo "$declared") <(echo "$bundled") >&2 || true
  exit 1
fi

bun_version="$(bun --version)"
curl -fsSL --retry 3 -o "${work}/bun-LICENSE.md" \
  "https://raw.githubusercontent.com/oven-sh/bun/bun-v${bun_version}/LICENSE.md"

read_field() {
  node -e "process.stdout.write(String(require('./node_modules/$1/package.json').$2 ?? ''))"
}

{
  echo "Third-party components statically included in the srt binary."
  echo
  echo "The binary is produced with 'bun build --compile', which embeds the Bun runtime and inlines the"
  echo "whole reachable module graph. Bun's license notice and the licenses of those modules are"
  echo "reproduced verbatim below."
  echo
  echo "================================================================================"
  echo "Bun ${bun_version} runtime (https://github.com/oven-sh/bun/tree/bun-v${bun_version})"
  echo "================================================================================"
  echo
  cat "${work}/bun-LICENSE.md"
} > "$OUTPUT"

for pkg in $PACKAGES; do
  dir="node_modules/${pkg}"
  [ -d "$dir" ] || { echo "Error: ${dir} is missing; run 'npm ci' first" >&2; exit 1; }

  license_file=""
  for candidate in LICENSE LICENSE.md LICENSE.txt LICENCE license; do
    if [ -f "${dir}/${candidate}" ]; then
      license_file="${dir}/${candidate}"
      break
    fi
  done
  [ -n "$license_file" ] || { echo "Error: no license file found in ${dir}" >&2; exit 1; }

  version="$(read_field "$pkg" version)"
  spdx="$(read_field "$pkg" license)"
  [ -n "$version" ] || { echo "Error: no version in ${dir}/package.json" >&2; exit 1; }

  {
    echo
    echo "================================================================================"
    printf '%s %s — %s\n' "$pkg" "$version" "${spdx:-see license text below}"
    if [ "$pkg" = "node-forge" ]; then
      echo "Dual-licensed; JetBrains elects BSD-3-Clause."
    fi
    echo "================================================================================"
    echo
    cat "$license_file"
  } >> "$OUTPUT"
done

echo "Wrote ${OUTPUT} for: ${PACKAGES}"
