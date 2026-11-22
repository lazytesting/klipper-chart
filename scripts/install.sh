#!/usr/bin/env bash
set -euo pipefail
umask 077
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

usage() {
    printf 'Usage: %s stage /dev/serial/by-id/DEVICE Z_OFFSET [ORIGIN [BRANCH]]\n' "$0"
    printf '       %s apply STAGE_DIR\n' "$0"
    exit 2
}

case ${1:-} in
    stage)
        [[ $# -ge 3 && $# -le 5 ]] || usage
        serial=$2
        z_offset=$3
        origin=${4:-$default_origin}
        branch=${5:-$default_branch}
        [[ $serial =~ ^/dev/(serial/by-(id|path)/[A-Za-z0-9_.:+-]+|tty[A-Za-z0-9]+)$ ]] ||
            die 'Supply a Pi serial device path.'
        [[ -c $serial ]] || die "The serial device is unavailable: $serial."
        [[ $z_offset =~ ^[0-9]+(\.[0-9]+)?$ ]] || die 'Supply a confirmed nonnegative BLTouch Z offset.'
        check_origin_and_branch "$origin" "$branch"
        [[ -f $active/moonraker.conf && ! -L $active/moonraker.conf ]] ||
            die 'Expected a regular moonraker.conf. See the manual steps for a symlink.'
        [[ ! -L $active && ! -e $active/$checkout_name && ! -L $active/$checkout_name ]] ||
            die 'Existing config symlink or ender3 checkout found. See the manual steps.'
        [[ ! -e $active/ender3-update.conf && ! -L $active/ender3-update.conf ]] ||
            die 'An existing updater include needs review.'
        if updater_matches=$(grep -rilE --include='*.conf' \
            '^[[:space:]]*\[(update_manager[[:space:]]+ender3|include[[:space:]]+ender3-update\.conf)\]' "$active"); then
            printf '%s\n' "$updater_matches" >&2
            die 'An existing Ender 3 updater stanza needs review.'
        else
            [[ $? == 1 ]] || die 'Could not inspect existing Moonraker configuration.'
        fi
        stage=$(mktemp -d "$data_dir/ender3-stage.XXXXXXXX")
        trap 'rm -rf -- "$stage"' EXIT
        cp -a -- "$active/." "$stage/"
        clone_checkout "$origin" "$branch" "$stage/$checkout_name"
        # Remove any copied printer.cfg symlink before writing the fresh local entry point.
        rm -f -- "$stage/printer.cfg"
        sed -e "s|@SERIAL@|$serial|g" -e "s|@Z_OFFSET@|$z_offset|g" \
            "$stage/$checkout_name/templates/printer.cfg.in" > "$stage/printer.cfg"
        sed -e "s|@ORIGIN@|$origin|g" -e "s|@BRANCH@|$branch|g" \
            "$stage/$checkout_name/templates/ender3-update.conf.in" > "$stage/ender3-update.conf"
        printf '\n[include ender3-update.conf]\n' >> "$stage/moonraker.conf"
        trap - EXIT
        printf 'Stage ready for review at %s\n' "$stage"
        ;;
    apply)
        [[ $# == 2 ]] || usage
        apply_candidate "$2"
        ;;
    *) usage ;;
esac
