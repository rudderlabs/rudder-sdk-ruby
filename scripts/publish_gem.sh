#!/usr/bin/env bash

set -euo pipefail

readonly GEM_NAME='rudder-sdk-ruby'
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly VERIFY_RETRY_COUNT=18
readonly VERIFY_RETRY_DELAY_SECONDS=5

usage() {
  echo "Usage: RELEASE_TAG=v<major>.<minor>.<patch> $0 <validate|verify>" >&2
  exit 1
}

validate_release() {
  if [[ ! "${RELEASE_TAG:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Expected RELEASE_TAG in the form v<major>.<minor>.<patch>, got: ${RELEASE_TAG:-<unset>}" >&2
    exit 1
  fi

  local tag_version="${RELEASE_TAG#v}"
  local source_version
  source_version="$(ruby -Ilib -rrudder/analytics/version -e 'print Rudder::Analytics::VERSION')"

  if [[ "$tag_version" != "$source_version" ]]; then
    echo "Release tag version ($tag_version) does not match gem version ($source_version)." >&2
    exit 1
  fi

  echo "$source_version"
}

verify_published_version() {
  local gem_version="$1"
  local published_version
  published_version="$(
    curl \
      --fail \
      --retry "$VERIFY_RETRY_COUNT" \
      --retry-all-errors \
      --retry-delay "$VERIFY_RETRY_DELAY_SECONDS" \
      --silent \
      --show-error \
      --header 'Cache-Control: no-cache' \
      "https://rubygems.org/api/v2/rubygems/$GEM_NAME/versions/$gem_version.json" \
      | ruby -rjson -e 'print JSON.parse(STDIN.read).fetch("version")'
  )"

  if [[ "$published_version" != "$gem_version" ]]; then
    echo "RubyGems returned version $published_version; expected $gem_version." >&2
    exit 1
  fi
}

main() {
  if [[ $# -ne 1 ]]; then
    usage
  fi

  cd "$REPOSITORY_ROOT"

  case "$1" in
    validate)
      validate_release
      ;;
    verify)
      version="$(validate_release)"
      verify_published_version "$version"
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
