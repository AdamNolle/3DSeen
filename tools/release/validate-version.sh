#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
DEFAULT_VERSION=$(awk '/MARKETING_VERSION:/ { print $2; exit }' "$ROOT/project.yml")
DEFAULT_BUILD=$(awk '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "$ROOT/project.yml")
VERSION=${RELEASE_VERSION:-$DEFAULT_VERSION}
BUILD=${BUILD_NUMBER:-$DEFAULT_BUILD}
TAG=${RELEASE_TAG:-}
if [[ -z "$TAG" && "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  TAG=${GITHUB_REF_NAME:-}
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid marketing version '$VERSION'; expected MAJOR.MINOR.PATCH." >&2
  exit 1
fi
if [[ ! "$BUILD" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid build number '$BUILD'; expected a positive integer." >&2
  exit 1
fi
if [[ -n "$TAG" && "$TAG" != "v$VERSION" ]]; then
  echo "Release tag '$TAG' does not match marketing version 'v$VERSION'." >&2
  exit 1
fi

printf 'MARKETING_VERSION=%s\nCURRENT_PROJECT_VERSION=%s\n' "$VERSION" "$BUILD"
if [[ "${1:-}" == "--github-env" ]]; then
  : "${GITHUB_ENV:?GITHUB_ENV is required with --github-env}"
  printf 'MARKETING_VERSION=%s\nCURRENT_PROJECT_VERSION=%s\n' "$VERSION" "$BUILD" >> "$GITHUB_ENV"
fi
