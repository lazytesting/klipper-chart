#!/usr/bin/env bash

data_dir="$HOME/printer_data"
active="$data_dir/config"
checkout_name=ender3
default_origin=git@github-ender3:lazytesting/klipper-chart.git
default_branch=main

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

check_origin_and_branch() {
    [[ $1 =~ ^git@github-ender3:[A-Za-z0-9._-]+/[A-Za-z0-9._-]+\.git$ ]] ||
        die 'Use the deploy-key remote git@github-ender3:OWNER/REPO.git.'
    git check-ref-format --branch "$2" >/dev/null || die 'Invalid branch.'
    [[ $2 =~ ^[A-Za-z0-9._/-]+$ ]] || die 'Unsupported branch name.'
}

clone_checkout() {
    check_origin_and_branch "$1" "$2"
    GIT_TERMINAL_PROMPT=0 git clone --branch "$2" -- "$1" "$3"
}

check_candidate() {
    local config_dir=$1
    local unresolved status
    [[ -f $config_dir/printer.cfg && ! -L $config_dir/printer.cfg ]] ||
        die 'The candidate printer.cfg must be a regular file.'
    if git -C "$config_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        die 'The local config is inside a Git worktree. Move it outside Git before applying.'
    fi
    [[ -f $config_dir/$checkout_name/config/printer-managed.cfg ]] ||
        die 'The managed include is missing.'
    if unresolved=$(git -C "$config_dir/$checkout_name" grep -nE 'REPLACE_[A-Z0-9_]+' -- config); then
        printf '%s\n' "$unresolved" >&2
        die 'Confirm the listed hardware settings on GitHub and stage again.'
    else
        [[ $? == 1 ]] || die 'Could not inspect managed configuration for placeholders.'
    fi
    status=$(git -C "$config_dir/$checkout_name" status --porcelain)
    [[ -z $status ]] ||
        die 'The managed checkout has uncommitted changes.'
}

apply_candidate() {
    local candidate unit state backup=''
    candidate=$(realpath -- "$1")
    [[ $(dirname -- "$candidate") == "$(realpath -- "$data_dir")" && ${candidate##*/} == ender3-stage.* ]] ||
        die 'Provide an installer or recovery stage directory under ~/printer_data.'
    check_candidate "$candidate"
    for unit in klipper.service moonraker.service; do
        state=$(systemctl show --property=ActiveState --value "$unit") ||
            die "Cannot verify the state of $unit."
        [[ $state == inactive || $state == failed ]] ||
            die "Stop $unit before applying the staged configuration."
    done
    [[ ! -L $active ]] || die 'The active config is a symlink. Use the manual steps.'
    if [[ -e $active ]]; then
        backup=$(mktemp -d "$data_dir/ender3-before.XXXXXXXX")
        mv -T -- "$active" "$backup/config"
        printf 'Previous config saved at %s/config\n' "$backup"
    fi
    if ! mv -T -- "$candidate" "$active"; then
        if [[ -n $backup ]]; then
            mv -T -- "$backup/config" "$active" ||
                die "Cannot restore automatically. The previous config is at $backup/config."
        fi
        die 'Could not place the staged config.'
    fi
    printf 'Installed at %s. Services are still stopped.\n' "$active"
}
