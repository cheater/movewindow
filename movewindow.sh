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

# SETTINGS:

min_width=750
preferred_width=884 # bug: why does this need to be 884 for the windows to
# become 882 pixels wide?
max_width=1500





# If your theme uses borders, set the border thickness here. This is important
# so that windows line up properly.
#
# Idea: maybe there's a way to find out about this programmatically.

border=1 # has something to do with 884/882 bug

# Now we're using cache for the expensive xrandr readout, so it should only
# happen once in a while. Set the cache timeout here, in seconds.

cache_timeout=4
cache="$HOME/.movewindow_cache"

declare -i delta
cache_modtime="$(stat -c %Y "$cache")"
now="$(date +%s)"
delta="$now - $cache_modtime"
if [ "$delta" -ge "$cache_timeout" ]; then
    # echo "generating and tee" >> "$log" # dbg
    monitor_info="$( \
        xrandr -q \
        | grep ' connected \(primary \|\)[0-9]\+x[0-9]\++[0-9]\++[0-9]\+' \
        | sed -e 's/.* \([0-9]\+x[0-9]\++[0-9]\++[0-9]\+\).*/\1/g' \
        | tee "$cache"
        )"
else
    # echo "restoring" >> "$log" # dbg
    monitor_info="$(cat "$cache")"
    touch "$cache" # If you're using this program, it probably means
    # that you aren't messing around with monitor connections or settings,
    # so let's re-validate the cache.
    fi

wmctrl -r :ACTIVE: -b remove,maximized_horz
wmctrl -r :ACTIVE: -b remove,maximized_vert

# Get the center of the window.
eval "$(xdotool getactivewindow getwindowgeometry --shell)"
# The above outputs something like:
# WINDOW=70385876
# X=593
# Y=190
# WIDTH=722
# HEIGHT=422
# SCREEN=0
#
# Do note, SCREEN has nothing to do with the monitor the window is being
# displayed on. It is the X11 "screen", which is a concept defined in the
# nomenclature of X11.

declare -i window_left # left border
window_left="$X"
declare -i window_right
window_right="$window_left + $WIDTH" # right border
let "horiz_center=($window_left+$window_right)/2" # integer division

# figure out which desktop the window falls on. we only need to use the widths
# and horizontal offsets.
declare -a columns
declare -i monitor_num
monitor_num=0

