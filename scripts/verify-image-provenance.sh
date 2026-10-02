#!/usr/bin/env bash
# Verify a locally built provenance image. Does not contact a registry.
#
# Usage: scripts/verify-image-provenance.sh [image]
# Default image is arcade:provenance. The release manifest and SBOM written
# by scripts/provenance-build.sh are read from dist/provenance/.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

image=${1:-arcade:provenance}
manifest=dist/provenance/release-manifest.json
sbom=dist/provenance/sbom.spdx.json

fail() {
  echo "provenance verification failed: $*" >&2
  exit 1
}

[[ -f "$manifest" ]] || fail "release manifest $manifest is missing"
[[ -f "$sbom" ]] || fail "SBOM $sbom is missing"
grep -q '"spdxVersion"' "$sbom" || fail "SBOM is not SPDX JSON"

eval "$(python3 - "$manifest" <<'PY'
import json, shlex, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
fields = {
    "MANIFEST_REVISION": doc.get("revision", ""),
    "MANIFEST_SOURCE": doc.get("source", ""),
    "MANIFEST_DIGEST": doc.get("digest", ""),
    "MANIFEST_SBOM": doc.get("sbom", ""),
    "MANIFEST_MODIFIED": "true" if doc.get("vcsModified") else "false",
}
for key, value in fields.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
)"

digest=$(docker image inspect --format '{{.Id}}' "$image")
oci_source=$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.source"}}' "$image")
oci_revision=$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$image")

[[ "$digest" == "$MANIFEST_DIGEST" ]] || fail "image digest $digest does not match manifest $MANIFEST_DIGEST"
[[ "$oci_source" == "$MANIFEST_SOURCE" && -n "$oci_source" ]] || fail "OCI source label is $oci_source"
[[ "$oci_revision" == "$MANIFEST_REVISION" ]] || fail "OCI revision $oci_revision does not match manifest $MANIFEST_REVISION"
[[ "$oci_revision" =~ ^[0-9a-f]{40}$ ]] || fail "OCI revision is not a full commit SHA"
[[ "$MANIFEST_MODIFIED" == "false" ]] || fail "manifest records a dirty tree"
[[ "$MANIFEST_SBOM" == "$sbom" ]] || fail "manifest SBOM path is $MANIFEST_SBOM"

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
cid=$(docker create "$image")
docker cp "$cid:/usr/local/bin/arcade" "$workdir/arcade"
docker rm "$cid" >/dev/null
info=$(go version -m "$workdir/arcade")
go_rev=$(printf '%s\n' "$info" | awk -F= '/[[:space:]]vcs\.revision=/{print $2; exit}')
go_mod=$(printf '%s\n' "$info" | awk -F= '/[[:space:]]vcs\.modified=/{print $2; exit}')

[[ "$go_rev" == "$oci_revision" ]] || fail "Go vcs.revision $go_rev does not match OCI revision $oci_revision"
[[ "$go_mod" == "false" ]] || fail "Go vcs.modified is ${go_mod:-<missing>}"

printf 'SOURCE_REVISION=%s\n' "$oci_revision"
printf 'SOURCE_CLEAN_STATE=clean\n'
printf 'OCI_SOURCE=%s\n' "$oci_source"
printf 'OCI_REVISION=%s\n' "$oci_revision"
printf 'GO_VCS_REVISION=%s\n' "$go_rev"
printf 'GO_VCS_MODIFIED=%s\n' "$go_mod"
printf 'IMAGE_DIGEST=%s\n' "$digest"
printf 'SBOM_PRESENT=true\n'
