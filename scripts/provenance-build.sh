#!/usr/bin/env bash
# Provenance-qualified Arcade image build.
#
# Fails closed when the source revision is missing or not a full commit, the
# working tree is dirty, ARCADE_EXPECTED_REVISION does not match HEAD, or the
# binary/image metadata cannot be embedded. Ordinary developer builds stay on
# `make build` and `make docker-build`.
#
# Does not push the image anywhere.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

if [[ "$(go env GOOS)" != "linux" ]]; then
  echo "provenance-build requires a Linux host: CGO + gobdk cannot cross-compile a linux binary from $(go env GOOS)." >&2
  exit 1
fi

rev=$(git rev-parse --verify HEAD)
if [[ ! "$rev" =~ ^[0-9a-f]{40}$ ]]; then
  echo "refusing provenance build: revision ${rev} is not a full commit SHA" >&2
  exit 1
fi

dirty=$(git status --porcelain)
if [[ -n "$dirty" ]]; then
  echo "refusing provenance build: working tree is dirty" >&2
  printf '%s\n' "$dirty" >&2
  exit 1
fi

if [[ -n "${ARCADE_EXPECTED_REVISION:-}" && "$ARCADE_EXPECTED_REVISION" != "$rev" ]]; then
  echo "refusing provenance build: HEAD ${rev} does not match ARCADE_EXPECTED_REVISION ${ARCADE_EXPECTED_REVISION}" >&2
  exit 1
fi

source_url=${ARCADE_IMAGE_SOURCE:-}
if [[ -z "$source_url" ]]; then
  remote=$(git remote get-url origin 2>/dev/null || true)
  remote=${remote%.git}
  if [[ "$remote" =~ ^git@([^:]+):(.+)$ ]]; then
    source_url="https://${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  elif [[ "$remote" =~ ^ssh://git@([^/]+)/(.+)$ ]]; then
    source_url="https://${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  elif [[ "$remote" =~ ^https:// ]]; then
    source_url=$remote
  fi
fi
if [[ ! "$source_url" =~ ^https://[^[:space:]]+$ ]]; then
  echo "refusing provenance build: set ARCADE_IMAGE_SOURCE to the https source repository URL" >&2
  exit 1
fi

version=${ARCADE_VERSION:-$(git describe --tags --always)}
if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
  created=$(date -u -d "@${SOURCE_DATE_EPOCH}" +%Y-%m-%dT%H:%M:%SZ)
else
  created=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fi

arch=$(go env GOARCH)
mkdir -p "dist/linux-${arch}" dist/provenance
bin="dist/linux-${arch}/arcade"

CGO_ENABLED=1 GOOS=linux GOARCH="$arch" go build \
  -trimpath \
  -buildvcs=true \
  -ldflags="-s -w -X github.com/bsv-blockchain/arcade/version.Version=${version}" \
  -o "$bin" \
  ./cmd/arcade

info=$(go version -m "$bin")
embedded_rev=$(printf '%s\n' "$info" | awk -F= '/[[:space:]]vcs\.revision=/{print $2; exit}')
embedded_mod=$(printf '%s\n' "$info" | awk -F= '/[[:space:]]vcs\.modified=/{print $2; exit}')
if [[ "$embedded_rev" != "$rev" || "$embedded_mod" != "false" ]]; then
  echo "refusing provenance build: embedded VCS revision=${embedded_rev:-<missing>} modified=${embedded_mod:-<missing>}, want ${rev} modified=false" >&2
  exit 1
fi

docker build \
  --platform="linux/${arch}" \
  --build-arg "ARCADE_IMAGE_SOURCE=${source_url}" \
  --build-arg "ARCADE_REVISION=${rev}" \
  --build-arg "ARCADE_CREATED=${created}" \
  --build-arg "ARCADE_VERSION=${version}" \
  -t arcade:provenance \
  .

digest=$(docker image inspect --format '{{.Id}}' arcade:provenance)
source_label=$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.source"}}' arcade:provenance)
revision_label=$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' arcade:provenance)
created_label=$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.created"}}' arcade:provenance)
version_label=$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' arcade:provenance)
if [[ "$source_label" != "$source_url" || "$revision_label" != "$rev" || "$created_label" != "$created" || -z "$version_label" ]]; then
  echo "refusing provenance build: image labels do not match the source stamp" >&2
  printf 'source=%q revision=%q created=%q version=%q\n' "$source_label" "$revision_label" "$created_label" "$version_label" >&2
  exit 1
fi

syft=$(bash scripts/install-syft.sh)
"$syft" arcade:provenance -o spdx-json=dist/provenance/sbom.spdx.json

python3 - "$rev" "$source_url" "$version" "$created" "$digest" <<'PY'
import json, sys
rev, source, version, created, digest = sys.argv[1:]
doc = {
    "revision": rev,
    "source": source,
    "version": version,
    "created": created,
    "image": "arcade:provenance",
    "digest": digest,
    "sbom": "dist/provenance/sbom.spdx.json",
    "vcsModified": False,
}
with open("dist/provenance/release-manifest.json", "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2)
    fh.write("\n")
PY

echo "provenance image arcade:provenance"
echo "revision ${rev}"
echo "digest ${digest}"
echo "manifest dist/provenance/release-manifest.json"
echo "sbom dist/provenance/sbom.spdx.json"
