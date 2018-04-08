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

# figure out which desktop the window falls on. we only need to use the widths
# and horizontal offsets.
declare -i monitor_num
monitor_num=0

declare -i vertical_offset
declare -i width
declare -i height
declare -i horizontal_offset
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
# columns is an array which contains entries of the form x1,x2,h;y;f where x1
# is the starting pixel column on the screen and x2 is the final pixel column,
# h is the height of the sub-display, y is the offset from top of desktop (i.e.
# starting pixel row), and finally f is 1 if the sub-display takes up the whole
# physical screen or 0 otherwise.
# This is output for every virtual column.

declare -a columns
mapfile -t columns < <(echo "$monitor_info" | while IFS= read -r info; do
    # the output is: widthxheight+horizontal_offset+vertical_offset
    IFS='x+' read -r width height horizontal_offset vertical_offset <<< "$info"
    left="$horizontal_offset"
    right="$left + $width"
    width="$right-$left"

    if [ "$width" -le "$max_width" ]; then
        echo "$range_and_height_and_offset;1"
        continue
        fi

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
                start_="$left+($i-1)*$part"
                if ((i+j == parts_with_overflow)); then
                    # The last submonitor might have one pixel column
                    # missing because we are dividing in the integers, so
                    # let us account for the division remainder here.
                    end="$right"
                else
                    end="$left+($i+$j)*$part"
                    fi
                wholescreen=0
                echo "$start_,$end,$height;$vertical_offset;$wholescreen"
                fi
            done
        done
    done)


# echo columns are: ${columns[@]} >> "$log" # dbg
# we need the columns plus one more, so if our window is at the last column,
# it can jump to the first column. So we tack a copy of the first column onto
# the end of the list/array/whatever bash has.
#
# awk '!x[$0]++' is like uniq but doesn't require sorting.
declare -a columns_extended
mapfile -t columns_extended < <(
    for r in "${columns[@]}"; do echo "$r"; done | awk '!x[$0]++'
    for r in "${columns[@]}"; do echo "$r"; break; done
    )

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
declare -i window_area
window_area="$WIDTH*$HEIGHT"

declare -i column_area
declare -a columns_area_diff
mapfile -t columns_area_diff < <(for virtual_column in ${columns[@]}; do
    echo "virtual_column is: $virtual_column" >> "$log" # dbg
    IFS=';,' read -r range_left range_right range_height range_vert_offset wholescreen <<< "$virtual_column"
    column_area="($range_right-$range_left)*$range_height"
    d="$window_area-$column_area"
    echo "sqrt(sqrt(($d)^2))" | bc
    # We need to apply a second square root. Without it, we would have a result
    # which is a difference of area in square units; however, later on, we need
    # to create a score that is equally affected by the output of this, and the
    # distance of window center to column center, which is in (non-square)
    # units. To do this properly, both have to have the same dimension. So we
    # either square root the result of this, or square the result of the other
    # thing, but using larger numbers is likely worse, so i opted for square
    # root here, because it resulted in smaller numbers.
    done)

# Get the center of the window.
declare -i window_left # left border
window_left="$X"
declare -i window_right
window_right="$window_left+$WIDTH" # right border
declare -i window_center_horiz
let "window_center_horiz=($window_left+$window_right)/2" # integer division

declare -i window_top
window_top="$Y"
declare -i window_bottom
window_bottom="$window_top+$HEIGHT"
declare -i window_center_vert
let "window_center_vert=($window_top+$window_bottom)/2" # integer division

declare -i column_center_horiz
declare -i column_center_vert
declare -a columns_center_diff
mapfile -t columns_center_diff < <(for virtual_column in "${columns[@]}"; do
    IFS=';,' read -r range_left range_right range_height range_vert_offset wholescreen <<< "$virtual_column"
    let "column_center_horiz=($range_left+$range_right)/2" # integer division
    let "column_center_vert=$range_vert_offset+$range_height/2" # integer division
    diff_horiz="$column_center_horiz-$window_center_horiz"
    diff_vert="$column_center_vert-$window_center_vert"
    echo "sqrt(($diff_horiz)^2+($diff_vert)^2)" | bc
    done)

declare -i columns_len
columns_amt=${#columns[@]}
columns_len="$columns_amt-1"

declare -a columns_score
for (( i=0; i<=columns_len; i++ )); do
    a=${columns_area_diff[$i]}
    c=${columns_center_diff[$i]}
    columns_score[$i]=$(echo "sqrt(($a)^2+($c)^2)" | bc)
    done

declare -i columns_score_min
columns_score_min=${columns_score[0]}
for n in ${columns_score[@]}; do
    if [ "$n" -lt "$columns_score_min" ]; then columns_score_min=$n; fi
    done

closest_column_idx="$(for (( i=0; i<=$columns_len; i++ )); do
    if [ "$columns_score_min" -eq "${columns_score[$i]}" ]; then
        echo "$i"
        break
        fi
    done)"

# Jump to next virtual column

declare -i closest_column_idx_next
closest_column_idx_next="$closest_column_idx+1"
virtual_column="${columns_extended[$closest_column_idx_next]}"
IFS=';,' read -r range_left range_right range_height range_vert_offset wholescreen <<< "$virtual_column"
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

gravity=0
width="$range_right-$range_left-2*$border" # has something to do with 884/882 bug
wmctrl -r :ACTIVE: -e "$gravity,$range_left,$range_vert_offset,$width,$range_height"

if [ "$wholescreen" -eq "1" ]; then
    wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
    fi
