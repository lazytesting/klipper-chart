#!/usr/bin/env bash
set -euo pipefail
umask 077
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

usage() {
    printf 'Usage: %s stage [ORIGIN [BRANCH]] | apply STAGE_DIR\n' "$0"
    exit 2
}

case ${1:-} in
    stage)
        [[ $# -le 3 ]] || usage
        mkdir -p -- "$data_dir"
        stage=$(mktemp -d "$data_dir/ender3-stage.XXXXXXXX")
        trap 'rm -rf -- "$stage"' EXIT
        clone_checkout "${2:-$default_origin}" "${3:-$default_branch}" "$stage"
        trap - EXIT
        printf 'Stage ready for review at %s\n' "$stage"
        ;;
    apply)
        [[ $# == 2 ]] || usage
        apply_candidate "$2"
        ;;
    *) usage ;;
esac
