#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "pomodoro [-s seconds] [-t time]"
    echo " -t  TASK TIME    length of time before break (in minutes)"
    echo " -b  BREAK TIME   length of break (in minutes)"
}

task_minutes=25
break_minutes=10

while getopts 'hb:t:' flag; do
    case "${flag}" in
         b)
             break_minutes="${OPTARG}"
             ;;
         t)
             task_minutes="${OPTARG}"
             ;;
         h|*)
             usage
             exit
             ;;
    esac
done
shift $((OPTIND-1))

#round to beginning of minute
pomodoro_start_time=$(date +'%F %H%M')
pomodoro_start_time_seconds=$(date +%s --date="${pomodoro_start_time}")
pomodoro_end_time_seconds=$((pomodoro_start_time_seconds + $((task_minutes * 60))))
break_end_time_seconds=$((pomodoro_end_time_seconds + $((60 * break_minutes))))
break_end_time=$(date +%I:%M --date="@${break_end_time_seconds}")
screenshot_filename="/tmp/pomodoro-bkg-$(date +%s).png"

var1=$(cat <<-EOF
export DISPLAY=:0

make_background() {
    maim --hidecursor | convert - -scale 2.5% -resize 4000% "${screenshot_filename}"
}

lock_screen() {
      i3lock -n -i "${screenshot_filename}" --no-verify \
          --insidecolor="373445ff" --ringcolor="ffffffaa" --line-uses-inside \
          --keyhlcolor="d23c3dff" --bshlcolor="d23c3dff" --separatorcolor="00000000" \
          --insidevercolor="aacf4dff" --insidewrongcolor="d23c3dff" \
          --ringvercolor="ffffffaa" --ringwrongcolor="ffffffff" --indpos="w/2:(h/2)+200" \
          --radius=30 --veriftext="" --wrongtext="" --noinputtext="" \
          --greetertext="Time for a ${break_minutes} minute break" --greeter-align=0 --greeterpos="w/2:h/2" \
          --greetercolor="ff0000cc" --greetersize=130 --greeteroutlinecolor="ef0000ff" \
          --datestr="Break ends at ${break_end_time}" --datepos="w/2:(h/2)+100"\
          --datesize=50 --datecolor="ff0000cc" --dateoutlinecolor="ef0000ff" \
          --timestr="%I:%M:%S" --timesize=35 --timepos="w/2:(h/2)+150" \
          --timecolor="aa0000cc" --timeoutlinecolor="ef0000ff" \
          --greeteroutlinewidth=3 --timeoutlinewidth=0 --dateoutlinewidth=0\
          --force-clock --no-modkeytext
}

make_background
lock_screen

while [ $
EOF
    )
var2=$(cat <<-EOF
(date +%s) -lt ${break_end_time_seconds} ]; do
      lock_screen
done
rm ${screenshot_filename}
EOF
    )

cmd="${var1}${var2}"

echo "Locking screen at $(date --date="@${pomodoro_end_time_seconds}")."
echo "$cmd" | nohup at "$(date +'%H:%M' --date="@${pomodoro_end_time_seconds}")" >/dev/null 2>&1
