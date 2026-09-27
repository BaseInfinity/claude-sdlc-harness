#!/bin/bash
set -euo pipefail

VERSION="${1:-}"

if [ -z "$VERSION" ]; then
  echo "Usage: derive-dist-tag.sh <version>" >&2
  exit 1
fi

if [[ "$VERSION" != *-* ]]; then
  echo "latest"
  exit 0
fi

PRERELEASE="${VERSION#*-}"
TAG="${PRERELEASE%%.*}"

if [[ ! "$TAG" =~ ^[a-zA-Z] ]]; then
  echo "::error::Cannot derive npm dist-tag from version '$VERSION': prerelease identifier '$TAG' does not start with a letter" >&2
  exit 1
fi

echo "$TAG"
