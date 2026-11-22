#!/usr/bin/env bash

data_dir="$HOME/printer_data"
config_dir="$data_dir/config"
checkout="$config_dir/ender3"
default_origin=https://github.com/lazytesting/klipper-chart.git
default_branch=main

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

clone_checkout() {
    local origin=$1 branch=$2
    if [[ ! $origin =~ ^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+\.git$ &&
          ! $origin =~ ^git@github-ender3:[A-Za-z0-9._-]+/[A-Za-z0-9._-]+\.git$ ]]; then
        die 'Use https://github.com/OWNER/REPO.git or git@github-ender3:OWNER/REPO.git.'
    fi
    git check-ref-format --branch "$branch" >/dev/null || die 'Invalid branch.'
    GIT_TERMINAL_PROMPT=0 git clone --branch "$branch" -- "$origin" "$3"
}

check_candidate() {
    local candidate=$1 unresolved status
    [[ -f $candidate/printer.cfg && ! -L $candidate/printer.cfg ]] ||
        die 'The tracked printer.cfg must be a regular file.'
    if unresolved=$(git -C "$candidate" grep -nE 'REPLACE_[A-Z0-9_]+' -- '*.cfg'); then
        printf '%s\n' "$unresolved" >&2
        die 'Commit the confirmed values to GitHub and stage again.'
    else
        [[ $? == 1 ]] || die 'Could not inspect the staged configuration.'
    fi
    status=$(git -C "$candidate" status --porcelain)
    [[ -z $status ]] || die 'The staged checkout has uncommitted changes.'
}

apply_candidate() {
    local candidate unit state backup
    candidate=$(realpath -- "$1")
    [[ $(dirname -- "$candidate") == "$(realpath -- "$data_dir")" &&
        ${candidate##*/} == ender3-stage.* ]] ||
        die 'Expected a staged checkout under ~/printer_data.'
    check_candidate "$candidate"
    for unit in klipper.service moonraker.service; do
        state=$(systemctl show --property=ActiveState --value "$unit") ||
            die "Cannot verify the state of $unit."
        [[ $state == inactive || $state == failed ]] ||
            die "Stop $unit before applying the staged checkout."
    done
    [[ -d $config_dir && ! -L $config_dir ]] || die 'Expected a regular printer_data/config directory.'
    backup=$(mktemp -d "$data_dir/ender3-before.XXXXXXXX")
    tar -czf "$backup/config.tar.gz" -C "$data_dir" config
    if [[ -d $data_dir/systemd ]]; then
        cp -a -- "$data_dir/systemd" "$backup/"
    fi
    printf 'Previous config and available service environment saved at %s\n' "$backup"
    if [[ -e $checkout || -L $checkout ]]; then
        mv -T -- "$checkout" "$backup/previous-checkout"
    fi
    if ! mv -T -- "$candidate" "$checkout"; then
        if [[ -e $backup/previous-checkout || -L $backup/previous-checkout ]]; then
            mv -T -- "$backup/previous-checkout" "$checkout" ||
                die "Restore the previous checkout from $backup."
        fi
        die 'Could not install the staged checkout.'
    fi
    printf 'Installed at %s. Services are still stopped.\n' "$checkout"
}
