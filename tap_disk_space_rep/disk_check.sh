#!/bin/bash
###############################################################################
# Script Name  : disk_check.sh
# Converted From: DISK_CHECK.COM / USAGE.COM (VMS DCL)
# Description   : Displays disk space usage for all mounted filesystems.
#                 Generates a formatted table with device name, mount point,
#                 filesystem type, total/free/used space, and a percentage bar.
#
# Parameters:
#   $1  Graph data:  U = Used percentage (default), F = Free percentage
#   $2  Display type: G = Graphical/video display (default), T = Textual display
#
# Examples:
#   ./disk_check.sh F G   # Video percentage graph of free space
#   ./disk_check.sh F T   # Textual percentage graph of free space
#   ./disk_check.sh U G   # Video percentage graph of used space
#   ./disk_check.sh U T   # Textual percentage graph of used space
#   ./disk_check.sh       # Video percentage graph of used space (default)
#
# Original Author: Thomas M. Maloney (30 JUN 10)
# Converted By   : Automated VMS-to-Linux conversion
###############################################################################

###############################################################################
#                       INITIALIZATION
###############################################################################

# Parameters (first character only, uppercased)
PASSED1=$(echo "${1:-U}" | cut -c1 | tr '[:lower:]' '[:upper:]')
PASSED2=$(echo "${2:-G}" | cut -c1 | tr '[:lower:]' '[:upper:]')

GRAPH="Used"      # Default: show used space
VIDEO="Yes"       # Default: graphical (ANSI) display

[[ "${PASSED1}" == "U" ]] && GRAPH="Used"
[[ "${PASSED1}" == "F" ]] && GRAPH="Free"

[[ "${PASSED2}" == "G" ]] && VIDEO="Yes"
[[ "${PASSED2}" == "T" ]] && VIDEO="No"

# ANSI escape codes
ESC=$'\033'
VTOFF="${ESC}[0m"
VTON="${ESC}[1;7m"        # Bold + Reverse video
CLS="${ESC}[H${ESC}[J"    # Home + Clear screen

# Bar characters
HASH_CHAR="X"

###############################################################################
#                       DISPLAY HELP
###############################################################################

if { [[ "${PASSED1}" != "U" ]] && [[ "${PASSED1}" != "F" ]] && [[ -n "${1:-}" ]]; } || \
   { [[ "${PASSED2}" != "G" ]] && [[ "${PASSED2}" != "T" ]] && [[ -n "${2:-}" ]]; }; then
    echo "Syntax is:"
    echo ""
    echo "  ./disk_check.sh [graph] [display]"
    echo ""
    echo "Where [graph] Is:   U = Used Percentage (Default)"
    echo "                    F = Free Percentage"
    echo ""
    echo "And [display] Is:   G = Graphical Display (Default)"
    echo "                    T = Textual Display"
    echo ""
    echo "Examples:           ./disk_check.sh F G   -   Video percentage graph of free blocks"
    echo "                    ./disk_check.sh F T   -   Textual percentage graph of free blocks"
    echo "                    ./disk_check.sh U G   -   Video percentage graph of used blocks"
    echo "                    ./disk_check.sh U T   -   Textual percentage graph of used blocks"
    echo "                    ./disk_check.sh       -   Video percentage graph of used blocks (default)"
    echo ""
    exit 0
fi

###############################################################################
#                       DISPLAY HEADER
###############################################################################

echo -e "${CLS}"
echo "Disk Space Usage for $(hostname) at $(date '+%d-%b-%Y %H:%M:%S')"
echo ""
printf "%-20s %-15s %-12s %12s %12s %12s  %% %s Graph\n" \
    "Device" "Mount Point" "Type" "Total(KB)" "Free(KB)" "Used(KB)" "${GRAPH}"
echo "==================== =============== ============ ============ ============ ============ ===================="

###############################################################################
#                       GENERATE DISK LIST
###############################################################################

# Read mounted filesystems (excluding pseudo/virtual filesystems)
df -T -P --exclude-type=tmpfs --exclude-type=devtmpfs --exclude-type=squashfs \
         --exclude-type=overlay --exclude-type=proc --exclude-type=sysfs 2>/dev/null | \
    tail -n +2 | while read -r filesystem fstype total used avail usepct mountpoint; do
    # Remove the trailing '%' from use%
    usepct_num=${usepct//%/}
    freepct_num=$((100 - usepct_num))

    # Format numbers
    printf -v fmt_total "%'12d" "${total}"
    printf -v fmt_avail "%'12d" "${avail}"
    printf -v fmt_used  "%'12d" "${used}"

    # Build percentage bar (20 chars wide = 100% → each char = 5%)
    bar_length=20
    if [[ "${GRAPH}" == "Used" ]]; then
        filled=$((usepct_num / 5))
        pct_display="${usepct_num}"
    else
        filled=$((freepct_num / 5))
        pct_display="${freepct_num}"
    fi

    bar=""
    if [[ "${VIDEO}" == "Yes" ]]; then
        # ANSI reverse-video bar
        bar_fill=""
        for ((i=0; i<filled; i++)); do bar_fill+=" "; done
        bar_empty=""
        for ((i=filled; i<bar_length; i++)); do bar_empty+=" "; done
        bar="${VTON}${bar_fill}${VTOFF}${bar_empty}"
    else
        # Textual bar with X characters
        bar_fill=""
        for ((i=0; i<filled; i++)); do bar_fill+="${HASH_CHAR}"; done
        bar_empty=""
        for ((i=filled; i<bar_length; i++)); do bar_empty+="."; done
        bar="${bar_fill}${bar_empty}"
    fi

    # Truncate/pad fields for alignment
    printf "%-20s %-15s %-12s %s %s %s %3d%% %s\n" \
        "$(echo "${filesystem}" | cut -c1-20)" \
        "$(echo "${mountpoint}" | cut -c1-15)" \
        "$(echo "${fstype}" | cut -c1-12)" \
        "${fmt_total}" "${fmt_avail}" "${fmt_used}" \
        "${pct_display}" "${bar}"
done

echo "==================== =============== ============ ============ ============ ============ ===================="
echo ""
