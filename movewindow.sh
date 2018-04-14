#!/bin/bash
# The aim of this tool is to move a window to subdivisions of physical monitors
# which we call panels.

# It is a workaround, since Marco (the window manager of MATE Desktop) cannot
# properly do this. Even though there's a function for this, it is very broken.

# You can use this tool by executing it with a key combination you set in your
# window manager. First make sure this program is in $PATH. Then you need to
# set up the key combo. For MATE Desktop, open mateconf-editor and navigate to
# apps/marco/keybinding_commands and type in the name of the executable in one
# of the items. Then, under apps/marco/global_keybindings/run_command_n, set
# the keyboard combination. That's it! A similar procedure works for GNOME 2
# with its metacity window manager, and there are very likely ways to do this
# with any other desktop software.

# You can break down very wide monitors into multiple panels. Define your
# preferred width to break down to (that is the minimum width a panel will
# have) and set the maximum width after which breaking down monitors should
# start occuring, using the $preferred_width and $max_width variables
# respectively. Set $min_width to define the minimum width of a panel. This is
# useful for eg when your screen can only display 230 character wide lines, so
# you'd like to have roughly two panels of 80 characters each, and another one
# that's smaller than that, for other uses.

# log="/tmp/dbglog" # dbg
# echo -n '' > "$log" # dbg
# echo "-----------" >> "$log" # dbg


# Check for the existence of the first argument and set movement to forward or
# backward according to what was detected.
forward=true
if [ "$#" -ge 1 ]; then
  forward=false
  fi


############
# SETTINGS #
############

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
declare -i p_left
declare -i p_right
declare -i panels_num
declare -i panels_num_o
declare -i panel_width
declare -i start_
declare -i end
declare -i i
declare -i j
declare -i overflow_size
# panels is an array which contains entries of the form x1,x2,h;y;f where x1 is
# the starting pixel column on the screen and x2 is the final pixel column, h
# is the height of the panel, y is the offset from top of desktop (i.e.
# starting pixel row), and finally f is 1 if the panel takes up the whole
# physical screen or 0 otherwise. This is output for every panel.

declare -a panels
mapfile -t panels < <(echo "$monitor_info" | while IFS= read -r info; do
    # echo info is "$info" >> "$log" # dbg
    # the output is: widthxheight+horizontal_offset+vertical_offset
    IFS='x+' read -r width height horizontal_offset vertical_offset <<< "$info"
    left="$horizontal_offset"
    right="$left + $width"

    # echo width is "$width" >> "$log" # dbg
    fullscreen=0
    if [ "$width" -le "$max_width" ]; then
        fullscreen=1 # FIXME: fix this case, part of the rest of the logic
        # should be skipped!
        fi

    panels_num="$width/$preferred_width" # $panels_num contains the amount of
    # panels of preferred size that will be created. There may also be an
    # overflow panel that will be less than preferred size.
    overflow=false
    overflow_size="$width-$panels_num*$preferred_width"
    if [ "$overflow_size" -ge "$min_width" ]; then
        overflow=true
        fi

    panels_num_o="$panels_num" # $panels_num_o contains the amount of panels we
    # will have with possibly an overflow panel that's smaller than the
    # preferred size but still larger than the min size.

    panel_width="$width/$panels_num" # $panel_width contains the number of pixel
    # columns which will form one panel. Note one pixel might be missing.

    if $overflow; then
        panel_width="$preferred_width"
        panels_num_o="$panels_num+1"
        fi

    for (( j=0; j<=panels_num_o; j++ )); do
        for (( i=1; i<=panels_num_o; i++ )); do
            if (( j<panels_num_o-1 && i+j<=panels_num_o )); then
                start_="$left+($i-1)*$panel_width"
                if (( i+j == panels_num_o )); then
                    # The last panel might have one pixel column missing
                    # because we are dividing in the integers, so let us
                    # account for the division remainder here.
                    end="$right"
                else
                    end="$left+($i+$j)*$panel_width"
                    fi
                echo "$start_,$end,$height;$vertical_offset;$fullscreen"
                fi
            done
        done
    # awk '!x[$0]++' is like uniq but doesn't require sorting.
    done | awk '!x[$0]++')

# echo panels are: ${panels[@]} >> "$log" # dbg


# Find the current panel our window is on (or closest to). This will be done by
# finding panels with a similar area to our window, and panels whose centers
# are close to the center of the window, and then scoring panels based on those
# two numbers. The panel with the best (lowest) score is the one that wins,
# i.e. the one we guess we are on right now.

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

declare -i panel_area
declare -a panels_area_diff
mapfile -t panels_area_diff < <(for panel in ${panels[@]}; do
    IFS=';,' read -r p_left p_right p_height p_top fullscreen <<< "$panel"
    panel_area="($p_right-$p_left)*$p_height"
    d="$window_area-$panel_area"
    echo "sqrt(sqrt(($d)^2))" | bc
    # We need to apply a second square root. Without it, we would have a result
    # which is a difference of area in square units; however, later on, we need
    # to create a score that is equally affected by the output of this, and the
    # distance of window center to panel center, which is in (non-square)
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

declare -i panel_center_horiz
declare -i panel_center_vert
declare -a panels_center_diff
mapfile -t panels_center_diff < <(for panel in "${panels[@]}"; do
    IFS=';,' read -r p_left p_right p_height p_top fullscreen <<< "$panel"
    let "panel_center_horiz=($p_left+$p_right)/2" # integer division
    let "panel_center_vert=$p_top+$p_height/2" # integer division
    diff_horiz="$panel_center_horiz-$window_center_horiz"
    diff_vert="$panel_center_vert-$window_center_vert"
    echo "sqrt(($diff_horiz)^2+($diff_vert)^2)" | bc
    done)

declare -i panels_len
panels_len=${#panels[@]}

declare -a panels_score
for (( i=0; i<panels_len; i++ )); do
    a=${panels_area_diff[i]}
    c=${panels_center_diff[i]}
    panels_score[i]=$(echo "sqrt(($a)^2+($c)^2)" | bc)
    done

declare -i panels_score_min
panels_score_min=${panels_score[0]}
for n in ${panels_score[@]}; do
    if [ "$n" -lt "$panels_score_min" ]; then panels_score_min=$n; fi
    done

closest_panel_idx="$(for (( i=0; i<$panels_len; i++ )); do
    if [ "$panels_score_min" -eq "${panels_score[i]}" ]; then
        echo "$i"
        break
        fi
    done)"


# Jump to next panel. Now that we know which panel we're on, let's go to the
# next one.

movement=1
if ! "$forward"; then
  movement='-1'
  fi

# Note: the % operator (modulo operator) in bash is "broken" in that x % n
# doesn't change x when -n < x < n, meaning it allows negative values. However,
# bash arrays can be indexed by negative values, and the thing we expect will
# happen, so it's two "broken" features that are "broken" consistently, working
# together to create a system that's not broken after all.
new_idx=$(( ( closest_panel_idx + movement ) % ${#panels[@]} ))
panel="${panels[new_idx]}"

IFS=';,' read -r p_left p_right p_height p_top fullscreen <<< "$panel"
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
# (echo 'xdotool output: '; xdotool getactivewindow getwindowgeometry --shell) >> "$log" # dbg

gravity=0
declare -i p_width
p_width="$p_right-$p_left-2*$border" # has something to do with 884/882 bug
wmctrl -r :ACTIVE: -e "$gravity,$p_left,$p_top,$p_width,$p_height"

if [ "$fullscreen" -eq "1" ]; then
    wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
    fi
