#!/bin/bash
# The aim of this tool is to move a window to either the left or right monitor.
# we assume there are two monitors, and they are side by side.

# It is a workaround, since Marco (the window manager of MATE Desktop) cannot
# properly do this. Even though there's a function for this, it is very broken.

# For some reason, this tool has a bug. It makes the non-maximized vertical
# size of the window equal to the vertical size of the previous monitor it was
# displayed on.

# You can use this tool by executing it with a key combination you set in your
# window manager. First make sure this program is in $PATH. Then you need to
# set up the key combo. For MATE Desktop, open mateconf-editor and navigate to
# apps/marco/keybinding_commands and type in the name of the executable in one
# of the items. Then, under apps/marco/global_keybindings/run_command_n, set
# the keyboard combination. That's it! A similar procedure works for GNOME 2
# with its metacity window manager, and there are very likely ways to do this
# with any other desktop software.

# Now you can also break down very wide monitors into smaller ones. Define your
# preferred width to break down to (that is the minimum width a sub-monitor
# will have) and set the maximum width after which breaking down monitors
# should occur, using the $preferred_width and $max_width variables
# respectively.

# log="/tmp/dbglog" # dbg
# echo "-----------" >> "$log" # dbg

preferred_width=800
max_width=1500

# If your theme uses borders, set the border thickness here. This is important
# so that windows line up properly.
#
# Idea: maybe there's a way to find out about this programmatically.

border=1

# Now we're using cache for the expensive xrandr readout, so it should only
# happen once in a while. Set the cache timeout here, in seconds.

cache_timeout=4
cache="$HOME/.movewindow_cache"

declare -i delta
cache_modtime=$(stat -c %Y "$cache")
now=$(date +%s)
delta="$now - $cache_modtime"
if [ "$delta" -ge "$cache_timeout" ]; then
    # echo "generating and tee" >> "$log"
    monitor_info=$( \
        xrandr -q \
        | awk '/ connected [0-9]+x[0-9]+\+[0-9]+\+[0-9]+/{print $3}' \
        | tee "$cache" \
        )
else
    # echo "restoring" >> "$log"
    monitor_info=$(cat "$cache")
    touch "$cache" # if you're using this program, it probably means
    # that you aren't messing around with monitor connections or settings,
    # so let's re-validate the cache.
    fi

wmctrl -r :ACTIVE: -b remove,maximized_horz
wmctrl -r :ACTIVE: -b remove,maximized_vert

# get the center of the window.
eval $(xdotool getactivewindow getwindowgeometry --shell)
# the above outputs something like:
# WINDOW=70385876
# X=593
# Y=190
# WIDTH=722
# HEIGHT=422
# SCREEN=0
#
# do note, SCREEN has nothing to do with the monitor the window is being
# displayed on.

declare -i window_left # left border
window_left="$X"
declare -i window_right
window_right="$window_left + $WIDTH" # right border
let "horiz_center=($window_left+$window_right)/2" # integer division

# figure out which desktop the window falls on. we only need to use the widths
# and horizontal offsets.
declare -a ranges
declare -i monitor_num
monitor_num=0

declare -i vertical_offset
declare -i width
declare -i horiz_offset
declare -i left
declare -i right
declare -i range_left
declare -i range_right
declare -i parts
declare -i part
declare -i start_
declare -i end
declare -i i
# ranges is an array which contains entries of the form x1,x2;y where x1 is
# the starting pixel column on the screen and x2 is the final pixel column and
# y is the offset from top of desktop (i.e. starting pixel row). This is output
# for every monitor.
ranges=$(echo "$monitor_info" | while read info; do
    # the output is: widthxheight+horizontal_offset+vertical_offset
    vertical_offset=${info/*+/}
    width=${info/x*/}
    offsets=${info#*+}
    horiz_offset=${offsets/+*/}
    left="$horiz_offset"
    right="$left + $width"
    echo "$left,$right;$vertical_offset"
    done | while read range_and_offset; do
        range=${range_and_offset/;*/}
        range_left=${range/,*/}
        range_right=${range/*,/}
        offset=${range_and_offset/*;/}
        width="$range_right-$range_left"

        # echo width is "$width" >> "$log" # dbg
        if [ "$width" -le "$max_width" ]; then
            # echo skipping "$range_and_offset" >> "$log" # dbg
            echo "$range_and_offset"
            continue
            fi
        # echo not skipping "$range_and_offset" >> "$log" # dbg

        parts="$width/$preferred_width" # $parts contains the amount of
        # sub-monitors that will be created.
        part="$width/$parts" # $part contains the number of pixel columns
        # which will form one sub-monitor. Note one pixel might be missing.

        for ((i=1; i<=$parts; i++)); do
            start_="$range_left+($i-1)*$part"
            if (($i == $parts)); then
                # the last submonitor might have one pixel column missing
                # because we are dividing in the integers, so let's account for
                # the division remainder here.
                end="$range_right"
            else
                end="$range_left+$i*$part"
                fi
            echo "$start_,$end;$offset"
            done
        done)

# echo ${ranges[@]} >> "$log" # dbg
ranges_extended=$(
    for r in ${ranges[@]}; do echo "$r"; done
    for r in ${ranges[@]}; do echo "$r"; break; done
    )

# search through the sub-displays to find the one we're on currently.
for range_and_offset in ${ranges[@]}; do
    range=${range_and_offset/;*/}
    # echo $range >> "$log" # dbg
    range_left=${range/,*/}
    range_right=${range/*,/}
    if [ "$range_left" -le "$horiz_center" ]\
    && [ "$horiz_center" -le "$range_right" ]; then
        # echo "found in $range_and_offset" >> "$log" # dbg
        passed_current=0
        # search through the sub-displays again to find one after the one we're
        # on currently; we also need to wrap around once.
        for range_and_offset2 in ${ranges_extended[@]}; do
            if [ "$range_and_offset2" == "$range_and_offset" ]; then
                passed_current=1
                continue
                fi
            if [ "$passed_current" -eq 1 ]\
            && [ "$range_and_offset2" != "$range_and_offset" ]; then
                range2=${range_and_offset2/;*/}
                range2_left=${range2/,*/}
                range2_right=${range2/*,/}
                # echo "found not in $range_and_offset2" >> "$log" # dbg
                eval $(xdotool getactivewindow getwindowgeometry --shell)
                # the above outputs something like:
                # WINDOW=70385876
                # X=593
                # Y=190
                # WIDTH=722
                # HEIGHT=422
                # SCREEN=0
                #
                # do note, SCREEN has nothing to do with the monitor the window
                # is being displayed on.
                # dbg
                # xdotool getactivewindow getwindowgeometry --shell >> "$log"

                gravity=0
                x="$range2_left"
                y=${range_and_offset2/*;/}
                width="$range2_right-$range2_left-2*$border"
                w="$width"
                h="$HEIGHT"
                # echo "$gravity,$x,$y,$w,$h" >> "$log" # dbg
                wmctrl -r :ACTIVE: -e "$gravity,$x,$y,$w,$h"

                wmctrl -r :ACTIVE: -b add,maximized_vert
                break
                fi
            done
        fi
    done
