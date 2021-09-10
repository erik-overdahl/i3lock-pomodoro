#!/usr/bin/env bash
set -euo pipefail

progPath="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/$(basename "$0")"

usage() {
    printf "pomodoro [OPTIONS] <COMMAND>\n
Schedule the screen to lock for B minutes in T minutes from now\n
COMMANDS
  start    stop    status    install\n
OPTIONS
  -t|--time  MINUTES   minutes before break (default 35)
  -b|--break MINUTES   length of break (default 10)
  -r|--repeat          repeat the timer
  -n|--notify MINUTES  notify MINUTES before screen locks
  -h|--help            show this help\n"
}

containsElement () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

_create_links() {
    local installDir
    installDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    ln -sf "${installDir}/pomodoro.sh" "${HOME}/.local/bin/pomodoro"
    if [ "$1" == "1" ]; then
        ln -sf "${installDir}/screenlock.service" "${HOME}/.config/systemd/user/screenlock.service"
        systemctl --user daemon-reload
        systemctl --user enable screenlock.service
    fi
}

_install() {
    if _create_links "$1"; then
        printf "Install successful\n"
        usage
        exit
    else
        printf "Install failed!\n"
        exit 1
    fi
}

_version_gt() {
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

_check_i3_deps() {
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
}

_check_wayland_deps() {
    dependencies=( "swaylock" "grim" "convert" )

    for dep in "${dependencies[@]}"; do
        if [ ! "$(command -v "${dep}")" ]; then
            printf "Could not find dependency '%s'\n" "${dep}" >&2
            exit 1
        fi
    done

    if ! grep -q 'swaylock-effects' "$(man -w swaylock)"; then
        printf "'swaylock' must be fork 'swaylock-effects'"
        exit 1
    fi
}

_make_background() {
    if [[ "$XDG_SESSION_TYPE" == "wayland" ]]; then
        grim -t png -
    else main --hidecursor
    fi | convert - -scale 2.5% -resize 4000% "${screenshot_filename}"
}

_x_lock_screen() {
    i3lock \
        -n \
        -i "${screenshot_filename}" \
        --no-verify \
        --inside-color="373445ff" \
        --ring-color="ffffffaa" \
        --line-uses-inside \
        --keyhl-color="d23c3dff"  \
        --bshl-color="d23c3dff"  \
        --separator-color="00000000" \
        --insidever-color="aacf4dff"  \
        --insidewrong-color="d23c3dff" \
        --ringver-color="ffffffaa"  \
        --ringwrong-color="ffffffff"  \
        --ind-pos="w/2:(h/2)+200" \
        --radius=30  \
        --verif-text=""  \
        --wrong-text=""  \
        --noinput-text="" \
        --greeter-text="Time for a ${break_minutes} minute break"  \
        --greeter-align=0  \
        --greeter-pos="w/2:h/2" \
        --greeter-color="ff0000cc"  \
        --greeter-size=130  \
        --greeteroutline-color="ef0000ff" \
        --date-str="Break ends at ${break_end_time}"  \
        --date-pos="w/2:(h/2)+100"\
        --date-size=50  \
        --date-color="ff0000cc"  \
        --dateoutline-color="ef0000ff" \
        --time-str="%I:%M:%S"  \
        --time-size=35  \
        --time-pos="w/2:(h/2)+150" \
        --time-color="aa0000cc"  \
        --timeoutline-color="ef0000ff" \
        --greeteroutline-width=3  \
        --timeoutline-width=0  \
        --dateoutline-width=0 \
        --force-clock \
        --no-modkey-text
}

_wayland_lock_screen() {
    swaylock \
        -i "${screenshot_filename}" \
        --indicator \
        --indicator-radius 300 \
        --clock \
        --text-color ff0000ff \
        --timestr "%T  --  ${break_end_time}" \
        --datestr "Time for a ${break_minutes} minute break" \
        --ring-color ffffff00 \
        --inside-color ffffff00 \
        --line-color ffffff00 \
        --grace 360000 \
        --grace-no-mouse \
        --grace-no-touch
}

_lock() {
    screenshot_filename="/tmp/pomodoro-bkg-$(date +%s).png"
    lock_screen=_x_lock_screen
    if [[ "$XDG_SESSION_TYPE" == "wayland" ]]; then
        _check_wayland_deps
        lock_screen=_wayland_lock_screen
    else
        _check_i3_deps
    fi
    _make_background
    "$lock_screen"
    while [ "$(date +%s)" -lt "${break_end_time_seconds}" ]; do
        "$lock_screen"
    done

    if [ -z "${screenshot_filename}" ]; then
        rm "${screenshot_filename}"
    fi

    if [ -n "${repeat}" ]; then
        "$progPath" start -r -t "$task_minutes" -b "$break_minutes" || \
            notify-send -u critical -a "Screenlock" "Pomodoro repeat failed!"
    fi
}

_notify() {
    notify-send -t 5000 "Screenlock in $1 minutes"
}

_status() {
    systemctl --user --no-pager -o json list-timers |
        jq '.[]
            | if .next then . else empty end
            | select(.unit|test("screenlock-[0-9]+.timer"))
            | (.next |= ((. / 1000000) - now | strftime("%H:%M:%S")))
            | .next'
}

run_after_time() {
    local args=( "$@" )
    local minutes="${args[0]}"
    local unitName="${args[1]}"
    local command="${args[2]}"
    systemd-run -q \
        --user \
        --timer-property=AccuracySec=1us \
        --on-active="$minutes"min \
        --unit="$unitName" \
        "$command" "${args[@]:3}"
}

notify() {
    local timeBefore
    timeBefore="$1"
    run_after_time "$((task_minutes - timeBefore))" \
        "screenlock-$(date +%s)-notify-${timeBefore}-min.timer" \
        "$progPath" _notify "$timeBefore"
}

start() {
    if _status | grep -q '.'; then
        printf "There is already a timer running, with %s minutes remaining\n" "$(_status)"
        exit 1
    else
        run_after_time "${task_minutes}" "screenlock-$(date +%s).timer" \
            "$progPath" _lock "$repeat" -t "$task_minutes" -b "$break_minutes"
        for time in "${notifyBefore[@]}"; do
            if [ "$time" -lt "$task_minutes" ]; then
                notify "$time" || printf "unable to start notification timer!"
            fi
        done
    fi
    status
}

stop() {
    if _status | grep -q '.'; then
        systemctl --user stop screenlock-*.timer &> /dev/null
        # systemctl --user stop screenlock-notify-* &> /dev/null
        printf "Stopped timer\n"
    else
        printf "No timer running.\n"
    fi
}

status() {
    local timeRemaining
    timeRemaining="$(_status)"
    if [ -z "$timeRemaining" ]; then
        printf "There is no timer running.\n"
    else
        printf "There is a timer with %s remaining\n" "$timeRemaining"
    fi
}

task_minutes=35
break_minutes=10
break_minutes=10
notifyBefore=()
repeat=
cmd=

while [[ $# -gt 0 ]]; do
    case "$1" in
         start|stop|status|install|_notify|_lock )
             cmd="$1"
             ;;
         -b|--break )
             shift
             break_minutes="$1"
             ;;
         -n|--notify )
             shift
             notifyBefore+=( "$1" )
             ;;
         -t|--time )
             shift
             task_minutes="$1"
             ;;
         -r|--repeat )
             repeat="-r"
             ;;
         -h|--help )
             usage
             exit
             ;;
    esac
    shift
done


break_start_time=$(date +%s --date="$(date +'%F %H%M')")
break_end_time_seconds=$((break_start_time + $((60 * break_minutes))))
break_end_time=$(date +%I:%M --date="@${break_end_time_seconds}")

if [ -n "$cmd" ]; then
    case "$cmd" in
         install )
             withBoot=0
             if [[ "$#" == "1" ]]; then
                 if [[ "$1" == "--with-boot" ]]; then
                     withBoot=1
                 fi
             fi
             _install "$withBoot"
             ;;
         _notify )
             if [[ "$#" == "1" ]]; then
                 _notify "$1"
             else
                 printf "'pomodoro _notify' requires an integer argument.\n"
                 exit 1
             fi
             ;;
         *)
             "$cmd"
    esac
else
    printf "No command specified.\n"
    usage
    exit 1
fi
