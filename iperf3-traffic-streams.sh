#!/usr/bin/env bash
# =============================================================================
# iperf3-traffic-streams.sh — Enterprise-grade iperf3 multi-stream traffic manager
# Version: 8.2.1.1
# Author : Waqas Daar (waqasdaar@gmail.com)
# =============================================================================

# =============================================================================
# BOOTSTRAP — OS and Bash version detection
# MUST run before any declare -A or other bash 4+ syntax.
# =============================================================================

OS_TYPE="linux"
BASH_MAJOR="${BASH_VERSINFO[0]:-3}"

_bootstrap_detect() {
    local raw_os
    raw_os=$(uname -s 2>/dev/null)
    case "$raw_os" in
        Darwin) OS_TYPE="macos" ;;
        Linux*)  OS_TYPE="linux" ;;
        *)        OS_TYPE="linux" ;;
    esac
    BASH_MAJOR="${BASH_VERSINFO[0]:-3}"
}

_bootstrap_detect

# =============================================================================
# ASSOCIATIVE ARRAY COMPATIBILITY LAYER
# =============================================================================

if (( BASH_MAJOR >= 4 )); then
    declare -A IFACE_TO_VRF=()
    declare -A VRF_MASTERS=()
    declare -A PMTU_RESULTS=()
    declare -A PMTU_STATUS=()
    declare -A PMTU_RECOMMEND=()
else
    declare -a _ASSOC_KEYS_IFACE_TO_VRF=()
    declare -a _ASSOC_VALS_IFACE_TO_VRF=()
    declare -a _ASSOC_KEYS_VRF_MASTERS=()
    declare -a _ASSOC_VALS_VRF_MASTERS=()
fi

_assoc_set() {
    local name="$1" key="$2" val="$3"
    local keys_var="_ASSOC_KEYS_${name}"
    local vals_var="_ASSOC_VALS_${name}"
    local i
    eval "local klen=\${#${keys_var}[@]}"
    for (( i=0; i<klen; i++ )); do
        eval "local k=\"\${${keys_var}[$i]}\""
        if [[ "$k" == "$key" ]]; then
            eval "${vals_var}[$i]=\"\$val\""
            return
        fi
    done
    eval "${keys_var}+=(\"$key\")"
    eval "${vals_var}+=(\"$val\")"
}

_assoc_get() {
    local name="$1" key="$2"
    local keys_var="_ASSOC_KEYS_${name}"
    local vals_var="_ASSOC_VALS_${name}"
    local i
    eval "local klen=\${#${keys_var}[@]}"
    for (( i=0; i<klen; i++ )); do
        eval "local k=\"\${${keys_var}[$i]}\""
        if [[ "$k" == "$key" ]]; then
            eval "printf '%s' \"\${${vals_var}[$i]}\""
            return
        fi
    done
    printf '%s' ""
}

_assoc_has() {
    local name="$1" key="$2"
    local keys_var="_ASSOC_KEYS_${name}"
    local i
    eval "local klen=\${#${keys_var}[@]}"
    for (( i=0; i<klen; i++ )); do
        eval "local k=\"\${${keys_var}[$i]}\""
        [[ "$k" == "$key" ]] && return 0
    done
    return 1
}

_assoc_clear() {
    local name="$1"
    eval "_ASSOC_KEYS_${name}=()"
    eval "_ASSOC_VALS_${name}=()"
}

_iface_to_vrf_set() {
    (( BASH_MAJOR >= 4 )) && IFACE_TO_VRF["$1"]="$2"  || _assoc_set  "IFACE_TO_VRF" "$1" "$2"
}
_iface_to_vrf_get() {
    (( BASH_MAJOR >= 4 )) && printf '%s' "${IFACE_TO_VRF[$1]:-}" || _assoc_get "IFACE_TO_VRF" "$1"
}
_iface_to_vrf_has() {
    (( BASH_MAJOR >= 4 )) && [[ -n "${IFACE_TO_VRF[$1]+x}" ]] || _assoc_has "IFACE_TO_VRF" "$1"
}
_iface_to_vrf_clear() {
    (( BASH_MAJOR >= 4 )) && IFACE_TO_VRF=() || _assoc_clear "IFACE_TO_VRF"
}
_vrf_masters_set() {
    (( BASH_MAJOR >= 4 )) && VRF_MASTERS["$1"]="$2"   || _assoc_set  "VRF_MASTERS"  "$1" "$2"
}
_vrf_masters_has() {
    (( BASH_MAJOR >= 4 )) && [[ -n "${VRF_MASTERS[$1]+x}" ]] || _assoc_has "VRF_MASTERS"  "$1"
}
_vrf_masters_clear() {
    (( BASH_MAJOR >= 4 )) && VRF_MASTERS=() || _assoc_clear "VRF_MASTERS"
}

# =============================================================================
# COLOUR CONSTANTS
# =============================================================================

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
NC=$'\033[0m'

_LEN_RED=0; _LEN_GREEN=0; _LEN_YELLOW=0; _LEN_BLUE=0
_LEN_CYAN=0; _LEN_BOLD=0; _LEN_NC=0

