#!/usr/bin/env bash
# Lints the embedded guide text (rust/src/*/guides/*.md) with Vale.
#
# Uses a pinned Vale release. If that exact version is already on PATH it is
# used (local runs); otherwise the Linux x86_64 release is downloaded and
# checked against the SHA-256 below. Config lives in .vale.ini at the repo root.
#
# Exit codes:
#   0  no findings, or findings while VALE_STRICT is unset (non-blocking mode)
#   1  findings while VALE_STRICT=true
#   2  the lint could not run: install or checksum failure, no guide files
#      matched, or Vale reported a configuration or runtime error
#
# To bump Vale: change VALE_VERSION and VALE_SHA256 together, using the hash from
# the release's published checksums file for vale_<version>_Linux_64-bit.tar.gz.
set -euo pipefail

VALE_VERSION="3.24.0"
VALE_SHA256="867534ddb678abca7f214bc4706ead0922bd5252ffe8035fc227013f66c8b214"
VALE_URL="https://github.com/errata-ai/vale/releases/download/v${VALE_VERSION}/vale_${VALE_VERSION}_Linux_64-bit.tar.gz"
GUIDE_GLOB='rust/src/*/guides/*.md'

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

tmp_dir=""
cleanup() { [ -z "$tmp_dir" ] || rm -rf "$tmp_dir"; }
trap cleanup EXIT

vale_bin=""
if command -v vale >/dev/null 2>&1 \
  && [ "$(vale --version 2>/dev/null | awk '{print $NF}')" = "$VALE_VERSION" ]; then
  vale_bin="$(command -v vale)"
else
  if [ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]; then
    echo "ERROR: Vale ${VALE_VERSION} not found on PATH, and the automatic download supports Linux x86_64 only." >&2
    echo "Install Vale ${VALE_VERSION} from https://github.com/errata-ai/vale/releases and re-run." >&2
    exit 2
  fi
  tmp_dir="$(mktemp -d)"
  archive="$tmp_dir/vale.tar.gz"
  echo "==> Downloading Vale ${VALE_VERSION}"
  curl --fail --silent --show-error --location --retry 3 --max-time 120 \
    --output "$archive" "$VALE_URL" || { echo "ERROR: Vale download failed." >&2; exit 2; }
  echo "${VALE_SHA256}  ${archive}" | sha256sum --check --status \
    || { echo "ERROR: Vale archive checksum mismatch." >&2; exit 2; }
  tar -xzf "$archive" -C "$tmp_dir" vale
  vale_bin="$tmp_dir/vale"
fi
echo "==> Using $("$vale_bin" --version) at ${vale_bin}"

# Vale exits 0 when a glob matches nothing, so count the files first.
shopt -s nullglob
files=($GUIDE_GLOB)
shopt -u nullglob
if [ "${#files[@]}" -eq 0 ]; then
  echo "ERROR: no guide files matched ${GUIDE_GLOB}; the lint would check nothing." >&2
  exit 2
fi
echo "==> Linting ${#files[@]} guide file(s)"

status=0
"$vale_bin" --output=line "${files[@]}" || status=$?

case "$status" in
  0)
    echo "==> No findings"
    ;;
  1)
    if [ "${VALE_STRICT:-}" = "true" ]; then
      echo "ERROR: Vale reported findings (shown above)." >&2
      exit 1
    fi
    echo "==> Vale reported findings (shown above). Not blocking: VALE_STRICT is not set."
    ;;
  *)
    echo "ERROR: Vale failed to run (exit ${status})." >&2
    exit 2
    ;;
esac
