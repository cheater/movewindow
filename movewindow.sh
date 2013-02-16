#!/bin/bash
# The aim of this tool is to move a window to either the left or right monitor.
# we assume there are two monitors, and they are side by side.

# It is a workaround, since Marco (the window manager of MATE Desktop) cannot
# properly do this. Even though there's a function for this, it is very broken.

# For some reason, this tool has a bug. It makes the non-maximized vertical
# size of the window equal to the vertical size of the previous monitor it was
# displayed on.

# Now you can also break down very wide monitors into smaller ones. Define your
# preferred width to break down to (that is the minimum width a sub-monitor
# will have) and set the maximum width after which breaking down monitors
# should occur, using the $preferred_width and $max_width variables
# respectively.

# log="/tmp/dbglog" # dbg
# echo "-----------" >> "$log" # dbg

preferred_width=800
max_width=1500

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

declare -i window_left
window_left="$X"
declare -i window_right
window_right="$window_left + $WIDTH"
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
ranges=$(xrandr -q | awk '/ connected/{print $3}' | while read info; do
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

        echo width is "$width" >> "$log"
        if [ "$width" -le "$max_width" ]; then
            echo skipping "$range_and_offset" >> "$log"
            echo "$range_and_offset"
            continue
            fi
        echo not skipping "$range_and_offset" >> "$log"

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

echo ${ranges[@]} >> "$log" # dbg
ranges_twice=$(
    for range_and_offset in ${ranges[@]}; do echo $range_and_offset; done
    for range_and_offset in ${ranges[@]}; do echo $range_and_offset; done
    )

for range_and_offset in ${ranges[@]}; do
    range=${range_and_offset/;*/}
    # echo $range >> "$log" # dbg
    range_left=${range/,*/}
    range_right=${range/*,/}
    if [ "$range_left" -le "$horiz_center" ] && [ "$horiz_center" -le "$range_right" ]; then
        # echo "found in $range_and_offset" >> "$log" # dbg
        passed_current=0
        for range_and_offset2 in ${ranges_twice[@]}; do
            if [ "$range_and_offset2" == "$range_and_offset" ]; then
                passed_current=1
                continue
                fi
            if [ "$passed_current" -eq 1 ] && [ "$range_and_offset2" != "$range_and_offset" ]; then
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
                # xdotool getactivewindow getwindowgeometry --shell >> "$log" # dbg

                gravity=0
                x="$range2_left"
                y=${range_and_offset2/*;/}
                width="$range2_right-$range2_left"
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
