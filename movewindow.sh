#!/bin/bash
# The aim of this tool is to move a window to either the left or right monitor.
# we assume there are two monitors, and they are side by side.

# It is a workaround, since Marco (the window manager of MATE Desktop) cannot
# properly do this. Even though there's a function for this, it is very broken.

# For some reason, this tool has a bug. It makes the non-maximized vertical
# size of the window equal to the vertical size of the previous monitor it was
# displayed on.

# log="/tmp/dbglog" # dbg
# echo "-----------" >> "$log" # dbg

wmctrl -r :ACTIVE: -b remove,maximized_horz,maximized_vert

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

ranges=$(xrandr -q | awk '/ connected/{print $3}' | while read info; do
    # the output is: widthxheight+horizontal_offset+vertical_offset
    declare -i vertical_offset
    vertical_offset=${info/*+/}
    declare -i width
    width=${info/x*/}
    offsets=${info#*+}
    declare -i horiz_offset
    horiz_offset=${offsets/+*/}
    declare -i left
    left="$horiz_offset"
    declare -i right
    right="$left + $width"
    echo "$left,$right;$vertical_offset"
    done)

# echo ${ranges[@]} >> "$log" # dbg
for range_and_offset in ${ranges[@]}; do
    range=${range_and_offset/;*/}
    # echo $range >> "$log" # dbg
    range_left=${range/,*/}
    range_right=${range/*,/}
    if [ "$range_left" -le "$horiz_center" ] && [ "$horiz_center" -le "$range_right" ]; then
        # echo "found in $range_and_offset" >> "$log" # dbg
        for range_and_offset2 in ${ranges[@]}; do
            if [ "$range_and_offset2" != "$range_and_offset" ]; then
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
                w="$WIDTH"
                h="$HEIGHT"
                # echo "$gravity,$x,$y,$w,$h" >> "$log" # dbg
                wmctrl -r :ACTIVE: -e "$gravity,$x,$y,$w,$h"

                wmctrl -r :ACTIVE: -b add,maximized_horz,maximized_vert
                break
                fi
            done
        fi
    done
