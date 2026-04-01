#!/usr/bin/env bash
# ============================================================================
# iperf3 Multi-Stream Traffic Manager v6.2
# Interactive menu-driven iperf3 wrapper with VRF support, DSCP, monitoring
# ============================================================================

# --- Safety: NO set -euo pipefail (breaks VRF detection, grep, command -v) ---

# ============================================================================
# COLOR SCHEME — Black/Green/Blue ONLY (no yellow anywhere)
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Semantic aliases (all map to green/blue/white — NO yellow)
HEADER_COLOR="$BLUE"
TITLE_COLOR="$GREEN"
PROMPT_COLOR="$CYAN"
WARN_COLOR="$RED"
INFO_COLOR="$GREEN"
ACCENT_COLOR="$BLUE"
LABEL_COLOR="$WHITE"
VALUE_COLOR="$GREEN"
MENU_NUM="$CYAN"
MENU_TEXT="$WHITE"
BAR_COLOR="$GREEN"
BAR_BG="$DIM"
BORDER_COLOR="$BLUE"
PKT_BORDER="$BLUE"
PKT_LABEL="$CYAN"
PKT_VALUE="$GREEN"

# ============================================================================
# GLOBAL VARIABLES
# ============================================================================
WORK_DIR="/tmp/iperf3_manager"
SCRIPT_DIR="$WORK_DIR/scripts"
LOG_DIR="$WORK_DIR"
PIDS=()
MONITOR_PIDS=()
declare -A VRF_DEVICE_MAP   # vrf_name -> vrf_device
declare -A VRF_IFACE_MAP    # interface -> vrf_name
declare -A DSCP_MAP
declare -a STREAM_CONFIGS    # array of stream config strings

# Stream config fields (per stream)
declare -a S_PROTO S_PORT S_BITRATE S_DURATION S_DSCP S_CONGESTION S_REVERSE S_LABEL

mkdir -p "$SCRIPT_DIR" 2>/dev/null || true
mkdir -p "$LOG_DIR" 2>/dev/null || true

