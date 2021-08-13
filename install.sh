#!/usr/bin/env bash
set -euo pipefail

function version_gt() { test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"; }

installDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
dependencies=( "i3lock" "convert" "maim" )

for dep in "${dependencies[@]}"; do
    if [ ! "$(command -v "${dep}")" ]; then
        printf "Could not find dependency '%s'\n" "${dep}" >&2
        exit 1
    fi
done

i3lockMinVersion="2.13.c.3"
i3lockInstalledVersion="$(i3lock --version 2>&1 | awk '{print $3}')"

if ! grep -q 'i3lock-color' "$(man -w i3lock)"; then
    printf "'i3lock' must be version 'i3lock-color'\n" >&2
    exit 1
elif version_gt "${i3lockMinVersion}" "${i3lockInstalledVersion}"; then
    printf "Minimum i3lock version not installed: requires %s, found %s\n" "${i3lockMinVersion}" "${i3lockInstalledVersion}" >&2
    exit 1
fi

ln -sf "${installDir}/screenlock-loop.sh" "${HOME}/.local/bin/screenlock-loop"
ln -sf "${installDir}/screenlock.service" "${HOME}/.config/systemd/user/screenlock.service"
ln -sf "${installDir}/screenlock.timer" "${HOME}/.config/systemd/user/screenlock.timer"

systemctl --user daemon-reload
systemctl --user enable screenlock.service
systemctl --user enable screenlock.timer
systemctl --user start screenlock.timer

printf "Install completed\nRun 'systemctl --user start screenlock.timer' to start the timer\n"
