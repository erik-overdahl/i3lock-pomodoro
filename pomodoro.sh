#!/usr/bin/env bash
set -euo pipefail

progPath="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/$(basename "$0")"
deps=( "convert" )
configDir="${XDG_CONFIG_HOME:-${HOME}/.config}/pomodoro"

usage() {
    printf "pomodoro [OPTIONS] <COMMAND>\n
Schedule the screen to lock for B minutes in T minutes from now\n
COMMANDS
  start    halt    check    install\n
OPTIONS
  -t|--time  MINUTES   minutes before break (default 35)
  -b|--break MINUTES   length of break (default 10)
  -R|--no-repeat       do not repeat the timer
  -n|--notify MINUTES  notify MINUTES before screen locks
  -h|--help            show this help\n"
}

_create_links() {
    local installDir
    installDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    ln -sf "${installDir}/pomodoro.sh" "${HOME}/.local/bin/pomodoro"
    mkdir -p "${configDir}"
    ln -sf "${installDir}/messages.txt" "${configDir}/messages.txt"
    completionDir="${XDG_DATA_HOME:-${HOME}/.local/share}/bash-completion"
    mkdir -p "${completionDir}"
    cp -f "${installDir}/pomodoro-completion.bash" "${completionDir}/pomodoro-completion"
    source "${completionDir}/pomodoro-completion"
    if [ "$1" == "1" ]; then
        # systemd user files don't always seem to work, or work the same across systems
        # this is my best effort
        printf "Installing with boot...\n"
        cp -f "${installDir}/screenlock.service" "${HOME}/.config/systemd/user/screenlock.service"
        systemctl --user daemon-reload
        systemctl --user enable screenlock.service
    fi
}

_install() {
    if _create_links "$1"; then
        printf "Install successful\n\n"
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
    dependencies=("${deps[@]}" "i3lock" "maim" )

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
    elif _version_gt "${i3lockMinVersion}" "${i3lockInstalledVersion}"; then
        printf "Minimum i3lock version not installed: requires %s, found %s\n" "${i3lockMinVersion}" "${i3lockInstalledVersion}" >&2
        exit 1
    fi
}

_check_wayland_deps() {
    dependencies=("${deps[@]}" "swaylock" "grim" )

    for dep in "${dependencies[@]}"; do
        if [ ! "$(command -v "${dep}")" ]; then
            printf "Could not find dependency '%s'\n" "${dep}" >&2
            exit 1
        fi
    done

    if ! grep -q 'swaylock-effects' "$(man -w swaylock)"; then
        printf "'swaylock' must be fork 'swaylock-effects'\n"
        exit 1
    fi
}

_make_background() {
    if [[ "$XDG_SESSION_TYPE" == "wayland" ]]; then
        grim -t png -
    else maim --hidecursor
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
        --greeter-text="${break_minutes} minute break; time to ${break_message}"  \
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
        --datestr "${break_minutes} minute break; time to ${break_message}" \
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
    break_message="$(choose_break_message)"
    "$lock_screen"
    while [ "$(date +%s)" -lt "${break_end_time_seconds}" ]; do
        "$lock_screen"
    done

    if [ -z "${screenshot_filename}" ]; then
        rm "${screenshot_filename}"
    fi

    if [ "${noRepeat}" != 1 ]; then
        unitCmd=( "$progPath" "start" "-t" "$task_minutes" "-b" "$break_minutes" )
        for time in "${notifyBefore[@]}"; do
            unitCmd=( "${unitCmd[@]}" "-n" "$time" )
        done
        "${unitCmd[@]}" || \
            (notify-send -u critical -a "Screenlock" "Pomodoro repeat failed!" \
            && printf "Pomodoro repeat failed!")
    fi
}

_time_remaining() {
    gdbus call --session \
        --dest org.freedesktop.systemd1 \
        --object-path /org/freedesktop/systemd1 \
        --method org.freedesktop.systemd1.Manager.ListUnits |
        sed -e 's#),#),\n#g' -e 's#[()'\'']##g' |
        awk '
            BEGIN {
                FS=", ";
            }
            /screenlock-[0-9]+.timer/ {
                getTime="gdbus call --session --dest org.freedesktop.systemd1 --object-path " $7 " --method org.freedesktop.DBus.Properties.Get org.freedesktop.systemd1.Timer TimersCalendar";
                if ((getTime | getline timeRes) > 0) {
                    gsub(/[(<>)\[\]]/, "", timeRes);
                    time = split(timeRes,array,",");
                    cmd = "date +'\''%s'\'' -d " array[2];
                    if ((cmd | getline res) > 0) {
                        diff = res - systime();
                        _hours = int(diff / 3600);
                        hours = _hours > 0 ? _hours " hours " : "";
                        _minutes = int((diff % 3600) / 60);
                        minutes = _minutes > 0 ? _minutes " minutes" : "";
                        _seconds = int((diff % 60));
                        _and = ((_minutes + _hours) > 0 && _seconds > 0) ? " and " : "";
                        seconds = _seconds > 0 ? _seconds " seconds" : "";
                        print hours minutes _and seconds;
                    } else {
                        print "Date conversion failed";
                        close(cmd);
                        exit 1;
                    }
                    close(cmd);
                } else {
                    close(getTime);
                    exit 0;
                }
            }'
}

