#!/usr/bin/env bash
set -euo pipefail

make_background() {
    maim --hidecursor | convert - -scale 2.5% -resize 4000% "${screenshot_filename}"
}

lock_screen() {
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

screenshot_filename="/tmp/pomodoro-bkg-$(date +%s).png"
break_minutes=${BREAK_MINUTES:-10}
break_start_time=$(date +%s --date="$(date +'%F %H%M')")
break_end_time_seconds=$((break_start_time + $((60 * break_minutes))))
break_end_time=$(date +%I:%M --date="@${break_end_time_seconds}")

make_background

while [ "$(date +%s)" -lt ${break_end_time_seconds} ]; do
        lock_screen
done

rm "${screenshot_filename}"