_init_ansi_lengths() {
    _LEN_RED=${#RED};   _LEN_GREEN=${#GREEN};   _LEN_YELLOW=${#YELLOW}
    _LEN_BLUE=${#BLUE}; _LEN_CYAN=${#CYAN};     _LEN_BOLD=${#BOLD}
    _LEN_NC=${#NC}
}

COLS=80
IPERF3_BIN=""
IPERF3_MAJOR=0; IPERF3_MINOR=0; IPERF3_PATCH=0
FORCEFLUSH_SUPPORTED=0
NOFQ_SUPPORTED=0
IS_ROOT=0
TMPDIR=""
CLEANUP_DONE=0

declare -a STREAM_PIDS=()
declare -a SERVER_PIDS=()
declare -a NETEM_IFACES=()

declare -a S_PROTO=()
declare -a S_TARGET=()
declare -a S_PORT=()
declare -a S_BW=()
declare -a S_DURATION=()
declare -a S_DSCP_NAME=()
declare -a S_DSCP_VAL=()
declare -a S_PARALLEL=()
declare -a S_REVERSE=()
declare -a S_CCA=()
declare -a S_WINDOW=()
declare -a S_MSS=()
declare -a S_BIND=()
declare -a S_VRF=()
declare -a S_DELAY=()
declare -a S_JITTER=()
declare -a S_LOSS=()
declare -a S_NOFQ=()
declare -a S_LOGFILE=()
declare -a S_SCRIPT=()
declare -a S_START_TS=()
declare -a S_STATUS_CACHE=()
declare -a S_ERROR_MSG=()
declare -a S_FINAL_SENDER_BW=()
declare -a S_FINAL_RECEIVER_BW=()

declare -a SRV_PORT=()
declare -a SRV_BIND=()
declare -a SRV_VRF=()
declare -a SRV_ONEOFF=()
declare -a SRV_LOGFILE=()
declare -a SRV_SCRIPT=()
declare -a SRV_PREV_STATE=()
declare -a SRV_BW_CACHE=()

declare -a RESULT_SENDER_BW=()
declare -a RESULT_RECEIVER_BW=()
declare -a RESULT_RTX=()
declare -a RESULT_JITTER=()
declare -a RESULT_LOSS_PCT=()
declare -a RESULT_LOSS_COUNT=()

declare -a VRF_LIST=()
declare -a IFACE_NAMES=()
declare -a IFACE_IPS=()
declare -a IFACE_STATES=()
declare -a IFACE_SPEEDS=()
declare -a IFACE_VRFS=()

STREAM_COUNT=0
SERVER_COUNT=0
FRAME_LINES=0
PROMPT_DSCP_NAME=""
PROMPT_DSCP_VAL=-1
SELECTED_IFACE=""
SELECTED_IP=""
SELECTED_VRF=""
_PREV_DYNAMIC_LINES=0

# =============================================================================
# SECTION 1 — PRIMITIVES
# =============================================================================

vlen() {
    local text="$1"
    local total=${#text}
    local plain="$text"
    local count ansi_bytes=0
    local temp

    temp="${plain//$RED/}";    count=$(( (${#plain} - ${#temp}) / _LEN_RED    )); (( _LEN_RED    > 0 )) && ansi_bytes=$(( ansi_bytes + count * _LEN_RED    )); plain="$temp"
    temp="${plain//$GREEN/}";  count=$(( (${#plain} - ${#temp}) / _LEN_GREEN  )); (( _LEN_GREEN  > 0 )) && ansi_bytes=$(( ansi_bytes + count * _LEN_GREEN  )); plain="$temp"
    temp="${plain//$YELLOW/}"; count=$(( (${#plain} - ${#temp}) / _LEN_YELLOW )); (( _LEN_YELLOW > 0 )) && ansi_bytes=$(( ansi_bytes + count * _LEN_YELLOW )); plain="$temp"
    temp="${plain//$BLUE/}";   count=$(( (${#plain} - ${#temp}) / _LEN_BLUE   )); (( _LEN_BLUE   > 0 )) && ansi_bytes=$(( ansi_bytes + count * _LEN_BLUE   )); plain="$temp"
    temp="${plain//$CYAN/}";   count=$(( (${#plain} - ${#temp}) / _LEN_CYAN   )); (( _LEN_CYAN   > 0 )) && ansi_bytes=$(( ansi_bytes + count * _LEN_CYAN   )); plain="$temp"
    temp="${plain//$BOLD/}";   count=$(( (${#plain} - ${#temp}) / _LEN_BOLD   )); (( _LEN_BOLD   > 0 )) && ansi_bytes=$(( ansi_bytes + count * _LEN_BOLD   )); plain="$temp"
    temp="${plain//$NC/}";     count=$(( (${#plain} - ${#temp}) / _LEN_NC     )); (( _LEN_NC     > 0 )) && ansi_bytes=$(( ansi_bytes + count * _LEN_NC     )); plain="$temp"

    printf '%d' $(( total - ansi_bytes ))
}

rpt() {
    local char="$1" n="$2" i out=""
    (( n <= 0 )) && printf '%s' "" && return
    for (( i=0; i<n; i++ )); do out+="$char"; done
    printf '%s' "$out"
}

pad_to() {
    local text="$1" width="$2" len=${#1}
    if (( len >= width )); then
        printf '%s' "${text:0:$((width-1))}~"
    else
        printf '%s%s' "$text" "$(rpt ' ' $(( width - len )))"
    fi
}

validate_port()      { [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }
validate_bandwidth() { local b="$1"; [[ -z "$b" ]] && return 0; [[ "$b" =~ ^[0-9]+([KMGkmg])?$ ]]; }
validate_duration()  { local d="$1"; [[ "$d" == "unlimited" || "$d" == "inf" ]] && return 0; [[ "$d" =~ ^[0-9]+$ ]]; }
validate_float()     { [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; }

validate_ip() {
    local ip="$1"
    [[ -z "$ip" ]] && return 1
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local o1 o2 o3 o4
        IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
        local o
        for o in "$o1" "$o2" "$o3" "$o4"; do
            [[ "$o" =~ ^[0-9]+$ ]] || return 1
            (( 10#$o > 255 )) && return 1
        done
        return 0
    fi
    [[ "$ip" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-\.]*[a-zA-Z0-9])?$ ]] && return 0
    return 1
}

# =============================================================================
# SECTION 2 — BOX DRAWING
# =============================================================================

bline() {
    local char="${1:--}" inner=$(( COLS - 2 ))
    printf '+%s+\033[K\n' "$(rpt "$char" "$inner")"
}

bcenter() {
    local text="$1" inner=$(( COLS - 2 ))
    local vl; vl=$(vlen "$text")
    local tp=$(( inner - vl ))
    local lp=$(( tp / 2 ))
    local rp=$(( tp - lp ))
    (( lp < 0 )) && lp=0
    (( rp < 0 )) && rp=0
    printf '|%s' "$(rpt ' ' $lp)"
    printf '%b' "$text"
    printf '%s|\033[K\n' "$(rpt ' ' $rp)"
}

bleft() {
    local text="$1" indent="${2:-1}" inner=$(( COLS - 2 ))
    local vl; vl=$(vlen "$text")
    local rp=$(( inner - indent - vl ))
    (( rp < 0 )) && rp=0
    printf '|%s' "$(rpt ' ' $indent)"
    printf '%b' "$text"
    printf '%s|\033[K\n' "$(rpt ' ' $rp)"
}

bempty() {
    local inner=$(( COLS - 2 ))
    printf '|%s|\033[K\n' "$(rpt ' ' $inner)"
}

print_header() {
    local t="${1:-iperf3 Traffic Streams}"
    bline '='; bempty; bcenter "${BOLD}${CYAN}${t}${NC}"; bempty; bline '='
}

print_separator() { bline '-'; }

confirm_proceed() {
    local prompt="${1:-Proceed?}" answer
    printf '\n'; read -r -p "  ${prompt} [Y/n]: " answer </dev/tty
    case "$answer" in [Nn]*) return 1 ;; *) return 0 ;; esac
}

format_seconds() {
    local s="$1"; (( s < 0 )) && s=0
    printf '%02d:%02d' "$(( s / 60 ))" "$(( s % 60 ))"
}

# =============================================================================
# SECTION 3 — BANDWIDTH FORMATTING & PARSING
# =============================================================================

_format_bps() {
    local bps="$1"
    if [[ ! "$bps" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [[ "$bps" == "0" ]]; then
        printf '%s' '---'; return
    fi
    printf '%s' "$(awk -v b="$bps" 'BEGIN {
        if      (b >= 1e9) printf "%.2f Gbps", b/1e9
        else if (b >= 1e6) printf "%.2f Mbps", b/1e6
        else if (b >= 1e3) printf "%.2f Kbps", b/1e3
        else               printf "%.0f bps",  b
    }')"
}

_normalise_text_bw() {
    local raw="$1"
    [[ -z "$raw" ]] && { printf '%s' '---'; return; }
    local val unit
    val=$(printf '%s' "$raw"  | awk '{print $1}')
    unit=$(printf '%s' "$raw" | awk '{print $2}')
    if [[ ! "$val" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        printf '%s' '---'; return
    fi
    printf '%s' "$(awk -v v="$val" -v u="$unit" 'BEGIN {
        b = v
        if      (u ~ /[Gg]bits/) b = v * 1e9
        else if (u ~ /[Mm]bits/) b = v * 1e6
        else if (u ~ /[Kk]bits/) b = v * 1e3
        if      (b >= 1e9) printf "%.2f Gbps", b/1e9
        else if (b >= 1e6) printf "%.2f Mbps", b/1e6
        else if (b >= 1e3) printf "%.2f Kbps", b/1e3
        else               printf "%.0f bps",  b
    }')"
}

parse_live_bandwidth_from_log() {
    local logfile="$1"
    [[ ! -f "$logfile" || ! -s "$logfile" ]] && { printf '%s' '---'; return; }
    local ll=""
    ll=$(grep -E '^\[SUM\][[:space:]]+[0-9.]+-[0-9.]+[[:space:]]+sec' \
         "$logfile" 2>/dev/null \
         | grep -vE '[[:space:]](sender|receiver)[[:space:]]*$' \
         | tail -1)
    if [[ -z "$ll" ]]; then
        ll=$(grep -E '^\[[[:space:]]*[0-9]+\][[:space:]]+[0-9.]+-[0-9.]+[[:space:]]+sec' \
             "$logfile" 2>/dev/null \
             | grep -vE '[[:space:]](sender|receiver)[[:space:]]*$' \
             | tail -1)
    fi
    [[ -z "$ll" ]] && { printf '%s' '---'; return; }
    local result
    result=$(printf '%s\n' "$ll" | awk '
    {
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^[KMGkmg]?bits\/sec$/) {
                if (i > 1) { print $(i-1) " " $i; exit }
            }
        }
    }')
    if [[ -n "$result" ]]; then
        _normalise_text_bw "$result"
    else
        printf '%s' '---'
    fi
}

parse_final_bw_from_log() {
    local logfile="$1" direction="$2"
    [[ ! -f "$logfile" || ! -s "$logfile" ]] && printf '%s' "" && return
    local line=""
    line=$(grep -E '^\[SUM\].*[[:space:]]'"$direction"'[[:space:]]*$' \
           "$logfile" 2>/dev/null | tail -1)
    if [[ -z "$line" ]]; then
        line=$(grep -E '^\[[[:space:]]*[0-9]+\].*[[:space:]]'"$direction"'[[:space:]]*$' \
               "$logfile" 2>/dev/null | tail -1)
    fi
    if [[ -n "$line" ]]; then
        local bw; bw=$(echo "$line" | grep -oE '[0-9.]+ [KMG]?bits/sec' | head -1)
        [[ -n "$bw" ]] && { _normalise_text_bw "$bw"; return; }
    fi
    printf '%s' ""
}

parse_retransmits_from_log() {
    local logfile="$1"
    [[ ! -f "$logfile" || ! -s "$logfile" ]] && printf '%s' "0" && return
    local line
    line=$(grep -E '[[:space:]]sender[[:space:]]*$' "$logfile" 2>/dev/null | tail -1)
    if [[ -n "$line" ]]; then
        local rtx; rtx=$(awk '{for(i=1;i<=NF;i++) if($i=="sender") print $(i-1)}' <<< "$line")
        if [[ "$rtx" =~ ^[0-9]+$ ]]; then printf '%s' "$rtx"; return; fi
    fi
    printf '%s' "0"
}

_capture_final_bw() {
    local idx="$1"
    local lf="${S_LOGFILE[$idx]:-}"
    [[ -n "${S_FINAL_SENDER_BW[$idx]:-}" ]] && return
    local sbw rbw
    sbw=$(parse_final_bw_from_log "$lf" "sender")
    rbw=$(parse_final_bw_from_log "$lf" "receiver")
    if [[ -z "$sbw" || "$sbw" == "---" ]]; then
        sbw=$(parse_live_bandwidth_from_log "$lf")
    fi
    if [[ -z "$rbw" || "$rbw" == "---" ]]; then
        rbw="$sbw"
    fi
    S_FINAL_SENDER_BW[$idx]="${sbw:-N/A}"
    S_FINAL_RECEIVER_BW[$idx]="${rbw:-N/A}"
}

# =============================================================================
# SECTION 4 — CLEANUP AND SIGNALS
# =============================================================================

tty_echo() { printf '%b\n' "$1" >/dev/tty 2>/dev/null || printf '%b\n' "$1"; }

cleanup() {
    [[ $CLEANUP_DONE -eq 1 ]] && return 0
    CLEANUP_DONE=1
    local sn="${1:-EXIT}"
    printf '\033[?25h' >/dev/tty 2>/dev/null; printf '\n' >/dev/tty 2>/dev/null
    local sep; sep=$(rpt '=' $(( COLS - 2 )))
    tty_echo "${BOLD}${CYAN}+${sep}+${NC}"
    tty_echo "${BOLD}${CYAN}  iperf3 Traffic Streams -- Cleanup  [signal: ${sn}]${NC}"
    tty_echo "${BOLD}${CYAN}+${sep}+${NC}"
    local killed=0 already=0

    if (( ${#STREAM_PIDS[@]} > 0 )); then
        tty_echo ""; tty_echo "${BOLD}  Client Streams:${NC}"
        local i
        for i in "${!STREAM_PIDS[@]}"; do
            local pid="${STREAM_PIDS[$i]}"
            local lbl="stream $((i+1)) [${S_PROTO[$i]:-?}->${S_TARGET[$i]:-?}:${S_PORT[$i]:-?}]"
            if [[ -z "$pid" || "$pid" == "0" ]]; then
                tty_echo "    ${YELLOW}[SKIP ]${NC}  $lbl  -- no PID"; continue
            fi
            if kill -0 "$pid" 2>/dev/null; then
                kill -TERM "$pid" 2>/dev/null
                local w=0
                while kill -0 "$pid" 2>/dev/null && (( w < 6 )); do sleep 0.5; (( w++ )); done
                if kill -0 "$pid" 2>/dev/null; then
                    kill -KILL "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
                    tty_echo "    ${RED}[KILLED]${NC}  PID $pid  $lbl"
                else
                    wait "$pid" 2>/dev/null
                    tty_echo "    ${GREEN}[STOP  ]${NC}  PID $pid  $lbl"
                fi; (( killed++ ))
            else
                wait "$pid" 2>/dev/null
                tty_echo "    ${CYAN}[DONE  ]${NC}  PID $pid  $lbl  (already exited)"; (( already++ ))
            fi
        done
    fi

    if (( ${#SERVER_PIDS[@]} > 0 )); then
        tty_echo ""; tty_echo "${BOLD}  Server Listeners:${NC}"
        local i
        for i in "${!SERVER_PIDS[@]}"; do
            local pid="${SERVER_PIDS[$i]}"
            local lbl="listener $((i+1)) [port ${SRV_PORT[$i]:-?} bind ${SRV_BIND[$i]:-0.0.0.0}]"
            if [[ -z "$pid" || "$pid" == "0" ]]; then
                tty_echo "    ${YELLOW}[SKIP ]${NC}  $lbl  -- no PID"; continue
            fi
            if kill -0 "$pid" 2>/dev/null; then
                kill -TERM "$pid" 2>/dev/null
                local w=0
                while kill -0 "$pid" 2>/dev/null && (( w < 6 )); do sleep 0.5; (( w++ )); done
                if kill -0 "$pid" 2>/dev/null; then
                    kill -KILL "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
                    tty_echo "    ${RED}[KILLED]${NC}  PID $pid  $lbl"
                else
                    wait "$pid" 2>/dev/null
                    tty_echo "    ${GREEN}[STOP  ]${NC}  PID $pid  $lbl"
                fi; (( killed++ ))
            else
                wait "$pid" 2>/dev/null
                tty_echo "    ${CYAN}[DONE  ]${NC}  PID $pid  $lbl  (already exited)"; (( already++ ))
            fi
        done
    fi

    if (( ${#NETEM_IFACES[@]} > 0 )); then
        tty_echo ""; tty_echo "${BOLD}  tc netem:${NC}"
        local iface
        for iface in "${NETEM_IFACES[@]}"; do
            [[ -z "$iface" ]] && continue
            if tc qdisc del dev "$iface" root 2>/dev/null; then
                tty_echo "    ${GREEN}[REMOVED]${NC}  netem on $iface"
            else
                tty_echo "    ${YELLOW}[SKIP   ]${NC}  netem on $iface  (already gone)"
            fi
        done
    fi

    tty_echo ""; tty_echo "${BOLD}  Temporary Files:${NC}"
    if [[ -n "$TMPDIR" && -d "$TMPDIR" ]]; then
        local fc=0
        while IFS= read -r -d '' fp; do
            local fsz; fsz=$(wc -c < "$fp" 2>/dev/null); fsz="${fsz// /}"
            tty_echo "    ${CYAN}[DEL]${NC}  $fp  (${fsz:-0} bytes)"; (( fc++ ))
        done < <(find "$TMPDIR" -maxdepth 3 -type f -print0 2>/dev/null)
        (( fc == 0 )) && tty_echo "    ${YELLOW}[INFO ]${NC}  No files in $TMPDIR"
        rm -rf "$TMPDIR" 2>/dev/null \
            && tty_echo "    ${GREEN}[REMOVED]${NC}  $TMPDIR" \
            || tty_echo "    ${RED}[ERROR  ]${NC}  Cannot remove $TMPDIR"
    else
        tty_echo "    ${YELLOW}[INFO ]${NC}  Temp dir not found or already removed"
    fi

    tty_echo ""; tty_echo "${BOLD}${CYAN}+${sep}+${NC}"
    tty_echo "  ${GREEN}Processes stopped : ${killed}${NC}"
    tty_echo "  ${CYAN}Already exited    : ${already}${NC}"
    tty_echo "${BOLD}${GREEN}  Cleanup complete. All resources released.${NC}"
    tty_echo "${BOLD}${CYAN}+${sep}+${NC}"; tty_echo ""
}

_trap_int()  { printf '\n'>/dev/tty 2>/dev/null; tty_echo "${BOLD}${YELLOW}  [SIGINT]  Ctrl+C -- stopping...${NC}";          cleanup "SIGINT (Ctrl+C)"; exit 130; }
_trap_term() { printf '\n'>/dev/tty 2>/dev/null; tty_echo "${BOLD}${YELLOW}  [SIGTERM] Stopping...${NC}";                     cleanup "SIGTERM";         exit 143; }
_trap_quit() { printf '\n'>/dev/tty 2>/dev/null; tty_echo "${BOLD}${YELLOW}  [SIGQUIT] Ctrl+\\ -- stopping...${NC}";          cleanup "SIGQUIT";         exit 131; }
_trap_hup()  { printf '\n'>/dev/tty 2>/dev/null; tty_echo "${BOLD}${YELLOW}  [SIGHUP]  Terminal closed -- stopping...${NC}";  cleanup "SIGHUP";          exit 129; }
_trap_tstp() {
    printf '\n'>/dev/tty 2>/dev/null
    tty_echo "${BOLD}${YELLOW}  [Ctrl+Z blocked]${NC}  Backgrounding orphans iperf3 processes."
    tty_echo "${YELLOW}  Use Ctrl+C to stop cleanly.${NC}"
}
_trap_exit() { local ec=$?; (( CLEANUP_DONE == 0 )) && cleanup "exit (code ${ec})"; }

register_traps() {
    trap '_trap_exit' EXIT; trap '_trap_int' INT; trap '_trap_term' TERM
    trap '_trap_quit' QUIT; trap '_trap_hup' HUP; trap '_trap_tstp' TSTP
}

# =============================================================================
# SECTION 5 — INITIALIZATION
# =============================================================================

find_iperf3() {
    local candidates=(
        "$(which iperf3 2>/dev/null)"
        "/usr/bin/iperf3" "/usr/local/bin/iperf3"
        "/usr/sbin/iperf3" "/snap/bin/iperf3"
        "$HOME/.local/bin/iperf3"
        "/opt/homebrew/bin/iperf3"
        "/usr/local/Cellar/iperf3/*/bin/iperf3"
    )
    local c
    for c in "${candidates[@]}"; do
        [[ -n "$c" && -x "$c" ]] && { IPERF3_BIN="$c"; return 0; }
    done
    printf '%b\n' "${RED}ERROR: iperf3 not found.${NC}"
    if [[ "$OS_TYPE" == "macos" ]]; then
        printf '%b\n' "${YELLOW}Install on macOS: brew install iperf3${NC}"
    else
        printf '%b\n' "${YELLOW}Install: apt install iperf3 | yum install iperf3${NC}"
    fi
    exit 1
}

get_iperf3_version() {
    local out; out=$("$IPERF3_BIN" --version 2>&1)
    local ver
    ver=$(printf '%s' "$out" | grep -oE 'iperf[[:space:]]+[0-9]+\.[0-9]+(\.[0-9]+)?' \
          | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
    [[ -z "$ver" ]] && \
        ver=$(printf '%s' "$out" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
    IPERF3_MAJOR=$(printf '%s' "$ver" | cut -d. -f1); IPERF3_MAJOR="${IPERF3_MAJOR:-3}"
    IPERF3_MINOR=$(printf '%s' "$ver" | cut -d. -f2); IPERF3_MINOR="${IPERF3_MINOR:-0}"
    IPERF3_PATCH=$(printf '%s' "$ver" | cut -d. -f3); IPERF3_PATCH="${IPERF3_PATCH:-0}"
}

version_ge() {
    local mj="$1" mn="${2:-0}" pt="${3:-0}"
    (( IPERF3_MAJOR > mj )) && return 0; (( IPERF3_MAJOR < mj )) && return 1
    (( IPERF3_MINOR > mn )) && return 0; (( IPERF3_MINOR < mn )) && return 1
    (( IPERF3_PATCH >= pt ))
}

detect_forceflush() {
    "$IPERF3_BIN" --help 2>&1 | grep -q 'forceflush' \
        && FORCEFLUSH_SUPPORTED=1 || FORCEFLUSH_SUPPORTED=0
    version_ge 3 12 && NOFQ_SUPPORTED=1 || NOFQ_SUPPORTED=0
}

check_root() {
    if [[ $EUID -eq 0 ]]; then IS_ROOT=1
    else
        IS_ROOT=0
        if [[ "$OS_TYPE" == "macos" ]]; then
            printf '%b\n' "${YELLOW}WARNING: Not root -- netem/ports <1024 need sudo.${NC}"
        else
            printf '%b\n' "${YELLOW}WARNING: Not root -- VRF/netem/ports <1024 need root.${NC}"
        fi
    fi
}

init_tmpdir() {
    TMPDIR=$(mktemp -d /tmp/iperf3_streams.XXXXXX)
    [[ -d "$TMPDIR" ]] || { printf '%b\n' "${RED}ERROR: cannot create temp dir.${NC}"; exit 1; }
}

# =============================================================================
# SECTION 6 — VRF & INTERFACE DISCOVERY
# =============================================================================

build_vrf_maps() {
    if [[ "$OS_TYPE" == "macos" ]]; then
        _iface_to_vrf_clear; _vrf_masters_clear; VRF_LIST=(); return
    fi
    _iface_to_vrf_clear; _vrf_masters_clear; VRF_LIST=()
    command -v ip >/dev/null 2>&1 || return
    local line vn

    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        vn=$(awk '{print $1}' <<< "$line")
        [[ -z "$vn" || "$vn" == "Name" ]] && continue
        local d=0 v
        for v in "${VRF_LIST[@]}"; do [[ "$v" == "$vn" ]] && d=1 && break; done
        (( d )) || VRF_LIST+=("$vn")
    done < <(ip vrf show 2>/dev/null)

    while IFS= read -r line; do
        [[ "$line" =~ ^[0-9]+: ]] || continue
        local mn; mn=$(echo "$line" | grep -oE '^[0-9]+:[[:space:]]+[^@: ]+' | awk '{print $2}')
        [[ -z "$mn" ]] && continue
        _vrf_masters_set "$mn" "1"
        local d=0 v
        for v in "${VRF_LIST[@]}"; do [[ "$v" == "$mn" ]] && d=1 && break; done
        (( d )) || VRF_LIST+=("$mn")
    done < <(ip -d link show type vrf 2>/dev/null)

    for vn in "${VRF_LIST[@]}"; do
        while IFS= read -r line; do
            [[ "$line" =~ ^[0-9]+: ]] || continue
            local iface; iface=$(echo "$line" | grep -oE '^[0-9]+:[[:space:]]+[^@: ]+' | awk '{print $2}')
            [[ -n "$iface" ]] && _iface_to_vrf_set "$iface" "$vn"
        done < <(ip link show master "$vn" 2>/dev/null)
    done
}

_get_iface_state_linux() {
    local iface="$1" fl=""
    command -v ip >/dev/null 2>&1 && fl=$(ip link show dev "$iface" 2>/dev/null | head -1)
    if [[ -n "$fl" ]]; then
        local flags; flags=$(echo "$fl" | grep -oE '<[^>]+>')
        [[ "$flags" == *"LOWER_UP"*   ]] && printf '%s' 'up'         && return
        [[ "$flags" == *"NO-CARRIER"* ]] && printf '%s' 'no-carrier' && return
        [[ "$flags" =~ (^|,)UP(,|>)  ]] && printf '%s' 'no-carrier' && return
        printf '%s' 'down'; return
    fi
    local op=""
    [[ -r /sys/class/net/$iface/operstate ]] && \
        op=$(< /sys/class/net/$iface/operstate 2>/dev/null)
    op="${op%$'\n'}"
    if [[ "$op" == "unknown" || -z "$op" ]]; then
        if [[ -r /sys/class/net/$iface/carrier ]]; then
            local c; c=$(< /sys/class/net/$iface/carrier 2>/dev/null); c="${c%$'\n'}"
            [[ "$c" == "1" ]] && printf '%s' 'up'   && return
            [[ "$c" == "0" ]] && printf '%s' 'down' && return
        fi
        printf '%s' 'unknown'; return
    fi
    printf '%s' "$op"
}

_get_iface_state_macos() {
    local iface="$1"
    local out
    out=$(ifconfig "$iface" 2>/dev/null)
    [[ -z "$out" ]] && { printf '%s' 'unknown'; return; }
    if echo "$out" | grep -q 'status: active';   then printf '%s' 'up';         return; fi
    if echo "$out" | grep -q 'status: inactive'; then printf '%s' 'no-carrier'; return; fi
    local flags_field
    flags_field=$(echo "$out" | head -1 | grep -oE '<[^>]+>')
    if [[ -n "$flags_field" ]]; then
        local has_up=0 has_running=0
        echo "$flags_field" | grep -qE '<(.*,)?UP(,.*)?>'      && has_up=1
        echo "$flags_field" | grep -qE '<(.*,)?RUNNING(,.*)?>' && has_running=1
        if (( has_up && has_running )); then
            printf '%s' 'up';         return
        elif (( has_up )); then
            printf '%s' 'no-carrier'; return
        else
            printf '%s' 'down';       return
        fi
    fi
    printf '%s' 'unknown'
}

get_iface_state() {
    if [[ "$OS_TYPE" == "macos" ]]; then _get_iface_state_macos "$1"
    else                                  _get_iface_state_linux "$1"; fi
}

_get_iface_speed_linux() {
    local iface="$1"
    if [[ -r /sys/class/net/$iface/speed ]]; then
        local rs; rs=$(cat /sys/class/net/$iface/speed 2>/dev/null); rs="${rs//[[:space:]]/}"
        if [[ "$rs" =~ ^[0-9]+$ ]] && (( rs > 0 )); then
            (( rs >= 1000000 )) && printf '%s' "$((rs/1000000)) Tb/s" && return
            (( rs >= 1000    )) && printf '%s' "$((rs/1000)) Gb/s"    && return
            printf '%s' "${rs} Mb/s"; return
        fi
    fi
    command -v ethtool >/dev/null 2>&1 && {
        local es; es=$(ethtool "$iface" 2>/dev/null | grep -oE 'Speed: [0-9]+Mb/s' | grep -oE '[0-9]+')
        if [[ -n "$es" && "$es" =~ ^[0-9]+$ ]]; then
            (( es >= 1000000 )) && printf '%s' "$((es/1000000)) Tb/s" && return
            (( es >= 1000    )) && printf '%s' "$((es/1000)) Gb/s"    && return
            printf '%s' "${es} Mb/s"; return
        fi
    }
    printf '%s' 'N/A'
}

_get_iface_speed_macos() {
    local iface="$1"
    local media_line
    media_line=$(ifconfig "$iface" 2>/dev/null | grep -i 'media:')
    if [[ -n "$media_line" ]]; then
        local spd
        spd=$(echo "$media_line" | grep -oE '[0-9]+(base[A-Za-z0-9]+)' \
            | grep -oE '^[0-9]+' | head -1)
        if [[ -n "$spd" && "$spd" =~ ^[0-9]+$ ]]; then
            (( spd >= 1000000 )) && printf '%s' "$((spd/1000000)) Tb/s" && return
            (( spd >= 1000    )) && printf '%s' "$((spd/1000)) Gb/s"    && return
            printf '%s' "${spd} Mb/s"; return
        fi
    fi
    printf '%s' 'N/A'
}

get_iface_speed() {
    if [[ "$OS_TYPE" == "macos" ]]; then _get_iface_speed_macos "$1"
    else                                  _get_iface_speed_linux "$1"; fi
}

_get_interface_list_linux() {
    IFACE_NAMES=(); IFACE_IPS=(); IFACE_STATES=(); IFACE_SPEEDS=(); IFACE_VRFS=()
    [[ -d /sys/class/net ]] || return
    local iface
    for iface in /sys/class/net/*/; do
        iface=$(basename "$iface")
        [[ "$iface" == "lo"     ]] && continue
        [[ "$iface" == docker*  ]] && continue
        [[ "$iface" == veth*    ]] && continue
        [[ "$iface" == br-*     ]] && continue
        [[ "$iface" == virbr*   ]] && continue
        [[ "$iface" == dummy*   ]] && continue
        [[ "$iface" == pimreg*  ]] && continue
        [[ "$iface" == pim6reg* ]] && continue
        _vrf_masters_has "$iface" && continue
        local ip_addr="N/A"
        command -v ip >/dev/null 2>&1 && {
            local ri; ri=$(ip -4 addr show dev "$iface" 2>/dev/null \
                | grep -oE 'inet [0-9.]+' | awk '{print $2}' | head -1)
            [[ -n "$ri" ]] && ip_addr="$ri"
        }
        local state; state="$(get_iface_state "$iface")"
        local speed; speed="$(get_iface_speed "$iface")"
        local vrf="GRT"
        _iface_to_vrf_has "$iface" && vrf="$(_iface_to_vrf_get "$iface")"
        IFACE_NAMES+=("$iface"); IFACE_IPS+=("$ip_addr")
        IFACE_STATES+=("$state"); IFACE_SPEEDS+=("$speed"); IFACE_VRFS+=("$vrf")
    done
}

_get_interface_list_macos() {
    IFACE_NAMES=(); IFACE_IPS=(); IFACE_STATES=(); IFACE_SPEEDS=(); IFACE_VRFS=()
    local raw_list
    raw_list=$(ifconfig -l 2>/dev/null)
    [[ -z "$raw_list" ]] && return
    local iface
    for iface in $raw_list; do
        [[ "$iface" == lo*    ]] && continue
        [[ "$iface" == gif*   ]] && continue
        [[ "$iface" == stf*   ]] && continue
        [[ "$iface" == utun*  ]] && continue
        [[ "$iface" == awdl*  ]] && continue
        [[ "$iface" == ipsec* ]] && continue
        [[ "$iface" == XHC*   ]] && continue
        local ip_addr="N/A"
        local ri
        ri=$(ifconfig "$iface" 2>/dev/null \
            | awk '/^\tinet / { print $2; exit }')
        [[ -n "$ri" ]] && ip_addr="$ri"
        local state; state="$(_get_iface_state_macos "$iface")"
        local speed; speed="$(_get_iface_speed_macos "$iface")"
        IFACE_NAMES+=("$iface"); IFACE_IPS+=("$ip_addr")
        IFACE_STATES+=("$state"); IFACE_SPEEDS+=("$speed"); IFACE_VRFS+=("GRT")
    done
}

get_interface_list() {
    if [[ "$OS_TYPE" == "macos" ]]; then _get_interface_list_macos
    else                                  _get_interface_list_linux; fi
}

# =============================================================================
# SECTION 7 — INTERFACE TABLE (dynamic column widths)
# =============================================================================

_build_iface_col_widths() {
    local _h_num=" #"
    local _h_iface=" Interface"
    local _h_ip=" IP Address"
    local _h_state=" State"
    local _h_speed=" Speed"
    local _h_vrf=" VRF"

    _CN=$(( ${#_h_num}    + 1 ))
    _CI=$(( ${#_h_iface}  + 1 ))
    _CIP=$(( ${#_h_ip}    + 1 ))
    _CS=$(( ${#_h_state}  + 1 ))
    _CSP=$(( ${#_h_speed} + 1 ))
    _CV=$(( ${#_h_vrf}    + 1 ))

    (( _CN  < 4  )) && _CN=4
    (( _CI  < 10 )) && _CI=10
    (( _CIP < 10 )) && _CIP=10
    (( _CS  < 7  )) && _CS=7
    (( _CSP < 7  )) && _CSP=7
    (( _CV  < 5  )) && _CV=5

    local total_ifaces=${#IFACE_NAMES[@]}
    local i

    for (( i=0; i<total_ifaces; i++ )); do
        local num_str=" $((i+1))"
        local num_w=$(( ${#num_str} + 1 ))
        (( num_w > _CN )) && _CN=$num_w

        local iname_str=" ${IFACE_NAMES[$i]}"
        local iname_w=$(( ${#iname_str} + 1 ))
        (( iname_w > _CI )) && _CI=$iname_w

        local ip_str=" ${IFACE_IPS[$i]}"
        local ip_w=$(( ${#ip_str} + 1 ))
        (( ip_w > _CIP )) && _CIP=$ip_w

        local st_str=" ${IFACE_STATES[$i]}"
        local st_w=$(( ${#st_str} + 1 ))
        (( st_w > _CS )) && _CS=$st_w

        local sp_str=" ${IFACE_SPEEDS[$i]}"
        local sp_w=$(( ${#sp_str} + 1 ))
        (( sp_w > _CSP )) && _CSP=$sp_w

        local vrf_str=" ${IFACE_VRFS[$i]}"
        local vrf_w=$(( ${#vrf_str} + 1 ))
        (( vrf_w > _CV )) && _CV=$vrf_w
    done

    local total=$(( _CN + _CI + _CIP + _CS + _CSP + _CV + 7 ))
    if (( total > COLS )); then
        local excess=$(( total - COLS ))
        local ip_shrink=$(( _CIP - 10 ))
        if (( ip_shrink >= excess )); then
            _CIP=$(( _CIP - excess ))
        else
            _CIP=10
            local remaining=$(( excess - ip_shrink ))
            local name_shrink=$(( _CI - 10 ))
            if (( name_shrink >= remaining )); then
                _CI=$(( _CI - remaining ))
            else
                _CI=10
            fi
        fi
    fi
}

_iface_rule() {
    printf '+%s+%s+%s+%s+%s+%s+\033[K\n' \
        "$(rpt '-' $_CN)"  "$(rpt '-' $_CI)"  "$(rpt '-' $_CIP)" \
        "$(rpt '-' $_CS)"  "$(rpt '-' $_CSP)" "$(rpt '-' $_CV)"
}

_iface_hdr() {
    printf '|%s|%s|%s|%s|%s|%s|\033[K\n' \
        "$(pad_to " #"          $_CN)"  "$(pad_to " Interface"  $_CI)" \
        "$(pad_to " IP Address" $_CIP)" "$(pad_to " State"      $_CS)" \
        "$(pad_to " Speed"      $_CSP)" "$(pad_to " VRF"        $_CV)"
}

_iface_banner() {
    local lbl="$1"
    local inner=$(( COLS - 2 ))
    local visible_len=$(( ${#lbl} + 2 ))
    local rp=$(( inner - visible_len ))
    (( rp < 0 )) && rp=0
    printf '|'
    printf '%b' "${BOLD}${CYAN}  ${lbl}${NC}"
    printf '%s|\033[K\n' "$(rpt ' ' $rp)"
}

_iface_row() {
    local num="$1" iface="$2" ip="$3" state="$4" speed="$5" vrf="$6"
    local sc
    case "$state" in
        up)         sc="$GREEN"  ;;
        down)       sc="$RED"    ;;
        no-carrier) sc="$YELLOW" ;;
        unknown)    sc="$YELLOW" ;;
        *)          sc="$YELLOW" ;;
    esac
    local fs; fs=$(pad_to " $state" $_CS)
    printf '|%s|%s|%s|%b%s%b|%s|%s|\033[K\n' \
        "$(pad_to " $num"   $_CN)"  "$(pad_to " $iface" $_CI)" \
        "$(pad_to " $ip"    $_CIP)" "$sc" "$fs" "$NC" \
        "$(pad_to " $speed" $_CSP)" "$(pad_to " $vrf"   $_CV)"
}

show_interface_table() {
    local total=${#IFACE_NAMES[@]}
    bline '='; bcenter "${BOLD}Network Interfaces${NC}"; bline '='
    if (( total == 0 )); then
        bempty; bleft "  No interfaces found."; bempty; bline '='; return
    fi
    _build_iface_col_widths
    _iface_rule; _iface_hdr; _iface_rule

    if [[ "$OS_TYPE" == "macos" ]]; then
        _iface_banner "[ All Interfaces (macOS) ]  (${total} interface(s))"
        _iface_rule
        local i
        for (( i=0; i<total; i++ )); do
            _iface_row "$((i+1))" "${IFACE_NAMES[$i]}" "${IFACE_IPS[$i]}" \
                "${IFACE_STATES[$i]}" "${IFACE_SPEEDS[$i]}" "${IFACE_VRFS[$i]}"
        done
    else
        local i gc=0
        for (( i=0; i<total; i++ )); do
            [[ "${IFACE_VRFS[$i]}" == "GRT" ]] && (( gc++ ))
        done
        if (( gc > 0 )); then
            _iface_banner "[ GRT -- Global Routing Table ]  (${gc} interface(s))"
            _iface_rule
            for (( i=0; i<total; i++ )); do
                [[ "${IFACE_VRFS[$i]}" != "GRT" ]] && continue
                _iface_row "$((i+1))" "${IFACE_NAMES[$i]}" "${IFACE_IPS[$i]}" \
                    "${IFACE_STATES[$i]}" "${IFACE_SPEEDS[$i]}" "GRT"
            done
        fi
        local vn
        for vn in "${VRF_LIST[@]}"; do
            local mc=0
            for (( i=0; i<total; i++ )); do
                [[ "${IFACE_VRFS[$i]}" == "$vn" ]] && (( mc++ ))
            done
            (( mc == 0 )) && continue
            _iface_rule
            _iface_banner "[ VRF: ${vn} ]  (${mc} interface(s))"
            _iface_rule
            for (( i=0; i<total; i++ )); do
                [[ "${IFACE_VRFS[$i]}" != "$vn" ]] && continue
                _iface_row "$((i+1))" "${IFACE_NAMES[$i]}" "${IFACE_IPS[$i]}" \
                    "${IFACE_STATES[$i]}" "${IFACE_SPEEDS[$i]}" "$vn"
            done
        done
    fi
    _iface_rule; bline '='
}

select_bind_interface() {
    local mode="${1:-client}"
    local total=${#IFACE_NAMES[@]}
    SELECTED_IFACE=""; SELECTED_IP=""; SELECTED_VRF=""
    show_interface_table; echo ""
    if [[ "$mode" == "server" ]]; then
        echo "  Enter interface # to bind, or 0 for all (0.0.0.0):"
    else
        echo "  Enter interface # as source bind, or 0 to skip (auto):"
    fi
    echo ""
    local sel
    while true; do
        read -r -p "  Selection [0]: " sel </dev/tty; sel="${sel:-0}"
        if [[ ! "$sel" =~ ^[0-9]+$ ]]; then
            printf '%b\n' "${RED}  Please enter a number (0-${total}).${NC}"; continue
        fi
        if (( sel == 0 )); then
            SELECTED_IFACE=""; SELECTED_IP=""; SELECTED_VRF=""; return 0
        elif (( sel >= 1 && sel <= total )); then
            local idx=$(( sel - 1 ))
            SELECTED_IFACE="${IFACE_NAMES[$idx]}"; SELECTED_IP="${IFACE_IPS[$idx]}"
            SELECTED_VRF="${IFACE_VRFS[$idx]}"
            [[ "${IFACE_STATES[$idx]}" != "up" ]] && \
                printf '%b\n' "${YELLOW}  WARNING: ${SELECTED_IFACE} state='${IFACE_STATES[$idx]}'. Proceeding.${NC}"
            [[ "$SELECTED_VRF" == "GRT" ]] && SELECTED_VRF=""
            return 0
        else
            printf '%b\n' "${RED}  Invalid. Enter 0 or 1-${total}.${NC}"
        fi
    done
}

# =============================================================================
# SECTION 8 — DSCP SUPPORT
# =============================================================================

dscp_name_to_value() {
    local u; u=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')
    if [[ "$u" =~ ^[0-9]+$ ]]; then
        (( u >= 0 && u <= 63 )) && printf '%d' "$u" && return 0
        printf '%s' '-1'; return 1
    fi
    case "$u" in
        DEFAULT|CS0) printf '%s' '0'  ;; CS1)  printf '%s' '8'  ;; CS2)  printf '%s' '16' ;; CS3)  printf '%s' '24' ;;
        CS4)  printf '%s' '32' ;; CS5)  printf '%s' '40' ;; CS6)  printf '%s' '48' ;; CS7)  printf '%s' '56' ;;
        AF11) printf '%s' '10' ;; AF12) printf '%s' '12' ;; AF13) printf '%s' '14' ;;
        AF21) printf '%s' '18' ;; AF22) printf '%s' '20' ;; AF23) printf '%s' '22' ;;
        AF31) printf '%s' '26' ;; AF32) printf '%s' '28' ;; AF33) printf '%s' '30' ;;
        AF41) printf '%s' '34' ;; AF42) printf '%s' '36' ;; AF43) printf '%s' '38' ;;
        EF)   printf '%s' '46' ;; VA)   printf '%s' '44' ;;
        *)    printf '%s' '-1'; return 1 ;;
    esac
}

show_dscp_table() {
    echo ""; print_header "DSCP Quick Reference Table"; bempty
    printf '  %-12s  %-4s  %-4s  %-44s\n' "Name" "DSCP" "TOS" "Typical Use Case"
    printf '  %s  %s  %s  %s\n' "$(rpt '-' 12)" "$(rpt '-' 4)" "$(rpt '-' 4)" "$(rpt '-' 44)"
    local rows=(
        "Default/CS0:0:0:Best Effort"            "CS1:8:32:Scavenger / Low-priority bulk"
        "AF11:10:40:Low data (assured, low drop)" "AF12:12:48:Low data (assured, med drop)"
        "AF13:14:56:Low data (assured, high drop)" "CS2:16:64:OAM / Network management"
        "AF21:18:72:High-throughput data (low drop)" "AF22:20:80:High-throughput data (med drop)"
        "AF23:22:88:High-throughput data (high drop)" "CS3:24:96:Broadcast video / Signaling"
        "AF31:26:104:Multimedia streaming (low drop)" "AF32:28:112:Multimedia streaming (med drop)"
        "AF33:30:120:Multimedia streaming (high drop)" "CS4:32:128:Real-time interactive"
        "AF41:34:136:Multimedia conf (low drop)" "AF42:36:144:Multimedia conf (med drop)"
        "AF43:38:152:Multimedia conf (high drop)" "CS5:40:160:Signaling -- call control"
        "VA:44:176:Voice Admit (CAC admitted)"    "EF:46:184:Expedited Forwarding -- VoIP"
        "CS6:48:192:Network Control (BGP/OSPF)"   "CS7:56:224:Reserved / Network Critical"
    )
    local e
    for e in "${rows[@]}"; do
        IFS=':' read -r nm dv tv uc <<< "$e"
        printf '  %-12s  %-4s  %-4s  %-44s\n' "$nm" "$dv" "$tv" "$uc"
    done
    printf '  %s  %s  %s  %s\n' "$(rpt '-' 12)" "$(rpt '-' 4)" "$(rpt '-' 4)" "$(rpt '-' 44)"
    echo ""; echo "  TOS = DSCP * 4  |  Enter name, 0-63, 'list', or press Enter for none."; echo ""
}

prompt_dscp() {
    local snum="${1:-1}"; PROMPT_DSCP_NAME=""; PROMPT_DSCP_VAL=-1
    while true; do
        echo ""
        printf "  Stream %d - DSCP (name/0-63/'list'/Enter=none) [none]: " "$snum"
        local inp; read -r inp </dev/tty; inp="${inp:-}"
        [[ -z "$inp" ]] && return 0
        local lo; lo=$(printf '%s' "$inp" | tr '[:upper:]' '[:lower:]')
        if [[ "$lo" == "list" ]]; then show_dscp_table; continue; fi
        local val; val=$(dscp_name_to_value "$inp")
        if [[ "$val" == "-1" ]]; then
            printf '%b\n' "${RED}  Invalid DSCP. Try EF, AF41, CS3, 0-63, 'list', or press Enter.${NC}"; continue
        fi
        PROMPT_DSCP_NAME=$(printf '%s' "$inp" | tr '[:lower:]' '[:upper:]')
        PROMPT_DSCP_VAL="$val"; return 0
    done
}

# =============================================================================
# SECTION 9 — STREAM CONFIGURATION
# =============================================================================

configure_client_streams() {
    local num="$1" dbind="${2:-}" dvrf="${3:-}"
    S_PROTO=();    S_TARGET=();    S_PORT=();      S_BW=()
    S_DURATION=(); S_DSCP_NAME=(); S_DSCP_VAL=();  S_PARALLEL=()
    S_REVERSE=();  S_CCA=();       S_WINDOW=();     S_MSS=()
    S_BIND=();     S_VRF=();       S_DELAY=();      S_JITTER=()
    S_LOSS=();     S_NOFQ=();      S_LOGFILE=();    S_SCRIPT=()
    S_START_TS=(); S_STATUS_CACHE=(); S_ERROR_MSG=()
    S_FINAL_SENDER_BW=(); S_FINAL_RECEIVER_BW=()
    local lt="" lp=5200 i

    for (( i=0; i<num; i++ )); do
        local sn=$(( i + 1 ))
        echo ""; bline '='; bcenter "${BOLD}Client Stream ${sn} of ${num}${NC}"; bline '='; echo ""

        local proto
        while true; do
            read -r -p "  Protocol [TCP/UDP] (default TCP): " proto </dev/tty
            proto="${proto:-TCP}"
            proto=$(printf '%s' "$proto" | tr '[:lower:]' '[:upper:]')
            [[ "$proto" == "TCP" || "$proto" == "UDP" ]] && break
            printf '%b\n' "${RED}  Enter TCP or UDP.${NC}"
        done
        S_PROTO+=("$proto")

        local tprompt
        [[ -n "$lt" ]] \
            && tprompt="  Target server IP/hostname [$lt]" \
            || tprompt="  Target server IP/hostname"
        local tgt
        while true; do
            read -r -p "${tprompt}: " tgt </dev/tty
            tgt="${tgt:-$lt}"
            if [[ -z "$tgt" ]]; then
                printf '%b\n' "${RED}  Target is required.${NC}"; continue
            fi
            validate_ip "$tgt" || \
                printf '%b\n' "${YELLOW}  Warning: '${tgt}' may not be valid. Continuing.${NC}"
            break
        done
        lt="$tgt"; S_TARGET+=("$tgt")

        local dp=$(( lp + 1 )) port
        while true; do
            read -r -p "  Server port [$dp]: " port </dev/tty
            port="${port:-$dp}"
            if validate_port "$port"; then
                port=$(( 10#$port ))
                (( port < 1024 && IS_ROOT == 0 )) && \
                    printf '%b\n' "${YELLOW}  WARNING: port $port < 1024 requires root.${NC}"
                break
            fi
            printf '%b\n' "${RED}  Invalid port. Enter 1-65535.${NC}"
        done
        lp="$port"; S_PORT+=("$port")

        local bw=""
        if [[ "$proto" == "UDP" ]]; then
            while true; do
                read -r -p "  Bandwidth (required for UDP, e.g. 100M): " bw </dev/tty
                bw="${bw:-100M}"
                validate_bandwidth "$bw" && break
                printf '%b\n' "${RED}  Invalid bandwidth. Use e.g. 100M, 500K, 1G.${NC}"
            done
        else
            while true; do
                read -r -p "  Bandwidth limit (empty=unlimited): " bw </dev/tty
                bw="${bw:-}"
                validate_bandwidth "$bw" && break
                printf '%b\n' "${RED}  Invalid bandwidth.${NC}"
            done
        fi
        S_BW+=("$bw")

        local din dval
        while true; do
            read -r -p "  Duration seconds (0=unlimited) [10]: " din </dev/tty
            din="${din:-10}"
            if validate_duration "$din"; then
                [[ "$din" == "unlimited" || "$din" == "inf" ]] \
                    && dval=0 || dval=$(( 10#$din ))
                break
            fi
            printf '%b\n' "${RED}  Invalid. Enter a non-negative integer or 'unlimited'.${NC}"
        done
        S_DURATION+=("$dval")

        prompt_dscp "$sn"
        S_DSCP_NAME+=("$PROMPT_DSCP_NAME"); S_DSCP_VAL+=("$PROMPT_DSCP_VAL")

        local pv
        while true; do
            read -r -p "  Parallel threads (-P) [1]: " pv </dev/tty
            pv="${pv:-1}"
            if [[ "$pv" =~ ^[0-9]+$ ]] && (( 10#$pv >= 1 && 10#$pv <= 128 )); then
                pv=$(( 10#$pv )); break
            fi
            printf '%b\n' "${RED}  Enter 1-128.${NC}"
        done
        S_PARALLEL+=("$pv")

        local ri; read -r -p "  Reverse mode -R? [no]: " ri </dev/tty
        local rev=0; [[ "$ri" =~ ^[Yy] ]] && rev=1
        S_REVERSE+=("$rev")

        local cca="" win="" mss=""
        if [[ "$proto" == "TCP" ]]; then
            echo ""; printf '%b\n' "${CYAN}  -- TCP Options (press Enter to skip each) --${NC}"
            if [[ "$OS_TYPE" == "linux" ]]; then
                [[ -r /proc/sys/net/ipv4/tcp_available_congestion_control ]] && \
                    printf '%b  Available CCAs: %s%b\n' "$CYAN" \
                    "$(< /proc/sys/net/ipv4/tcp_available_congestion_control)" "$NC"
            else
                printf '%b  Note: CCA support depends on your macOS iperf3 build.%b\n' \
                    "$YELLOW" "$NC"
            fi
            read -r -p "  CCA [kernel default]: " cca </dev/tty; cca="${cca:-}"
            while true; do
                read -r -p "  Window size (e.g. 256K, empty=default): " win </dev/tty
                win="${win:-}"
                [[ -z "$win" || "$win" =~ ^[0-9]+[KMGkmg]?$ ]] && break
                printf '%b\n' "${RED}  Invalid window size.${NC}"
            done
            while true; do
                read -r -p "  MSS (e.g. 1460, empty=default): " mss </dev/tty
                mss="${mss:-}"; [[ -z "$mss" ]] && break
                [[ "$mss" =~ ^[0-9]+$ ]] && (( 10#$mss >= 512 && 10#$mss <= 9000 )) && break
                printf '%b\n' "${RED}  Enter 512-9000 or press Enter to skip.${NC}"
            done
        fi
        S_CCA+=("$cca"); S_WINDOW+=("$win"); S_MSS+=("$mss")

        local bip=""
        local auto_vrf=""
        local bind_from_grt=0
        local _bind_table_shown=0

        echo ""
        printf '%b\n' "${CYAN}  -- Bind Source IP --${NC}"
        printf '%b\n' \
            "  Enter an IP, interface ${BOLD}#${NC} from table, '${BOLD}list${NC}' to show table, or '${BOLD}0${NC}' for auto."
        echo ""
        get_interface_list
        show_interface_table
        echo ""
        _bind_table_shown=1

        while true; do
            local _bind_raw
            read -r -p "  Bind source IP (0=auto, #=interface, IP, 'list'): " \
                _bind_raw </dev/tty
            _bind_raw="${_bind_raw:-}"

            if [[ -z "$_bind_raw" ]]; then
                printf '%b\n' \
                    "${RED}  A bind IP is required. Enter an IP, interface number, or 0 for auto.${NC}"
                continue
            fi

            local _bind_lower
            _bind_lower=$(printf '%s' "$_bind_raw" | tr '[:upper:]' '[:lower:]')
            if [[ "$_bind_lower" == "list" ]]; then
                echo ""; get_interface_list; show_interface_table; echo ""
                _bind_table_shown=1; continue
            fi

            if [[ "$_bind_raw" =~ ^[0-9]+$ ]]; then
                local _sel_num=$(( 10#$_bind_raw ))
                local _total_ifaces=${#IFACE_NAMES[@]}

                if (( _sel_num == 0 )); then
                    bip=""; auto_vrf=""; bind_from_grt=0
                    printf '%b\n' "${CYAN}  Auto source address selected (no bind IP, no VRF override).${NC}"
                    break
                fi

                if (( _sel_num >= 1 && _sel_num <= _total_ifaces )); then
                    local _sel_idx=$(( _sel_num - 1 ))
                    local _sel_ip="${IFACE_IPS[$_sel_idx]}"
                    local _sel_iface="${IFACE_NAMES[$_sel_idx]}"
                    local _sel_state="${IFACE_STATES[$_sel_idx]}"
                    local _sel_vrf="${IFACE_VRFS[$_sel_idx]}"

                    if [[ "$_sel_ip" == "N/A" || -z "$_sel_ip" ]]; then
                        printf '%b\n' \
                            "${RED}  ${_sel_iface} has no IPv4 address. Choose another or enter an IP.${NC}"
                        continue
                    fi

                    [[ "$_sel_state" != "up" ]] && \
                        printf '%b\n' "${YELLOW}  WARNING: ${_sel_iface} state='${_sel_state}'.${NC}"

                    printf '%b  Bound to: %s → %s%b\n' "$GREEN" "$_sel_iface" "$_sel_ip" "$NC"
                    bip="$_sel_ip"

                    if [[ "$OS_TYPE" == "linux" ]]; then
                        if [[ "$_sel_vrf" == "GRT" || -z "$_sel_vrf" ]]; then
                            auto_vrf=""; bind_from_grt=1
                            printf '%b  Interface is in GRT — VRF will not be used for this stream.%b\n' \
                                "$CYAN" "$NC"
                        else
                            auto_vrf="$_sel_vrf"; bind_from_grt=0
                            printf '%b  Auto-detected VRF from interface: %s%b\n' \
                                "$GREEN" "$auto_vrf" "$NC"
                        fi
                    fi
                    break
                else
                    printf '%b\n' "${RED}  Invalid number. Enter 0 or 1-${_total_ifaces}.${NC}"
                    continue
                fi
            fi

            if validate_ip "$_bind_raw"; then
                printf '%b  Bind IP set to: %s%b\n' "$GREEN" "$_bind_raw" "$NC"
                bip="$_bind_raw"; auto_vrf=""; bind_from_grt=0; break
            fi

            printf '%b\n' "${RED}  Unrecognised input '${_bind_raw}'.${NC}"
            printf '%b\n' "${RED}  Enter: IP address | interface number | 'list' | 0 for auto${NC}"
        done
        S_BIND+=("$bip")

        local vval=""
        if [[ "$OS_TYPE" == "linux" ]]; then
            if (( bind_from_grt == 1 )); then
                vval=""
                printf '%b  Stream will use GRT (no VRF exec applied).%b\n' "$CYAN" "$NC"
            elif [[ -n "$auto_vrf" ]]; then
                printf '%b\n' \
                    "  ${GREEN}Auto-detected VRF: ${BOLD}${auto_vrf}${NC}${GREEN} (from selected interface)${NC}"
                read -r -p "  VRF [${auto_vrf}]: " vval </dev/tty
                vval="${vval:-$auto_vrf}"
                if [[ -z "$vval" ]]; then
                    printf '%b  VRF cleared — stream will use GRT.%b\n' "$YELLOW" "$NC"
                else
                    if [[ -n "$bip" ]]; then
                        local _vrf_match=0 _ki
                        for (( _ki=0; _ki<${#IFACE_IPS[@]}; _ki++ )); do
                            if [[ "${IFACE_IPS[$_ki]}" == "$bip" && \
                                  "${IFACE_VRFS[$_ki]}" == "$vval" ]]; then
                                _vrf_match=1; break
                            fi
                        done
                        if (( _vrf_match == 0 )); then
                            printf '%b\n' \
                                "${YELLOW}  WARNING: bind IP ${bip} does not appear to belong to VRF ${vval}.${NC}"
                            printf '%b\n' \
                                "${YELLOW}           Stream may fail with 'bad file descriptor' at runtime.${NC}"
                        fi
                    fi
                    (( IS_ROOT == 0 )) && \
                        printf '%b\n' "${YELLOW}  WARNING: ip vrf exec requires root.${NC}"
                    printf '%b  Stream will use VRF: %s%b\n' "$CYAN" "$vval" "$NC"
                fi
            elif [[ -n "$dvrf" ]]; then
                read -r -p "  VRF [$dvrf]: " vval </dev/tty
                vval="${vval:-$dvrf}"
                if [[ -n "$vval" ]]; then
                    (( IS_ROOT == 0 )) && \
                        printf '%b\n' "${YELLOW}  WARNING: ip vrf exec requires root.${NC}"
                    printf '%b  Stream will use VRF: %s%b\n' "$CYAN" "$vval" "$NC"
                else
                    printf '%b  Stream will use GRT (no VRF).%b\n' "$CYAN" "$NC"
                fi
            else
                read -r -p "  VRF (press Enter for GRT/none): " vval </dev/tty
                vval="${vval:-}"
                if [[ -n "$vval" ]]; then
                    if [[ -n "$bip" && "$bip" != "0.0.0.0" ]]; then
                        local _vrf_match=0 _ki
                        for (( _ki=0; _ki<${#IFACE_IPS[@]}; _ki++ )); do
                            if [[ "${IFACE_IPS[$_ki]}" == "$bip" && \
                                  "${IFACE_VRFS[$_ki]}" == "$vval" ]]; then
                                _vrf_match=1; break
                            fi
                        done
                        if (( _vrf_match == 0 )); then
                            printf '%b\n' \
                                "${YELLOW}  WARNING: bind IP ${bip} was not found on any interface in VRF ${vval}.${NC}"
                            printf '%b\n' \
                                "${YELLOW}           If this IP belongs to GRT, leave VRF blank.${NC}"
                            printf '%b\n' \
                                "${YELLOW}           Proceeding — stream may fail with 'bad file descriptor'.${NC}"
                        fi
                    fi
                    (( IS_ROOT == 0 )) && \
                        printf '%b\n' "${YELLOW}  WARNING: ip vrf exec requires root.${NC}"
                    printf '%b  Stream will use VRF: %s%b\n' "$CYAN" "$vval" "$NC"
                else
                    printf '%b  Stream will use GRT (no VRF).%b\n' "$CYAN" "$NC"
                fi
            fi
        fi
        S_VRF+=("$vval")

        local dly="" jit="" loss=""
        if [[ "$OS_TYPE" == "linux" ]]; then
            echo ""
            printf '%b\n' "${CYAN}  -- Network Impairment via tc netem (press Enter to skip each) --${NC}"
            while true; do
                read -r -p "  Delay ms   [skip]: " dly </dev/tty; dly="${dly:-}"
                [[ -z "$dly" ]] && break
                if validate_float "$dly"; then break; fi
                printf '%b\n' "${RED}  Invalid. Enter a number e.g. 100${NC}"
            done
            while true; do
                read -r -p "  Jitter ms  [skip]: " jit </dev/tty; jit="${jit:-}"
                [[ -z "$jit" ]] && break
                if validate_float "$jit"; then break; fi
                printf '%b\n' "${RED}  Invalid. Enter a number e.g. 10${NC}"
            done
            while true; do
                read -r -p "  Loss %%     [skip]: " loss </dev/tty; loss="${loss:-}"
                [[ -z "$loss" ]] && break
                if validate_float "$loss"; then
                    local li; li=$(printf '%.0f' "$loss" 2>/dev/null)
                    if (( li > 100 )); then
                        printf '%b\n' "${RED}  Loss must be between 0 and 100.${NC}"
                        loss=""; continue
                    fi
                    break
                fi
                printf '%b\n' "${RED}  Invalid. Enter a number e.g. 0.5${NC}"
            done
            [[ ( -n "$dly" || -n "$jit" || -n "$loss" ) && $IS_ROOT -eq 0 ]] && \
                printf '%b\n' "${YELLOW}  WARNING: tc netem requires root privileges.${NC}"
        else
            printf '%b\n' \
                "${YELLOW}  -- Network impairment (tc netem) not available on macOS --${NC}"
        fi
        S_DELAY+=("$dly"); S_JITTER+=("$jit"); S_LOSS+=("$loss")

        local nofq=0
        if [[ "$OS_TYPE" == "linux" ]]; then
            (( NOFQ_SUPPORTED )) && {
                local nfi; read -r -p "  Disable FQ socket pacing? [no]: " nfi </dev/tty
                [[ "$nfi" =~ ^[Yy] ]] && nofq=1
            }
        fi
        S_NOFQ+=("$nofq")

        S_LOGFILE+=(""); S_SCRIPT+=(""); S_START_TS+=(0)
        S_STATUS_CACHE+=("STARTING"); S_ERROR_MSG+=("")
        S_FINAL_SENDER_BW+=(""); S_FINAL_RECEIVER_BW+=("")
    done
    STREAM_COUNT="$num"
}

configure_server_streams() {
    local num="$1" dbind="${2:-}" dvrf="${3:-}"
    SRV_PORT=(); SRV_BIND=(); SRV_VRF=(); SRV_ONEOFF=(); SRV_LOGFILE=(); SRV_SCRIPT=()
    local lp=5200 i

    for (( i=0; i<num; i++ )); do
        local sn=$(( i + 1 ))
        echo ""; bline '='; bcenter "${BOLD}Server Listener ${sn} of ${num}${NC}"; bline '='; echo ""

        # ── Port ─────────────────────────────────────────────────────────────
        local dp=$(( lp + 1 )) port
        while true; do
            read -r -p "  Listen port [$dp]: " port </dev/tty
            port="${port:-$dp}"
            if validate_port "$port"; then
                port=$(( 10#$port ))
                (( port < 1024 && IS_ROOT == 0 )) && \
                    printf '%b\n' "${YELLOW}  WARNING: port $port < 1024 requires root.${NC}"
                break
            fi
            printf '%b\n' "${RED}  Invalid port. Enter 1-65535.${NC}"
        done
        lp="$port"; SRV_PORT+=("$port")

        # ── Bind IP ───────────────────────────────────────────────────────────
        # The operator can:
        #   Enter    → bind to 0.0.0.0 (all interfaces)
        #   0        → bind to 0.0.0.0 (all interfaces, explicit)
        #   list     → print the interface table, then re-prompt
        #   1..N     → select interface #N from the table
        #   x.x.x.x  → enter a specific IP directly
        #
        # When an interface is selected by number, the VRF membership of
        # that interface is auto-detected and used as the default VRF.

        local bip=""
        local auto_vrf=""
        local bind_from_grt=0
        local _srv_bind_table_shown=0

        echo ""
        printf '%b\n' "${CYAN}  -- Bind IP Address --${NC}"
        printf '%b\n' \
            "  Enter an IP, interface ${BOLD}#${NC} from table, '${BOLD}list${NC}' to show table, or ${BOLD}Enter${NC} for 0.0.0.0."
        echo ""

        # Show the interface table automatically the first time
        get_interface_list
        show_interface_table
        echo ""
        _srv_bind_table_shown=1

        while true; do
            local _srv_bind_raw
            read -r -p "  Bind IP (Enter=0.0.0.0, #=interface, IP, 'list'): " \
                _srv_bind_raw </dev/tty
            _srv_bind_raw="${_srv_bind_raw:-}"

            # ── Empty input → bind all interfaces ────────────────────────────
            if [[ -z "$_srv_bind_raw" ]]; then
                bip=""
                auto_vrf=""
                bind_from_grt=0
                printf '%b\n' "${CYAN}  Listener will bind to 0.0.0.0 (all interfaces).${NC}"
                break
            fi

            # ── 'list' keyword → refresh and reprint table ────────────────────
            local _srv_bind_lower
            _srv_bind_lower=$(printf '%s' "$_srv_bind_raw" | tr '[:upper:]' '[:lower:]')
            if [[ "$_srv_bind_lower" == "list" ]]; then
                echo ""
                get_interface_list
                show_interface_table
                echo ""
                _srv_bind_table_shown=1
                continue
            fi

            # ── Numeric input → select interface by table row number ──────────
            if [[ "$_srv_bind_raw" =~ ^[0-9]+$ ]]; then
                local _srv_sel_num=$(( 10#$_srv_bind_raw ))
                local _srv_total_ifaces=${#IFACE_NAMES[@]}

                # 0 = explicit all-interfaces bind
                if (( _srv_sel_num == 0 )); then
                    bip=""
                    auto_vrf=""
                    bind_from_grt=0
                    printf '%b\n' "${CYAN}  Listener will bind to 0.0.0.0 (all interfaces).${NC}"
                    break
                fi

                if (( _srv_sel_num >= 1 && _srv_sel_num <= _srv_total_ifaces )); then
                    local _srv_sel_idx=$(( _srv_sel_num - 1 ))
                    local _srv_sel_ip="${IFACE_IPS[$_srv_sel_idx]}"
                    local _srv_sel_iface="${IFACE_NAMES[$_srv_sel_idx]}"
                    local _srv_sel_state="${IFACE_STATES[$_srv_sel_idx]}"
                    local _srv_sel_vrf="${IFACE_VRFS[$_srv_sel_idx]}"

                    # Reject interfaces with no IPv4 address
                    if [[ "$_srv_sel_ip" == "N/A" || -z "$_srv_sel_ip" ]]; then
                        printf '%b\n' \
                            "${RED}  ${_srv_sel_iface} has no IPv4 address. Choose another or enter an IP directly.${NC}"
                        continue
                    fi

                    # Warn but allow non-up interfaces
                    if [[ "$_srv_sel_state" != "up" ]]; then
                        printf '%b\n' \
                            "${YELLOW}  WARNING: ${_srv_sel_iface} state='${_srv_sel_state}'.${NC}"
                    fi

                    printf '%b  Bind IP: %s → %s%b\n' \
                        "$GREEN" "$_srv_sel_iface" "$_srv_sel_ip" "$NC"
                    bip="$_srv_sel_ip"

                    # ── Auto-detect VRF from selected interface ────────────────
                    if [[ "$OS_TYPE" == "linux" ]]; then
                        if [[ "$_srv_sel_vrf" == "GRT" || -z "$_srv_sel_vrf" ]]; then
                            auto_vrf=""
                            bind_from_grt=1
                            printf '%b  Interface is in GRT — VRF will not be used for this listener.%b\n' \
                                "$CYAN" "$NC"
                        else
                            auto_vrf="$_srv_sel_vrf"
                            bind_from_grt=0
                            printf '%b  Auto-detected VRF from interface: %s%b\n' \
                                "$GREEN" "$auto_vrf" "$NC"
                        fi
                    fi
                    break

                else
                    printf '%b\n' \
                        "${RED}  Invalid number. Enter 0 or 1-${_srv_total_ifaces}.${NC}"
                    continue
                fi
            fi

            # ── Direct IP address entry ───────────────────────────────────────
            if validate_ip "$_srv_bind_raw"; then
                printf '%b  Bind IP set to: %s%b\n' "$GREEN" "$_srv_bind_raw" "$NC"
                bip="$_srv_bind_raw"
                auto_vrf=""
                bind_from_grt=0
                break
            fi

            # ── Unrecognised input ────────────────────────────────────────────
            printf '%b\n' "${RED}  Unrecognised input '${_srv_bind_raw}'.${NC}"
            printf '%b\n' \
                "${RED}  Enter: IP address | interface number | 'list' | Enter for 0.0.0.0${NC}"
        done
        SRV_BIND+=("$bip")

        # ── VRF (Linux only) ──────────────────────────────────────────────────
        #
        # Decision matrix — same as client mode:
        #
        #   bind_from_grt == 1   → GRT interface selected, skip VRF prompt,
        #                          force vval="" so no ip vrf exec is applied.
        #
        #   auto_vrf non-empty   → VRF auto-detected from interface selection.
        #                          Present as default, operator can override.
        #
        #   bip empty (0.0.0.0)  → No specific interface, allow optional VRF.
        #
        #   bip non-empty +
        #   no auto_vrf          → Raw IP entered. Prompt for optional VRF.
        #
        local vval=""
        if [[ "$OS_TYPE" == "linux" ]]; then

            if (( bind_from_grt == 1 )); then
                # GRT interface — skip VRF prompt entirely
                vval=""
                printf '%b  Listener will use GRT (no VRF exec applied).%b\n' \
                    "$CYAN" "$NC"

            elif [[ -n "$auto_vrf" ]]; then
                # VRF auto-detected from selected interface
                printf '%b\n' \
                    "  ${GREEN}Auto-detected VRF: ${BOLD}${auto_vrf}${NC}${GREEN} (from selected interface)${NC}"
                read -r -p "  VRF [${auto_vrf}]: " vval </dev/tty
                vval="${vval:-$auto_vrf}"

                if [[ -z "$vval" ]]; then
                    printf '%b  VRF cleared — listener will use GRT.%b\n' \
                        "$YELLOW" "$NC"
                else
                    if (( IS_ROOT == 0 )); then
                        printf '%b\n' \
                            "${YELLOW}  WARNING: ip vrf exec requires root.${NC}"
                    fi
                    printf '%b  Listener will use VRF: %s%b\n' "$CYAN" "$vval" "$NC"
                fi

            elif [[ -n "$dvrf" ]]; then
                # Session-level VRF default
                read -r -p "  VRF [$dvrf]: " vval </dev/tty
                vval="${vval:-$dvrf}"
                if [[ -n "$vval" ]]; then
                    (( IS_ROOT == 0 )) && \
                        printf '%b\n' "${YELLOW}  WARNING: ip vrf exec requires root.${NC}"
                    printf '%b  Listener will use VRF: %s%b\n' "$CYAN" "$vval" "$NC"
                else
                    printf '%b  Listener will use GRT (no VRF).%b\n' "$CYAN" "$NC"
                fi

            else
                # No auto-detection — prompt for optional VRF
                read -r -p "  VRF (press Enter for GRT/none): " vval </dev/tty
                vval="${vval:-}"
                if [[ -n "$vval" ]]; then
                    (( IS_ROOT == 0 )) && \
                        printf '%b\n' "${YELLOW}  WARNING: ip vrf exec requires root.${NC}"
                    printf '%b  Listener will use VRF: %s%b\n' "$CYAN" "$vval" "$NC"
                else
                    printf '%b  Listener will use GRT (no VRF).%b\n' "$CYAN" "$NC"
                fi
            fi
        fi
        SRV_VRF+=("$vval")

        # ── One-off mode ──────────────────────────────────────────────────────
        local oi
        read -r -p "  One-off mode -1 (exit after one client)? [no]: " oi </dev/tty
        local oo=0; [[ "$oi" =~ ^[Yy] ]] && oo=1
        SRV_ONEOFF+=("$oo")
        SRV_LOGFILE+=("")
        SRV_SCRIPT+=("")
    done

    SERVER_COUNT="$num"
}

show_stream_summary() {
    local mode="${1:-client}"; echo ""; print_header "Stream Configuration Summary"; echo ""
    if [[ "$mode" == "client" ]]; then
        printf '  %-3s  %-5s  %-18s  %-6s  %-10s  %-5s  %-5s  %-10s\n' \
            "#" "Proto" "Target" "Port" "Bandwidth" "Dur" "DSCP" "VRF"
        printf '  %s\n' "$(rpt '-' 72)"
        local i
        for (( i=0; i<STREAM_COUNT; i++ )); do
            local dd; (( S_DURATION[$i] == 0 )) && dd="inf" || dd="${S_DURATION[$i]}s"
            local vrf_disp="${S_VRF[$i]:-GRT}"; [[ "$OS_TYPE" == "macos" ]] && vrf_disp="N/A"
            printf '  %-3d  %-5s  %-18s  %-6s  %-10s  %-5s  %-5s  %-10s\n' \
                "$((i+1))" "${S_PROTO[$i]}" "${S_TARGET[$i]}" "${S_PORT[$i]}" \
                "${S_BW[$i]:-unlimited}" "$dd" "${S_DSCP_NAME[$i]:-none}" "$vrf_disp"
            local ex=""
            [[ -n "${S_CCA[$i]}"    ]] && ex+=" CCA:${S_CCA[$i]}"
            [[ -n "${S_WINDOW[$i]}" ]] && ex+=" Win:${S_WINDOW[$i]}"
            [[ -n "${S_MSS[$i]}"    ]] && ex+=" MSS:${S_MSS[$i]}"
            (( S_REVERSE[$i]  == 1  )) && ex+=" [REV]"
            (( S_PARALLEL[$i] >  1  )) && ex+=" P:${S_PARALLEL[$i]}"
            if [[ "$OS_TYPE" == "linux" ]]; then
                [[ -n "${S_DELAY[$i]}" ]] && ex+=" delay:${S_DELAY[$i]}ms"
                [[ -n "${S_LOSS[$i]}"  ]] && ex+=" loss:${S_LOSS[$i]}%"
            fi
            [[ -n "$ex" ]] && printf '%b    %s%b\n' "$CYAN" "$ex" "$NC"
        done
        printf '  %s\n' "$(rpt '-' 72)"
    else
        printf '  %-3s  %-7s  %-18s  %-12s  %-6s\n' "#" "Port" "Bind IP" "VRF" "1-off"
        printf '  %s\n' "$(rpt '-' 52)"
        local i
        for (( i=0; i<SERVER_COUNT; i++ )); do
            local oo="no"; (( SRV_ONEOFF[$i] )) && oo="yes"
            local vrf_disp="${SRV_VRF[$i]:-GRT}"; [[ "$OS_TYPE" == "macos" ]] && vrf_disp="N/A"
            printf '  %-3d  %-7s  %-18s  %-12s  %-6s\n' \
                "$((i+1))" "${SRV_PORT[$i]}" "${SRV_BIND[$i]:-0.0.0.0}" "$vrf_disp" "$oo"
        done
        printf '  %s\n' "$(rpt '-' 52)"
    fi; echo ""
}

# =============================================================================
# SECTION 10 — COMMAND BUILDING AND LAUNCHING
# =============================================================================

build_server_command() {
    local idx="$1" cmd=""
    [[ "$OS_TYPE" == "linux" && -n "${SRV_VRF[$idx]}" ]] && \
        cmd="ip vrf exec ${SRV_VRF[$idx]} "
    cmd+="${IPERF3_BIN} -s -p ${SRV_PORT[$idx]}"
    [[ -n "${SRV_BIND[$idx]}" ]] && cmd+=" -B ${SRV_BIND[$idx]}"
    (( SRV_ONEOFF[$idx] )) && cmd+=" -1"
    cmd+=" -i 1"
    (( FORCEFLUSH_SUPPORTED )) && cmd+=" --forceflush"
    printf '%s' "$cmd"
}

build_client_command() {
    local idx="$1" cmd=""

    local stream_vrf="${S_VRF[$idx]:-}"
    local stream_bind="${S_BIND[$idx]:-}"

    if [[ -n "$stream_vrf" && -n "$stream_bind" && \
          "$stream_bind" != "0.0.0.0" && \
          "$OS_TYPE" == "linux" ]]; then
        local _vrf_consistent=0 _ki
        for (( _ki=0; _ki<${#IFACE_IPS[@]}; _ki++ )); do
            if [[ "${IFACE_IPS[$_ki]}"  == "$stream_bind" && \
                  "${IFACE_VRFS[$_ki]}" == "$stream_vrf"  ]]; then
                _vrf_consistent=1; break
            fi
        done
        if (( _vrf_consistent == 0 )); then
            local _in_grt=0
            for (( _ki=0; _ki<${#IFACE_IPS[@]}; _ki++ )); do
                if [[ "${IFACE_IPS[$_ki]}"  == "$stream_bind" && \
                      "${IFACE_VRFS[$_ki]}" == "GRT" ]]; then
                    _in_grt=1; break
                fi
            done
            if (( _in_grt == 1 )); then
                printf '%b\n' \
                    "${YELLOW}  [WARN] Stream $((idx+1)): bind IP ${stream_bind} is in GRT but VRF '${stream_vrf}' was configured. VRF cleared to prevent bad file descriptor.${NC}" >&2
                stream_vrf=""
            fi
        fi
    fi

    if [[ "$OS_TYPE" == "linux" && -n "$stream_vrf" ]]; then
        cmd="ip vrf exec ${stream_vrf} "
    fi

    cmd+="${IPERF3_BIN} -c ${S_TARGET[$idx]} -p ${S_PORT[$idx]}"
    [[ "${S_PROTO[$idx]}" == "UDP" ]] && cmd+=" -u"
    [[ -n "${S_BW[$idx]}" ]] && cmd+=" -b ${S_BW[$idx]}"
    if (( S_DURATION[$idx] == 0 )); then
        version_ge 3 1 && cmd+=" -t 0" || cmd+=" -t 86400"
    else
        cmd+=" -t ${S_DURATION[$idx]}"
    fi
    cmd+=" -i 1"
    (( S_PARALLEL[$idx] > 1 ))  && cmd+=" -P ${S_PARALLEL[$idx]}"
    (( S_REVERSE[$idx]  == 1 )) && cmd+=" -R"
    if [[ -n "${S_DSCP_VAL[$idx]}" ]] && (( S_DSCP_VAL[$idx] >= 0 )); then
        cmd+=" -S $(( S_DSCP_VAL[$idx] * 4 ))"
    fi
    [[ -n "${S_CCA[$idx]}"    ]] && cmd+=" -C ${S_CCA[$idx]}"
    [[ -n "${S_WINDOW[$idx]}" ]] && cmd+=" -w ${S_WINDOW[$idx]}"
    [[ -n "${S_MSS[$idx]}"    ]] && cmd+=" -M ${S_MSS[$idx]}"
    [[ -n "$stream_bind"      ]] && cmd+=" -B $stream_bind"
    if [[ "$OS_TYPE" == "linux" ]]; then
        (( S_NOFQ[$idx] )) && (( NOFQ_SUPPORTED )) && cmd+=" --no-fq-socket-pacing"
    fi
    (( FORCEFLUSH_SUPPORTED )) && cmd+=" --forceflush"
    printf '%s' "$cmd"
}

write_launch_script() {
    local sf="$1" cmd="$2"
    [[ -d "$TMPDIR" ]] || { printf '%b\n' "${RED}ERROR: TMPDIR missing.${NC}"; return 1; }
    printf '#!/usr/bin/env bash\n%s\n' "$cmd" > "$sf"; chmod +x "$sf"
}

launch_servers() {
    SERVER_PIDS=(); SRV_PREV_STATE=(); SRV_BW_CACHE=()
    local i
    for (( i=0; i<SERVER_COUNT; i++ )); do
        local sn=$(( i + 1 )) sf="${TMPDIR}/server_${sn}.sh" lf="${TMPDIR}/server_${sn}.log"
        if ! write_launch_script "$sf" "$(build_server_command "$i")"; then
            printf '%b\n' "${RED}  [ERROR] Cannot write script for server ${sn}.${NC}"
            SERVER_PIDS+=(0); SRV_LOGFILE[$i]="$lf"
            SRV_PREV_STATE+=(""); SRV_BW_CACHE+=("---"); continue
        fi
        SRV_SCRIPT[$i]="$sf"; SRV_LOGFILE[$i]="$lf"
        bash "$sf" > "$lf" 2>&1 &
        local pid=$!
        SERVER_PIDS+=("$pid"); SRV_PREV_STATE+=(""); SRV_BW_CACHE+=("---")
        printf '%b[STARTED]%b  server %d  PID %-6d  port %s\n' \
            "$GREEN" "$NC" "$sn" "$pid" "${SRV_PORT[$i]}"
    done
}

launch_clients() {
    STREAM_PIDS=()
    local i
    for (( i=0; i<STREAM_COUNT; i++ )); do
        local sn=$(( i + 1 )) sf="${TMPDIR}/stream_${sn}.sh" lf="${TMPDIR}/stream_${sn}.log"
        if ! write_launch_script "$sf" "$(build_client_command "$i")"; then
            printf '%b\n' "${RED}  [ERROR] Cannot write script for stream ${sn}.${NC}"
            STREAM_PIDS+=(0); S_LOGFILE[$i]="$lf"
            S_STATUS_CACHE[$i]="FAILED"; S_ERROR_MSG[$i]="Script creation failed"; continue
        fi
        S_SCRIPT[$i]="$sf"; S_LOGFILE[$i]="$lf"
        S_START_TS[$i]=$(date +%s); S_STATUS_CACHE[$i]="STARTING"; S_ERROR_MSG[$i]=""
        bash "$sf" > "$lf" 2>&1 &
        local pid=$!; STREAM_PIDS+=("$pid")
        printf '%b[STARTED]%b  stream %d  PID %-6d  %s -> %s:%s\n' \
            "$GREEN" "$NC" "$sn" "$pid" "${S_PROTO[$i]}" "${S_TARGET[$i]}" "${S_PORT[$i]}"
    done
}

wait_for_servers() {
    local timeout=15 i all_ok=1
    printf '%b\n' "  ${CYAN}Waiting for servers to start listening...${NC}"
    for (( i=0; i<SERVER_COUNT; i++ )); do
        local sn=$(( i + 1 )) port="${SRV_PORT[$i]}" elapsed=0 ready=0
        while (( elapsed < timeout * 2 )); do
            if [[ "$OS_TYPE" == "macos" ]]; then
                lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 && ready=1 && break
            else
                ss -tlnp 2>/dev/null | grep -qE ":${port}([[:space:]]|$|:)" && ready=1 && break
            fi
            sleep 0.5; (( elapsed++ ))
        done
        (( ready )) \
            && printf '%b[READY  ]%b  server %d  port %s\n' "$GREEN" "$NC" "$sn" "$port" \
            || { printf '%b[TIMEOUT]%b  server %d  port %s -- not listening after %ds\n' \
                    "$RED" "$NC" "$sn" "$port" "$timeout"; all_ok=0; }
    done; return $(( 1 - all_ok ))
}

apply_netem() {
    [[ "$OS_TYPE" == "macos" ]] && return 0
    NETEM_IFACES=()
    local i
    for (( i=0; i<STREAM_COUNT; i++ )); do
        local dly="${S_DELAY[$i]:-}" jit="${S_JITTER[$i]:-}" loss="${S_LOSS[$i]:-}"
        [[ -z "$dly" && -z "$jit" && -z "$loss" ]] && continue
        if (( IS_ROOT == 0 )); then
            printf '%b\n' "${YELLOW}  WARNING: tc netem skipped for stream $((i+1)) -- not root.${NC}"; continue
        fi
        local oif=""
        if command -v ip >/dev/null 2>&1; then
            oif=$(ip route get "${S_TARGET[$i]}" 2>/dev/null \
                | grep -oE '\bdev [^ ]+' | awk '{print $2}' | head -1)
        fi
        if [[ -z "$oif" ]]; then
            printf '%b\n' "${YELLOW}  WARNING: cannot resolve route for ${S_TARGET[$i]} -- netem skipped for stream $((i+1)).${NC}"
            continue
        fi
        if [[ "$oif" == lo || "$oif" == lo0 || "$oif" =~ ^lo[0-9] ]]; then
            printf '%b\n' "${YELLOW}  WARNING: stream $((i+1)) routes via loopback (${oif}) -- netem skipped.${NC}"
            continue
        fi
        local already_applied=0
        local applied_iface
        for applied_iface in "${NETEM_IFACES[@]}"; do
            [[ "$applied_iface" == "$oif" ]] && already_applied=1 && break
        done
        if (( already_applied )); then
            printf '%b  [NETEM  ]  dev %-12s  already applied -- shared by stream %d%b\n' \
                "$CYAN" "$oif" "$((i+1))" "$NC"
            continue
        fi
        tc qdisc del dev "$oif" root 2>/dev/null || true
        local nc="tc qdisc add dev ${oif} root netem"
        if [[ -n "$dly" && -n "$jit" ]]; then
            nc+=" delay ${dly}ms ${jit}ms"
        elif [[ -n "$dly" ]]; then
            nc+=" delay ${dly}ms"
        elif [[ -n "$jit" ]]; then
            nc+=" delay 0ms ${jit}ms"
        fi
        [[ -n "$loss" ]] && nc+=" loss ${loss}%"
        if bash -c "$nc" 2>/dev/null; then
            printf '%b[NETEM  ]%b  dev %-12s  delay=%s jitter=%s loss=%s\n' \
                "$GREEN" "$NC" "$oif" "${dly:-0}ms" "${jit:-0}ms" "${loss:-0}%"
            NETEM_IFACES+=("$oif")
        else
            printf '%b\n' "${RED}  WARNING: tc netem failed on ${oif} for stream $((i+1)).${NC}"
        fi
    done
}

# =============================================================================
# SECTION 10b — PRE-FLIGHT CONNECTIVITY CHECKS
# =============================================================================

_preflight_ping_vrf() {
    local target="$1"
    local vrf_name="${2:-}"
    local ping_out loss_pct rtt_summary status

    if [[ "$OS_TYPE" == "macos" ]]; then
        ping_out=$(ping -c 3 -W 2000 "$target" 2>&1)
    else
        if [[ -n "$vrf_name" ]]; then
            ping_out=$(ip vrf exec "${vrf_name}" ping -c 3 -W 2 "$target" 2>&1)
        else
            ping_out=$(ping -c 3 -W 2 "$target" 2>&1)
        fi
    fi

    loss_pct=$(printf '%s' "$ping_out" \
        | grep -oE '[0-9]+(\.[0-9]+)?% packet loss' \
        | grep -oE '^[0-9]+(\.[0-9]+)?')
    loss_pct="${loss_pct:-100}"

    local rtt_line
    rtt_line=$(printf '%s' "$ping_out" | grep -E 'min/avg/max')
    if [[ -n "$rtt_line" ]]; then
        local rtt_vals
        rtt_vals=$(printf '%s' "$rtt_line" \
            | grep -oE '[0-9]+\.[0-9]+/[0-9]+\.[0-9]+/[0-9]+\.[0-9]+')
        if [[ -n "$rtt_vals" ]]; then
            local rtt_min rtt_avg rtt_max
            rtt_min=$(printf '%s' "$rtt_vals" | cut -d/ -f1)
            rtt_avg=$(printf '%s' "$rtt_vals" | cut -d/ -f2)
            rtt_max=$(printf '%s' "$rtt_vals" | cut -d/ -f3)
            rtt_summary="${rtt_min}/${rtt_avg}/${rtt_max} ms"
        else
            rtt_summary="N/A"
        fi
    else
        rtt_summary="N/A"
    fi

    local loss_int
    loss_int=$(printf '%.0f' "$loss_pct" 2>/dev/null || echo 100)
    if   (( loss_int == 0   )); then status="PASS"
    elif (( loss_int == 100 )); then status="FAIL"
    else                              status="WARN"
    fi

    printf '%s|%s|%s%%' "$status" "$rtt_summary" "$loss_int"
}

_preflight_tcp_port_vrf() {
    local target="$1"
    local port="$2"
    local vrf_name="${3:-}"
    local result=1

    if [[ -n "$vrf_name" && "$OS_TYPE" == "linux" ]]; then
        local probe_script="${TMPDIR}/_preflight_tcp_probe_$$.sh"
        cat > "$probe_script" << PROBE_EOF
#!/usr/bin/env bash
(
    exec 5<>"/dev/tcp/${target}/${port}"
    echo \$?
    exec 5>&-
) 2>/dev/null
PROBE_EOF
        chmod +x "$probe_script"
        local probe_out
        probe_out=$(timeout 3 ip vrf exec "${vrf_name}" bash "$probe_script" 2>/dev/null)
        rm -f "$probe_script"
        [[ "$probe_out" == "0" ]] && result=0
    else
        local probe_out
        probe_out=$(
            (
                if [[ "$OS_TYPE" == "macos" ]]; then
                    exec 5<>"/dev/tcp/${target}/${port}" 2>/dev/null
                    echo $?
                    exec 5>&-
                else
                    timeout 2 bash -c \
                        "exec 5<>/dev/tcp/${target}/${port}" 2>/dev/null
                    echo $?
                fi
            ) 2>/dev/null
        )
        [[ "$probe_out" == "0" ]] && result=0
    fi

    (( result == 0 )) && printf '%s' "PASS" || printf '%s' "FAIL"
}

_find_traceroute_bin() {
    local bin_in_path
    bin_in_path=$(command -v traceroute 2>/dev/null)
    if [[ -n "$bin_in_path" && -x "$bin_in_path" ]]; then
        printf '%s|traceroute' "$bin_in_path"; return 0
    fi
    bin_in_path=$(command -v tracepath 2>/dev/null)
    if [[ -n "$bin_in_path" && -x "$bin_in_path" ]]; then
        printf '%s|tracepath' "$bin_in_path"; return 0
    fi

    local -a candidates=(
        "traceroute:/usr/bin/traceroute"
        "traceroute:/usr/sbin/traceroute"
        "traceroute:/sbin/traceroute"
        "traceroute:/usr/local/bin/traceroute"
        "traceroute:/opt/homebrew/bin/traceroute"
        "tracepath:/usr/bin/tracepath"
        "tracepath:/usr/sbin/tracepath"
        "tracepath:/sbin/tracepath"
        "tracepath:/usr/local/bin/tracepath"
    )
    local entry bin_type bin_path
    for entry in "${candidates[@]}"; do
        bin_type=$(printf '%s' "$entry" | cut -d: -f1)
        bin_path=$(printf '%s' "$entry" | cut -d: -f2)
        if [[ -x "$bin_path" ]]; then
            printf '%s|%s' "$bin_path" "$bin_type"; return 0
        fi
    done

    printf '%s' "UNAVAILABLE"; return 1
}

_preflight_sudo_warmup() {
    local vrf_name="${1:-}"
    (( IS_ROOT == 1 )) && return 0
    [[ "$OS_TYPE" != "linux" || -z "$vrf_name" ]] && return 0
    command -v sudo >/dev/null 2>&1 || return 0
    if sudo -n true 2>/dev/null; then return 0; fi
    printf '%b\n' \
        "${YELLOW}  sudo authentication required for VRF traceroute (ip vrf exec ${vrf_name})${NC}"
    printf '%b\n' "${CYAN}  Please enter your sudo password:${NC}"
    sudo -v </dev/tty 2>/dev/tty
    local sudo_rc=$?
    if (( sudo_rc != 0 )); then
        printf '%b\n' "${YELLOW}  sudo authentication failed or was cancelled.${NC}"
        printf '%b\n' "${YELLOW}  VRF traceroute will be skipped for VRF: ${vrf_name}${NC}"
        return 1
    fi
    printf '%b\n' "${GREEN}  sudo credential cached successfully.${NC}"
    return 0
}

_preflight_traceroute_vrf() {
    local target="$1"
    local vrf_name="${2:-}"
    local tr_out=""

    local bin_info
    bin_info=$(_find_traceroute_bin)
    if [[ "$bin_info" == "UNAVAILABLE" ]]; then
        printf '%s' "UNAVAILABLE"; return
    fi

    local tr_bin tr_type
    tr_bin=$(printf '%s' "$bin_info" | cut -d'|' -f1)
    tr_type=$(printf '%s' "$bin_info" | cut -d'|' -f2)

    if [[ "$OS_TYPE" == "linux" && -n "$vrf_name" ]]; then
        if [[ "$tr_type" == "traceroute" ]]; then
            tr_out=$(sudo ip vrf exec "${vrf_name}" \
                "${tr_bin}" -m 20 -w 2 -q 1 "${target}" \
                2>/dev/tty | tail -n +2)
        else
            tr_out=$(sudo ip vrf exec "${vrf_name}" \
                "${tr_bin}" "${target}" \
                2>/dev/tty | tail -n +2)
        fi
    elif [[ "$OS_TYPE" == "linux" ]]; then
        if [[ "$tr_type" == "traceroute" ]]; then
            tr_out=$("${tr_bin}" -m 20 -w 2 -q 1 "${target}" \
                2>/dev/null | tail -n +2)
        else
            tr_out=$("${tr_bin}" "${target}" \
                2>/dev/null | tail -n +2)
        fi
    else
        if [[ "$tr_type" == "traceroute" ]]; then
            tr_out=$("${tr_bin}" -m 20 -q 1 "${target}" \
                2>/dev/null | tail -n +2)
        else
            tr_out=$("${tr_bin}" "${target}" \
                2>/dev/null | tail -n +2)
        fi
    fi

    [[ -z "$tr_out" ]] && { printf '%s' "UNAVAILABLE"; return; }

    printf '%s' "$tr_out" | awk '
    {
        sub(/^[[:space:]]+/, "")
        if (NF == 0) next
        if ($0 ~ /pmtu|asymm|Resume/) next
        if ($1 !~ /^[0-9]/) next
        gsub(/\?$/, "", $1)
        hop = $1
        host = "* * *"
        rtt  = "---"
        for (i = 2; i <= NF; i++) {
            if ($i == "*") continue
            if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
                host = $i
                for (j = i+1; j <= NF; j++) {
                    if ($(j) ~ /^[0-9]+\.[0-9]+ms$/) {
                        v = $(j); gsub(/ms$/, "", v)
                        rtt = v " ms"; break
                    }
                    if ($(j) ~ /^[0-9]+\.[0-9]+$/) {
                        rtt = $(j) " ms"; break
                    }
                }
                break
            }
            if ($i ~ /^\(.*\)$/) {
                v = $i; gsub(/[()]/, "", v)
                if (v ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
                    host = v
                    for (j = i+1; j <= NF; j++) {
                        if ($(j) ~ /^[0-9]+\.[0-9]+ms$/) {
                            w = $(j); gsub(/ms$/, "", w)
                            rtt = w " ms"; break
                        }
                        if ($(j) ~ /^[0-9]+\.[0-9]+$/) {
                            rtt = $(j) " ms"; break
                        }
                    }
                    break
                }
            }
            if ($i !~ /^[0-9]+(\.[0-9]+)?$/ && \
                $i !~ /^ms$/ && \
                $i !~ /^\[/ ) {
                host = $i
                for (j = i+1; j <= NF; j++) {
                    if ($(j) ~ /^[0-9]+\.[0-9]+ms$/) {
                        w = $(j); gsub(/ms$/, "", w)
                        rtt = w " ms"; break
                    }
                    if ($(j) ~ /^[0-9]+\.[0-9]+$/) {
                        rtt = $(j) " ms"; break
                    }
                }
                break
            }
        }
        printf "%s|%s|%s\n", hop, host, rtt
    }'
}

run_preflight_checks() {
    local inner=$(( COLS - 2 ))

    printf '\n'
    printf '+%s+\n' "$(rpt '=' "$inner")"
    bcenter "${BOLD}${CYAN}Pre-Flight Connectivity Checks${NC}"
    printf '+%s+\n' "$(rpt '=' "$inner")"
    bleft "  Verifying reachability for all configured stream targets..."
    printf '+%s+\n' "$(rpt '-' "$inner")"
    printf '\n'

    local -a pf_targets=()
    local -a pf_ports=()
    local -a pf_protos=()
    local -a pf_vrfs=()
    local -a pf_stream_ids=()

    local i j found
    for (( i=0; i<STREAM_COUNT; i++ )); do
        local tgt="${S_TARGET[$i]}"
        local prt="${S_PORT[$i]}"
        local pro="${S_PROTO[$i]}"
        local vrf="${S_VRF[$i]:-}"
        found=0

        for (( j=0; j<${#pf_targets[@]}; j++ )); do
            if [[ "${pf_targets[$j]}" == "$tgt" && \
                  "${pf_ports[$j]}"   == "$prt" && \
                  "${pf_protos[$j]}"  == "$pro"  && \
                  "${pf_vrfs[$j]}"    == "$vrf"  ]]; then
                pf_stream_ids[$j]="${pf_stream_ids[$j]},$((i+1))"
                found=1; break
            fi
        done

        if (( found == 0 )); then
            pf_targets+=("$tgt"); pf_ports+=("$prt")
            pf_protos+=("$pro");  pf_vrfs+=("$vrf")
            pf_stream_ids+=("$((i+1))")
        fi
    done

    local total_checks=${#pf_targets[@]}
    local any_fail=0 any_warn=0

    local -a res_ping_status=()
    local -a res_ping_rtt=()
    local -a res_ping_loss=()
    local -a res_tcp_status=()
    local -a res_overall=()

    local k
    for (( k=0; k<total_checks; k++ )); do
        local tgt="${pf_targets[$k]}"
        local prt="${pf_ports[$k]}"
        local pro="${pf_protos[$k]}"
        local vrf="${pf_vrfs[$k]}"
        local vrf_label
        [[ -n "$vrf" ]] && vrf_label="VRF:${vrf}" || vrf_label="GRT"

        printf '  Checking  %s:%s  (%s / %s)...\n' "$tgt" "$prt" "$pro" "$vrf_label"

        local ping_result
        ping_result=$(_preflight_ping_vrf "$tgt" "$vrf")
        local p_status p_rtt p_loss
        p_status=$(printf '%s' "$ping_result" | cut -d'|' -f1)
        p_rtt=$(printf '%s'    "$ping_result" | cut -d'|' -f2)
        p_loss=$(printf '%s'   "$ping_result" | cut -d'|' -f3)

        res_ping_status+=("$p_status")
        res_ping_rtt+=("$p_rtt")
        res_ping_loss+=("$p_loss")

        local t_status
        if [[ "${pro^^}" == "UDP" ]]; then
            t_status="SKIP"
        else
            t_status=$(_preflight_tcp_port_vrf "$tgt" "$prt" "$vrf")
        fi
        res_tcp_status+=("$t_status")

        local overall="PASS"
        if   [[ "$p_status" == "FAIL" || "$t_status" == "FAIL" ]]; then
            overall="FAIL"; any_fail=1
        elif [[ "$p_status" == "WARN" ]]; then
            overall="WARN"; any_warn=1
        fi
        res_overall+=("$overall")
    done

    printf '\n'
    printf '+%s+\n' "$(rpt '=' "$inner")"
    bcenter "${BOLD}Pre-Flight Results${NC}"
    printf '+%s+\n' "$(rpt '=' "$inner")"
    bleft "${BOLD}$(printf '%-3s  %-16s  %-5s  %-5s  %-8s  %-6s  %-20s  %-6s  %-8s' \
        '#' 'Target' 'Port' 'Proto' 'VRF' 'Result' 'RTT min/avg/max' 'Loss' 'TCP Port')${NC}"
    printf '+%s+\n' "$(rpt '-' "$inner")"

    for (( k=0; k<total_checks; k++ )); do
        local tgt="${pf_targets[$k]}"
        local prt="${pf_ports[$k]}"
        local pro="${pf_protos[$k]}"
        local vrf="${pf_vrfs[$k]}"
        local overall="${res_overall[$k]}"
        local p_rtt="${res_ping_rtt[$k]}"
        local p_loss="${res_ping_loss[$k]}"
        local t_status="${res_tcp_status[$k]}"

        local tgt_disp="$tgt"
        (( ${#tgt_disp} > 16 )) && tgt_disp="${tgt_disp:0:15}~"
        local rtt_disp="$p_rtt"
        (( ${#rtt_disp} > 20 )) && rtt_disp="${rtt_disp:0:19}~"
        local vrf_disp="${vrf:-GRT}"
        (( ${#vrf_disp} > 8 )) && vrf_disp="${vrf_disp:0:7}~"

        local result_col
        case "$overall" in
            PASS) result_col="${GREEN}${BOLD}PASS  ${NC}" ;;
            WARN) result_col="${YELLOW}${BOLD}WARN  ${NC}" ;;
            FAIL) result_col="${RED}${BOLD}FAIL  ${NC}"   ;;
        esac

        local tcp_col
        case "$t_status" in
            PASS) tcp_col="${GREEN}PASS${NC}    " ;;
            FAIL) tcp_col="${RED}FAIL${NC}    "   ;;
            SKIP) tcp_col="${CYAN}SKIP${NC}    "  ;;
        esac

        local pfx
        pfx=$(printf '%-3d  %-16s  %-5s  %-5s  %-8s  ' \
            $(( k+1 )) "$tgt_disp" "$prt" "$pro" "$vrf_disp")
        bleft " ${pfx}${result_col}$(printf '%-20s  %-6s  ' \
            "$rtt_disp" "$p_loss")${tcp_col}"
    done

    printf '+%s+\n' "$(rpt '=' "$inner")"

    # ── Traceroute section ────────────────────────────────────────────────
    local -a tr_done_keys=()
    local do_traceroute=0
    for (( k=0; k<total_checks; k++ )); do
        local tgt="${pf_targets[$k]}"
        [[ "$tgt" =~ ^127\. || "$tgt" == "::1" ]] && continue
        do_traceroute=1; break
    done

    if (( do_traceroute )); then
        printf '\n'
        printf '+%s+\n' "$(rpt '=' "$inner")"
        bcenter "${BOLD}Path Discovery — Traceroute${NC}"
        printf '+%s+\n' "$(rpt '=' "$inner")"

        local -a sudo_warmed_vrfs=()
        for (( k=0; k<total_checks; k++ )); do
            local tgt="${pf_targets[$k]}"
            [[ "$tgt" =~ ^127\. || "$tgt" == "::1" ]] && continue
            local vrf="${pf_vrfs[$k]}"
            [[ -z "$vrf" ]] && continue
            local _already_warmed=0
            local _wv
            for _wv in "${sudo_warmed_vrfs[@]}"; do
                [[ "$_wv" == "$vrf" ]] && _already_warmed=1 && break
            done
            (( _already_warmed )) && continue
            if _preflight_sudo_warmup "$vrf"; then
                sudo_warmed_vrfs+=("$vrf")
            fi
        done

        for (( k=0; k<total_checks; k++ )); do
            local tgt="${pf_targets[$k]}"
            [[ "$tgt" =~ ^127\. || "$tgt" == "::1" ]] && continue

            local vrf="${pf_vrfs[$k]}"
            local tr_key="${tgt}|${vrf}"
            local already=0
            local td
            for td in "${tr_done_keys[@]}"; do
                [[ "$td" == "$tr_key" ]] && already=1 && break
            done
            (( already )) && continue
            tr_done_keys+=("$tr_key")

            local vrf_label
            [[ -n "$vrf" ]] && vrf_label="VRF: ${vrf}" || vrf_label="GRT"

            local cmd_display
            if [[ "$OS_TYPE" == "linux" && -n "$vrf" ]]; then
                cmd_display="sudo ip vrf exec ${vrf} traceroute ${tgt}"
            else
                cmd_display="traceroute ${tgt}"
            fi

            bleft "  ${BOLD}Target: ${CYAN}${tgt}${NC}  ${DIM}(${vrf_label})${NC}"
            bleft "  ${DIM}Command: ${cmd_display}${NC}"
            printf '+%s+\n' "$(rpt '-' "$inner")"
            bleft "  ${BOLD}$(printf '%-4s  %-40s  %-12s' 'Hop' 'Host / IP' 'RTT')${NC}"
            printf '+%s+\n' "$(rpt '-' "$inner")"

            local tr_output
            tr_output=$(_preflight_traceroute_vrf "$tgt" "$vrf")

            if [[ "$tr_output" == "UNAVAILABLE" ]]; then
                local _bin_check
                _bin_check=$(_find_traceroute_bin)
                if [[ "$_bin_check" == "UNAVAILABLE" ]]; then
                    bleft "  ${YELLOW}traceroute and tracepath not found${NC}"
                    bleft "  ${DIM}Install: apt install traceroute  |  yum install traceroute${NC}"
                else
                    local _found_bin _found_type
                    _found_bin=$(printf '%s' "$_bin_check" | cut -d'|' -f1)
                    _found_type=$(printf '%s' "$_bin_check" | cut -d'|' -f2)
                    bleft "  ${YELLOW}${_found_type} found at ${_found_bin} but produced no output${NC}"
                    if [[ "$OS_TYPE" == "linux" && -n "$vrf" ]]; then
                        bleft "  ${DIM}Verify: sudo ip vrf exec ${vrf} ${_found_type} ${tgt}${NC}"
                    fi
                    bleft "  ${DIM}Possible causes: sudo auth failed, target on same subnet, ICMP TTL exceeded blocked${NC}"
                fi
            else
                local hop_line hop_count=0
                while IFS= read -r hop_line; do
                    [[ -z "$hop_line" ]] && continue
                    local h_num h_host h_rtt
                    h_num=$(printf '%s'  "$hop_line" | cut -d'|' -f1)
                    h_host=$(printf '%s' "$hop_line" | cut -d'|' -f2)
                    h_rtt=$(printf '%s'  "$hop_line" | cut -d'|' -f3)
                    local h_host_disp="$h_host"
                    (( ${#h_host_disp} > 40 )) && h_host_disp="${h_host_disp:0:39}~"
                    local h_col="$NC"
                    [[ "$h_host" == "$tgt" ]] && h_col="$GREEN"
                    [[ "$h_host" == "* * *" || "$h_host" == "*" ]] && h_col="$YELLOW"
                    bleft "  $(printf '%-4s  ' "$h_num")${h_col}$(printf '%-40s  %-12s' \
                        "$h_host_disp" "$h_rtt")${NC}"
                    (( hop_count++ ))
                    (( hop_count >= 20 )) && break
                done <<< "$tr_output"
                (( hop_count == 0 )) && bleft "  ${YELLOW}No hop information returned${NC}"
            fi

            printf '+%s+\n' "$(rpt '=' "$inner")"
        done
    fi

    # ── Failure / Warning detail panel ────────────────────────────────────
    if (( any_fail || any_warn )); then
        printf '\n'
        printf '+%s+\n' "$(rpt '=' "$inner")"
        if (( any_fail )); then
            bcenter "${BOLD}${RED}Pre-Flight Failures Detected${NC}"
        else
            bcenter "${BOLD}${YELLOW}Pre-Flight Warnings Detected${NC}"
        fi
        printf '+%s+\n' "$(rpt '=' "$inner")"

        for (( k=0; k<total_checks; k++ )); do
            [[ "${res_overall[$k]}" == "PASS" ]] && continue
            local tgt="${pf_targets[$k]}"
            local prt="${pf_ports[$k]}"
            local pro="${pf_protos[$k]}"
            local vrf="${pf_vrfs[$k]}"
            local p_status="${res_ping_status[$k]}"
            local t_status="${res_tcp_status[$k]}"
            local streams="${pf_stream_ids[$k]}"
            local vrf_label
            [[ -n "$vrf" ]] && vrf_label="VRF: ${vrf}" || vrf_label="GRT"

            bleft "  ${BOLD}Target ${tgt}:${prt} (${pro} / ${vrf_label})  — stream(s): ${streams}${NC}"

            case "$p_status" in
                FAIL)
                    bleft "  ${RED}  ✗ ICMP Ping FAILED — target unreachable in ${vrf_label}${NC}"
                    if [[ -n "$vrf" ]]; then
                        bleft "    ${DIM}Check: VRF ${vrf} routing, target reachable in this VRF${NC}"
                    else
                        bleft "    ${DIM}Check: routing, firewall ICMP rules, target is up${NC}"
                    fi
                    ;;
                WARN)
                    bleft "  ${YELLOW}  ⚠ ICMP Ping PARTIAL — packet loss in ${vrf_label}${NC}"
                    bleft "    ${DIM}Check: intermittent connectivity or ICMP rate-limiting${NC}"
                    ;;
            esac

            if [[ "$t_status" == "FAIL" ]]; then
                bleft "  ${RED}  ✗ TCP Port ${prt} UNREACHABLE in ${vrf_label}${NC}"
                if [[ -n "$vrf" ]]; then
                    bleft "    ${DIM}Check: iperf3 server running in VRF ${vrf}, firewall allows port ${prt}${NC}"
                else
                    bleft "    ${DIM}Check: iperf3 server is running, firewall allows port ${prt}${NC}"
                fi
            fi

            printf '+%s+\n' "$(rpt '-' "$inner")"
        done
        printf '+%s+\n' "$(rpt '=' "$inner")"
    fi

    # ── Decision prompt ───────────────────────────────────────────────────
    if (( any_fail )); then
        printf '\n'
        printf '%b  %d target(s) FAILED pre-flight checks.\n%b' "$RED" "$any_fail" "$NC"
        printf '\n'
        printf '  Options:\n'
        printf '    %s%sP%s%s  Proceed anyway  (streams may fail at runtime)\n' \
            "$BOLD" "$YELLOW" "$NC" "$NC"
        printf '    %s%sA%s%s  Abort           (recommended)\n' \
            "$BOLD" "$GREEN" "$NC" "$NC"
        printf '\n'
        local decision
        while true; do
            read -r -p "  Choice [A]: " decision </dev/tty
            decision="${decision:-A}"
            case "${decision^^}" in
                P) printf '%b  Proceeding despite pre-flight failures.%b\n' \
                       "$YELLOW" "$NC"; printf '\n'; return 0 ;;
                A) printf '%b  Aborted. Fix connectivity issues and retry.%b\n' \
                       "$RED" "$NC";    printf '\n'; return 1 ;;
                *) printf '%b  Enter P to proceed or A to abort.%b\n' "$RED" "$NC" ;;
            esac
        done

    elif (( any_warn )); then
        printf '\n'
        printf '%b  %d target(s) have pre-flight warnings.\n%b' "$YELLOW" "$any_warn" "$NC"
        printf '\n'
        printf '  Options:\n'
        printf '    %s%sP%s%s  Proceed  (streams may experience packet loss)\n' \
            "$BOLD" "$YELLOW" "$NC" "$NC"
        printf '    %s%sA%s%s  Abort\n' "$BOLD" "$GREEN" "$NC" "$NC"
        printf '\n'
        local decision
        while true; do
            read -r -p "  Choice [P]: " decision </dev/tty
            decision="${decision:-P}"
            case "${decision^^}" in
                P) printf '%b  Proceeding with warnings noted.%b\n' \
                       "$YELLOW" "$NC"; printf '\n'; return 0 ;;
                A) printf '%b  Aborted.%b\n' "$RED" "$NC"; printf '\n'; return 1 ;;
                *) printf '%b  Enter P to proceed or A to abort.%b\n' "$RED" "$NC" ;;
            esac
        done

    else
        printf '\n'
        printf '%b  All pre-flight checks PASSED. Proceeding to path MTU discovery.%b\n' \
            "$GREEN" "$NC"
        printf '\n'
        return 0
    fi
}

# =============================================================================
# SECTION 10c — PATH MTU DISCOVERY
# =============================================================================

_pmtu_ping_probe() {
    local target="$1"
    local payload="$2"
    local vrf_name="${3:-}"
    local rc=0

    if [[ "$OS_TYPE" == "linux" ]]; then
        if [[ -n "$vrf_name" ]]; then
            ip vrf exec "${vrf_name}" \
                ping -M do -s "${payload}" -c 1 -W 2 "${target}" \
                >/dev/null 2>&1
            rc=$?
        else
            ping -M do -s "${payload}" -c 1 -W 2 "${target}" \
                >/dev/null 2>&1
            rc=$?
        fi
    else
        ping -D -s "${payload}" -c 1 -W 2000 "${target}" \
            >/dev/null 2>&1
        rc=$?
    fi

    return $rc
}

_pmtu_get_iface_mtu() {
    local target="$1"
    local vrf_name="${2:-}"
    local mtu=1500

    if [[ "$OS_TYPE" == "linux" ]]; then
        local oif=""
        if [[ -n "$vrf_name" ]]; then
            oif=$(ip vrf exec "${vrf_name}" ip route get "${target}" \
                2>/dev/null | grep -oE '\bdev [^ ]+' | awk '{print $2}' | head -1)
        else
            oif=$(ip route get "${target}" \
                2>/dev/null | grep -oE '\bdev [^ ]+' | awk '{print $2}' | head -1)
        fi
        if [[ -n "$oif" ]]; then
            local iface_mtu
            iface_mtu=$(ip link show dev "${oif}" 2>/dev/null \
                | grep -oE 'mtu [0-9]+' | awk '{print $2}' | head -1)
            if [[ "$iface_mtu" =~ ^[0-9]+$ ]] && (( iface_mtu > 0 )); then
                mtu=$iface_mtu
            fi
        fi
    elif [[ "$OS_TYPE" == "macos" ]]; then
        local oif=""
        oif=$(route -n get "${target}" 2>/dev/null \
            | grep -E 'interface:' | awk '{print $2}' | head -1)
        if [[ -n "$oif" ]]; then
            local iface_mtu
            iface_mtu=$(ifconfig "${oif}" 2>/dev/null \
                | grep -oE 'mtu [0-9]+' | awk '{print $2}' | head -1)
            if [[ "$iface_mtu" =~ ^[0-9]+$ ]] && (( iface_mtu > 0 )); then
                mtu=$iface_mtu
            fi
        fi
    fi

    printf '%d' "$mtu"
}

_pmtu_discover() {
    local target="$1"
    local vrf_name="${2:-}"

    local iface_mtu
    iface_mtu=$(_pmtu_get_iface_mtu "$target" "$vrf_name")

    local lower=548
    local upper=$(( iface_mtu - 28 ))
    (( upper < lower )) && upper=$lower

    if ! _pmtu_ping_probe "$target" "$lower" "$vrf_name"; then
        printf '%d' 0; return
    fi

    if _pmtu_ping_probe "$target" "$upper" "$vrf_name"; then
        printf '%d' $(( upper + 28 )); return
    fi

    local mid
    local iterations=0
    local max_iterations=12

    while (( upper - lower > 1 && iterations < max_iterations )); do
        mid=$(( (lower + upper) / 2 ))
        if _pmtu_ping_probe "$target" "$mid" "$vrf_name"; then
            lower=$mid
        else
            upper=$mid
        fi
        (( iterations++ ))
    done

    printf '%d' $(( lower + 28 ))
}

_pmtu_classify() {
    local discovered="$1"
    local iface_mtu="$2"

    (( discovered == 0 )) && { printf '%s' "UNKNOWN"; return; }

    local diff=$(( iface_mtu - discovered ))

    if   (( discovered < 576  )); then printf '%s' "CRITICAL"
    elif (( discovered < 1280 )); then printf '%s' "CRITICAL"
    elif (( diff > 200        )); then printf '%s' "FRAGMENTATION"
    elif (( diff > 50         )); then printf '%s' "REDUCED"
    else                               printf '%s' "OK"
    fi
}

run_pmtu_discovery() {
    local inner=$(( COLS - 2 ))

    printf '\n'
    printf '+%s+\n' "$(rpt '=' "$inner")"
    bcenter "${BOLD}${CYAN}Path MTU Discovery${NC}"
    printf '+%s+\n' "$(rpt '=' "$inner")"
    bleft "  Probing path MTU for all configured stream targets..."
    bleft "  ${DIM}Method: ICMP DF-bit binary search (payload 576 – interface MTU)${NC}"
    printf '+%s+\n' "$(rpt '-' "$inner")"
    printf '\n'

    local -a pmtu_targets=()
    local -a pmtu_vrfs=()
    local -a pmtu_stream_ids=()

    local i j found
    for (( i=0; i<STREAM_COUNT; i++ )); do
        local tgt="${S_TARGET[$i]}"
        local vrf="${S_VRF[$i]:-}"
        found=0

        for (( j=0; j<${#pmtu_targets[@]}; j++ )); do
            if [[ "${pmtu_targets[$j]}" == "$tgt" && \
                  "${pmtu_vrfs[$j]}"    == "$vrf"  ]]; then
                pmtu_stream_ids[$j]="${pmtu_stream_ids[$j]},$((i+1))"
                found=1; break
            fi
        done

        if (( found == 0 )); then
            pmtu_targets+=("$tgt")
            pmtu_vrfs+=("$vrf")
            pmtu_stream_ids+=("$((i+1))")
        fi
    done

    local total=${#pmtu_targets[@]}
    local any_warn=0 any_critical=0

    local -a disc_mtus=()
    local -a iface_mtus=()
    local -a statuses=()
    local -a recommends=()

    local k
    for (( k=0; k<total; k++ )); do
        local tgt="${pmtu_targets[$k]}"
        local vrf="${pmtu_vrfs[$k]}"
        local vrf_label
        [[ -n "$vrf" ]] && vrf_label="VRF:${vrf}" || vrf_label="GRT"

        printf '  Probing  %s  (%s)...' "$tgt" "$vrf_label"

        local iface_mtu
        iface_mtu=$(_pmtu_get_iface_mtu "$tgt" "$vrf")

        local disc_mtu
        disc_mtu=$(_pmtu_discover "$tgt" "$vrf")

        local status
        status=$(_pmtu_classify "$disc_mtu" "$iface_mtu")

        local recommend="N/A"
        if (( disc_mtu > 40 )); then
            recommend=$(( disc_mtu - 40 ))
        fi

        disc_mtus+=("$disc_mtu")
        iface_mtus+=("$iface_mtu")
        statuses+=("$status")
        recommends+=("$recommend")

        if (( BASH_MAJOR >= 4 )); then
            local key="${tgt}|${vrf}"
            PMTU_RESULTS["$key"]="$disc_mtu"
            PMTU_STATUS["$key"]="$status"
            PMTU_RECOMMEND["$key"]="$recommend"
        fi

        case "$status" in
            CRITICAL)      (( any_critical++ )); printf ' CRITICAL\n' ;;
            FRAGMENTATION) (( any_warn++     )); printf ' WARNING\n'  ;;
            REDUCED)       (( any_warn++     )); printf ' REDUCED\n'  ;;
            OK)                                  printf ' OK\n'       ;;
            UNKNOWN)                             printf ' UNKNOWN\n'  ;;
        esac
    done

    printf '\n'
    printf '+%s+\n' "$(rpt '=' "$inner")"
    bcenter "${BOLD}Path MTU Discovery Results${NC}"
    printf '+%s+\n' "$(rpt '=' "$inner")"
    bleft "${BOLD}$(printf '%-16s  %-8s  %-10s  %-10s  %-9s  %-13s  %-7s' \
        'Target' 'VRF' 'Iface MTU' 'Path MTU' 'Rec MSS' 'Status' 'Streams')${NC}"
    printf '+%s+\n' "$(rpt '-' "$inner")"

    for (( k=0; k<total; k++ )); do
        local tgt="${pmtu_targets[$k]}"
        local vrf="${pmtu_vrfs[$k]}"
        local disc="${disc_mtus[$k]}"
        local imtu="${iface_mtus[$k]}"
        local stat="${statuses[$k]}"
        local rec="${recommends[$k]}"
        local sids="${pmtu_stream_ids[$k]}"

        local tgt_disp="$tgt"
        (( ${#tgt_disp} > 16 )) && tgt_disp="${tgt_disp:0:15}~"
        local vrf_disp="${vrf:-GRT}"
        (( ${#vrf_disp} > 8 )) && vrf_disp="${vrf_disp:0:7}~"

        local disc_disp
        (( disc == 0 )) && disc_disp="UNKNOWN" || disc_disp="${disc} B"

        local rec_disp="$rec"
        [[ "$rec" != "N/A" ]] && rec_disp="${rec} B"

        local stat_col
        case "$stat" in
            OK)            stat_col="${GREEN}${BOLD}OK           ${NC}" ;;
            REDUCED)       stat_col="${YELLOW}${BOLD}REDUCED      ${NC}" ;;
            FRAGMENTATION) stat_col="${YELLOW}${BOLD}FRAG WARN    ${NC}" ;;
            CRITICAL)      stat_col="${RED}${BOLD}CRITICAL     ${NC}"   ;;
            UNKNOWN)       stat_col="${DIM}UNKNOWN      ${NC}"           ;;
        esac

        local pfx
        pfx=$(printf '%-16s  %-8s  %-10s  %-10s  %-9s  ' \
            "$tgt_disp" "$vrf_disp" "${imtu} B" "$disc_disp" "$rec_disp")
        bleft " ${pfx}${stat_col}${DIM}s:${sids}${NC}"
    done

    printf '+%s+\n' "$(rpt '=' "$inner")"

    # ── Warning and advisory panel ─────────────────────────────────────────
    if (( any_critical > 0 || any_warn > 0 )); then
        printf '\n'
        printf '+%s+\n' "$(rpt '=' "$inner")"
        if (( any_critical > 0 )); then
            bcenter "${BOLD}${RED}Path MTU Warnings — Action Required${NC}"
        else
            bcenter "${BOLD}${YELLOW}Path MTU Warnings — Review Recommended${NC}"
        fi
        printf '+%s+\n' "$(rpt '=' "$inner")"

        for (( k=0; k<total; k++ )); do
            local stat="${statuses[$k]}"
            [[ "$stat" == "OK" || "$stat" == "UNKNOWN" ]] && continue

            local tgt="${pmtu_targets[$k]}"
            local vrf="${pmtu_vrfs[$k]}"
            local disc="${disc_mtus[$k]}"
            local imtu="${iface_mtus[$k]}"
            local rec="${recommends[$k]}"
            local sids="${pmtu_stream_ids[$k]}"
            local vrf_label
            [[ -n "$vrf" ]] && vrf_label="VRF: ${vrf}" || vrf_label="GRT"

            bleft "  ${BOLD}Target: ${CYAN}${tgt}${NC}  ${DIM}(${vrf_label})  stream(s): ${sids}${NC}"

            case "$stat" in
                CRITICAL)
                    bleft "  ${RED}  ✗ CRITICAL: Path MTU is ${disc} bytes${NC}"
                    bleft "    ${DIM}Interface MTU: ${imtu} B — Path MTU reduction: $(( imtu - disc )) B${NC}"
                    bleft "    ${RED}  This path has severe MTU constraints.${NC}"
                    bleft "    ${DIM}  Impact: TCP throughput severely degraded, excessive fragmentation${NC}"
                    bleft "    ${DIM}  Action: Investigate tunnels, MPLS labels, or VPN overhead on path${NC}"
                    if [[ "$rec" != "N/A" ]]; then
                        bleft "    ${BOLD}  Recommended MSS: ${rec} bytes${NC}"
                        bleft "    ${DIM}  Apply with: iperf3 -M ${rec} or configure TCP MSS clamping${NC}"
                    fi
                    ;;
                FRAGMENTATION)
                    bleft "  ${YELLOW}  ⚠ FRAGMENTATION RISK: Path MTU is ${disc} bytes${NC}"
                    bleft "    ${DIM}Interface MTU: ${imtu} B — Path MTU reduction: $(( imtu - disc )) B${NC}"
                    bleft "    ${YELLOW}  A network segment on this path has a smaller MTU.${NC}"
                    bleft "    ${DIM}  Common causes: MPLS encapsulation (+4-20 B), GRE tunnel (+24 B),${NC}"
                    bleft "    ${DIM}                 IPsec ESP overhead, VXLAN (+50 B), WAN link MTU${NC}"
                    if [[ "$rec" != "N/A" ]]; then
                        bleft "    ${BOLD}  Recommended MSS: ${rec} bytes  (configure on iperf3 with -M ${rec})${NC}"
                    fi
                    ;;
                REDUCED)
                    bleft "  ${YELLOW}  ⚠ REDUCED MTU: Path MTU is ${disc} bytes${NC}"
                    bleft "    ${DIM}Interface MTU: ${imtu} B — Minor reduction of $(( imtu - disc )) B${NC}"
                    bleft "    ${DIM}  Small reduction likely due to minor encapsulation overhead.${NC}"
                    bleft "    ${DIM}  Impact: Minor efficiency loss, unlikely to affect throughput.${NC}"
                    if [[ "$rec" != "N/A" ]]; then
                        bleft "    ${DIM}  Recommended MSS: ${rec} bytes${NC}"
                    fi
                    ;;
            esac

            printf '+%s+\n' "$(rpt '-' "$inner")"
        done

        printf '+%s+\n' "$(rpt '=' "$inner")"
    fi

    # ── UNKNOWN advisory ───────────────────────────────────────────────────
    local has_unknown=0
    for (( k=0; k<total; k++ )); do
        [[ "${statuses[$k]}" == "UNKNOWN" ]] && has_unknown=1 && break
    done

    if (( has_unknown )); then
        printf '\n'
        printf '+%s+\n' "$(rpt '=' "$inner")"
        bcenter "${BOLD}${DIM}Path MTU Discovery Notes${NC}"
        printf '+%s+\n' "$(rpt '=' "$inner")"
        bleft "  ${DIM}One or more targets returned UNKNOWN MTU.${NC}"
        bleft "  ${DIM}This occurs when:${NC}"
        bleft "  ${DIM}  - The target does not respond to ICMP echo requests${NC}"
        bleft "  ${DIM}  - A firewall blocks ICMP or ICMP-unreachable messages${NC}"
        bleft "  ${DIM}  - The target is unreachable at any probe size${NC}"
        bleft "  ${DIM}iperf3 streams will use the default interface MTU.${NC}"
        printf '+%s+\n' "$(rpt '=' "$inner")"
    fi

    printf '\n'
}

_pmtu_annotate_stream_summary() {
    local idx="$1"
    (( BASH_MAJOR < 4 )) && return

    local tgt="${S_TARGET[$idx]:-}"
    local vrf="${S_VRF[$idx]:-}"
    local key="${tgt}|${vrf}"

    [[ -z "${PMTU_RESULTS[$key]+x}" ]] && return

    local disc="${PMTU_RESULTS[$key]}"
    local stat="${PMTU_STATUS[$key]}"
    local rec="${PMTU_RECOMMEND[$key]}"

    local annotation=""
    case "$stat" in
        OK)
            annotation="${DIM}Path MTU: ${disc} B  MSS: ${rec} B  ✓ OK${NC}"
            ;;
        REDUCED)
            annotation="${YELLOW}Path MTU: ${disc} B  MSS: ${rec} B  ⚠ Reduced${NC}"
            ;;
        FRAGMENTATION)
            annotation="${YELLOW}Path MTU: ${disc} B  MSS: ${rec} B  ⚠ Fragmentation risk${NC}"
            ;;
        CRITICAL)
            annotation="${RED}Path MTU: ${disc} B  MSS: ${rec} B  ✗ CRITICAL${NC}"
            ;;
        UNKNOWN)
            annotation="${DIM}Path MTU: UNKNOWN (ICMP probe failed)${NC}"
            ;;
    esac

    [[ -n "$annotation" ]] && bleft "    ${annotation}"
}

# =============================================================================
# SECTION 10d — DSCP MARKING VERIFICATION
# =============================================================================
#
# Captures a brief tcpdump sample on the egress interface for a selected
# stream and parses the IP TOS field from captured packets to verify that
# the DSCP value in live traffic matches what was configured.
#
# Design:
#   - Triggered interactively by the operator pressing v/V or p/P during
#     the live client dashboard
#   - When multiple streams are running the operator selects which stream
#     to verify
#   - tcpdump runs for a short capture window (default 3 seconds, 50 packets)
#     on the correct egress interface for the stream's target
#   - VRF-aware: when the stream uses a VRF the interface is resolved inside
#     that VRF's routing table
#   - Output shows per-packet details: src IP, dst IP, src port, dst port,
#     TOS hex, DSCP decimal, and a PASS/FAIL verdict
#   - Results are displayed in a formatted box below the dashboard and
#     cleared when the operator dismisses them
#
# Requirements:
#   tcpdump     — packet capture
#   root/sudo   — tcpdump requires CAP_NET_RAW or root
#   Linux only  — not supported on macOS in VRF context (no ip vrf exec)
#                 macOS supported in GRT mode if tcpdump is available
#
# Failure scenarios handled:
#   - tcpdump not installed → clear error message
#   - insufficient privileges → sudo prompt or error
#   - interface not resolvable → error with guidance
#   - stream has no DSCP configured → PASS treated as DSCP=0
#   - no packets captured → warning, possible causes listed
#   - UDP stream with no active traffic → advisory shown
#   - stream not in CONNECTED state → warning
#   - loopback interface → special handling (src=dst interface)
# =============================================================================

# ---------------------------------------------------------------------------
# _dscp_verify_get_iface  <stream_index>
#
# Returns the correct capture interface for a stream based on:
#   Priority 1: S_BIND[$idx] — if a source IP is bound, find the interface
#               that owns that IP address. This is the actual egress interface
#               regardless of VRF membership.
#   Priority 2: Route lookup for S_TARGET[$idx] inside the stream's VRF
#               or GRT when no VRF is configured.
#   Special:    Loopback targets (127.x.x.x) always return "lo".
#
# Prints the interface name or empty string on failure.
# ---------------------------------------------------------------------------

_dscp_verify_get_iface() {
    local idx="$1"
    local target="${S_TARGET[$idx]:-}"
    local vrf="${S_VRF[$idx]:-}"
    local bind_ip="${S_BIND[$idx]:-}"

    # ── Special case: loopback target ─────────────────────────────────────
    if [[ "$target" =~ ^127\. || "$target" == "::1" ]]; then
        printf '%s' "lo"
        return 0
    fi

    # ── Priority 1: resolve interface from bind IP ────────────────────────
    # When S_BIND is set, iperf3 sends packets from that specific IP.
    # Find the interface that owns that IP — this is the actual capture iface.
    if [[ -n "$bind_ip" && "$bind_ip" != "0.0.0.0" ]]; then
        local bind_iface=""

        if [[ "$OS_TYPE" == "linux" ]]; then
            # Search all interfaces for the bind IP
            bind_iface=$(ip -4 addr show 2>/dev/null \
                | awk -v ip="$bind_ip" '
                    /^[0-9]+:/ { iface = $2; gsub(/:$/, "", iface) }
                    /inet / {
                        split($2, a, "/")
                        if (a[1] == ip) { print iface; exit }
                    }')

            # If VRF is set, also try searching within the VRF context
            if [[ -z "$bind_iface" && -n "$vrf" ]]; then
                bind_iface=$(ip vrf exec "${vrf}" ip -4 addr show 2>/dev/null \
                    | awk -v ip="$bind_ip" '
                        /^[0-9]+:/ { iface = $2; gsub(/:$/, "", iface) }
                        /inet / {
                            split($2, a, "/")
                            if (a[1] == ip) { print iface; exit }
                        }')
            fi
        elif [[ "$OS_TYPE" == "macos" ]]; then
            bind_iface=$(ifconfig 2>/dev/null \
                | awk -v ip="$bind_ip" '
                    /^[a-z]/ { iface = $1; gsub(/:$/, "", iface) }
                    /inet / {
                        if ($2 == ip) { print iface; exit }
                    }')
        fi

        if [[ -n "$bind_iface" ]]; then
            printf '%s' "$bind_iface"
            return 0
        fi

        # bind_ip set but interface not found — fall through to route lookup
        # and warn in the caller
    fi

    # ── Priority 2: route lookup for target ───────────────────────────────
    if [[ "$OS_TYPE" == "linux" ]]; then
        local oif=""
        if [[ -n "$vrf" ]]; then
            oif=$(ip vrf exec "${vrf}" ip route get "${target}" \
                2>/dev/null | grep -oE '\bdev [^ ]+' | awk '{print $2}' | head -1)
        else
            oif=$(ip route get "${target}" \
                2>/dev/null | grep -oE '\bdev [^ ]+' | awk '{print $2}' | head -1)
        fi
        printf '%s' "${oif:-}"
    elif [[ "$OS_TYPE" == "macos" ]]; then
        local oif=""
        oif=$(route -n get "${target}" 2>/dev/null \
            | grep -E 'interface:' | awk '{print $2}' | head -1)
        printf '%s' "${oif:-}"
    fi
}

# ---------------------------------------------------------------------------
# _dscp_verify_check_tcpdump
#
# Checks whether tcpdump is available and we have permission to use it.
# Returns 0 if available, 1 if not.
# Prints a descriptive error to stdout on failure (caller displays it).
# ---------------------------------------------------------------------------
_dscp_verify_check_tcpdump() {
    # Check binary exists
    local tcpdump_bin=""
    if command -v tcpdump >/dev/null 2>&1; then
        tcpdump_bin=$(command -v tcpdump)
    elif [[ -x "/usr/sbin/tcpdump" ]]; then
        tcpdump_bin="/usr/sbin/tcpdump"
    elif [[ -x "/usr/bin/tcpdump" ]]; then
        tcpdump_bin="/usr/bin/tcpdump"
    fi

    if [[ -z "$tcpdump_bin" ]]; then
        printf '%s' "NOTFOUND"
        return 1
    fi

    # Check permission (root or sudo)
    if (( IS_ROOT == 0 )); then
        if ! sudo -n true 2>/dev/null; then
            printf '%s' "NOPERM"
            return 1
        fi
    fi

    printf '%s' "$tcpdump_bin"
    return 0
}

# ---------------------------------------------------------------------------
# _dscp_verify_run  <stream_index>
#
# Runs tcpdump on the correct interface for the stream, parses TOS/DSCP
# values from captured packets, and displays a verification table.
# ---------------------------------------------------------------------------
_dscp_verify_run() {
    local idx="$1"
    local inner=$(( COLS - 2 ))

    local target="${S_TARGET[$idx]:-}"
    local port="${S_PORT[$idx]:-}"
    local proto="${S_PROTO[$idx]:-TCP}"
    local vrf="${S_VRF[$idx]:-}"
    local bind_ip="${S_BIND[$idx]:-}"
    local configured_dscp="${S_DSCP_VAL[$idx]:--1}"
    local configured_dscp_name="${S_DSCP_NAME[$idx]:-}"
    local stream_num=$(( idx + 1 ))

    # Normalise unconfigured DSCP to 0 (Best Effort)
    if [[ "$configured_dscp" == "-1" || -z "$configured_dscp" ]]; then
        configured_dscp=0
        configured_dscp_name="CS0/BE"
    fi
    [[ -z "$configured_dscp_name" ]] && configured_dscp_name="CS0/BE"

    # ── Display header ────────────────────────────────────────────────────
    printf '\n'
    printf '+%s+\n' "$(rpt '=' "$inner")"
    bcenter "${BOLD}${CYAN}DSCP Marking Verification — Stream ${stream_num}${NC}"
    printf '+%s+\n' "$(rpt '=' "$inner")"

    local vrf_label
    [[ -n "$vrf" ]] && vrf_label="VRF: ${vrf}" || vrf_label="GRT"

    bleft "  Target   : ${BOLD}${target}:${port}${NC}  (${proto} / ${vrf_label})"
    [[ -n "$bind_ip" ]] && bleft "  Bind IP  : ${BOLD}${bind_ip}${NC}"
    bleft "  DSCP cfg : ${BOLD}${configured_dscp_name}${NC}  (value: ${configured_dscp},  TOS: $(( configured_dscp * 4 )))"
    printf '+%s+\n' "$(rpt '-' "$inner")"

    # ── Check tcpdump ─────────────────────────────────────────────────────
    local tcpdump_result
    tcpdump_result=$(_dscp_verify_check_tcpdump)
    local tcpdump_rc=$?

    if (( tcpdump_rc != 0 )); then
        case "$tcpdump_result" in
            NOTFOUND)
                bleft "  ${RED}✗ tcpdump not found.${NC}"
                bleft "  ${DIM}Install: apt install tcpdump  |  yum install tcpdump${NC}"
                ;;
            NOPERM)
                bleft "  ${RED}✗ Insufficient privileges for tcpdump.${NC}"
                bleft "  ${DIM}Run as root or grant sudo access for tcpdump.${NC}"
                ;;
        esac
        printf '+%s+\n' "$(rpt '=' "$inner")"
        return 1
    fi

    local tcpdump_bin="$tcpdump_result"

    # ── Check stream status ───────────────────────────────────────────────
    local stream_status="${S_STATUS_CACHE[$idx]:-STARTING}"
    if [[ "$stream_status" != "CONNECTED" && "$stream_status" != "DONE" ]]; then
        bleft "  ${YELLOW}⚠ Stream ${stream_num} is not CONNECTED (current: ${stream_status}).${NC}"
        bleft "  ${DIM}Traffic may not be flowing — capture may return no results.${NC}"
        printf '+%s+\n' "$(rpt '-' "$inner")"
    fi

    # ── Resolve interface ─────────────────────────────────────────────────
    local iface
    iface=$(_dscp_verify_get_iface "$idx")

    if [[ -z "$iface" ]]; then
        bleft "  ${RED}✗ Cannot resolve egress interface.${NC}"
        if [[ -n "$bind_ip" ]]; then
            bleft "  ${DIM}Bind IP ${bind_ip} was not found on any local interface.${NC}"
        fi
        bleft "  ${DIM}Check routing: ip route get ${target}${NC}"
        [[ -n "$vrf" ]] && \
            bleft "  ${DIM}In VRF: ip vrf exec ${vrf} ip route get ${target}${NC}"
        printf '+%s+\n' "$(rpt '=' "$inner")"
        return 1
    fi

    bleft "  Interface: ${BOLD}${iface}${NC}"

    # ── Determine interface resolution method for display ─────────────────
    if [[ -n "$bind_ip" && "$bind_ip" != "0.0.0.0" ]]; then
        bleft "  ${DIM}Interface resolved from bind IP ${bind_ip}${NC}"
    elif [[ -n "$vrf" ]]; then
        bleft "  ${DIM}Interface resolved via VRF ${vrf} route to ${target}${NC}"
    else
        bleft "  ${DIM}Interface resolved via GRT route to ${target}${NC}"
    fi

    bleft "  ${DIM}Capturing up to 50 packets (3 second window)...${NC}"
    printf '+%s+\n' "$(rpt '-' "$inner")"

    # ── Build tcpdump filter ───────────────────────────────────────────────
    local proto_lower
    proto_lower=$(printf '%s' "$proto" | tr '[:upper:]' '[:lower:]')

    local tcpdump_filter
    if [[ "$iface" == "lo" || "$iface" == "lo0" ]]; then
        # Loopback: capture both directions
        tcpdump_filter="${proto_lower} and host ${target} and port ${port}"
    else
        # Physical interface: capture outbound to target
        tcpdump_filter="${proto_lower} and dst host ${target} and dst port ${port}"
    fi

    # ── Run tcpdump ───────────────────────────────────────────────────────
    # Use -v for TOS field, -n for no DNS, -l for line-buffered output.
    # Run for 3 seconds or 50 packets, whichever comes first.
    local capture_file="${TMPDIR}/dscp_cap_${idx}_$$.txt"

    local capture_cmd
    if (( IS_ROOT == 1 )); then
        capture_cmd="${tcpdump_bin} -i ${iface} -v -n -l -c 50 ${tcpdump_filter}"
    else
        capture_cmd="sudo ${tcpdump_bin} -i ${iface} -v -n -l -c 50 ${tcpdump_filter}"
    fi

    # Capture stdout and stderr together so we see tcpdump error messages
    timeout 3 bash -c "${capture_cmd}" > "$capture_file" 2>&1
    # timeout rc 124 = time limit reached (normal for our 3s window)

    if [[ ! -f "$capture_file" || ! -s "$capture_file" ]]; then
        bleft "  ${YELLOW}⚠ No output from tcpdump.${NC}"
        bleft "  ${DIM}Ensure traffic is actively flowing and retry.${NC}"
        printf '+%s+\n' "$(rpt '=' "$inner")"
        rm -f "$capture_file"
        return 1
    fi

    # Check if tcpdump reported an error (permission denied, interface not found)
    if grep -qiE 'permission denied|Operation not permitted|No such device|SIOCETHTOOL' \
            "$capture_file" 2>/dev/null; then
        bleft "  ${RED}✗ tcpdump error:${NC}"
        local err_line
        err_line=$(grep -iE 'permission denied|Operation not permitted|No such device' \
            "$capture_file" 2>/dev/null | head -1)
        bleft "  ${DIM}${err_line}${NC}"
        printf '+%s+\n' "$(rpt '=' "$inner")"
        rm -f "$capture_file"
        return 1
    fi

    # ── Parse captured packets ────────────────────────────────────────────
    #
    # tcpdump -v produces output in this general form per packet:
    #
    # HH:MM:SS.ffffff IP (tos 0xb8, ttl 64, id 1234, ...) \
    #     SRC_IP.SRC_PORT > DST_IP.DST_PORT: FLAGS
    #
    # The timestamp + "IP (tos ...)" part may be on line 1.
    # The "SRC > DST:" part may be on the same line or the next.
    #
    # Strategy:
    #   1. Pre-process the file: join continuation lines (lines starting
    #      with whitespace) onto the preceding line.
    #   2. For each merged line: extract TOS hex, src IP:port, dst IP:port.
    #
    # This handles all known tcpdump -v output formats.

    # Step 1: merge continuation lines
    local merged_file="${TMPDIR}/dscp_merged_${idx}_$$.txt"
    awk '
        /^[[:space:]]/ && NR > 1 {
            # continuation line — append to previous
            printf " %s", $0
            next
        }
        NR > 1 { print "" }
        { printf "%s", $0 }
        END { print "" }
    ' "$capture_file" > "$merged_file"

    # Step 2: parse merged lines
    bleft "  ${BOLD}$(printf '%-4s  %-21s  %-21s  %-6s  %-4s  %-4s  %-6s' \
        'Pkt' 'Source IP:Port' 'Destination IP:Port' 'TOS' 'Got' 'Exp' 'Result')${NC}"
    printf '+%s+\n' "$(rpt '-' "$inner")"

    local pass_count=0
    local fail_count=0
    local pkt_num=0

    while IFS= read -r merged_line; do
        # Must contain "tos" and ">" to be a packet data line
        echo "$merged_line" | grep -qiE 'tos 0x' || continue
        echo "$merged_line" | grep -qE '>' || continue

        # ── Extract TOS hex ───────────────────────────────────────────────
        local tos_hex
        tos_hex=$(printf '%s' "$merged_line" \
            | grep -oE 'tos 0x[0-9a-fA-F]+' \
            | awk '{print $2}' | head -1)
        [[ -z "$tos_hex" ]] && continue

        # ── Extract src and dst addresses ─────────────────────────────────
        # Pattern: w.x.y.z.PORT > a.b.c.d.PORT  (dot-separated port)
        # or:      w.x.y.z:PORT > a.b.c.d:PORT  (colon-separated port)
        local addr_match
        addr_match=$(printf '%s' "$merged_line" | grep -oE \
            '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}[.:][0-9]+ +> +[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}[.:][0-9]+' \
            | head -1)
        [[ -z "$addr_match" ]] && continue

        # Parse src and dst from the match
        local src_raw dst_raw
        src_raw=$(printf '%s' "$addr_match" | awk '{print $1}')
        dst_raw=$(printf '%s' "$addr_match" | awk '{print $3}')

        # Convert dot-notation port to colon-notation for display
        # "192.168.1.1.54321" → "192.168.1.1:54321"
        # "192.168.1.1:54321" → unchanged
        local src_display dst_display
        src_display=$(printf '%s' "$src_raw" | awk -F'.' '{
            if (NF == 5) {
                printf "%s.%s.%s.%s:%s", $1, $2, $3, $4, $5
            } else {
                print $0
            }
        }')
        dst_display=$(printf '%s' "$dst_raw" | awk -F'.' '{
            if (NF == 5) {
                printf "%s.%s.%s.%s:%s", $1, $2, $3, $4, $5
            } else {
                print $0
            }
        }')

        # ── Calculate DSCP ────────────────────────────────────────────────
        local tos_dec
        tos_dec=$(( 16#${tos_hex#0x} ))
        local captured_dscp=$(( tos_dec >> 2 ))

        # ── Verdict ───────────────────────────────────────────────────────
        local verdict_col
        if (( captured_dscp == configured_dscp )); then
            verdict_col="${GREEN}${BOLD}PASS${NC}"
            (( pass_count++ ))
        else
            verdict_col="${RED}${BOLD}FAIL${NC}"
            (( fail_count++ ))
        fi

        (( pkt_num++ ))

        # Display up to 20 rows
        if (( pkt_num <= 20 )); then
            local src_disp="$src_display"
            local dst_disp="$dst_display"
            (( ${#src_disp} > 21 )) && src_disp="${src_disp:0:20}~"
            (( ${#dst_disp} > 21 )) && dst_disp="${dst_disp:0:20}~"

            local pfx
            pfx=$(printf '%-4d  %-21s  %-21s  %-6s  %-4d  %-4d  ' \
                "$pkt_num" "$src_disp" "$dst_disp" \
                "$tos_hex" "$captured_dscp" "$configured_dscp")
            bleft " ${pfx}${verdict_col}"
        fi

    done < "$merged_file"

    rm -f "$capture_file" "$merged_file"

    # ── Summary ───────────────────────────────────────────────────────────
    printf '+%s+\n' "$(rpt '-' "$inner")"

    local total_pkts=$(( pass_count + fail_count ))

    if (( total_pkts == 0 )); then
        bleft "  ${YELLOW}⚠ Packets captured but TOS/address data could not be parsed.${NC}"
        bleft "  ${DIM}This usually means traffic was not flowing during the capture window.${NC}"
        bleft "  ${DIM}Try again while the stream is actively sending data.${NC}"
    else
        if (( pkt_num > 20 )); then
            bleft "  ${DIM}(Showing first 20 of ${total_pkts} packets analysed)${NC}"
        fi

        local overall_col overall_label
        if (( fail_count == 0 )); then
            overall_col="$GREEN"
            overall_label="PASS"
        else
            overall_col="$RED"
            overall_label="FAIL"
        fi

        bleft "  ${BOLD}Summary:${NC}  ${total_pkts} packets  |  ${GREEN}${pass_count} PASS${NC}  |  ${RED}${fail_count} FAIL${NC}"
        bleft "  ${BOLD}Verdict:${NC}  ${overall_col}${BOLD}${overall_label}${NC}  — DSCP marking$(
            (( fail_count == 0 )) \
                && printf ' verified correct' \
                || printf ' MISMATCH detected'
        ) on stream ${stream_num}"

        if (( fail_count > 0 )); then
            bleft "  ${RED}  Expected DSCP ${configured_dscp} (TOS 0x$(
                printf '%02x' $(( configured_dscp * 4 ))
            )) — captured DSCP values differ${NC}"
            bleft "  ${DIM}  Possible causes:${NC}"
            bleft "  ${DIM}    - QoS policy rewriting DSCP on egress${NC}"
            bleft "  ${DIM}    - iptables/nftables DSCP remarking rules${NC}"
            bleft "  ${DIM}    - NIC hardware offload overwriting TOS${NC}"
            bleft "  ${DIM}    - DSCP not applied (iperf3 -S flag missing or ignored)${NC}"
        fi
    fi

    printf '+%s+\n' "$(rpt '=' "$inner")"
    return 0
}

# ---------------------------------------------------------------------------
# _dscp_verify_interactive
#
# Called from the dashboard input handler when the operator presses v/V or p/P.
# Temporarily suspends the dashboard, runs DSCP verification for a selected
# stream, displays results, then resumes the dashboard.
#
# Must be called OUTSIDE the dashboard render loop (from the input poller).
# ---------------------------------------------------------------------------

_dscp_verify_interactive() {
    local inner=$(( COLS - 2 ))

    printf '\033[?25h'
    printf '\n'

    # Check tcpdump availability early
    local tcpdump_check
    tcpdump_check=$(_dscp_verify_check_tcpdump)
    local tc_rc=$?

    if (( tc_rc != 0 )); then
        printf '\n'
        printf '+%s+\n' "$(rpt '=' "$inner")"
        bcenter "${BOLD}${CYAN}DSCP Marking Verification${NC}"
        printf '+%s+\n' "$(rpt '=' "$inner")"
        case "$tcpdump_check" in
            NOTFOUND)
                bleft "  ${RED}✗ tcpdump is not installed on this system.${NC}"
                bleft "  ${DIM}Install: apt install tcpdump  |  yum install tcpdump${NC}"
                ;;
            NOPERM)
                bleft "  ${YELLOW}⚠ tcpdump requires elevated privileges.${NC}"
                bleft "  ${DIM}Re-run the script as root, or cache sudo credentials first.${NC}"
                bleft "  ${DIM}Run: sudo -v   then retry the verification.${NC}"
                ;;
        esac
        printf '+%s+\n' "$(rpt '=' "$inner")"
        printf '\n'
        read -r -p "  Press Enter to return to dashboard..." </dev/tty
        printf '\033[?25l'
        return 1
    fi

    # Select stream
    local selected_idx=-1

    if (( STREAM_COUNT == 1 )); then
        selected_idx=0
    else
        printf '\n'
        printf '+%s+\n' "$(rpt '=' "$inner")"
        bcenter "${BOLD}${CYAN}DSCP Marking Verification — Select Stream${NC}"
        printf '+%s+\n' "$(rpt '=' "$inner")"
        bleft "  ${BOLD}$(printf '%-3s  %-5s  %-16s  %-6s  %-8s  %-10s' \
            '#' 'Proto' 'Target' 'Port' 'DSCP' 'Status')${NC}"
        printf '+%s+\n' "$(rpt '-' "$inner")"

        local i
        for (( i=0; i<STREAM_COUNT; i++ )); do
            local sn=$(( i + 1 ))
            local st="${S_STATUS_CACHE[$i]:-STARTING}"
            local tgt="${S_TARGET[$i]:-?}"
            (( ${#tgt} > 16 )) && tgt="${tgt:0:15}~"
            local dscp_disp="${S_DSCP_NAME[$i]:-CS0}"
            [[ -z "$dscp_disp" ]] && dscp_disp="CS0"

            local st_col
            case "$st" in
                CONNECTED) st_col="${GREEN}${st}${NC}"  ;;
                DONE)      st_col="${CYAN}${st}${NC}"   ;;
                FAILED)    st_col="${RED}${st}${NC}"    ;;
                *)         st_col="${YELLOW}${st}${NC}" ;;
            esac

            local pfx
            pfx=$(printf '%-3d  %-5s  %-16s  %-6s  %-8s  ' \
                "$sn" "${S_PROTO[$i]}" "$tgt" "${S_PORT[$i]}" "$dscp_disp")
            bleft " ${pfx}${st_col}"
        done

        printf '+%s+\n' "$(rpt '=' "$inner")"
        printf '\n'

        local sel_raw sel_lower
        while true; do
            read -r -p "  Stream number to verify (or q to cancel): " sel_raw </dev/tty
            # Portable lowercase — tr instead of ${var,,}
            sel_lower=$(printf '%s' "$sel_raw" | tr '[:upper:]' '[:lower:]')
            [[ "$sel_lower" == "q" || -z "$sel_raw" ]] && {
                printf '\033[?25l'
                return 0
            }
            if [[ "$sel_raw" =~ ^[0-9]+$ ]] && \
               (( 10#$sel_raw >= 1 && 10#$sel_raw <= STREAM_COUNT )); then
                selected_idx=$(( 10#$sel_raw - 1 ))
                break
            fi
            printf '%b\n' "${RED}  Enter a number 1-${STREAM_COUNT} or q to cancel.${NC}"
        done
    fi

    _dscp_verify_run "$selected_idx"

    printf '\n'
    read -r -p "  Press Enter to return to dashboard..." </dev/tty

    printf '\033[?25l'
    return 0
}
# =============================================================================
# SECTION 11 — STATUS ENGINE
# =============================================================================

extract_error_from_log() {
    local lf="$1" idx="${2:-0}"
    [[ -f "$lf" && -s "$lf" ]] || return
    local te
    te=$(grep -iE '^iperf3:[[:space:]]+error|^connect failed|^unable to connect|^error -' \
         "$lf" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')
    if [[ -z "$te" ]]; then
        te=$(grep -iE 'error|failed|refused|unable|timed out|no route|unreachable|cannot connect' \
             "$lf" 2>/dev/null \
             | grep -ivE 'bits/sec|bytes/sec|warning|Connecting to|local[[:space:]]+[0-9]|Transfer|Bandwidth|interval' \
             | head -1 | sed 's/^[[:space:]]*//')
    fi
    if [[ -n "$te" ]]; then
        case "$te" in
            *"Connection refused"*)
                printf '%s' "Connection refused -- is iperf3 server on ${S_TARGET[$idx]:-?}:${S_PORT[$idx]:-?}?" ;;
            *"No route to host"*)
                printf '%s' "No route to host -- check path to ${S_TARGET[$idx]:-?}" ;;
            *"timed out"*|*"Connection timed out"*)
                printf '%s' "Connection timed out -- server unreachable or firewall blocking port ${S_PORT[$idx]:-?}" ;;
            *"Name or service"*|*"nodename nor"*)
                printf '%s' "DNS failure -- cannot resolve '${S_TARGET[$idx]:-?}'" ;;
            *"Network is unreachable"*)
                printf '%s' "Network unreachable -- no route to ${S_TARGET[$idx]:-?}" ;;
            *"Permission denied"*)
                printf '%s' "Permission denied -- check bind address or port privileges" ;;
            *"Address already in use"*)
                printf '%s' "Port ${S_PORT[$idx]:-?} is already in use" ;;
            *"Bad file descriptor"*)
                printf '%s' "Bad file descriptor -- VRF/bind IP mismatch or iperf3 server not reachable" ;;
            *) printf '%s' "$te" ;;
        esac
    fi
}

ip_to_hex() {
    local ip="$1" o1 o2 o3 o4
    IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
    [[ "$o1" =~ ^[0-9]+$ && "$o2" =~ ^[0-9]+$ && \
       "$o3" =~ ^[0-9]+$ && "$o4" =~ ^[0-9]+$ ]] || { printf '%s' ""; return 1; }
    printf '%02X%02X%02X%02X' "$(( 10#$o4 ))" "$(( 10#$o3 ))" "$(( 10#$o2 ))" "$(( 10#$o1 ))"
}

port_to_hex() { printf '%04X' "$(( 10#$1 ))"; }

_check_pid_tcp_connected_linux() {
    local pid="$1" target_ip="$2" target_port="$3"
    local rem_hex_ip; rem_hex_ip=$(ip_to_hex "$target_ip")
    local rem_hex_port; rem_hex_port=$(port_to_hex "$target_port")
    [[ -z "$rem_hex_ip" || -z "$rem_hex_port" ]] && return 1
    local target_field="${rem_hex_ip}:${rem_hex_port}"
    local tcp_file="/proc/${pid}/net/tcp"
    if [[ -r "$tcp_file" ]]; then
        if awk -v tgt="$target_field" '
            NR > 1 && $4 == "01" && $3 == tgt { found=1; exit }
            END { exit (found ? 0 : 1) }
        ' "$tcp_file" 2>/dev/null; then return 0; fi
    fi
    local tcp6_file="/proc/${pid}/net/tcp6"
    if [[ -r "$tcp6_file" ]]; then
        if awk -v port=":${rem_hex_port}" '
            NR > 1 && $4 == "01" && $3 ~ port { found=1; exit }
            END { exit (found ? 0 : 1) }
        ' "$tcp6_file" 2>/dev/null; then return 0; fi
    fi
    if ss -tnp 2>/dev/null | grep -qE "pid=${pid},[0-9]+" 2>/dev/null; then
        local conn_line
        conn_line=$(ss -tnp 2>/dev/null | grep -E "pid=${pid}," | grep "ESTAB")
        if [[ -n "$conn_line" ]]; then
            echo "$conn_line" | grep -qE "${target_ip}:${target_port}" && return 0
            [[ "$target_ip" == "127.0.0.1" || "$target_ip" == "::1" ]] && return 0
        fi
    fi
    if [[ -d "/proc/${pid}/fd" ]]; then
        local socket_inodes=()
        local fd_link
        while IFS= read -r fd_link; do
            if [[ "$fd_link" =~ socket:\[([0-9]+)\] ]]; then
                socket_inodes+=("${BASH_REMATCH[1]}")
            fi
        done < <(ls -la "/proc/${pid}/fd" 2>/dev/null | grep -oE 'socket:\[[0-9]+\]')
        if (( ${#socket_inodes[@]} > 0 )); then
            local inode_pattern; inode_pattern=$(printf '%s|' "${socket_inodes[@]}")
            inode_pattern="${inode_pattern%|}"
            if [[ -r /proc/net/tcp ]]; then
                if awk -v tgt="$target_field" -v inodes="$inode_pattern" '
                    NR > 1 && $4 == "01" && $3 == tgt {
                        inode = $(NF-1); n = split(inodes, arr, "|")
                        for (k=1; k<=n; k++) if (arr[k] == inode) { found=1; exit }
                    }
                    END { exit (found ? 0 : 1) }
                ' /proc/net/tcp 2>/dev/null; then return 0; fi
            fi
        fi
    fi
    return 1
}

_check_pid_tcp_connected_macos() {
    local pid="$1" target_ip="$2" target_port="$3"
    if command -v lsof >/dev/null 2>&1; then
        lsof -p "$pid" -i TCP 2>/dev/null \
            | grep -qE "ESTABLISHED.*${target_ip}:${target_port}" && return 0
        if [[ "$target_ip" == "127.0.0.1" || "$target_ip" == "::1" ]]; then
            lsof -p "$pid" -i TCP 2>/dev/null | grep -q "ESTABLISHED" && return 0
        fi
    fi
    if command -v netstat >/dev/null 2>&1; then
        netstat -an 2>/dev/null \
            | grep -qE "ESTABLISHED.*${target_ip}[.\:]${target_port}" && return 0
    fi
    return 1
}

check_pid_tcp_connected() {
    if [[ "$OS_TYPE" == "macos" ]]; then _check_pid_tcp_connected_macos "$@"
    else                                  _check_pid_tcp_connected_linux "$@"; fi
}

probe_client_status() {
    local idx="$1"
    local pid="${STREAM_PIDS[$idx]:-0}"
    local lf="${S_LOGFILE[$idx]:-}"
    local target="${S_TARGET[$idx]:-}"
    local port="${S_PORT[$idx]:-}"
    local proto="${S_PROTO[$idx]:-TCP}"
    local cur="${S_STATUS_CACHE[$idx]:-}"

    if [[ "$cur" == "DONE" ]]; then
        _capture_final_bw "$idx"; return
    fi
    [[ "$cur" == "FAILED" ]] && return

    if [[ "$pid" == "0" ]]; then
        S_STATUS_CACHE[$idx]="FAILED"
        [[ -z "${S_ERROR_MSG[$idx]}" ]] && S_ERROR_MSG[$idx]="Failed to launch iperf3 process"
        return
    fi

    local alive=0; kill -0 "$pid" 2>/dev/null && alive=1

    if (( ! alive )); then
        local err; err=$(extract_error_from_log "$lf" "$idx")
        if [[ -n "$err" ]]; then
            S_STATUS_CACHE[$idx]="FAILED"; S_ERROR_MSG[$idx]="$err"; return
        fi
        if [[ -f "$lf" ]] && grep -qE 'sender|receiver' "$lf" 2>/dev/null; then
            S_STATUS_CACHE[$idx]="DONE"; _capture_final_bw "$idx"; return
        fi
        if [[ -f "$lf" && -s "$lf" ]]; then
            S_STATUS_CACHE[$idx]="FAILED"
            S_ERROR_MSG[$idx]=$(tail -3 "$lf" 2>/dev/null | tr '\n' ' ' | sed 's/^[[:space:]]*//')
            return
        fi
        S_STATUS_CACHE[$idx]="DONE"; _capture_final_bw "$idx"; return
    fi

    if [[ -f "$lf" && -s "$lf" ]]; then
        local early_err; early_err=$(extract_error_from_log "$lf" "$idx")
        [[ -n "$early_err" ]] && { S_STATUS_CACHE[$idx]="CONNECTING"; return; }
    fi

    local tcp_connected=0
    if [[ "$proto" == "TCP" && -n "$target" && -n "$port" ]]; then
        check_pid_tcp_connected "$pid" "$target" "$port" && tcp_connected=1
    fi
    if [[ "$proto" == "UDP" && -n "$target" && -n "$port" ]]; then
        if [[ "$OS_TYPE" == "macos" ]]; then
            command -v lsof >/dev/null 2>&1 && \
                lsof -p "$pid" -i UDP 2>/dev/null | grep -q "$target" && tcp_connected=1
        else
            ss -un 2>/dev/null | grep -qE "${target}:${port}([[:space:]]|$)" && tcp_connected=1
        fi
    fi

    local log_connected=0 has_interval=0
    if [[ -f "$lf" && -s "$lf" ]]; then
        if grep -qE '^\[SUM\][[:space:]]+[0-9.]+-[0-9.]+[[:space:]]+sec.*bits' \
                "$lf" 2>/dev/null || \
           grep -qE '^\[[[:space:]]*[0-9]+\][[:space:]]+[0-9.]+-[0-9.]+[[:space:]]+sec.*bits' \
                "$lf" 2>/dev/null; then
            has_interval=1
        fi
        if (( has_interval == 0 )); then
            grep -qE '^\[[[:space:]]*[0-9]+\].*local.*port.*connected to' \
                "$lf" 2>/dev/null && log_connected=1
        fi
    fi

    if (( tcp_connected || has_interval || log_connected )); then
        S_STATUS_CACHE[$idx]="CONNECTED"; S_ERROR_MSG[$idx]=""; return
    fi

    if [[ ! -f "$lf" || ! -s "$lf" ]]; then
        S_STATUS_CACHE[$idx]="STARTING"
    else
        S_STATUS_CACHE[$idx]="CONNECTING"
    fi
    S_ERROR_MSG[$idx]=""
}

probe_server_status() {
    local idx="$1"
    local pid="${SERVER_PIDS[$idx]:-0}"
    local lf="${SRV_LOGFILE[$idx]:-}"
    local port="${SRV_PORT[$idx]:-}"

    [[ "$pid" == "0" ]] && { printf '%s' 'FAILED'; return; }
    kill -0 "$pid" 2>/dev/null || { printf '%s' 'DONE'; return; }

    local current_state="STARTING"
    if [[ -n "$port" ]]; then
        if [[ "$OS_TYPE" == "macos" ]]; then
            if lsof -iTCP:"$port" 2>/dev/null | grep -q "ESTABLISHED"; then
                current_state="CONNECTED"
            elif lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
                if [[ -f "$lf" && -s "$lf" ]] && \
                   grep -qiE 'accepted connection|connected|bits/sec' "$lf" 2>/dev/null; then
                    current_state="RUNNING"
                else
                    current_state="LISTENING"
                fi
            fi
        else
            if ss -tn 2>/dev/null | grep -qE "ESTAB.*:${port}([[:space:]]|$)"; then
                current_state="CONNECTED"
            elif ss -tn 2>/dev/null | grep -qE "ESTAB.+:${port}[[:space:]]"; then
                current_state="CONNECTED"
            elif ss -tlnp 2>/dev/null | grep -qE ":${port}([[:space:]]|$)"; then
                if [[ -f "$lf" && -s "$lf" ]] && \
                   grep -qiE 'accepted connection|connected|bits/sec' "$lf" 2>/dev/null; then
                    current_state="RUNNING"
                else
                    current_state="LISTENING"
                fi
            fi
        fi
    fi

    if [[ "$current_state" == "STARTING" ]]; then
        if [[ -f "$lf" && -s "$lf" ]]; then
            grep -qiE 'accepted connection|connected' "$lf" 2>/dev/null \
                && current_state="RUNNING" \
                || { grep -qi 'server listening\|listening on' "$lf" 2>/dev/null \
                    && current_state="LISTENING" || current_state="STARTING"; }
        fi
    fi

    local prev_state="${SRV_PREV_STATE[$idx]:-}"

    # ── Bandwidth cache reset policy ──────────────────────────────────────
    #
    # Reset the BW cache ONLY when the server transitions from CONNECTED
    # to LISTENING or STARTING. This means a client fully disconnected
    # and the server has returned to waiting with no active connection.
    #
    # Do NOT reset when transitioning CONNECTED → RUNNING:
    #   RUNNING means the server accepted the connection and is either
    #   still processing or just finished — the cached BW from that
    #   connection is still meaningful and should be shown.
    #
    # Do NOT reset when staying in RUNNING:
    #   The server may cycle CONNECTED → RUNNING between client connections.
    #   Retaining the cached BW provides continuity in the dashboard.
    #
    if [[ "$prev_state" == "CONNECTED" ]]; then
        case "$current_state" in
            LISTENING|STARTING)
                # Client fully gone, server back to waiting — clear BW
                SRV_BW_CACHE[$idx]="---"
                ;;
            # RUNNING, CONNECTED: retain cache — connection still active or
            # just completed, BW is still relevant
        esac
    fi

    SRV_PREV_STATE[$idx]="$current_state"
    printf '%s' "$current_state"
}

# =============================================================================
# SECTION 12 — DASHBOARD
# =============================================================================

# ---------------------------------------------------------------------------
# calculate_frame_lines  <stream_count>
#
# Returns the exact number of lines printed inside the fixed dashboard
# frame by _render_client_frame and _render_server_frame.
#
# Client frame anatomy with progress bars:
#   line 1    bline '='           top border
#   line 2    bcenter             title
#   line 3    bline '='           title border
#   line 4    bleft counters      active/connected/done/failed/elapsed
#   line 5    print_separator     ---
#   line 6    bleft col header    # Proto Target ...
#   line 7    bleft sub-header    Progress (only when has_fixed_dur)
#   line 8    print_separator     ---
#   lines 9..(8+2N) data rows:   one main row + one bar row per stream
#                                 (bar row only when stream has fixed dur)
#   line 9+2N  print_separator   ---
#   line 10+2N bleft hint        Ctrl+C hint
#   line 11+2N print_separator   ---
#
# Worst case (all N streams have fixed duration):
#   fixed overhead = 11
#   per stream = 2 (main row + bar row)
#   total = 11 + (2 * N)
#
# Best case (all N streams are unlimited duration / no bar):
#   fixed overhead = 10  (no sub-header line)
#   per stream = 1
#   total = 10 + N
#
# Since calculate_frame_lines is called before streams start (so we do not
# know yet which streams will show bars) we use the worst case to ensure
# the pre-reserved blank block is always large enough:
#   total = 11 + (2 * N)
#
# This over-reserves by at most N+1 lines for unlimited streams but that
# is safe — the extra blank lines just sit below the rendered frame.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# calculate_frame_lines  <mode>  <stream_count>
#
# Returns the FIXED frame line count for cursor pre-reservation.
# This is used ONLY for the initial pre-reserve blank lines.
# The actual cursor-up distance each tick uses _LAST_FRAME_LINES
# which is updated after every render.
#
# Server frame (never has progress bars):
#   1  top border
#   2  title
#   3  title border
#   4  listeners active line
#   5  separator
#   6  column header
#   7  separator
#   8..(7+N)  data rows
#   8+N  separator
#   9+N  hint
#   10+N separator
#   Total: 10 + N
#
# Client frame base (without progress bars counted here):
#   Same structure: 10 + N
#   Progress bar rows and the sub-header are accounted for dynamically.
#
# Pre-reservation uses the client worst-case: 11 + (2*N)
# so the viewport always has enough space on the first tick.
# ---------------------------------------------------------------------------
calculate_frame_lines() {
    local mode="${1:-client}"
    local count="${2:-0}"
    printf '%d' $(( 10 + count ))
}
# ---------------------------------------------------------------------------
# _count_client_frame_lines
#
# Returns the ACTUAL number of lines that _render_client_frame will print
# on the current tick based on live stream state.
#
# This is called after each render to record exactly how many lines were
# printed so run_dashboard knows how far up to move the cursor next tick.
#
# Anatomy:
#   3  fixed header lines (top border + title + title border)
#   1  counters row
#   1  separator
#   1  column header
#   1  sub-header (only when at least one stream has fixed duration)
#   1  separator
#   N × (1 main row + 0 or 1 bar row)
#   1  separator
#   1  hint
#   1  separator
# ---------------------------------------------------------------------------
_count_client_frame_lines() {
    local base=9   # top border + title + title border + counters +
                   # separator + col header + separator + hint + separator

    # Sub-header line — present when any stream has fixed duration
    local has_fixed=0
    local i
    for (( i=0; i<STREAM_COUNT; i++ )); do
        (( S_DURATION[$i] > 0 )) && has_fixed=1 && break
    done
    (( has_fixed )) && (( base++ ))

    # Per-stream rows: 1 main row + 1 bar row if stream has fixed duration
    for (( i=0; i<STREAM_COUNT; i++ )); do
        (( base++ ))   # main data row always present
        # Bar row present when stream has fixed duration AND is not FAILED
        local st="${S_STATUS_CACHE[$i]:-STARTING}"
        if (( S_DURATION[$i] > 0 )) && [[ "$st" != "FAILED" ]]; then
            (( base++ ))
        fi
    done

    printf '%d' "$base"
}

_count_completed_panel_lines() {
    local done_count=0 i
    for (( i=0; i<STREAM_COUNT; i++ )); do
        [[ "${S_STATUS_CACHE[$i]}" == "DONE" ]] && (( done_count++ ))
    done
    (( done_count == 0 )) && { printf '%d' 0; return; }
    printf '%d' $(( 6 + done_count ))
}

_count_failed_panel_lines() {
    local fail_count=0 i
    for (( i=0; i<STREAM_COUNT; i++ )); do
        [[ "${S_STATUS_CACHE[$i]}" == "FAILED" ]] && (( fail_count++ ))
    done
    (( fail_count == 0 )) && { printf '%d' 0; return; }
    printf '%d' $(( 6 + fail_count ))
}

_render_completed_panel() {
    local done_count=0 i
    for (( i=0; i<STREAM_COUNT; i++ )); do
        [[ "${S_STATUS_CACHE[$i]}" == "DONE" ]] && (( done_count++ ))
    done
    (( done_count == 0 )) && return

    # ── Dynamic target column width ───────────────────────────────────────
    # Same calculation as _render_client_frame so columns are consistent.
    # Panel layout:
    #   " " + sn(3) + "  " + proto(5) + "  " + target(W) + "  " +
    #   port(5) + "  " + sender(14) + "  " + receiver(14)
    #   = 1+3+2+5+2+W+2+5+2+14+2+14 = 52+W  must fit in COLS-2 (78)
    #   → W <= 26  (generous — use same cap as live dashboard for consistency)
    local _tgt_col_w=14
    for (( i=0; i<STREAM_COUNT; i++ )); do
        [[ "${S_STATUS_CACHE[$i]}" != "DONE" ]] && continue
        local _tlen=${#S_TARGET[$i]}
        (( _tlen > _tgt_col_w )) && _tgt_col_w=$_tlen
    done
    local _tgt_max=$(( COLS - 54 ))
    (( _tgt_max < 14 )) && _tgt_max=14
    (( _tgt_col_w > _tgt_max )) && _tgt_col_w=$_tgt_max

    printf '+%s+\033[K\n' "$(rpt '=' $(( COLS - 2 )))"
    bcenter "${BOLD}${CYAN}Completed Streams${NC}"
    printf '+%s+\033[K\n' "$(rpt '=' $(( COLS - 2 )))"
    bleft "${BOLD}$(printf '%-3s  %-5s  %-*s  %-5s  %-14s  %-14s' \
        '#' 'Proto' "$_tgt_col_w" 'Target' 'Port' 'Sender BW' \
        'Receiver BW')${NC}"
    printf '+%s+\033[K\n' "$(rpt '-' $(( COLS - 2 )))"

    for (( i=0; i<STREAM_COUNT; i++ )); do
        [[ "${S_STATUS_CACHE[$i]}" != "DONE" ]] && continue
        local sn=$(( i + 1 ))
        local tgt="${S_TARGET[$i]:-?}"
        if (( ${#tgt} > _tgt_col_w )); then
            tgt="${tgt:0:$(( _tgt_col_w - 1 ))}~"
        fi
        local sbw="${S_FINAL_SENDER_BW[$i]:-N/A}"
        local rbw="${S_FINAL_RECEIVER_BW[$i]:-N/A}"
        local pfx
        pfx=$(printf '%-3d  %-5s  %-*s  %-5s  ' \
            "$sn" "${S_PROTO[$i]}" "$_tgt_col_w" "$tgt" "${S_PORT[$i]}")
        bleft " ${pfx}${GREEN}$(printf '%-14s' "$sbw")${NC}  ${CYAN}$(printf '%-14s' "$rbw")${NC}"
    done
    printf '+%s+\033[K\n' "$(rpt '=' $(( COLS - 2 )))"
}

_render_failed_panel() {
    local fail_count=0 i
    for (( i=0; i<STREAM_COUNT; i++ )); do
        [[ "${S_STATUS_CACHE[$i]}" == "FAILED" ]] && (( fail_count++ ))
    done
    (( fail_count == 0 )) && return

    printf '+%s+\033[K\n' "$(rpt '=' $(( COLS - 2 )))"
    bcenter "${BOLD}${RED}Failed Streams${NC}"
    printf '+%s+\033[K\n' "$(rpt '=' $(( COLS - 2 )))"
    bleft "${BOLD}$(printf '%-3s  %-5s  %-14s  %-5s  %-40s' \
        '#' 'Proto' 'Target' 'Port' 'Error')${NC}"
    printf '+%s+\033[K\n' "$(rpt '-' $(( COLS - 2 )))"

    for (( i=0; i<STREAM_COUNT; i++ )); do
        [[ "${S_STATUS_CACHE[$i]}" != "FAILED" ]] && continue
        local sn=$(( i + 1 ))
        local tgt="${S_TARGET[$i]:-?}"
        (( ${#tgt} > 14 )) && tgt="${tgt:0:13}~"
        local err="${S_ERROR_MSG[$i]:-Unknown error}"
        local max_err=$(( COLS - 34 ))
        (( ${#err} > max_err )) && err="${err:0:$((max_err-3))}..."
        local pfx
        pfx=$(printf '%-3d  %-5s  %-14s  %-5s  ' \
            "$sn" "${S_PROTO[$i]}" "$tgt" "${S_PORT[$i]}")
        bleft " ${pfx}${RED}${err}${NC}"
    done
    printf '+%s+\033[K\n' "$(rpt '=' $(( COLS - 2 )))"
}


# ---------------------------------------------------------------------------
# _count_client_frame_lines_for_state
#
# Calculates how many lines _render_client_frame will print given the
# CURRENT stream states and durations.
#
# Called BEFORE rendering (to size the pre-reserve) and AFTER rendering
# (to record the exact cursor-up distance for the next tick).
#
# Anatomy:
#   1  top border          bline '='
#   2  title               bcenter
#   3  title border        bline '='
#   4  counters row        bleft
#   5  separator           print_separator
#   6  column header       bleft
#   +1 sub-header          bleft  (only when any stream has fixed duration)
#   7  separator           print_separator
#   per stream:
#     +1  main data row    bleft
#     +1  bar row          bleft  (only when stream has fixed dur AND not FAILED)
#   8+N  separator         print_separator
#   9+N  hint row          bleft
#   10+N separator         print_separator
# ---------------------------------------------------------------------------
_count_client_frame_lines_for_state() {
    # Base fixed lines (no streams, no sub-header):
    #   bline'=' + bcenter + bline'=' + bleft-counters +
    #   print_sep + bleft-col-hdr + print_sep +
    #   print_sep + bleft-hint + print_sep = 10
    local total=10

    # Sub-header: present when any stream has fixed duration
    local has_fixed=0
    local i
    for (( i=0; i<STREAM_COUNT; i++ )); do
        (( S_DURATION[$i] > 0 )) && has_fixed=1 && break
    done
    (( has_fixed )) && (( total++ ))

    # Per-stream rows
    for (( i=0; i<STREAM_COUNT; i++ )); do
        (( total++ ))   # main data row always present
        local st="${S_STATUS_CACHE[$i]:-STARTING}"
        if (( S_DURATION[$i] > 0 )) && [[ "$st" != "FAILED" ]]; then
            (( total++ ))   # bar row
        fi
    done

    printf '%d' "$total"
}

_count_client_frame_lines() {
    _count_client_frame_lines_for_state
}

# ---------------------------------------------------------------------------
# _render_progress_bar  <elapsed_seconds>  <total_seconds>
#
# Renders a Unicode block-character progress bar of a fixed width.
# Only called when total_seconds > 0 (fixed-duration streams).
#
# Bar anatomy:
#   [████████████░░░░░░░░]  62%
#    ↑ filled blocks      ↑ empty blocks
#
# Unicode characters used:
#   U+2588  █  FULL BLOCK          — completed portion
#   U+2591  ░  LIGHT SHADE         — remaining portion
#
# Parameters:
#   elapsed  — seconds elapsed since stream start
#   total    — configured duration in seconds
#
# Prints the bar string WITHOUT a trailing newline so the caller can
# append it inline inside a dashboard row.
# ---------------------------------------------------------------------------

_render_progress_bar() {
    local elapsed="$1"
    local total="$2"
    local bar_width=16   # number of characters inside the brackets

    # Clamp elapsed to total
    (( elapsed > total )) && elapsed=$total
    (( elapsed < 0     )) && elapsed=0

    # Calculate percentage (integer, 0-100)
    local pct=0
    (( total > 0 )) && pct=$(( (elapsed * 100) / total ))
    (( pct > 100 )) && pct=100

    # Calculate how many block chars to fill
    local filled=$(( (pct * bar_width) / 100 ))
    (( filled > bar_width )) && filled=$bar_width
    local empty=$(( bar_width - filled ))

    # Choose bar colour based on progress
    local bar_col
    if   (( pct >= 90 )); then bar_col="$CYAN"
    elif (( pct >= 60 )); then bar_col="$GREEN"
    elif (( pct >= 30 )); then bar_col="$YELLOW"
    else                       bar_col="$GREEN"
    fi

    # Build filled and empty segments
    local filled_str="" empty_str=""
    local k
    for (( k=0; k<filled; k++ )); do filled_str+=$'\xe2\x96\x88'; done   # █
    for (( k=0; k<empty;  k++ )); do empty_str+=$'\xe2\x96\x91';  done   # ░

    printf '[%b%s%b%s] %3d%%' \
        "$bar_col" "$filled_str" "$NC" "$empty_str" "$pct"
}

_render_client_frame() {
    local now; now=$(date +%s)
    local i
    for (( i=0; i<STREAM_COUNT; i++ )); do probe_client_status "$i"; done

    local nc=0 ni=0 ns=0 nd=0 nf=0
    for (( i=0; i<STREAM_COUNT; i++ )); do
        case "${S_STATUS_CACHE[$i]}" in
            CONNECTED)  (( nc++ )) ;; CONNECTING) (( ni++ )) ;;
            STARTING)   (( ns++ )) ;; DONE)       (( nd++ )) ;; FAILED) (( nf++ )) ;;
        esac
    done
    local act=$(( nc + ni + ns ))
    local fts="${S_START_TS[0]:-0}"; (( fts == 0 )) && fts="$now"
    local efmt; efmt=$(format_seconds $(( now - fts )))

    # ── Dynamic target column width ───────────────────────────────────────
    # Calculate the minimum width needed to display all targets without
    # truncation, capped so the total row fits within COLS (80).
    #
    # Row layout (characters):
    #   " " + sn(3) + "  " + proto(5) + "  " + target(W) + "  " +
    #   port(5) + "  " + bw(11) + "  " + time(6) + "  " + dscp(5) +
    #   "  " + status(9) = 1+3+2+5+2+W+2+5+2+11+2+6+2+5+2+9 = 59+W
    # Box overhead (| on each side + 1 indent) = 3
    # Total = 62 + W  must be <= COLS (80)  →  W <= 18
    # Minimum useful width = 13 (fits "192.168.1.1" + some)
    local _tgt_col_w=13
    for (( i=0; i<STREAM_COUNT; i++ )); do
        local _tlen=${#S_TARGET[$i]}
        (( _tlen > _tgt_col_w )) && _tgt_col_w=$_tlen
    done
    # Cap to fit in 80-column box
    local _tgt_max=$(( COLS - 62 ))
    (( _tgt_col_w > _tgt_max )) && _tgt_col_w=$_tgt_max
    (( _tgt_col_w < 13 )) && _tgt_col_w=13

    local has_fixed_dur=0
    for (( i=0; i<STREAM_COUNT; i++ )); do
        (( S_DURATION[$i] > 0 )) && has_fixed_dur=1 && break
    done

    # ── Fixed frame ───────────────────────────────────────────────────────
    bline '='
    bcenter "${BOLD}${CYAN}iperf3 Traffic Streams -- Live Dashboard${NC}"
    bline '='
    bleft "  $(printf 'Active:%-2d  Connected:%-2d  Done:%-2d  Failed:%-2d  Elapsed:%s' \
        "$act" "$nc" "$nd" "$nf" "$efmt")"
    print_separator

    # Column header uses dynamic target width
    bleft "${BOLD}$(printf '%-3s  %-5s  %-*s  %-5s  %-11s  %-6s  %-5s  %-9s' \
        '#' 'Proto' "$_tgt_col_w" 'Target' 'Port' 'Bandwidth' 'Time' 'DSCP' \
        'Status')${NC}"
    if (( has_fixed_dur )); then
        bleft "${DIM}$(printf '%-3s  %-5s  %-*s  %-5s  %-11s  %-29s' \
            '' '' "$_tgt_col_w" '' '' '' 'Progress')${NC}"
    fi
    print_separator

    # ── Per-stream rows ───────────────────────────────────────────────────
    for (( i=0; i<STREAM_COUNT; i++ )); do
        local sn=$(( i + 1 ))
        local st="${S_STATUS_CACHE[$i]:-STARTING}"
        local lf="${S_LOGFILE[$i]:-}"

        local bw="---"
        [[ "$st" == "CONNECTED" ]] && bw=$(parse_live_bandwidth_from_log "$lf")
        [[ "$st" == "DONE"      ]] && bw="${S_FINAL_SENDER_BW[$i]:-N/A}"

        local td="--:--"
        local sts="${S_START_TS[$i]:-0}"; (( sts == 0 )) && sts="$now"
        local dur="${S_DURATION[$i]:-10}"
        local stream_elapsed=$(( now - sts ))
        local show_bar=0

        case "$st" in
            CONNECTED|STARTING|CONNECTING)
                if (( dur == 0 )); then
                    td="inf $(format_seconds "$stream_elapsed")"
                    show_bar=0
                else
                    local stream_remaining=$(( dur - stream_elapsed ))
                    (( stream_remaining < 0 )) && stream_remaining=0
                    td=$(format_seconds "$stream_remaining")
                    show_bar=1
                fi
                ;;
            DONE)
                td="done"
                if (( dur > 0 )); then
                    show_bar=1
                    stream_elapsed=$dur
                fi
                ;;
            FAILED)
                td="failed"
                show_bar=0
                ;;
        esac

        local dscp_display="---"
        if [[ -n "${S_DSCP_NAME[$i]}" ]]; then
            dscp_display="${S_DSCP_NAME[$i]}"
        elif [[ -n "${S_DSCP_VAL[$i]}" ]] && (( S_DSCP_VAL[$i] >= 0 )); then
            dscp_display="${S_DSCP_VAL[$i]}"
        fi

        local sb sc
        case "$st" in
            CONNECTED)  sb="CONNECTED"  sc="$GREEN"  ;;
            CONNECTING) sb="CONNECTING" sc="$YELLOW" ;;
            STARTING)   sb="STARTING"   sc="$YELLOW" ;;
            DONE)       sb="DONE"       sc="$CYAN"   ;;
            FAILED)     sb="FAILED"     sc="$RED"    ;;
            *)          sb="$st"        sc="$NC"     ;;
        esac

        # Truncate target only when it exceeds the dynamic column width
        local tgt="${S_TARGET[$i]:-?}"
        if (( ${#tgt} > _tgt_col_w )); then
            tgt="${tgt:0:$(( _tgt_col_w - 1 ))}~"
        fi

        # Main data row uses dynamic target width
        local pfx
        pfx=$(printf '%-3d  %-5s  %-*s  %-5s  %-11s  %-6s  %-5s  ' \
            "$sn" "${S_PROTO[$i]}" "$_tgt_col_w" "$tgt" "${S_PORT[$i]}" \
            "$bw" "$td" "$dscp_display")
        bleft " ${pfx}${sc}${sb}${NC}"

        # Progress bar row — indent matches target column width
        if (( show_bar && has_fixed_dur )); then
            local bar_str
            bar_str=$(_render_progress_bar "$stream_elapsed" "$dur")
            local bar_prefix
            bar_prefix=$(printf ' %-3s  %-5s  %-*s  %-5s  %-11s  ' \
                '' '' "$_tgt_col_w" '' '' '')
            bleft " ${bar_prefix}${bar_str}"
        fi
    done

    print_separator
    bleft "  ${YELLOW}Ctrl+C to stop all streams${NC}"
    print_separator
}

_render_server_frame() {
    local running=0 i
    for (( i=0; i<SERVER_COUNT; i++ )); do
        local pid="${SERVER_PIDS[$i]:-0}"
        [[ "$pid" != "0" ]] && kill -0 "$pid" 2>/dev/null && (( running++ ))
    done

    bline '='
    bcenter "${BOLD}${CYAN}iperf3 Traffic Streams -- Server Dashboard${NC}"
    bline '='
    bleft "  $(printf 'Listeners active: %d / %d' "$running" "$SERVER_COUNT")"
    print_separator
    bleft "${BOLD}$(printf '%-3s  %-6s  %-16s  %-10s  %-12s  %-9s' \
        '#' 'Port' 'Bind IP' 'VRF' 'Bandwidth' 'Status')${NC}"
    print_separator

    for (( i=0; i<SERVER_COUNT; i++ )); do
        local sn=$(( i + 1 )) lf="${SRV_LOGFILE[$i]:-}"
        local st; st=$(probe_server_status "$i")

        # ── Bandwidth display logic ───────────────────────────────────────
        #
        # CONNECTED or RUNNING:
        #   Try to parse a live bandwidth sample from the log.
        #   If a new sample is available, update the cache and display it.
        #   If no new sample, display the cached value (last known BW).
        #   This retains the previous connection's bandwidth while the
        #   server is in RUNNING state waiting for the next client.
        #
        # LISTENING or STARTING:
        #   No client has connected yet (or server just started).
        #   Clear the cache and show "---" — there is no meaningful
        #   bandwidth figure to display.
        #
        # DONE or FAILED:
        #   Show "---" — listener is no longer active.

        local bw
        case "$st" in
            CONNECTED|RUNNING)
                local live_bw
                live_bw=$(parse_live_bandwidth_from_log "$lf")
                if [[ "$live_bw" != "---" && -n "$live_bw" ]]; then
                    # Fresh live sample available — update cache
                    bw="$live_bw"
                    SRV_BW_CACHE[$i]="$live_bw"
                else
                    # No live sample — retain cached value from last
                    # active connection (may be from previous client)
                    bw="${SRV_BW_CACHE[$i]:----}"
                fi
                ;;
            LISTENING|STARTING)
                # No client has ever connected to this listener in the
                # current session, or server is initialising.
                # Clear cache and show placeholder.
                bw="---"
                SRV_BW_CACHE[$i]="---"
                ;;
            *)
                # DONE, FAILED, or unknown
                bw="---"
                ;;
        esac

        local sb sc
        case "$st" in
            CONNECTED) sb="CONNECTED" sc="$GREEN"  ;;
            RUNNING)   sb="RUNNING"   sc="$CYAN"   ;;
            LISTENING) sb="LISTENING" sc="$BLUE"   ;;
            STARTING)  sb="STARTING"  sc="$YELLOW" ;;
            DONE)      sb="DONE"      sc="$NC"     ;;
            FAILED)    sb="FAILED"    sc="$RED"    ;;
            *)         sb="$st"       sc="$NC"     ;;
        esac

        local vrf_disp="${SRV_VRF[$i]:-GRT}"
        [[ "$OS_TYPE" == "macos" ]] && vrf_disp="N/A"

        local pfx
        pfx=$(printf '%-3d  %-6s  %-16s  %-10s  %-12s  ' \
            "$sn" "${SRV_PORT[$i]}" "${SRV_BIND[$i]:-0.0.0.0}" \
            "$vrf_disp" "$bw")
        bleft " ${pfx}${sc}${sb}${NC}"
    done

    print_separator
    bleft "  ${YELLOW}Ctrl+C to stop all listeners${NC}"
    print_separator
}

run_dashboard() {
    local mode="${1:-client}"
    local count
    [[ "$mode" == "server" ]] && count=$SERVER_COUNT || count=$STREAM_COUNT

    # Probe status BEFORE calculating pre-reserve size
    if [[ "$mode" != "server" ]]; then
        local j
        for (( j=0; j<STREAM_COUNT; j++ )); do
            probe_client_status "$j"
        done
    fi

    # Calculate exact pre-reserve size
    local pre_lines
    if [[ "$mode" == "server" ]]; then
        pre_lines=$(( 10 + count ))
    else
        pre_lines=$(_count_client_frame_lines_for_state)
    fi

    FRAME_LINES=$pre_lines
    _PREV_DYNAMIC_LINES=0
    local _last_total=$pre_lines

    local k
    for (( k=0; k<pre_lines; k++ )); do printf '\n'; done
    printf '\033[%dA' "$pre_lines"
    printf '\033[?25l'

    local first_tick=1

    while true; do
        # Probe (skip on tick 1 — already done before pre-reserve)
        if (( first_tick == 0 )) && [[ "$mode" != "server" ]]; then
            local j
            for (( j=0; j<STREAM_COUNT; j++ )); do
                probe_client_status "$j"
            done
        fi

        # Move cursor to top of last rendered block
        if (( first_tick == 0 )); then
            printf '\033[%dA' "$_last_total"
        fi
        first_tick=0

        # Render fixed frame
        local fixed_lines
        if [[ "$mode" == "server" ]]; then
            _render_server_frame
            fixed_lines=$(( 10 + SERVER_COUNT ))
        else
            _render_client_frame
            fixed_lines=$(_count_client_frame_lines_for_state)
        fi

        # Erase from cursor to end of screen
        printf '\033[J'

        # Render dynamic panels (client only)
        local completed_lines=0 failed_lines=0
        if [[ "$mode" != "server" ]]; then
            completed_lines=$(_count_completed_panel_lines)
            failed_lines=$(_count_failed_panel_lines)
            (( completed_lines > 0 )) && _render_completed_panel
            (( failed_lines    > 0 )) && _render_failed_panel
        fi

        # ── DSCP verification hint (client mode, when streams are CONNECTED) ──
        local _hint_lines=0
        if [[ "$mode" != "server" ]]; then
            local _any_connected=0
            local _ji
            for (( _ji=0; _ji<STREAM_COUNT; _ji++ )); do
                [[ "${S_STATUS_CACHE[$_ji]}" == "CONNECTED" ]] && \
                    _any_connected=1 && break
            done
            if (( _any_connected )); then
                printf '\033[K\n'
                printf '  %b[v/p]%b  Verify DSCP marking for a stream\033[K\n' \
                    "$DIM" "$NC"
                printf '\033[K\n'
                _hint_lines=3
            fi
        fi

        # Record total lines rendered this tick
        local dynamic_lines=$(( completed_lines + failed_lines ))
        _last_total=$(( fixed_lines + dynamic_lines + _hint_lines ))
        _PREV_DYNAMIC_LINES=$dynamic_lines

        # Check whether all processes have finished
        local any=0
        if [[ "$mode" == "server" ]]; then
            local j
            for (( j=0; j<SERVER_COUNT; j++ )); do
                local pid="${SERVER_PIDS[$j]:-0}"
                [[ "$pid" != "0" ]] && kill -0 "$pid" 2>/dev/null && any=1 && break
            done
        else
            local j
            for (( j=0; j<STREAM_COUNT; j++ )); do
                local pid="${STREAM_PIDS[$j]:-0}"
                [[ "$pid" != "0" ]] && kill -0 "$pid" 2>/dev/null && any=1 && break
            done
        fi

        (( any == 0 )) && break

        # ── Non-blocking keyboard check ───────────────────────────────────
        # Poll stdin for a keypress during the 1-second tick.
        # Split into 10 × 0.1s checks so we respond within 0.1s.
        # Use tr for lowercase conversion — bash 3.2 compatible.
        local key_pressed=""
        local key_lower=""
        local tick_slice
        for (( tick_slice=0; tick_slice<10; tick_slice++ )); do
            if IFS= read -r -s -n 1 -t 0.1 key_pressed </dev/tty 2>/dev/null; then
                # Convert to lowercase using tr — works on bash 3.2 and 4+
                key_lower=$(printf '%s' "$key_pressed" | tr '[:upper:]' '[:lower:]')
                break
            fi
            key_pressed=""
            key_lower=""
        done

        # ── Handle DSCP verification keypress (client mode only) ──────────
        if [[ "$mode" != "server" ]] && \
           [[ "$key_lower" == "v" || "$key_lower" == "p" ]]; then

            # Restore cursor and move below the rendered content
            printf '\033[?25h'
            printf '\033[%dB' "$_last_total"

            _dscp_verify_interactive

            # After returning, re-probe streams and recalculate frame size
            local j
            for (( j=0; j<STREAM_COUNT; j++ )); do
                probe_client_status "$j"
            done

            local new_pre
            new_pre=$(_count_client_frame_lines_for_state)
            FRAME_LINES=$new_pre

            # Re-reserve space and reposition cursor for clean redraw
            for (( k=0; k<new_pre; k++ )); do printf '\n'; done
            printf '\033[%dA' "$new_pre"
            printf '\033[?25l'

            _last_total=$new_pre
            first_tick=1
        fi
    done

    printf '\033[?25h'
    printf '\n'
}

# =============================================================================
# SECTION 13 — FINAL RESULTS
# =============================================================================

parse_final_results() {
    RESULT_SENDER_BW=()
    RESULT_RECEIVER_BW=()
    RESULT_RTX=()
    RESULT_JITTER=()
    RESULT_LOSS_PCT=()
    RESULT_LOSS_COUNT=()

    local i
    for (( i=0; i<STREAM_COUNT; i++ )); do
        if [[ "${S_STATUS_CACHE[$i]}" == "FAILED" ]]; then
            RESULT_SENDER_BW+=("FAILED"); RESULT_RECEIVER_BW+=("FAILED")
            RESULT_RTX+=("-"); RESULT_JITTER+=("-")
            RESULT_LOSS_PCT+=("-"); RESULT_LOSS_COUNT+=("-")
            continue
        fi

        local lf="${S_LOGFILE[$i]:-}"
        local sbw="N/A" rbw="N/A" rtx="0" jit="N/A" lpct="N/A" lcnt="N/A"

        if [[ -f "$lf" && -s "$lf" ]]; then
            local proto="${S_PROTO[$i]}"
            local sender_bw; sender_bw=$(parse_final_bw_from_log "$lf" "sender")
            [[ -n "$sender_bw" ]] && sbw="$sender_bw"
            local recv_bw; recv_bw=$(parse_final_bw_from_log "$lf" "receiver")
            [[ -n "$recv_bw" ]] && rbw="$recv_bw"
            [[ "$rbw" == "N/A" && "$sbw" != "N/A" ]] && rbw="$sbw"
            if [[ "$sbw" == "N/A" ]]; then
                local last_bw; last_bw=$(parse_live_bandwidth_from_log "$lf")
                [[ "$last_bw" != "---" && -n "$last_bw" ]] && sbw="$last_bw" && rbw="$last_bw"
            fi
            if [[ "$proto" == "TCP" ]]; then
                rtx=$(parse_retransmits_from_log "$lf")
            else
                local udp_line
                udp_line=$(grep -E '[[:space:]]sender[[:space:]]*$' "$lf" 2>/dev/null | tail -1)
                if [[ -z "$udp_line" ]]; then
                    udp_line=$(grep -E '^\[SUM\]|^\[[[:space:]]*[0-9]+\]' "$lf" 2>/dev/null \
                               | grep -v 'receiver' | tail -1)
                fi
                if [[ -n "$udp_line" ]]; then
                    jit=$(echo "$udp_line" | grep -oE '[0-9.]+ ms' | head -1)
                    [[ -z "$jit" ]] && jit="N/A"
                    local loss_frac; loss_frac=$(echo "$udp_line" | grep -oE '[0-9]+/[0-9]+' | head -1)
                    if [[ -n "$loss_frac" ]]; then
                        lcnt=$(cut -d/ -f1 <<< "$loss_frac")
                        local tp; tp=$(cut -d/ -f2 <<< "$loss_frac")
                        if [[ -n "$lcnt" && -n "$tp" ]] && (( tp > 0 )); then
                            lpct=$(awk -v l="$lcnt" -v t="$tp" 'BEGIN { printf "%.3f%%", (l/t)*100 }')
                        else lpct="0.000%"; fi
                    else
                        lpct=$(echo "$udp_line" | grep -oE '\([0-9.]+%\)' | tr -d '()' | head -1)
                        [[ -z "$lpct" ]] && lpct="0.000%"
                    fi
                fi
            fi
        fi

        RESULT_SENDER_BW+=("$sbw"); RESULT_RECEIVER_BW+=("$rbw")
        RESULT_RTX+=("$rtx"); RESULT_JITTER+=("$jit")
        RESULT_LOSS_PCT+=("$lpct"); RESULT_LOSS_COUNT+=("$lcnt")
    done
}

display_results_table() {
    echo ""; print_header "Final Results"; echo ""
    printf '  %-3s  %-5s  %-16s  %-5s  %-12s  %-12s  %-20s\n' \
        "#" "Proto" "Target" "Port" "Sender BW" "Receiver BW" "Retx / Jitter+Loss"
    printf '  %s\n' "$(rpt '-' 80)"
    local i
    for (( i=0; i<STREAM_COUNT; i++ )); do
        local sn=$(( i + 1 )) proto="${S_PROTO[$i]}" tgt="${S_TARGET[$i]:-?}"
        (( ${#tgt} > 16 )) && tgt="${tgt:0:15}~"
        if [[ "${S_STATUS_CACHE[$i]}" == "FAILED" ]]; then
            local err="${S_ERROR_MSG[$i]:-Connection failed}"
            (( ${#err} > 36 )) && err="${err:0:33}..."
            printf '  %-3d  %-5s  %-16s  %-5s  %b%s%b\n' \
                "$sn" "$proto" "$tgt" "${S_PORT[$i]}" "$RED" "FAILED: $err" "$NC"
        else
            local extra
            [[ "$proto" == "TCP" ]] \
                && extra="Retx:${RESULT_RTX[$i]}" \
                || extra="J:${RESULT_JITTER[$i]} L:${RESULT_LOSS_PCT[$i]}"
            printf '  %-3d  %-5s  %-16s  %-5s  %b%-12s%b  %b%-12s%b  %-20s\n' \
                "$sn" "$proto" "$tgt" "${S_PORT[$i]}" \
                "$GREEN" "${RESULT_SENDER_BW[$i]}"   "$NC" \
                "$CYAN"  "${RESULT_RECEIVER_BW[$i]}" "$NC" "$extra"
        fi

        # Append MTU annotation for this stream
        _pmtu_annotate_stream_summary "$i"
    done
    printf '  %s\n' "$(rpt '-' 80)"; echo ""

    local tf=0 td=0
    for (( i=0; i<STREAM_COUNT; i++ )); do
        [[ "${S_STATUS_CACHE[$i]}" == "FAILED" ]] && (( tf++ ))
        [[ "${S_STATUS_CACHE[$i]}" == "DONE"   ]] && (( td++ ))
    done
    if (( tf > 0 )); then
        printf '%b  %d stream(s) FAILED.  %d completed OK.%b\n' "$RED" "$tf" "$td" "$NC"
    else
        printf '%b  All %d stream(s) completed successfully.%b\n' "$GREEN" "$td" "$NC"
    fi

    # MTU summary footer
    if (( BASH_MAJOR >= 4 && ${#PMTU_RESULTS[@]} > 0 )); then
        local _has_mtu_warn=0 _k
        for _k in "${!PMTU_STATUS[@]}"; do
            local _s="${PMTU_STATUS[$_k]}"
            [[ "$_s" == "FRAGMENTATION" || "$_s" == "CRITICAL" || \
               "$_s" == "REDUCED" ]] && _has_mtu_warn=1 && break
        done
        if (( _has_mtu_warn )); then
            echo ""
            printf '%b  Path MTU advisory: one or more paths have reduced MTU.%b\n' \
                "$YELLOW" "$NC"
            printf '%b  See MTU details above. Consider configuring MSS with iperf3 -M <value>.%b\n' \
                "$YELLOW" "$NC"
        fi
    fi

    echo ""
}

offer_log_view() {
    while true; do
        echo ""
        read -r -p "  View raw log for stream # (or press Enter/q to quit): " sel </dev/tty
        case "$sel" in
            ""|q|Q) return ;;
            *)
                if [[ "$sel" =~ ^[0-9]+$ ]] && \
                   (( 10#$sel >= 1 && 10#$sel <= STREAM_COUNT )); then
                    local idx=$(( 10#$sel - 1 ))
                    local lf="${S_LOGFILE[$idx]:-}"
                    if [[ -f "$lf" ]]; then
                        echo ""; bline '='
                        bcenter "Log: stream ${sel} -- ${S_PROTO[$idx]} to ${S_TARGET[$idx]}:${S_PORT[$idx]}"
                        bline '='; cat "$lf"; echo ""; bline '='
                    else
                        printf '%b\n' "${RED}  Log file not found for stream ${sel}.${NC}"
                    fi
                else
                    printf '%b\n' "${RED}  Enter a number 1-${STREAM_COUNT} or press Enter to quit.${NC}"
                fi ;;
        esac
    done
}

# =============================================================================
# SECTION 14 — MODE IMPLEMENTATIONS
# =============================================================================

run_server_mode() {
    echo ""; print_header "Server Mode"; echo ""
    select_bind_interface "server"
    local bind_ip="$SELECTED_IP" vrf="$SELECTED_VRF"; echo ""
    local n
    while true; do
        read -r -p "  How many listeners? [1]: " n </dev/tty; n="${n:-1}"
        [[ "$n" =~ ^[0-9]+$ ]] && (( 10#$n >= 1 && 10#$n <= 64 )) && break
        printf '%b\n' "${RED}  Enter a positive integer (1-64).${NC}"
    done
    configure_server_streams "$n" "$bind_ip" "$vrf"
    show_stream_summary "server"
    confirm_proceed "Launch ${n} listener(s)?" || return
    echo ""; launch_servers
    echo ""; printf '%b\n' "${GREEN}  Servers running. Opening dashboard...${NC}"; sleep 1
    run_dashboard "server"
    echo ""; printf '%b\n' "${CYAN}  Server mode ended.${NC}"; echo ""
}

run_client_mode() {
    echo ""; print_header "Client Mode"; echo ""
    local n
    while true; do
        read -r -p "  How many streams? [1]: " n </dev/tty; n="${n:-1}"
        [[ "$n" =~ ^[0-9]+$ ]] && (( 10#$n >= 1 && 10#$n <= 64 )) && break
        printf '%b\n' "${RED}  Enter a positive integer (1-64).${NC}"
    done

    configure_client_streams "$n" "" ""
    show_stream_summary "client"
    confirm_proceed "Launch ${n} stream(s)?" || return

    apply_netem

    echo ""
    if ! run_preflight_checks; then
        if (( ${#NETEM_IFACES[@]} > 0 )); then
            printf '%b  Removing netem rules applied before abort...%b\n' "$YELLOW" "$NC"
            local iface
            for iface in "${NETEM_IFACES[@]}"; do
                tc qdisc del dev "$iface" root 2>/dev/null && \
                    printf '%b  [REMOVED]%b  netem on %s\n' "$GREEN" "$NC" "$iface"
            done
            NETEM_IFACES=()
        fi
        return
    fi

    run_pmtu_discovery

    local _pmtu_critical=0
    if (( BASH_MAJOR >= 4 )); then
        local _pmtu_key
        for _pmtu_key in "${!PMTU_STATUS[@]}"; do
            [[ "${PMTU_STATUS[$_pmtu_key]}" == "CRITICAL" ]] && \
                _pmtu_critical=1 && break
        done
    fi

    if (( _pmtu_critical )); then
        printf '%b\n' \
            "${RED}  CRITICAL path MTU detected on one or more stream paths.${NC}"
        printf '%b\n' \
            "${YELLOW}  Consider adjusting MSS values (TCP options) before proceeding.${NC}"
        printf '\n'
        if ! confirm_proceed "Proceed with stream launch despite MTU warnings?"; then
            printf '%b  Aborted. Adjust stream MSS settings and retry.%b\n' "$RED" "$NC"
            return
        fi
    fi

    echo ""; launch_clients
    echo ""
    printf '%b\n' "${GREEN}  Streams running. Opening dashboard...${NC}"
    sleep 1
    run_dashboard "client"
    echo ""
    parse_final_results
    display_results_table
    offer_log_view
}

run_loopback_mode() {
    echo ""; print_header "Loopback Test Mode"; echo ""
    echo "  Launches server and client on 127.0.0.1 for local validation."
    echo ""
    local n
    while true; do
        read -r -p "  How many loopback streams? [1]: " n </dev/tty; n="${n:-1}"
        [[ "$n" =~ ^[0-9]+$ ]] && (( 10#$n >= 1 && 10#$n <= 16 )) && break
        printf '%b\n' "${RED}  Enter a positive integer (1-16).${NC}"
    done

    SERVER_COUNT="$n"
    SRV_PORT=(); SRV_BIND=(); SRV_VRF=(); SRV_ONEOFF=(); SRV_LOGFILE=(); SRV_SCRIPT=()
    local bp=5201 i
    for (( i=0; i<n; i++ )); do
        SRV_PORT+=("$(( bp + i ))"); SRV_BIND+=("127.0.0.1"); SRV_VRF+=("")
        SRV_ONEOFF+=(1); SRV_LOGFILE+=(""); SRV_SCRIPT+=("")
    done

    STREAM_COUNT="$n"
    S_PROTO=();    S_TARGET=();    S_PORT=();      S_BW=()
    S_DURATION=(); S_DSCP_NAME=(); S_DSCP_VAL=();  S_PARALLEL=()
    S_REVERSE=();  S_CCA=();       S_WINDOW=();     S_MSS=()
    S_BIND=();     S_VRF=();       S_DELAY=();      S_JITTER=()
    S_LOSS=();     S_NOFQ=();      S_LOGFILE=();    S_SCRIPT=()
    S_START_TS=(); S_STATUS_CACHE=(); S_ERROR_MSG=()
    S_FINAL_SENDER_BW=(); S_FINAL_RECEIVER_BW=()

    printf '%b\n' "${CYAN}  Configure each stream (target: 127.0.0.1, ports from ${bp}):${NC}"
    for (( i=0; i<n; i++ )); do
        local sn=$(( i + 1 )) ap=$(( bp + i ))
        echo ""; printf '%b\n' "${BOLD}  Stream ${sn}:${NC}"

        local proto
        while true; do
            read -r -p "  Protocol [TCP/UDP] (default TCP): " proto </dev/tty
            proto="${proto:-TCP}"; proto=$(printf '%s' "$proto" | tr '[:lower:]' '[:upper:]')
            [[ "$proto" == "TCP" || "$proto" == "UDP" ]] && break
            printf '%b\n' "${RED}  Enter TCP or UDP.${NC}"
        done
        S_PROTO+=("$proto"); S_TARGET+=("127.0.0.1"); S_PORT+=("$ap")

        local bw=""
        if [[ "$proto" == "UDP" ]]; then
            while true; do
                read -r -p "  Bandwidth [100M]: " bw </dev/tty; bw="${bw:-100M}"
                validate_bandwidth "$bw" && break; printf '%b\n' "${RED}  Invalid.${NC}"
            done
        else
            while true; do
                read -r -p "  Bandwidth limit (empty=unlimited): " bw </dev/tty; bw="${bw:-}"
                validate_bandwidth "$bw" && break; printf '%b\n' "${RED}  Invalid.${NC}"
            done
        fi; S_BW+=("$bw")

        local dur
        while true; do
            read -r -p "  Duration [10]: " dur </dev/tty; dur="${dur:-10}"
            validate_duration "$dur" && break
            printf '%b\n' "${RED}  Enter a non-negative integer.${NC}"
        done; S_DURATION+=("$(( 10#$dur ))")

        prompt_dscp "$sn"; S_DSCP_NAME+=("$PROMPT_DSCP_NAME"); S_DSCP_VAL+=("$PROMPT_DSCP_VAL")

        S_PARALLEL+=(1); S_REVERSE+=(0); S_CCA+=(""); S_WINDOW+=(""); S_MSS+=("")
        S_BIND+=("127.0.0.1"); S_VRF+=("")
        S_DELAY+=(""); S_JITTER+=(""); S_LOSS+=(""); S_NOFQ+=(0)
        S_LOGFILE+=(""); S_SCRIPT+=(""); S_START_TS+=(0)
        S_STATUS_CACHE+=("STARTING"); S_ERROR_MSG+=("")
        S_FINAL_SENDER_BW+=(""); S_FINAL_RECEIVER_BW+=("")
    done

    show_stream_summary "client"
    confirm_proceed "Launch loopback test?" || return
    echo ""; launch_servers; echo ""; wait_for_servers
    echo ""; launch_clients
    echo ""; printf '%b\n' "${GREEN}  Running. Opening dashboard...${NC}"; sleep 1
    run_dashboard "client"
    echo ""; parse_final_results; display_results_table; offer_log_view
}

# =============================================================================
# SECTION 15 — MAIN MENU
# =============================================================================

show_main_menu() {
    clear; echo ""
    bline '='; bempty
    bcenter "${BOLD}${CYAN}iperf3 Traffic Streams  v8.2.1${NC}"
    bempty; bline '='

    if [[ "$OS_TYPE" == "macos" ]]; then
        bleft "  iperf3 ${IPERF3_MAJOR}.${IPERF3_MINOR}.${IPERF3_PATCH}   at ${IPERF3_BIN}  ${YELLOW}[macOS / bash ${BASH_MAJOR}.x]${NC}"
    else
        bleft "  iperf3 ${IPERF3_MAJOR}.${IPERF3_MINOR}.${IPERF3_PATCH}   at ${IPERF3_BIN}"
    fi

    if (( IS_ROOT )); then
        bleft "  Running as: ${GREEN}root${NC}  (full feature access)"
    else
        if [[ "$OS_TYPE" == "macos" ]]; then
            bleft "  Running as: ${YELLOW}non-root${NC}  (netem/low-ports may fail; VRF not applicable)"
        else
            bleft "  Running as: ${YELLOW}non-root${NC}  (VRF/netem/low-ports may fail)"
        fi
    fi

    bempty; bline '-'; bempty
    bleft "   ${BOLD}1${NC}   Interface Table"
    bleft "   ${BOLD}2${NC}   Server Mode   --  start iperf3 listener(s)"
    bleft "   ${BOLD}3${NC}   Client Mode   --  generate traffic stream(s)"
    bleft "   ${BOLD}4${NC}   Loopback Test --  local server + client validation"
    bleft "   ${BOLD}5${NC}   DSCP Reference Table"
    bleft "   ${BOLD}6${NC}   Exit"
    bempty; bline '='; echo ""
}

main_menu() {
    while true; do
        show_main_menu
        local choice
        read -r -p "  Select [1-6]: " choice </dev/tty
        case "$choice" in
            1)
                echo ""; build_vrf_maps; get_interface_list
                show_interface_table; echo ""
                read -r -p "  Press Enter to return to menu..." </dev/tty ;;
            2)
                build_vrf_maps; get_interface_list; run_server_mode; echo ""
                read -r -p "  Press Enter to return to menu..." </dev/tty
                SERVER_COUNT=0; SERVER_PIDS=()
                SRV_PORT=(); SRV_BIND=(); SRV_VRF=()
                SRV_ONEOFF=(); SRV_LOGFILE=(); SRV_SCRIPT=()
                SRV_PREV_STATE=(); SRV_BW_CACHE=() ;;
            3)
                build_vrf_maps; get_interface_list; run_client_mode; echo ""
                read -r -p "  Press Enter to return to menu..." </dev/tty
                STREAM_COUNT=0; STREAM_PIDS=(); NETEM_IFACES=()
                if (( BASH_MAJOR >= 4 )); then
                    PMTU_RESULTS=(); PMTU_STATUS=(); PMTU_RECOMMEND=()
                fi ;;
            4)
                build_vrf_maps; get_interface_list; run_loopback_mode; echo ""
                read -r -p "  Press Enter to return to menu..." </dev/tty
                STREAM_COUNT=0; SERVER_COUNT=0
                STREAM_PIDS=(); SERVER_PIDS=(); NETEM_IFACES=()
                SRV_PREV_STATE=(); SRV_BW_CACHE=() ;;
            5)
                echo ""; show_dscp_table
                read -r -p "  Press Enter to return to menu..." </dev/tty ;;
            6|q|Q)
                echo ""; printf '%b\n' "${GREEN}  Goodbye!${NC}"; echo ""; exit 0 ;;
            "") ;;
            *)
                printf '%b\n' "${RED}  Invalid choice '${choice}'. Enter 1 to 6.${NC}"
                sleep 1 ;;
        esac
    done
}

# =============================================================================
# SECTION 16 — ENTRY POINT
# =============================================================================

main() {
    _init_ansi_lengths
    register_traps
    init_tmpdir
    find_iperf3
    get_iperf3_version
    detect_forceflush
    check_root
    build_vrf_maps
    get_interface_list
    main_menu
}

main "$@"