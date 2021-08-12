#!/usr/bin/env bash
set -euo pipefail

installdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

ln -s "${installdir}/screenlock-loop.sh" "${HOME}/.local/bin/screenlock-loop"
ln -s "${installdir}/screenlock.service" "${HOME}/.config/systemd/user/screenlock.service"
ln -s "${installdir}/screenlock.timer" "${HOME}/.config/systemd/user/screenlock.timer"

systemctl --user daemon-reload
systemctl --user enable screenlock.service
systemctl --user enable screenlock.timer
systemctl --user start screenlock.timer
