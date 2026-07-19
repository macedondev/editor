#!/usr/bin/env bash

set -euo pipefail

check_release_tag() {
  local tag="$1"
  local expected_revision="$2"
  local output_file="$3"
  local tag_ref="refs/tags/$tag"

  if ! git check-ref-format "$tag_ref" >/dev/null; then
    echo "Invalid release tag: $tag" >&2
    return 1
  fi

  local expected_sha
  expected_sha=$(git rev-parse --verify "${expected_revision}^{commit}")

  if git show-ref --verify --quiet "$tag_ref"; then
    local existing_sha
    if ! existing_sha=$(git rev-parse --verify "${tag_ref}^{commit}"); then
      echo "Release tag $tag does not point to a commit." >&2
      return 1
    fi
    if [[ "$existing_sha" != "$expected_sha" ]]; then
      echo "Release tag $tag points to $existing_sha, not $expected_sha." >&2
      return 1
    fi
    echo "Release tag $tag already points to $expected_sha; reusing it."
    printf 'exists=true\n' >> "$output_file"
    return
  fi

  echo "Release tag $tag does not exist; it will be created."
  printf 'exists=false\n' >> "$output_file"
}

self_test() {
  local test_root
  test_root=$(mktemp -d)
  trap 'if [[ -n ${test_root:-} && -d $test_root ]]; then rm -rf -- "$test_root"; fi' EXIT

  (
    cd "$test_root"
    git init --quiet
    git config user.name release-test
    git config user.email release-test@example.invalid
    printf 'first\n' > package.txt
    git add package.txt
    git commit --quiet -m first

    local first_sha
    first_sha=$(git rev-parse HEAD)
    local output_file="$test_root/output"

    check_release_tag flutter_monaco-v1.2.3 "$first_sha" "$output_file"
    grep -qx 'exists=false' "$output_file"

    git tag flutter_monaco-v1.2.3
    : > "$output_file"
    check_release_tag flutter_monaco-v1.2.3 "$first_sha" "$output_file"
    grep -qx 'exists=true' "$output_file"

    printf 'second\n' >> package.txt
    git add package.txt
    git commit --quiet -m second
    local second_sha
    second_sha=$(git rev-parse HEAD)
    : > "$output_file"
    if check_release_tag flutter_monaco-v1.2.3 "$second_sha" "$output_file"; then
      echo 'A conflicting release tag was accepted.' >&2
      return 1
    fi
    [[ ! -s "$output_file" ]]
  )

  echo 'Release tag checker self-test passed.'
}

if [[ "${1:-}" == '--self-test' ]]; then
  self_test
elif [[ "$#" == 3 ]]; then
  check_release_tag "$1" "$2" "$3"
else
  echo "Usage: $0 <tag> <expected-revision> <github-output-file>" >&2
  echo "       $0 --self-test" >&2
  exit 64
fi