_print_notify() {
    printf "%s\n" "${1}"
    if [ "$#" -gt 1 ]; then
        notify-send -t 5000 -u critical "${1}"
    else
        notify-send -t 5000 "${1}"
    fi
}

run_after_time() {
    local args=( "$@" )
    local minutes="${args[0]}"
    local unitName="${args[1]}"
    local command="${args[2]}"
    systemd-run -q \
        --user \
        --timer-property=AccuracySec=1us \
        --on-calendar="$(date --utc +'%Y-%m-%d %T UTC' -d "+${minutes}min")" \
        --unit="$unitName" \
        "$command" "${args[@]:3}"
}

choose_break_message() {
    sort -R "${configDir}/messages.txt" | head -n 1
}

schedule_notify() {
    local timeBefore
    timeBefore="$1"
    run_after_time "$((task_minutes - timeBefore))" \
        "screenlock-$(date +%s)-notify-${timeBefore}-min.timer" \
        notify-send -t 5000 "Screenlock in ${timeBefore} minutes"
}

start() {
    if _time_remaining | grep -q '.'; then
        printf "There is already a timer running, with %s minutes remaining\n" "$(_time_remaining)"
        exit 1
    fi
    if [ "${#notifyBefore[@]}" == 0 ]; then
        notifyBefore=( "${defaultNotify[@]}" )
    fi
    unitCmd=( "$progPath" "_lock" "-t" "$task_minutes" "-b" "$break_minutes" )
    for time in "${notifyBefore[@]}"; do
        if [ "$time" -lt "$task_minutes" ]; then
            schedule_notify "$time" || printf "unable to start notification timer!"
            unitCmd=( "${unitCmd[@]}" "-n" "$time" )
        fi
    done
    if run_after_time "${task_minutes}" "screenlock-$(date +%s).timer" "${unitCmd[@]}"; then
        _print_notify "Started pomodoro timer; screen locks in $(_time_remaining)."
    else
        _print_notify "Failed to start pomodoro timer!" "critical"
        exit 1
    fi
}

halt() {
    local remaining
    remaining="$(_time_remaining)"
    if [ -n "$remaining" ]; then
        gdbus call --session \
            --dest org.freedesktop.systemd1 \
            --object-path /org/freedesktop/systemd1 \
            --method org.freedesktop.systemd1.Manager.ListUnits |
            sed -e 's#),#),\n#g' -e 's#[()'\'']##g' |
            awk 'BEGIN {FS=", "}
                /screenlock-/ {
                    if ($4 == "active") {
                        sub(/^ /,"")
                        print $7
                    }
                }' |
            xargs -n 1 -I '{}' \
                gdbus call --session \
                --dest org.freedesktop.systemd1 \
                --object-path '{}' \
                --method org.freedesktop.systemd1.Unit.Stop 'replace' \
                &> /dev/null

        _print_notify "Stopped timer with ${remaining} remaining."
    else
        printf "No timer running.\n"
    fi
}

check() {
    local nextLock
    local msg
    nextLock=$(_time_remaining)
    if [ -z "$nextLock" ]; then
        msg="There is no timer running."
    else
        msg="${nextLock} to next break"
    fi
    _print_notify "${msg}"
}

task_minutes=35
break_minutes=10
notifyBefore=()
noRepeat=0
cmd=
installWithBoot=0

while [[ $# -gt 0 ]]; do
    case "$1" in
         start|halt|check|install|_lock )
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
         -R|--no-repeat )
             noRepeat=1
             ;;
         --with-boot )
             installWithBoot=1
             ;;
         -h|--help )
             usage
             exit
             ;;
    esac
    shift
done

break_start_time="$(date +%s --date="$(date +'%F %H%M')")"
break_end_time_seconds="$((break_start_time + $((60 * break_minutes))))"
break_end_time="$(date +%I:%M --date="@${break_end_time_seconds}")"
defaultNotify=( 1 5 )

if [ -n "$cmd" ]; then
    case "$cmd" in
         install )
             _install "$installWithBoot"
             ;;
         *)
             "$cmd"
    esac
else
    printf "No command specified.\n"
    usage
    exit 1
fi