# ============================================================================
# DSCP REFERENCE TABLE (22 entries, TOS = DSCP << 2)
# ============================================================================
init_dscp_map() {
    DSCP_MAP=(
        ["default"]="0"
        ["cs1"]="32"
        ["cs2"]="64"
        ["cs3"]="96"
        ["cs4"]="128"
        ["cs5"]="160"
        ["cs6"]="192"
        ["cs7"]="224"
        ["af11"]="40"
        ["af12"]="48"
        ["af13"]="56"
        ["af21"]="72"
        ["af22"]="80"
        ["af23"]="88"
        ["af31"]="104"
        ["af32"]="112"
        ["af33"]="120"
        ["af41"]="136"
        ["af42"]="144"
        ["af43"]="152"
        ["ef"]="184"
        ["va"]="172"
    )
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================
print_header() {
    local title="$1"
    local width=70
    local pad
    pad=$(( (width - ${#title} - 2) / 2 ))
    echo ""
    echo -e "${BORDER_COLOR}$(printf '═%.0s' $(seq 1 $width))${NC}"
    echo -e "${BORDER_COLOR}║${NC}$(printf ' %.0s' $(seq 1 $pad))${TITLE_COLOR}${BOLD}${title}${NC}$(printf ' %.0s' $(seq 1 $((width - pad - ${#title} - 2))))${BORDER_COLOR}║${NC}"
    echo -e "${BORDER_COLOR}$(printf '═%.0s' $(seq 1 $width))${NC}"
}

print_section() {
    local title="$1"
    echo ""
    echo -e "${ACCENT_COLOR}── ${WHITE}${BOLD}${title} ${ACCENT_COLOR}$(printf '─%.0s' $(seq 1 $((55 - ${#title}))))${NC}"
}

print_info() {
    echo -e "  ${INFO_COLOR}●${NC} $1"
}

print_warn() {
    echo -e "  ${WARN_COLOR}⚠${NC} $1"
}

print_error() {
    echo -e "  ${RED}✖${NC} $1"
}

print_success() {
    echo -e "  ${GREEN}✔${NC} $1"
}

prompt_input() {
    local prompt_text="$1"
    local var_name="$2"
    local default_val="${3:-}"
    local display_default=""
    if [[ -n "$default_val" ]]; then
        display_default=" ${DIM}[${default_val}]${NC}"
    fi
    echo -ne "  ${PROMPT_COLOR}▶${NC} ${prompt_text}${display_default}: "
    local input
    read -r input
    if [[ -z "$input" && -n "$default_val" ]]; then
        input="$default_val"
    fi
    eval "$var_name=\"$input\""
}

press_enter() {
    echo ""
    echo -ne "  ${DIM}Press Enter to continue...${NC}"
    read -r
}

# ============================================================================
# CLEANUP
# ============================================================================
cleanup_all() {
    echo ""
    echo -e "${INFO_COLOR}Cleaning up...${NC}"
    for pid in "${MONITOR_PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    MONITOR_PIDS=()
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    PIDS=()
    # Kill any lingering iperf3 processes we started
    pkill -f "iperf3_manager/scripts" 2>/dev/null || true
    rm -f "$SCRIPT_DIR"/*.sh 2>/dev/null || true
    echo -e "  ${GREEN}✔${NC} Cleanup complete"
}

trap cleanup_all EXIT INT TERM

# ============================================================================
# IPERF3 CHECK / INSTALL
# ============================================================================
check_iperf3() {
    if command -v iperf3 >/dev/null 2>&1; then
        local ver
        ver=$(iperf3 --version 2>&1 | head -1)
        print_success "iperf3 found: ${VALUE_COLOR}${ver}${NC}"
        return 0
    else
        print_warn "iperf3 not found"
        echo -ne "  ${PROMPT_COLOR}▶${NC} Install iperf3? (y/n): "
        local ans
        read -r ans
        if [[ "$ans" =~ ^[Yy] ]]; then
            if command -v apt-get >/dev/null 2>&1; then
                sudo apt-get update && sudo apt-get install -y iperf3
            elif command -v yum >/dev/null 2>&1; then
                sudo yum install -y iperf3
            elif command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y iperf3
            elif command -v pacman >/dev/null 2>&1; then
                sudo pacman -S --noconfirm iperf3
            else
                print_error "Package manager not detected. Install iperf3 manually."
                return 1
            fi
            if command -v iperf3 >/dev/null 2>&1; then
                print_success "iperf3 installed successfully"
                return 0
            else
                print_error "iperf3 installation failed"
                return 1
            fi
        else
            print_error "iperf3 is required"
            return 1
        fi
    fi
}

# ============================================================================
# VRF DETECTION (3-method)
# ============================================================================
build_vrf_maps() {
    VRF_DEVICE_MAP=()
    VRF_IFACE_MAP=()

    # Method 1: ip vrf show
    if ip vrf show >/dev/null 2>&1; then
        while read -r vrf_name vrf_dev rest; do
            if [[ -n "$vrf_name" && "$vrf_name" != "Name" ]]; then
                # Verify it is actually a VRF master device
                local link_info
                link_info=$(ip -d link show "$vrf_name" 2>/dev/null || true)
                if echo "$link_info" | grep -q "vrf table"; then
                    VRF_DEVICE_MAP["$vrf_name"]="$vrf_name"
                fi
            fi
        done < <(ip vrf show 2>/dev/null || true)
    fi

    # Method 2: ip -d link show type vrf
    while read -r line; do
        local dev_name
        dev_name=$(echo "$line" | grep -oP '^\d+: \K[^@:]+' || true)
        if [[ -n "$dev_name" ]]; then
            local detail
            detail=$(ip -d link show "$dev_name" 2>/dev/null || true)
            if echo "$detail" | grep -q "vrf table"; then
                VRF_DEVICE_MAP["$dev_name"]="$dev_name"
            fi
        fi
    done < <(ip -d link show type vrf 2>/dev/null || true)

    # Method 3: Check each interface for master VRF
    while read -r line; do
        local iface
        iface=$(echo "$line" | awk '{print $2}' | tr -d ':')
        # Remove @xxx suffix
        iface="${iface%%@*}"
        local master
        master=$(ip -d link show "$iface" 2>/dev/null | grep -oP 'master \K\S+' || true)
        if [[ -n "$master" ]]; then
            # Verify master is a VRF device
            local master_detail
            master_detail=$(ip -d link show "$master" 2>/dev/null || true)
            if echo "$master_detail" | grep -q "vrf table"; then
                VRF_IFACE_MAP["$iface"]="$master"
                VRF_DEVICE_MAP["$master"]="$master"
            fi
        fi
    done < <(ip -o link show 2>/dev/null || true)
}

get_iface_vrf() {
    local iface="$1"
    echo "${VRF_IFACE_MAP[$iface]:-}"
}

# ============================================================================
# INTERFACE LISTING & SELECTION
# ============================================================================
list_interfaces() {
    print_section "Network Interfaces"
    local idx=0
    local -a ifaces=()
    while read -r line; do
        local iface
        iface=$(echo "$line" | awk '{print $2}' | tr -d ':')
        iface="${iface%%@*}"
        # Skip VRF master devices themselves
        if [[ -n "${VRF_DEVICE_MAP[$iface]:-}" ]]; then
            continue
        fi
        # Skip loopback for non-loopback modes
        local state
        state=$(ip -o link show "$iface" 2>/dev/null | grep -oP 'state \K\S+' || echo "UNKNOWN")
        local addrs
        addrs=$(ip -o -4 addr show "$iface" 2>/dev/null | grep -oP 'inet \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?' || true)
        local vrf_name
        vrf_name=$(get_iface_vrf "$iface")
        local vrf_display=""
        if [[ -n "$vrf_name" ]]; then
            vrf_display=" ${ACCENT_COLOR}[VRF:${vrf_name}]${NC}"
        fi
        idx=$((idx + 1))
        ifaces+=("$iface")
        local addr_display="${DIM}no IPv4${NC}"
        if [[ -n "$addrs" ]]; then
            addr_display="${VALUE_COLOR}${addrs}${NC}"
        fi
        echo -e "  ${MENU_NUM}${idx})${NC} ${MENU_TEXT}${iface}${NC} - ${addr_display} [${state}]${vrf_display}"
    done < <(ip -o link show 2>/dev/null || true)

    IFACE_LIST=("${ifaces[@]}")
}

select_interface() {
    local prompt_msg="${1:-Select interface}"
    list_interfaces
    echo ""
    prompt_input "$prompt_msg (number, or 'any' for 0.0.0.0)" IFACE_CHOICE "any"

    SELECTED_IFACE=""
    SELECTED_IP=""
    SELECTED_VRF=""

    if [[ "$IFACE_CHOICE" == "any" ]]; then
        SELECTED_IP="0.0.0.0"
        return
    fi

    if [[ "$IFACE_CHOICE" =~ ^[0-9]+$ ]] && (( IFACE_CHOICE >= 1 && IFACE_CHOICE <= ${#IFACE_LIST[@]} )); then
        SELECTED_IFACE="${IFACE_LIST[$((IFACE_CHOICE - 1))]}"
        SELECTED_IP=$(ip -o -4 addr show "$SELECTED_IFACE" 2>/dev/null | grep -oP 'inet \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?' | head -1 || true)
        SELECTED_IP="${SELECTED_IP%%/*}"
        SELECTED_VRF=$(get_iface_vrf "$SELECTED_IFACE")
        if [[ -z "$SELECTED_IP" ]]; then
            print_warn "No IPv4 on ${SELECTED_IFACE}, using 0.0.0.0"
            SELECTED_IP="0.0.0.0"
        fi
        print_info "Selected: ${VALUE_COLOR}${SELECTED_IFACE}${NC} (${SELECTED_IP})"
        if [[ -n "$SELECTED_VRF" ]]; then
            print_info "VRF: ${VALUE_COLOR}${SELECTED_VRF}${NC}"
        fi
    else
        print_warn "Invalid choice, using 0.0.0.0"
        SELECTED_IP="0.0.0.0"
    fi
}

# ============================================================================
# DSCP REFERENCE TABLE
# ============================================================================
show_dscp_table() {
    print_header "DSCP Reference Table"
    echo ""
    printf "  ${LABEL_COLOR}%-12s %-8s %-10s %-14s %-8s${NC}\n" "Name" "DSCP" "TOS Dec" "TOS Hex" "Binary"
    echo -e "  ${BORDER_COLOR}$(printf '─%.0s' $(seq 1 58))${NC}"

    local -a ordered_keys=("default" "cs1" "af11" "af12" "af13" "cs2" "af21" "af22" "af23"
        "cs3" "af31" "af32" "af33" "cs4" "af41" "af42" "af43" "cs5"
        "ef" "va" "cs6" "cs7")

    for key in "${ordered_keys[@]}"; do
        local tos="${DSCP_MAP[$key]}"
        local dscp=$((tos >> 2))
        local hex
        hex=$(printf "0x%02X" "$tos")
        local bin=""
        for i in 7 6 5 4 3 2 1 0; do
            bin="${bin}$(( (tos >> i) & 1 ))"
        done
        printf "  ${VALUE_COLOR}%-12s${NC} %-8s ${GREEN}%-10s${NC} %-14s ${DIM}%s${NC}\n" \
            "$key" "$dscp" "$tos" "$hex" "$bin"
    done
    echo ""
}

# ============================================================================
# PACKET FORMAT VISUALIZATION
# ============================================================================
draw_packet_detail() {
    local stream_num="$1"
    local protocol="$2"
    local src_ip="$3"
    local dst_ip="$4"
    local dst_port="$5"
    local dscp_name="$6"
    local bitrate="$7"

    local tos_dec="${DSCP_MAP[${dscp_name,,}]:-0}"
    local dscp_val=$((tos_dec >> 2))
    local tos_hex
    tos_hex=$(printf "0x%02X" "$tos_dec")

    # DSCP binary (6 bits)
    local dscp_bin=""
    for i in 5 4 3 2 1 0; do
        dscp_bin="${dscp_bin}$(( (dscp_val >> i) & 1 ))"
    done

    local proto_upper="${protocol^^}"
    local proto_num="6"
    if [[ "$proto_upper" == "UDP" ]]; then
        proto_num="17"
    fi

    local src_mac="xx:xx:xx:xx:xx:xx"
    local dst_mac="xx:xx:xx:xx:xx:xx"

    # Try to get real MACs if interface is known
    if [[ -n "$SELECTED_IFACE" ]]; then
        local real_mac
        real_mac=$(ip link show "$SELECTED_IFACE" 2>/dev/null | grep -oP 'link/ether \K[0-9a-f:]+' || true)
        if [[ -n "$real_mac" ]]; then
            src_mac="$real_mac"
        fi
    fi

    local w=68
    echo ""
    echo -e "  ${PKT_BORDER}┌$(printf '─%.0s' $(seq 1 $((w-2))))┐${NC}"
    echo -e "  ${PKT_BORDER}│${NC} ${WHITE}${BOLD}Stream #${stream_num} — Packet Structure${NC}$(printf ' %.0s' $(seq 1 $((w - 35 - ${#stream_num}))))${PKT_BORDER}│${NC}"
    echo -e "  ${PKT_BORDER}├$(printf '─%.0s' $(seq 1 $((w-2))))┤${NC}"

    # L2 - Ethernet
    echo -e "  ${PKT_BORDER}│${NC} ${PKT_LABEL}${BOLD}L2 Ethernet${NC}$(printf ' %.0s' $(seq 1 $((w - 14))))${PKT_BORDER}│${NC}"
    printf "  ${PKT_BORDER}│${NC}   Dst MAC : ${PKT_VALUE}%-42s${NC}${PKT_BORDER}│${NC}\n" "$dst_mac"
    printf "  ${PKT_BORDER}│${NC}   Src MAC : ${PKT_VALUE}%-42s${NC}${PKT_BORDER}│${NC}\n" "$src_mac"
    printf "  ${PKT_BORDER}│${NC}   EtherType : ${PKT_VALUE}%-39s${NC}${PKT_BORDER}│${NC}\n" "0x0800 (IPv4)"
    echo -e "  ${PKT_BORDER}├$(printf '─%.0s' $(seq 1 $((w-2))))┤${NC}"

    # L3 - IPv4
    echo -e "  ${PKT_BORDER}│${NC} ${PKT_LABEL}${BOLD}L3 IPv4${NC}$(printf ' %.0s' $(seq 1 $((w - 10))))${PKT_BORDER}│${NC}"
    printf "  ${PKT_BORDER}│${NC}   Src IP    : ${PKT_VALUE}%-39s${NC}${PKT_BORDER}│${NC}\n" "$src_ip"
    printf "  ${PKT_BORDER}│${NC}   Dst IP    : ${PKT_VALUE}%-39s${NC}${PKT_BORDER}│${NC}\n" "$dst_ip"
    printf "  ${PKT_BORDER}│${NC}   DSCP      : ${PKT_VALUE}%-39s${NC}${PKT_BORDER}│${NC}\n" "${dscp_name^^} (${dscp_val}) [${dscp_bin}]"
    printf "  ${PKT_BORDER}│${NC}   TOS       : ${PKT_VALUE}%-39s${NC}${PKT_BORDER}│${NC}\n" "${tos_dec} (${tos_hex})"
    printf "  ${PKT_BORDER}│${NC}   TTL       : ${PKT_VALUE}%-39s${NC}${PKT_BORDER}│${NC}\n" "64"
    printf "  ${PKT_BORDER}│${NC}   Protocol  : ${PKT_VALUE}%-39s${NC}${PKT_BORDER}│${NC}\n" "${proto_num} (${proto_upper})"
    echo -e "  ${PKT_BORDER}├$(printf '─%.0s' $(seq 1 $((w-2))))┤${NC}"

    # L4
    echo -e "  ${PKT_BORDER}│${NC} ${PKT_LABEL}${BOLD}L4 ${proto_upper}${NC}$(printf ' %.0s' $(seq 1 $((w - 7 - ${#proto_upper}))))${PKT_BORDER}│${NC}"
    printf "  ${PKT_BORDER}│${NC}   Src Port  : ${PKT_VALUE}%-39s${NC}${PKT_BORDER}│${NC}\n" "ephemeral (49152-65535)"
    printf "  ${PKT_BORDER}│${NC}   Dst Port  : ${PKT_VALUE}%-39s${NC}${PKT_BORDER}│${NC}\n" "$dst_port"
    printf "  ${PKT_BORDER}│${NC}   Bandwidth : ${PKT_VALUE}%-39s${NC}${PKT_BORDER}│${NC}\n" "$bitrate"
    echo -e "  ${PKT_BORDER}└$(printf '─%.0s' $(seq 1 $((w-2))))┘${NC}"
}

# ============================================================================
# BAR GRAPH
# ============================================================================
draw_bar() {
    local value="$1"
    local max="$2"
    local width="${3:-30}"

    if [[ "$max" == "0" || -z "$max" ]]; then
        max=1
    fi

    local pct=$((value * 100 / max))
    if (( pct > 100 )); then pct=100; fi
    local filled=$((pct * width / 100))
    local empty=$((width - filled))

    local bar=""
    local i
    for (( i=0; i<filled; i++ )); do
        bar+="█"
    done
    for (( i=0; i<empty; i++ )); do
        bar+="░"
    done

    echo -e "${BAR_COLOR}${bar}${NC} ${WHITE}${pct}%${NC}"
}

# ============================================================================
# IN-PLACE BANDWIDTH MONITOR
# ============================================================================
start_bandwidth_monitor() {
    local log_file="$1"
    local label="$2"
    local target_bw="${3:-0}"  # target in Mbits for bar scaling
    local num_streams="${4:-1}"

    if [[ "$target_bw" == "0" || -z "$target_bw" ]]; then
        target_bw=1000
    fi

    # Background subshell that updates in-place
    (
        # Wait for log file to appear
        local wait_count=0
        while [[ ! -f "$log_file" ]]; do
            sleep 0.5
            wait_count=$((wait_count + 1))
            if (( wait_count > 60 )); then
                exit 0
            fi
        done

        local header_printed=0
        local display_lines=$((num_streams + 2))
        local last_bw=""

        tail -f "$log_file" 2>/dev/null | while IFS= read -r line; do
            # Parse iperf3 bandwidth lines: [  5]   0.00-1.00   sec  112 MBytes  941 Mbits/sec
            # Also handles: [ 4]   ... Mbits/sec  or Kbits/sec or Gbits/sec
            local bw_val=""
            local bw_unit=""

            if echo "$line" | grep -qP '\d+(\.\d+)?\s+(M|K|G)bits/sec'; then
                bw_val=$(echo "$line" | grep -oP '[\d.]+(?=\s+(M|K|G)bits/sec)' | tail -1 || true)
                bw_unit=$(echo "$line" | grep -oP '(M|K|G)bits/sec' | tail -1 || true)

                if [[ -n "$bw_val" && -n "$bw_unit" ]]; then
                    # Convert to Mbits
                    local bw_mbits
                    case "$bw_unit" in
                        Gbits/sec) bw_mbits=$(echo "$bw_val * 1000" | bc 2>/dev/null || echo "$bw_val");;
                        Mbits/sec) bw_mbits="$bw_val";;
                        Kbits/sec) bw_mbits=$(echo "scale=2; $bw_val / 1000" | bc 2>/dev/null || echo "0");;
                        *) bw_mbits="$bw_val";;
                    esac

                    # Convert to integer for bar
                    local bw_int
                    bw_int=$(printf "%.0f" "$bw_mbits" 2>/dev/null || echo "0")

                    # Skip if same as last (avoid flicker)
                    if [[ "$bw_int" == "$last_bw" ]]; then
                        continue
                    fi
                    last_bw="$bw_int"

                    local bar
                    bar=$(draw_bar "$bw_int" "$target_bw" 30)

                    # Move cursor up if we've printed before, erase line, rewrite
                    if (( header_printed == 1 )); then
                        # Move up 1 line, clear it
                        printf '\033[1A\033[2K'
                    fi

                    printf "\r  ${GREEN}●${NC} ${LABEL_COLOR}%-15s${NC} ${VALUE_COLOR}%8s Mbps${NC}  %s\n" \
                        "$label" "$bw_mbits" "$bar"

                    header_printed=1
                fi
            fi

            # Detect connection events
            if echo "$line" | grep -qi "connected to\|accepted connection"; then
                # Print above the bar — move up if needed, insert event line
                if (( header_printed == 1 )); then
                    printf '\033[1A\033[2K'
                fi
                echo -e "  ${INFO_COLOR}⚡${NC} ${DIM}$(date '+%H:%M:%S')${NC} ${line}"
                # Re-flag so next bar prints fresh
                header_printed=0
            fi

            # Detect completion
            if echo "$line" | grep -qi "iperf done\|sender\|receiver"; then
                if echo "$line" | grep -qP '\d+(\.\d+)?\s+(M|K|G)bits/sec'; then
                    # Final summary line
                    echo -e "  ${GREEN}✔${NC} ${WHITE}${BOLD}Final:${NC} ${line}"
                fi
            fi
        done
    ) &
    local mon_pid=$!
    MONITOR_PIDS+=("$mon_pid")
}

# Multi-stream in-place monitor: handles N streams each on their own line
start_multi_bandwidth_monitor() {
    local num_streams="$1"
    shift
    # Remaining args: pairs of (log_file, label, target_bw)
    local -a log_files=()
    local -a labels=()
    local -a targets=()

    while (( $# >= 3 )); do
        log_files+=("$1")
        labels+=("$2")
        targets+=("$3")
        shift 3
    done

    (
        # Wait for at least one log file
        local wait_count=0
        local any_exists=0
        while (( any_exists == 0 )); do
            for lf in "${log_files[@]}"; do
                if [[ -f "$lf" ]]; then
                    any_exists=1
                    break
                fi
            done
            sleep 0.5
            wait_count=$((wait_count + 1))
            if (( wait_count > 60 )); then
                exit 0
            fi
        done

        # Print initial placeholder lines
        echo ""
        echo -e "  ${ACCENT_COLOR}── ${WHITE}${BOLD}Live Bandwidth Monitor ${ACCENT_COLOR}$(printf '─%.0s' $(seq 1 35))${NC}"
        for (( s=0; s<num_streams; s++ )); do
            printf "  ${DIM}●${NC} ${LABEL_COLOR}%-15s${NC} ${DIM}waiting...${NC}\n" "${labels[$s]}"
        done
        local printed_lines=$((num_streams))

        # Last known values
        local -a last_bw=()
        for (( s=0; s<num_streams; s++ )); do
            last_bw+=("0")
        done

        # Polling loop
        while true; do
            local any_update=0

            for (( s=0; s<num_streams; s++ )); do
                local lf="${log_files[$s]}"
                if [[ ! -f "$lf" ]]; then
                    continue
                fi

                # Get last bandwidth line
                local last_line
                last_line=$(grep -P '\d+(\.\d+)?\s+(M|K|G)bits/sec' "$lf" 2>/dev/null | tail -1 || true)
                if [[ -z "$last_line" ]]; then
                    continue
                fi

                local bw_val
                bw_val=$(echo "$last_line" | grep -oP '[\d.]+(?=\s+(M|K|G)bits/sec)' | tail -1 || true)
                local bw_unit
                bw_unit=$(echo "$last_line" | grep -oP '(M|K|G)bits/sec' | tail -1 || true)

                if [[ -n "$bw_val" && -n "$bw_unit" ]]; then
                    local bw_mbits
                    case "$bw_unit" in
                        Gbits/sec) bw_mbits=$(echo "$bw_val * 1000" | bc 2>/dev/null || echo "$bw_val");;
                        Mbits/sec) bw_mbits="$bw_val";;
                        Kbits/sec) bw_mbits=$(echo "scale=2; $bw_val / 1000" | bc 2>/dev/null || echo "0");;
                        *) bw_mbits="$bw_val";;
                    esac

                    local bw_int
                    bw_int=$(printf "%.0f" "$bw_mbits" 2>/dev/null || echo "0")

                    if [[ "$bw_int" != "${last_bw[$s]}" ]]; then
                        last_bw[$s]="$bw_int"
                        any_update=1
                    fi
                fi
            done

            if (( any_update == 1 )); then
                # Move cursor up N lines
                printf "\033[${printed_lines}A"

                for (( s=0; s<num_streams; s++ )); do
                    local tgt="${targets[$s]}"
                    if [[ "$tgt" == "0" || -z "$tgt" ]]; then tgt=1000; fi
                    local bw_int="${last_bw[$s]}"
                    local bar
                    bar=$(draw_bar "$bw_int" "$tgt" 30)
                    # Clear line and print
                    printf "\033[2K\r  ${GREEN}●${NC} ${LABEL_COLOR}%-15s${NC} ${VALUE_COLOR}%8s Mbps${NC}  %s\n" \
                        "${labels[$s]}" "${bw_int}" "$bar"
                done
            fi

            sleep 1

            # Check if any iperf3 is still running
            local any_alive=0
            for pid in "${PIDS[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    any_alive=1
                    break
                fi
            done
            if (( any_alive == 0 )); then
                sleep 2  # Final read
                # Print final summary
                printf "\033[${printed_lines}A"
                for (( s=0; s<num_streams; s++ )); do
                    local lf="${log_files[$s]}"
                    local final_line=""
                    if [[ -f "$lf" ]]; then
                        final_line=$(grep -P '(sender|receiver)' "$lf" 2>/dev/null | tail -1 || true)
                    fi
                    local tgt="${targets[$s]}"
                    if [[ "$tgt" == "0" || -z "$tgt" ]]; then tgt=1000; fi
                    local bw_int="${last_bw[$s]}"
                    local bar
                    bar=$(draw_bar "$bw_int" "$tgt" 30)
                    printf "\033[2K\r  ${GREEN}✔${NC} ${LABEL_COLOR}%-15s${NC} ${VALUE_COLOR}%8s Mbps${NC}  %s ${DIM}(done)${NC}\n" \
                        "${labels[$s]}" "${bw_int}" "$bar"
                done
                echo ""
                echo -e "  ${GREEN}✔${NC} ${WHITE}${BOLD}All streams completed${NC}"
                break
            fi
        done
    ) &
    local mon_pid=$!
    MONITOR_PIDS+=("$mon_pid")
}

# ============================================================================
# SCRIPT BUILDERS
# ============================================================================
build_server_script() {
    local script_file="$1"
    local port="$2"
    local bind_ip="$3"
    local vrf="$4"
    local log_file="$5"
    local one_off="${6:-no}"

    cat > "$script_file" << 'SCRIPT_HEADER'
#!/usr/bin/env bash
SCRIPT_HEADER

    # VRF sysctl check
    if [[ -n "$vrf" && "$vrf" != "" ]]; then
        cat >> "$script_file" << VRFCHECK
# VRF sysctl checks
sysctl -w net.ipv4.tcp_l3mdev_accept=1 2>/dev/null || true
sysctl -w net.ipv4.udp_l3mdev_accept=1 2>/dev/null || true
VRFCHECK
    fi

    # Build command
    local cmd=""
    if [[ -n "$vrf" && "$vrf" != "" ]]; then
        cmd="ip vrf exec ${vrf} "
    fi
    cmd+="iperf3 -s"
    cmd+=" -p ${port}"
    if [[ -n "$bind_ip" && "$bind_ip" != "0.0.0.0" ]]; then
        cmd+=" --bind ${bind_ip}"
    fi
    cmd+=" -i 1 --forceflush"
    if [[ "$one_off" == "yes" ]]; then
        cmd+=" -1"
    fi

    cat >> "$script_file" << SCRIPT_CMD
exec ${cmd} >> "${log_file}" 2>&1
SCRIPT_CMD

    chmod +x "$script_file"
}

build_client_script() {
    local script_file="$1"
    local server_ip="$2"
    local port="$3"
    local protocol="$4"   # tcp or udp
    local bitrate="$5"    # e.g., 100M, 1G, 0 for unlimited
    local duration="$6"
    local dscp_name="$7"
    local congestion="$8"
    local reverse="$9"
    local bind_ip="${10:-}"
    local vrf="${11:-}"
    local log_file="${12}"

    cat > "$script_file" << 'SCRIPT_HEADER'
#!/usr/bin/env bash
SCRIPT_HEADER

    if [[ -n "$vrf" && "$vrf" != "" ]]; then
        cat >> "$script_file" << VRFCHECK
sysctl -w net.ipv4.tcp_l3mdev_accept=1 2>/dev/null || true
sysctl -w net.ipv4.udp_l3mdev_accept=1 2>/dev/null || true
VRFCHECK
    fi

    local cmd=""
    if [[ -n "$vrf" && "$vrf" != "" ]]; then
        cmd="ip vrf exec ${vrf} "
    fi
    cmd+="iperf3 -c ${server_ip}"
    cmd+=" -p ${port}"

    if [[ "${protocol,,}" == "udp" ]]; then
        cmd+=" -u"
    fi

    if [[ -n "$bitrate" && "$bitrate" != "0" ]]; then
        cmd+=" -b ${bitrate}"
    fi

    if [[ -n "$duration" && "$duration" != "0" ]]; then
        cmd+=" -t ${duration}"
    fi

    # DSCP via -S (TOS value)
    if [[ -n "$dscp_name" && "$dscp_name" != "default" && "$dscp_name" != "" ]]; then
        local tos_val="${DSCP_MAP[${dscp_name,,}]:-}"
        if [[ -n "$tos_val" && "$tos_val" != "0" ]]; then
            cmd+=" -S ${tos_val}"
        fi
    fi

    if [[ -n "$congestion" && "$congestion" != "" && "$congestion" != "default" ]]; then
        cmd+=" -C ${congestion}"
    fi

    if [[ "$reverse" == "yes" ]]; then
        cmd+=" -R"
    fi

    if [[ -n "$bind_ip" && "$bind_ip" != "0.0.0.0" && "$bind_ip" != "" ]]; then
        cmd+=" --bind ${bind_ip}"
    fi

    cmd+=" -i 1 --forceflush"

    cat >> "$script_file" << SCRIPT_CMD
exec ${cmd} >> "${log_file}" 2>&1
SCRIPT_CMD

    chmod +x "$script_file"
}

# ============================================================================
# STREAM CONFIGURATION
# ============================================================================
configure_stream() {
    local stream_num="$1"
    local total_streams="$2"

    print_section "Configure Stream #${stream_num} of ${total_streams}"

    # Protocol
    echo -e "  ${MENU_NUM}1)${NC} TCP"
    echo -e "  ${MENU_NUM}2)${NC} UDP"
    prompt_input "Protocol" PROTO_CHOICE "1"
    local proto="tcp"
    if [[ "$PROTO_CHOICE" == "2" ]]; then
        proto="udp"
    fi

    # Port
    local default_port=$((5201 + stream_num - 1))
    prompt_input "Destination port" STREAM_PORT "$default_port"

    # Bitrate
    prompt_input "Bitrate (e.g., 100M, 1G, 0=unlimited)" STREAM_BITRATE "100M"

    # Duration
    prompt_input "Duration (seconds)" STREAM_DURATION "10"

    # DSCP
    echo ""
    echo -e "  ${DIM}Common: default, ef, af11, af21, af31, af41, cs1-cs7${NC}"
    echo -e "  ${DIM}Type 'list' to see full DSCP table${NC}"
    prompt_input "DSCP class" STREAM_DSCP "default"
    if [[ "${STREAM_DSCP,,}" == "list" ]]; then
        show_dscp_table
        prompt_input "DSCP class" STREAM_DSCP "default"
    fi

    # Validate DSCP
    if [[ -z "${DSCP_MAP[${STREAM_DSCP,,}]:-}" ]]; then
        print_warn "Unknown DSCP '${STREAM_DSCP}', using 'default'"
        STREAM_DSCP="default"
    fi

    # Congestion control (TCP only)
    local cong="default"
    if [[ "$proto" == "tcp" ]]; then
        local available_cc
        available_cc=$(cat /proc/sys/net/ipv4/tcp_allowed_congestion_control 2>/dev/null || echo "cubic reno")
        echo -e "  ${DIM}Available: ${available_cc}${NC}"
        prompt_input "Congestion control" cong "cubic"
    fi

    # Reverse mode
    prompt_input "Reverse mode (server sends)? (y/n)" REV_CHOICE "n"
    local rev="no"
    if [[ "$REV_CHOICE" =~ ^[Yy] ]]; then
        rev="yes"
    fi

    # Store config
    S_PROTO[$stream_num]="$proto"
    S_PORT[$stream_num]="$STREAM_PORT"
    S_BITRATE[$stream_num]="$STREAM_BITRATE"
    S_DURATION[$stream_num]="$STREAM_DURATION"
    S_DSCP[$stream_num]="${STREAM_DSCP,,}"
    S_CONGESTION[$stream_num]="$cong"
    S_REVERSE[$stream_num]="$rev"
    S_LABEL[$stream_num]="S${stream_num}:${proto^^}:${STREAM_PORT}"

    print_success "Stream #${stream_num} configured: ${VALUE_COLOR}${proto^^}${NC} port ${VALUE_COLOR}${STREAM_PORT}${NC} @ ${VALUE_COLOR}${STREAM_BITRATE}${NC} DSCP=${VALUE_COLOR}${STREAM_DSCP}${NC}"
}

# ============================================================================
# SERVER MODE
# ============================================================================
run_server_mode() {
    print_header "Server Mode"

    select_interface "Bind to interface"
    local bind_ip="$SELECTED_IP"
    local vrf="$SELECTED_VRF"

    prompt_input "Number of server ports" NUM_PORTS "1"
    prompt_input "Starting port" START_PORT "5201"
    prompt_input "One-off mode (exit after one client)? (y/n)" ONE_OFF "n"
    local one_off="no"
    if [[ "$ONE_OFF" =~ ^[Yy] ]]; then
        one_off="yes"
    fi

    print_section "Launching Servers"

    for (( i=0; i<NUM_PORTS; i++ )); do
        local port=$((START_PORT + i))
        local script_file="${SCRIPT_DIR}/server_${port}.sh"
        local log_file="${LOG_DIR}/server_${port}.log"

        : > "$log_file"

        build_server_script "$script_file" "$port" "$bind_ip" "$vrf" "$log_file" "$one_off"

        bash "$script_file" &
        local pid=$!
        PIDS+=("$pid")

        print_success "Server on port ${VALUE_COLOR}${port}${NC} (PID: ${pid})"

        # Start single-stream monitor for each server port
        start_bandwidth_monitor "$log_file" "Server:${port}" "1000"
    done

    print_info "Servers running. Press Enter to stop..."
    read -r
    cleanup_all
}

# ============================================================================
# CLIENT MODE (single stream)
# ============================================================================
run_client_mode() {
    print_header "Client Mode"

    prompt_input "Server IP address" SERVER_IP "127.0.0.1"

    select_interface "Bind to interface (source)"
    local bind_ip="$SELECTED_IP"
    local src_ip="$bind_ip"
    local vrf="$SELECTED_VRF"

    if [[ "$src_ip" == "0.0.0.0" ]]; then
        src_ip="(auto)"
    fi

    configure_stream 1 1

    local proto="${S_PROTO[1]}"
    local port="${S_PORT[1]}"
    local bitrate="${S_BITRATE[1]}"
    local duration="${S_DURATION[1]}"
    local dscp="${S_DSCP[1]}"
    local cong="${S_CONGESTION[1]}"
    local rev="${S_REVERSE[1]}"

    # --- Packet Visualization ---
    draw_packet_detail "1" "$proto" "$src_ip" "$SERVER_IP" "$port" "$dscp" "$bitrate"

    # Confirm launch
    echo ""
    echo -ne "  ${PROMPT_COLOR}▶${NC} Launch this stream? (y/n): "
    local confirm
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        print_warn "Cancelled"
        return
    fi

    print_section "Launching Client"

    local script_file="${SCRIPT_DIR}/client_1.sh"
    local log_file="${LOG_DIR}/client_1.log"
    : > "$log_file"

    build_client_script "$script_file" "$SERVER_IP" "$port" "$proto" \
        "$bitrate" "$duration" "$dscp" "$cong" "$rev" "$bind_ip" "$vrf" "$log_file"

    bash "$script_file" &
    local pid=$!
    PIDS+=("$pid")
    print_success "Client PID: ${pid}"

    # Parse target Mbps for bar scaling
    local target_mbps=1000
    if [[ "$bitrate" =~ ^([0-9]+)[Mm]$ ]]; then
        target_mbps="${BASH_REMATCH[1]}"
    elif [[ "$bitrate" =~ ^([0-9]+)[Gg]$ ]]; then
        target_mbps=$(( ${BASH_REMATCH[1]} * 1000 ))
    elif [[ "$bitrate" =~ ^([0-9]+)[Kk]$ ]]; then
        target_mbps=1
    fi

    start_bandwidth_monitor "$log_file" "${S_LABEL[1]}" "$target_mbps"

    # Wait for completion
    echo ""
    print_info "Stream running for ${duration}s... (Press Enter to abort)"
    read -t "$((duration + 5))" -r || true

    # Wait for iperf3 to finish
    wait "$pid" 2>/dev/null || true
    sleep 1

    print_section "Results"
    if [[ -f "$log_file" ]]; then
        # Show summary lines
        grep -E '(sender|receiver|iperf Done)' "$log_file" 2>/dev/null | while IFS= read -r line; do
            echo -e "  ${VALUE_COLOR}${line}${NC}"
        done
    fi
}

# ============================================================================
# MULTI-STREAM MODE
# ============================================================================
run_multi_stream_mode() {
    print_header "Multi-Stream Mode"

    prompt_input "Server IP address" SERVER_IP "127.0.0.1"

    select_interface "Bind to interface (source)"
    local bind_ip="$SELECTED_IP"
    local src_ip="$bind_ip"
    local vrf="$SELECTED_VRF"

    if [[ "$src_ip" == "0.0.0.0" ]]; then
        src_ip="(auto)"
    fi

    prompt_input "Number of streams" NUM_STREAMS "2"

    if ! [[ "$NUM_STREAMS" =~ ^[0-9]+$ ]] || (( NUM_STREAMS < 1 || NUM_STREAMS > 20 )); then
        print_warn "Invalid number. Using 2."
        NUM_STREAMS=2
    fi

    # Configure each stream
    for (( s=1; s<=NUM_STREAMS; s++ )); do
        configure_stream "$s" "$NUM_STREAMS"
    done

    # --- Packet Visualization for ALL streams ---
    print_section "Packet Format Preview"
    for (( s=1; s<=NUM_STREAMS; s++ )); do
        draw_packet_detail "$s" "${S_PROTO[$s]}" "$src_ip" "$SERVER_IP" \
            "${S_PORT[$s]}" "${S_DSCP[$s]}" "${S_BITRATE[$s]}"
    done

    # Summary table
    print_section "Stream Summary"
    printf "  ${LABEL_COLOR}%-6s %-6s %-7s %-10s %-8s %-8s %-10s %-5s${NC}\n" \
        "Stream" "Proto" "Port" "Bitrate" "DSCP" "TOS" "Congestion" "Rev"
    echo -e "  ${BORDER_COLOR}$(printf '─%.0s' $(seq 1 62))${NC}"
    for (( s=1; s<=NUM_STREAMS; s++ )); do
        local tos_val="${DSCP_MAP[${S_DSCP[$s]}]:-0}"
        local tos_hex
        tos_hex=$(printf "0x%02X" "$tos_val")
        printf "  ${VALUE_COLOR}%-6s${NC} %-6s %-7s %-10s %-8s %-8s %-10s %-5s\n" \
            "#${s}" "${S_PROTO[$s]^^}" "${S_PORT[$s]}" "${S_BITRATE[$s]}" \
            "${S_DSCP[$s]}" "${tos_hex}" "${S_CONGESTION[$s]}" "${S_REVERSE[$s]}"
    done

    # Confirm launch
    echo ""
    echo -ne "  ${PROMPT_COLOR}▶${NC} Launch all ${NUM_STREAMS} streams? (y/n): "
    local confirm
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        print_warn "Cancelled"
        return
    fi

    print_section "Launching Streams"

    local -a log_files=()
    local -a labels=()
    local -a target_list=()

    for (( s=1; s<=NUM_STREAMS; s++ )); do
        local script_file="${SCRIPT_DIR}/client_stream_${s}.sh"
        local log_file="${LOG_DIR}/client_stream_${s}.log"
        : > "$log_file"

        build_client_script "$script_file" "$SERVER_IP" "${S_PORT[$s]}" \
            "${S_PROTO[$s]}" "${S_BITRATE[$s]}" "${S_DURATION[$s]}" \
            "${S_DSCP[$s]}" "${S_CONGESTION[$s]}" "${S_REVERSE[$s]}" \
            "$bind_ip" "$vrf" "$log_file"

        bash "$script_file" &
        local pid=$!
        PIDS+=("$pid")
        print_success "Stream #${s} launched (PID: ${pid})"

        log_files+=("$log_file")
        labels+=("${S_LABEL[$s]}")

        # Parse target for bar
        local target_mbps=1000
        local br="${S_BITRATE[$s]}"
        if [[ "$br" =~ ^([0-9]+)[Mm]$ ]]; then
            target_mbps="${BASH_REMATCH[1]}"
        elif [[ "$br" =~ ^([0-9]+)[Gg]$ ]]; then
            target_mbps=$(( ${BASH_REMATCH[1]} * 1000 ))
        elif [[ "$br" =~ ^([0-9]+)[Kk]$ ]]; then
            target_mbps=1
        fi
        target_list+=("$target_mbps")
    done

    # Build args for multi-monitor
    local -a mon_args=()
    for (( s=0; s<NUM_STREAMS; s++ )); do
        mon_args+=("${log_files[$s]}" "${labels[$s]}" "${target_list[$s]}")
    done

    start_multi_bandwidth_monitor "$NUM_STREAMS" "${mon_args[@]}"

    # Find max duration
    local max_dur=10
    for (( s=1; s<=NUM_STREAMS; s++ )); do
        if (( S_DURATION[$s] > max_dur )); then
            max_dur="${S_DURATION[$s]}"
        fi
    done

    echo ""
    print_info "Streams running (max ${max_dur}s)... Press Enter to abort."
    read -t "$((max_dur + 10))" -r || true

    # Wait for all pids
    for pid in "${PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    sleep 2

    # Show final results
    print_section "Final Results"
    for (( s=1; s<=NUM_STREAMS; s++ )); do
        local lf="${LOG_DIR}/client_stream_${s}.log"
        echo -e "  ${ACCENT_COLOR}── Stream #${s} (${S_LABEL[$s]}) ──${NC}"
        if [[ -f "$lf" ]]; then
            grep -E '(sender|receiver)' "$lf" 2>/dev/null | while IFS= read -r line; do
                echo -e "    ${VALUE_COLOR}${line}${NC}"
            done
        fi
    done
}

# ============================================================================
# CONGESTION COMPARISON MODE
# ============================================================================
run_congestion_comparison() {
    print_header "Congestion Algorithm Comparison"

    local available_cc
    available_cc=$(cat /proc/sys/net/ipv4/tcp_allowed_congestion_control 2>/dev/null || echo "cubic reno")
    print_info "Available algorithms: ${VALUE_COLOR}${available_cc}${NC}"

    prompt_input "Server IP" SERVER_IP "127.0.0.1"
    prompt_input "Port" CMP_PORT "5201"
    prompt_input "Bitrate" CMP_BITRATE "100M"
    prompt_input "Duration per test (seconds)" CMP_DURATION "10"

    echo ""
    echo -e "  ${DIM}Enter algorithms to compare, space-separated${NC}"
    prompt_input "Algorithms" CMP_ALGOS "cubic reno bbr"

    read -ra algo_list <<< "$CMP_ALGOS"

    print_section "Running Comparison"

    local -a results=()

    for algo in "${algo_list[@]}"; do
        print_info "Testing ${VALUE_COLOR}${algo}${NC}..."

        local script_file="${SCRIPT_DIR}/cmp_${algo}.sh"
        local log_file="${LOG_DIR}/cmp_${algo}.log"
        : > "$log_file"

        build_client_script "$script_file" "$SERVER_IP" "$CMP_PORT" \
            "tcp" "$CMP_BITRATE" "$CMP_DURATION" "default" "$algo" "no" "" "" "$log_file"

        bash "$script_file" &
        local pid=$!

        start_bandwidth_monitor "$log_file" "$algo" "1000"

        wait "$pid" 2>/dev/null || true
        sleep 1

        # Extract sender result
        local sender_line
        sender_line=$(grep -i "sender" "$log_file" 2>/dev/null | tail -1 || true)
        local sender_bw="N/A"
        if [[ -n "$sender_line" ]]; then
            sender_bw=$(echo "$sender_line" | grep -oP '[\d.]+\s+(M|K|G)bits/sec' | tail -1 || echo "N/A")
        fi
        results+=("${algo}:${sender_bw}")

        # Kill monitor
        for mpid in "${MONITOR_PIDS[@]}"; do
            kill "$mpid" 2>/dev/null || true
        done
        MONITOR_PIDS=()

        echo ""
    done

    # Summary
    print_section "Comparison Results"
    printf "  ${LABEL_COLOR}%-15s %-20s${NC}\n" "Algorithm" "Bandwidth"
    echo -e "  ${BORDER_COLOR}$(printf '─%.0s' $(seq 1 36))${NC}"
    for entry in "${results[@]}"; do
        local a="${entry%%:*}"
        local b="${entry#*:}"
        printf "  ${VALUE_COLOR}%-15s${NC} %-20s\n" "$a" "$b"
    done
}

# ============================================================================
# QUICK LOOPBACK TEST
# ============================================================================
run_loopback_test() {
    print_header "Quick Loopback Test"

    prompt_input "Protocol (tcp/udp)" LB_PROTO "tcp"
    prompt_input "Bitrate" LB_BITRATE "100M"
    prompt_input "Duration" LB_DURATION "5"
    prompt_input "DSCP" LB_DSCP "default"

    local port=5201
    local server_script="${SCRIPT_DIR}/lb_server.sh"
    local server_log="${LOG_DIR}/lb_server.log"
    local client_script="${SCRIPT_DIR}/lb_client.sh"
    local client_log="${LOG_DIR}/lb_client.log"

    : > "$server_log"
    : > "$client_log"

    # Build and start server
    build_server_script "$server_script" "$port" "127.0.0.1" "" "$server_log" "yes"
    bash "$server_script" &
    local srv_pid=$!
    PIDS+=("$srv_pid")
    print_success "Loopback server started (PID: ${srv_pid})"

    sleep 1

    # Draw packet
    draw_packet_detail "1" "$LB_PROTO" "127.0.0.1" "127.0.0.1" "$port" "$LB_DSCP" "$LB_BITRATE"

    # Build and start client
    build_client_script "$client_script" "127.0.0.1" "$port" "$LB_PROTO" \
        "$LB_BITRATE" "$LB_DURATION" "$LB_DSCP" "default" "no" "" "" "$client_log"

    bash "$client_script" &
    local cli_pid=$!
    PIDS+=("$cli_pid")
    print_success "Loopback client started (PID: ${cli_pid})"

    start_bandwidth_monitor "$client_log" "Loopback" "1000"

    wait "$cli_pid" 2>/dev/null || true
    sleep 1
    kill "$srv_pid" 2>/dev/null || true

    print_section "Results"
    if [[ -f "$client_log" ]]; then
        grep -E '(sender|receiver)' "$client_log" 2>/dev/null | while IFS= read -r line; do
            echo -e "  ${VALUE_COLOR}${line}${NC}"
        done
    fi
}

# ============================================================================
# LOG MANAGEMENT
# ============================================================================
manage_logs() {
    print_header "Log Management"

    echo -e "  ${MENU_NUM}1)${NC} ${MENU_TEXT}View logs${NC}"
    echo -e "  ${MENU_NUM}2)${NC} ${MENU_TEXT}Clear all logs${NC}"
    echo -e "  ${MENU_NUM}3)${NC} ${MENU_TEXT}Export logs${NC}"
    echo -e "  ${MENU_NUM}4)${NC} ${MENU_TEXT}Back${NC}"
    echo ""
    prompt_input "Choice" LOG_CHOICE "1"

    case "$LOG_CHOICE" in
        1)
            local logs
            logs=$(ls -1 "$LOG_DIR"/*.log 2>/dev/null || true)
            if [[ -z "$logs" ]]; then
                print_info "No logs found"
            else
                echo ""
                local idx=0
                local -a log_arr=()
                while IFS= read -r lf; do
                    idx=$((idx + 1))
                    local size
                    size=$(wc -c < "$lf" 2>/dev/null || echo "0")
                    echo -e "  ${MENU_NUM}${idx})${NC} $(basename "$lf") ${DIM}(${size} bytes)${NC}"
                    log_arr+=("$lf")
                done <<< "$logs"
                echo ""
                prompt_input "View log number (0 to cancel)" LOG_VIEW "0"
                if [[ "$LOG_VIEW" =~ ^[0-9]+$ ]] && (( LOG_VIEW >= 1 && LOG_VIEW <= ${#log_arr[@]} )); then
                    echo ""
                    echo -e "  ${BORDER_COLOR}$(printf '─%.0s' $(seq 1 60))${NC}"
                    cat "${log_arr[$((LOG_VIEW - 1))]}"
                    echo -e "  ${BORDER_COLOR}$(printf '─%.0s' $(seq 1 60))${NC}"
                fi
            fi
            ;;
        2)
            rm -f "$LOG_DIR"/*.log 2>/dev/null || true
            print_success "All logs cleared"
            ;;
        3)
            local export_dir="${HOME}/iperf3_logs_$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$export_dir"
            cp "$LOG_DIR"/*.log "$export_dir/" 2>/dev/null || true
            print_success "Logs exported to ${VALUE_COLOR}${export_dir}${NC}"
            ;;
        4) return ;;
    esac
}

# ============================================================================
# MAIN MENU
# ============================================================================
main_menu() {
    while true; do
        print_header "iperf3 Multi-Stream Traffic Manager v6.2"
        echo ""
        echo -e "  ${MENU_NUM}1)${NC} ${MENU_TEXT}Check / Install iperf3${NC}"
        echo -e "  ${MENU_NUM}2)${NC} ${MENU_TEXT}Server Mode${NC}"
        echo -e "  ${MENU_NUM}3)${NC} ${MENU_TEXT}Client Mode (Single Stream)${NC}"
        echo -e "  ${MENU_NUM}4)${NC} ${MENU_TEXT}Client Mode (Multi-Stream)${NC}"
        echo -e "  ${MENU_NUM}5)${NC} ${MENU_TEXT}Congestion Algorithm Comparison${NC}"
        echo -e "  ${MENU_NUM}6)${NC} ${MENU_TEXT}Quick Loopback Test${NC}"
        echo -e "  ${MENU_NUM}7)${NC} ${MENU_TEXT}DSCP Reference Table${NC}"
        echo -e "  ${MENU_NUM}8)${NC} ${MENU_TEXT}Log Management${NC}"
        echo -e "  ${MENU_NUM}9)${NC} ${MENU_TEXT}Network Interfaces & VRF${NC}"
        echo -e "  ${MENU_NUM}0)${NC} ${MENU_TEXT}Exit${NC}"
        echo ""
        prompt_input "Select option" MENU_CHOICE ""

        case "$MENU_CHOICE" in
            1) check_iperf3; press_enter ;;
            2) run_server_mode; press_enter ;;
            3) run_client_mode; press_enter ;;
            4) run_multi_stream_mode; press_enter ;;
            5) run_congestion_comparison; press_enter ;;
            6) run_loopback_test; press_enter ;;
            7) show_dscp_table; press_enter ;;
            8) manage_logs; press_enter ;;
            9)
                build_vrf_maps
                list_interfaces
                if [[ ${#VRF_DEVICE_MAP[@]} -gt 0 ]]; then
                    print_section "VRF Devices"
                    for vrf in "${!VRF_DEVICE_MAP[@]}"; do
                        print_info "${VALUE_COLOR}${vrf}${NC}"
                    done
                    print_section "VRF Interface Mappings"
                    for iface in "${!VRF_IFACE_MAP[@]}"; do
                        print_info "${iface} → ${VALUE_COLOR}${VRF_IFACE_MAP[$iface]}${NC}"
                    done
                else
                    print_info "No VRF devices detected"
                fi
                press_enter
                ;;
            0)
                echo -e "\n  ${GREEN}Goodbye!${NC}\n"
                exit 0
                ;;
            *)
                print_warn "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# ============================================================================
# ENTRY POINT
# ============================================================================
init_dscp_map
build_vrf_maps
main_menu