declare -i vertical_offset
declare -i width
declare -i height
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
declare -i j
declare -i overflow_size
declare -i parts_with_overflow
# columns is an array which contains entries of the form x1,x2;y;f where x1
# is the starting pixel column on the screen and x2 is the final pixel
# column, y is the offset from top of desktop (i.e. starting pixel row), and
# finally f is 1 if the virtual column takes up the whole physical screen or
# 0 otherwise.
# This is put out for every virtual column.
columns="$(echo "$monitor_info" | while IFS= read -r info; do
    # echo info is "$info" >> "$log" # dbg
    # the output is: widthxheight+horizontal_offset+vertical_offset
    vertical_offset=${info/*+/}
    width=${info/x*/}
    height_and_offset=${info##*x}
    height=${height_and_offset%%+*}
    offsets=${info#*+}
    horiz_offset=${offsets/+*/}
    left="$horiz_offset"
    right="$left + $width"
    echo "$left,$right,$height;$vertical_offset" # we are echoing the dimensions
    # of physical monitors as reported by X; not virtual columns that we will
    # move the panels to. The format is x1,x2,h;y. It is missing information on
    # correspondence of virtual columns to physical monitors, since everything
    # we echo here is a physical monitor.
        # echo range_and_offset is: "$range_and_offset" >> "$log" # dbg
    done | while IFS= read -r range_and_height_and_offset; do
        range=${range_and_height_and_offset%%;*}
        range_left=${range%%,*}
        range_right_and_height=${range#*,}
        range_right=${range_right_and_height%,*}
        height=${range_right_and_height##*,}
        offset=${range_and_height_and_offset##*;}
        width="$range_right-$range_left"

        # echo width is "$width" >> "$log" # dbg
        if [ "$width" -le "$max_width" ]; then
            # echo skipping "$range_and_height_and_offset" >> "$log" # dbg
            echo "$range_and_height_and_offset;1"
            continue
            fi
        # echo not skipping "$range_and_height_and_offset" >> "$log" # dbg

        parts="$width/$preferred_width" # $parts contains the amount of
        # sub-monitors (columns) of preferred size that will be created. There
        # may also be an overflow sub-monitor that will be less than preferred
        # size.
        overflow=false
        overflow_size="$width-$parts*$preferred_width"
        if [ "$overflow_size" -ge "$min_width" ]; then
            overflow=true
            fi

        parts_with_overflow="$parts" # $parts_with_overflow contains the amount
        # of sub-monitors we will have with possibly an overflow sub-monitor
        # that's smaller than the preferred size but still larger than the min
        # size.

        part="$width/$parts" # $part contains the number of pixel columns
        # which will form one sub-monitor. Note one pixel might be missing.

        if $overflow; then
            part="$preferred_width"
            parts_with_overflow="$parts+1"
            fi

        for ((j=0; j<=parts_with_overflow; j++)); do
            for ((i=1; i<=parts_with_overflow; i++)); do
                if ((j<parts_with_overflow-1 && i+j<=parts_with_overflow)); then
                    echo i is: "$i" >> "$log" # dbg
                    start_="$range_left+($i-1)*$part"
                    if ((i+j == parts_with_overflow)); then
                        # The last submonitor might have one pixel column
                        # missing because we are dividing in the integers, so
                        # let us account for the division remainder here.
                        end="$range_right"
                    else
                        end="$range_left+($i+$j)*$part"
                        fi
                    echo "$start_,$end,$height;$offset;0"
                    fi
                done
            done
        done)"

# echo columns are: ${columns[@]} >> "$log" # dbg
# we need the columns plus one more, so if our window is at the last column,
# it can jump to the first column. So we tack a copy of the first column onto
# the end of the list/array/whatever bash has.
columns_extended="$(
    for r in ${columns[@]}; do echo "$r"; done
    for r in ${columns[@]}; do echo "$r"; break; done
    )"

# search through the sub-displays to find the one we're on currently.
for virtual_column in ${columns[@]}; do
    range=${virtual_column%%;*}
    # echo $range >> "range: $log" # dbg
    range_left=${range%%,*}
    range_right_and_height=${range#*,}
    range_right=${range_right_and_height%%,*}
    range_height=${range_right_and_height#*,}
    if [ "$range_left" -le "$horiz_center" ]\
    && [ "$horiz_center" -le "$range_right" ]; then
        # echo "found in $virtual_column" >> "$log" # dbg
        passed_current=0
        # search through the sub-displays again for one after the one we are
        # on currently; we also need to wrap around once.
        for virtual_column2 in ${columns_extended[@]}; do
            if [ "$virtual_column2" == "$virtual_column" ]; then
                passed_current=1
                continue
                fi
            if [ "$passed_current" -eq 1 ]\
            && [ "$virtual_column2" != "$virtual_column" ]; then
                range2=${virtual_column2%%;*}
                range2_left=${range2%%,*}
                # echo "found not in $virtual_column2" >> "$log" # dbg
                range2_right_and_height=${range2#*,}
                range2_right=${range2_right_and_height%%,*}
                range2_height=${range2_right_and_height#*,}
                eval "$(xdotool getactivewindow getwindowgeometry --shell)"
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
                # (echo 'xdotool output: '; xdotool getactivewindow getwindowgeometry --shell) >> "$log" # dbg

                y_and_wholescreen=${virtual_column2#*;}
                wholescreen=${y_and_wholescreen#*;}
                gravity=0
                x="$range2_left"
                y=${y_and_wholescreen%%;*}
                width="$range2_right-$range2_left-2*$border" # has something to
                # do with 884/882 bug
                w="$width"
                h="$HEIGHT"
                # echo "$gravity,$x,$y,$w,$h" >> "$log" # dbg
                wmctrl -r :ACTIVE: -e "$gravity,$x,$y,$w,$h"

                if [ "$wholescreen" -eq "1" ]; then
                    wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
                else
                    wmctrl -r :ACTIVE: -b add,maximized_vert
                    fi

                break
                fi
            done
        fi
    done
