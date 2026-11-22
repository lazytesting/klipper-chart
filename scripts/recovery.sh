#!/usr/bin/env bash
set -euo pipefail
umask 077
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

usage() {
    printf 'Usage: %s backup BACKUP_PARENT | stage SNAPSHOT | apply STAGE_DIR\n' "$0"
    exit 2
}

[[ $# == 2 ]] || usage
case $1 in
    backup)
        parent=$(realpath -- "$2")
        [[ -d $parent && $parent != "$active" && $parent != "$active/"* ]] ||
            die 'Use an existing backup directory outside the active config.'
        repo="$active/$checkout_name"
        check_candidate "$active"
        origin=$(git -C "$repo" config --get remote.origin.url)
        branch=$(git -C "$repo" symbolic-ref --short HEAD)
        check_origin_and_branch "$origin" "$branch"
        commit=$(git -C "$repo" rev-parse HEAD)
        snapshot=$(mktemp -d "$parent/ender3-snapshot.XXXXXXXX")
        trap 'rm -rf -- "$snapshot"' EXIT
        mkdir -- "$snapshot/config"
        tar -C "$active" --exclude="./$checkout_name" -cf - . |
            tar -C "$snapshot/config" -xf -
        printf '%s\n' "$origin" "$branch" "$commit" > "$snapshot/revision"
        trap - EXIT
        printf 'Snapshot ready to copy off the Pi at %s\n' "$snapshot"
        ;;
    stage)
        snapshot=$(realpath -- "$2")
        [[ -f $snapshot/revision && -d $snapshot/config && ! -e $snapshot/config/$checkout_name &&
            ! -L $snapshot/config/$checkout_name ]] || die 'Invalid snapshot layout.'
        mapfile -t revision < "$snapshot/revision"
        [[ ${#revision[@]} == 3 && ${revision[2]} =~ ^[0-9a-f]{40}$ ]] ||
            die 'Invalid snapshot revision.'
        mkdir -p -- "$data_dir"
        stage=$(mktemp -d "$data_dir/ender3-stage.XXXXXXXX")
        trap 'rm -rf -- "$stage"' EXIT
        cp -a -- "$snapshot/config/." "$stage/"
        repo="$stage/$checkout_name"
        clone_checkout "${revision[0]}" "${revision[1]}" "$repo"
        git -C "$repo" merge-base --is-ancestor "${revision[2]}" HEAD ||
            die 'The saved commit is no longer in the configured upstream branch.'
        git -C "$repo" reset --hard "${revision[2]}"
        check_candidate "$stage"
        trap - EXIT
        printf 'Recovery stage ready for review at %s\n' "$stage"
        ;;
    apply)
        apply_candidate "$2"
        ;;
    *) usage ;;
esac
