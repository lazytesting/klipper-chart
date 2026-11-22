#!/usr/bin/env bash
set -euo pipefail
umask 077
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

if [[ $# -lt 1 || $# -gt 3 || ! $1 =~ ^[0-9a-f]{40}$ ]]; then
    printf 'Usage: %s COMMIT_SHA [ORIGIN [BRANCH]]\n' "$0" >&2
    exit 2
fi

mkdir -p -- "$data_dir"
stage=$(mktemp -d "$data_dir/ender3-stage.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
clone_checkout "${2:-$default_origin}" "${3:-$default_branch}" "$stage"
git -C "$stage" merge-base --is-ancestor "$1" HEAD ||
    die 'The requested commit must exist in the configured branch history.'
git -C "$stage" reset --hard "$1"
check_candidate "$stage"
trap - EXIT
printf 'Recovery checkout ready for review at %s\n' "$stage"
