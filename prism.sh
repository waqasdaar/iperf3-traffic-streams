#!/usr/bin/env bash
# =============================================================================
# PRISM — Performance Real-time iPerf3 Stream Manager
# Enterprise-grade multi-stream traffic orchestration with live QoS dashboard
# Version: 8.3.9
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

CAP_DNS_COLOR=""
CAP_DNS_RAW=""
CAP_DNS_REASON=""

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

_init_colors() {
    # Use $'...' syntax to store true escape bytes (not literal backslash)
    R=$'\033[31m'
    G=$'\033[32m'
    Y=$'\033[33m'
    B=$'\033[34m'
    M=$'\033[35m'
    C=$'\033[36m'
    W=$'\033[37m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    NC=$'\033[0m'

    # ==================================================================
    # ANSI length constants
    # These reflect the BYTE length of each escape sequence.
    # Used by any TUI renderer that needs to account for invisible chars.
    # With $'...' syntax: \033[Xm = ESC(1) + [(1) + digit(1) + m(1) = 4
    # With $'...' syntax: \033[0m = ESC(1) + [(1) + 0(1)   + m(1) = 4
    # ==================================================================
    _LEN_RED=${#R}       # Should be 5: ESC [ 3 1 m
    _LEN_GREEN=${#G}
    _LEN_YELLOW=${#Y}
    _LEN_NC=${#NC}       # Should be 4: ESC [ 0 m
    _LEN_DIM=${#DIM}
    _LEN_BOLD=${#BOLD}

    # Safety guard: if any length resolved to 0 (bare assignment fallback),
    # force them to the known correct values so division never hits zero.
    [[ $_LEN_RED   -eq 0 ]] && _LEN_RED=5
    [[ $_LEN_GREEN -eq 0 ]] && _LEN_GREEN=5
    [[ $_LEN_YELLOW -eq 0 ]] && _LEN_YELLOW=5
    [[ $_LEN_NC    -eq 0 ]] && _LEN_NC=4
    [[ $_LEN_DIM   -eq 0 ]] && _LEN_DIM=4
    [[ $_LEN_BOLD  -eq 0 ]] && _LEN_BOLD=4
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

# =============================================================================
# SIGNAL DEFERRAL GLOBALS
#
# _RENDER_LOCK  : set to 1 while a frame is being written to stdout.
#                 Signal handlers check this and set _DEFERRED_SIGNAL
#                 instead of acting immediately.
# _DEFERRED_SIGNAL : name of the signal that fired during a locked render.
#                 Checked and dispatched at the end of each tick.
# =============================================================================
_RENDER_LOCK=0
_DEFERRED_SIGNAL=""

# ==============================================================================
# _init_colors
#
# PURPOSE:
#   Initializes all ANSI escape code variables and their associated byte-length
#   constants used throughout the PRISM TUI renderer, Capability Matrix, and
#   session header functions.
#
# DESIGN RULES:
#   1. Uses $'...' syntax for TRUE escape byte storage (not literal backslash).
#   2. Populates _LEN_* constants for every color so TUI padding arithmetic
#      never divides by zero or miscalculates visible column widths.
#   3. Detects NO_COLOR / non-interactive terminals and gracefully degrades
#      to plain text mode, setting all _LEN_* to 0 safely.
#   4. Provides _strip_ansi() and _visible_len() as inline TUI helpers so
#      any renderer can calculate true printable width without fragile division.
#   5. Safety guards ensure _LEN_* are never zero in color mode, preventing
#      the (N - N) / _LEN_RED division-by-zero seen in run_dashboard().
#
# DEPENDENCIES: None (pure Bash 3.2+, sed, tput optional)
#
# GLOBALS SET:
#   Color codes    : R G Y B M C W BOLD DIM UL NC
#   Length consts  : _LEN_R _LEN_G _LEN_Y _LEN_B _LEN_M _LEN_C _LEN_W
#                    _LEN_BOLD _LEN_DIM _LEN_UL _LEN_NC
#                    _LEN_RED (alias of _LEN_R, legacy compat)
#   Mode flag      : _COLORS_ENABLED (1 = color, 0 = plain)
#   Helpers        : _strip_ansi(), _visible_len()
#
# CALLED BY: Entry point, before any TUI, CAP, or dashboard function.
# ==============================================================================
_init_colors() {

    # --------------------------------------------------------------------------
    # SECTION 1: Terminal Capability Detection
    # Determines whether the current environment supports ANSI color output.
    # Degrades gracefully when:
    #   - stdout is not a terminal (e.g., piped to a file or another process)
    #   - The NO_COLOR environment variable is set (https://no-color.org)
    #   - The TERM variable indicates a non-color terminal (dumb, unknown)
    # --------------------------------------------------------------------------
    _COLORS_ENABLED=1

    # Respect the NO_COLOR standard
    if [[ -n "${NO_COLOR+x}" ]]; then
        _COLORS_ENABLED=0
    fi

    # Disable colors when stdout is not a TTY (e.g., redirected to a file)
    if [[ ! -t 1 ]]; then
        _COLORS_ENABLED=0
    fi

    # Disable colors for known non-color terminal types
    case "${TERM:-}" in
        dumb|unknown|"")
            _COLORS_ENABLED=0
            ;;
    esac

    # --------------------------------------------------------------------------
    # SECTION 2A: Color Mode — assign true ANSI escape sequences
    # Uses $'...' ANSI-C quoting so the ESC byte (0x1B) is stored as a real
    # single byte, not as the 4-character literal string \033.
    #
    # Byte layout reference:
    #   \033[0m    = ESC(1) + [(1) + 0(1) + m(1)      = 4 bytes
    #   \033[1m    = ESC(1) + [(1) + 1(1) + m(1)      = 4 bytes
    #   \033[2m    = ESC(1) + [(1) + 2(1) + m(1)      = 4 bytes
    #   \033[4m    = ESC(1) + [(1) + 4(1) + m(1)      = 4 bytes
    #   \033[31m   = ESC(1) + [(1) + 3(1) + 1(1) + m  = 5 bytes
    #   \033[1;33m = ESC(1) + [(1) + 1;33 (4)  + m    = 7 bytes
    # --------------------------------------------------------------------------
    if [[ $_COLORS_ENABLED -eq 1 ]]; then

        # Standard foreground colors
        R=$'\033[31m'          # Red
        G=$'\033[32m'          # Green
        Y=$'\033[33m'          # Yellow
        B=$'\033[34m'          # Blue
        M=$'\033[35m'          # Magenta
        C=$'\033[36m'          # Cyan
        W=$'\033[37m'          # White

        # Text attributes
        BOLD=$'\033[1m'        # Bold
        DIM=$'\033[2m'         # Dim / faint
        UL=$'\033[4m'          # Underline

        # Reset — returns terminal to default state
        NC=$'\033[0m'          # No Color / Reset

        # Bright variants (used in headers and alerts)
        BR=$'\033[91m'         # Bright Red
        BG=$'\033[92m'         # Bright Green
        BY=$'\033[93m'         # Bright Yellow
        BB=$'\033[94m'         # Bright Blue
        BM=$'\033[95m'         # Bright Magenta
        BC=$'\033[96m'         # Bright Cyan
        BW=$'\033[97m'         # Bright White

        # Combined attributes (Bold + Color, used in titles/warnings)
        BOLD_R=$'\033[1;31m'   # Bold Red
        BOLD_G=$'\033[1;32m'   # Bold Green
        BOLD_Y=$'\033[1;33m'   # Bold Yellow
        BOLD_C=$'\033[1;36m'   # Bold Cyan
        BOLD_W=$'\033[1;37m'   # Bold White

    # --------------------------------------------------------------------------
    # SECTION 2B: Plain Text Mode — assign empty strings
    # All color variables resolve to "", making every printf identical to
    # a no-color call. The TUI boxes and borders remain intact.
    # --------------------------------------------------------------------------
    else
        R="" G="" Y="" B="" M="" C="" W=""
        BOLD="" DIM="" UL="" NC=""
        BR="" BG="" BY="" BB="" BM="" BC="" BW=""
        BOLD_R="" BOLD_G="" BOLD_Y="" BOLD_C="" BOLD_W=""
    fi

    # --------------------------------------------------------------------------
    # SECTION 3: Byte-Length Constants
    # Each _LEN_* variable stores the byte count of its corresponding escape
    # sequence as measured by the shell itself using ${#var}.
    #
    # These constants are used by TUI renderers to calculate the visible
    # (printable) width of colored strings so that box borders align correctly.
    #
    # Example usage in a renderer:
    #   colored_str="${R}FAIL${NC}"
    #   visible_len=$(( ${#colored_str} - _LEN_R - _LEN_NC ))
    #   padding=$(( box_width - visible_len ))
    #
    # In plain text mode all lengths are 0, making the arithmetic transparent.
    # --------------------------------------------------------------------------

    # Standard colors
    _LEN_R=${#R}
    _LEN_G=${#G}
    _LEN_Y=${#Y}
    _LEN_B=${#B}
    _LEN_M=${#M}
    _LEN_C=${#C}
    _LEN_W=${#W}

    # Attributes
    _LEN_BOLD=${#BOLD}
    _LEN_DIM=${#DIM}
    _LEN_UL=${#UL}
    _LEN_NC=${#NC}

    # Bright variants
    _LEN_BR=${#BR}
    _LEN_BG=${#BG}
    _LEN_BY=${#BY}
    _LEN_BB=${#BB}
    _LEN_BM=${#BM}
    _LEN_BC=${#BC}
    _LEN_BW=${#BW}

    # Combined bold+color lengths
    _LEN_BOLD_R=${#BOLD_R}
    _LEN_BOLD_G=${#BOLD_G}
    _LEN_BOLD_Y=${#BOLD_Y}
    _LEN_BOLD_C=${#BOLD_C}
    _LEN_BOLD_W=${#BOLD_W}

    # Legacy alias — preserves compatibility with existing run_dashboard()
    # arithmetic that references _LEN_RED directly.
    _LEN_RED=$_LEN_R

    # --------------------------------------------------------------------------
    # SECTION 4: Safety Guards
    # In color mode, no _LEN_* should ever be 0. If ${#var} returned 0 for
    # any reason (e.g., a subshell export issue, locale problem, or edge case
    # in the Bash version), force the known correct byte lengths here.
    #
    # This directly prevents the:
    #   "prism.sh: line 1694: (37 - 37) / _LEN_RED : division by 0"
    # error seen in run_dashboard() even when _init_colors() is called first.
    # --------------------------------------------------------------------------
    if [[ $_COLORS_ENABLED -eq 1 ]]; then

        # 4-byte sequences: \033[Xm (reset, bold, dim, underline)
        [[ $_LEN_NC   -eq 0 ]] && _LEN_NC=4
        [[ $_LEN_BOLD -eq 0 ]] && _LEN_BOLD=4
        [[ $_LEN_DIM  -eq 0 ]] && _LEN_DIM=4
        [[ $_LEN_UL   -eq 0 ]] && _LEN_UL=4

        # 5-byte sequences: \033[XXm (standard colors 30-37, 90-97)
        [[ $_LEN_R  -eq 0 ]] && _LEN_R=5
        [[ $_LEN_G  -eq 0 ]] && _LEN_G=5
        [[ $_LEN_Y  -eq 0 ]] && _LEN_Y=5
        [[ $_LEN_B  -eq 0 ]] && _LEN_B=5
        [[ $_LEN_M  -eq 0 ]] && _LEN_M=5
        [[ $_LEN_C  -eq 0 ]] && _LEN_C=5
        [[ $_LEN_W  -eq 0 ]] && _LEN_W=5
        [[ $_LEN_BR -eq 0 ]] && _LEN_BR=5
        [[ $_LEN_BG -eq 0 ]] && _LEN_BG=5
        [[ $_LEN_BY -eq 0 ]] && _LEN_BY=5
        [[ $_LEN_BB -eq 0 ]] && _LEN_BB=5
        [[ $_LEN_BM -eq 0 ]] && _LEN_BM=5
        [[ $_LEN_BC -eq 0 ]] && _LEN_BC=5
        [[ $_LEN_BW -eq 0 ]] && _LEN_BW=5

        # 7-byte sequences: \033[1;XXm (bold+color)
        [[ $_LEN_BOLD_R -eq 0 ]] && _LEN_BOLD_R=7
        [[ $_LEN_BOLD_G -eq 0 ]] && _LEN_BOLD_G=7
        [[ $_LEN_BOLD_Y -eq 0 ]] && _LEN_BOLD_Y=7
        [[ $_LEN_BOLD_C -eq 0 ]] && _LEN_BOLD_C=7
        [[ $_LEN_BOLD_W -eq 0 ]] && _LEN_BOLD_W=7

        # Sync legacy alias after guards
        _LEN_RED=$_LEN_R

    fi

    # --------------------------------------------------------------------------
    # SECTION 5: ANSI-Safe TUI Helper Functions
    # These inline helpers allow any renderer to calculate the true visible
    # (printable) width of a string containing ANSI escape codes without
    # relying on _LEN_* arithmetic, which requires knowing exactly how many
    # and which color codes are embedded.
    #
    # Use _visible_len() when the number of embedded codes is dynamic or
    # unknown. Use _LEN_* arithmetic when the codes are statically known
    # (e.g., exactly one ${R}...${NC} wrap) for maximum performance.
    # --------------------------------------------------------------------------

    # _strip_ansi <string>
    # Removes all ANSI CSI escape sequences from the input string.
    # Handles: colors, bold, dim, underline, reset, and cursor codes.
    # Compatible with GNU sed and BSD sed (macOS).
    _strip_ansi() {
        printf "%s" "$1" | sed $'s/\033\\[[0-9;]*[a-zA-Z]//g'
    }

    # _visible_len <string>
    # Returns the integer printable character count of a string,
    # after stripping all embedded ANSI escape sequences.
    #
    # Usage:
    #   local vlen
    #   vlen=$(_visible_len "${R}ERROR${NC} something")
    #   # vlen = 14 (length of "ERROR something")
    _visible_len() {
        local _stripped
        _stripped=$(_strip_ansi "$1")
        printf "%d" "${#_stripped}"
    }

    # _rpad <string> <width>
    # Prints <string> followed by enough spaces to reach <width> visible chars.
    # ANSI-safe: uses _visible_len() so color codes do not count toward width.
    #
    # Usage:
    #   _rpad "${G}OK${NC}" 12
    #   # prints: "\033[32mOK\033[0m          " (10 trailing spaces)
    _rpad() {
        local _str="$1"
        local _width="$2"
        local _vlen
        _vlen=$(_visible_len "$_str")
        local _pad=$(( _width - _vlen ))
        [[ $_pad -lt 0 ]] && _pad=0
        printf "%b%s" "$_str" "$(rpt ' ' $_pad)"
    }

    # _lpad <string> <width>
    # Prints enough spaces to left-pad <string> to <width> visible chars,
    # then prints the string. ANSI-safe.
    _lpad() {
        local _str="$1"
        local _width="$2"
        local _vlen
        _vlen=$(_visible_len "$_str")
        local _pad=$(( _width - _vlen ))
        [[ $_pad -lt 0 ]] && _pad=0
        printf "%s%b" "$(rpt ' ' $_pad)" "$_str"
    }

    # _center <string> <width>
    # Centers <string> within <width> visible characters.
    # ANSI-safe: invisible escape bytes do not affect centering math.
    #
    # Usage:
    #   _center "${BOLD}PRISM${NC}" 78
    _center() {
        local _str="$1"
        local _width="$2"
        local _vlen
        _vlen=$(_visible_len "$_str")
        local _lpad=$(( (_width - _vlen) / 2 ))
        local _rpad=$(( _width - _vlen - _lpad ))
        [[ $_lpad -lt 0 ]] && _lpad=0
        [[ $_rpad -lt 0 ]] && _rpad=0
        printf "%s%b%s" "$(rpt ' ' $_lpad)" "$_str" "$(rpt ' ' $_rpad)"
    }

    # --------------------------------------------------------------------------
    # SECTION 6: Initialization Confirmation (Debug Mode Only)
    # Prints a compact verification line when PRISM_DEBUG=1 is set.
    # Shows the resolved byte lengths so color-mode issues are immediately
    # visible without needing to instrument the TUI renderer.
    # --------------------------------------------------------------------------
    if [[ "${PRISM_DEBUG:-0}" == "1" ]]; then
        printf "%b[_init_colors]%b color=%d  " "$DIM" "$NC" "$_COLORS_ENABLED"
        printf "_LEN_R=%d _LEN_G=%d _LEN_Y=%d " "$_LEN_R" "$_LEN_G" "$_LEN_Y"
        printf "_LEN_NC=%d _LEN_BOLD=%d _LEN_DIM=%d " "$_LEN_NC" "$_LEN_BOLD" "$_LEN_DIM"
        printf "_LEN_RED=%d\n" "$_LEN_RED"
    fi
}

# ---------------------------------------------------------------------------
# _theme_detect_default
#
# Returns "dark", "light", or "mono" based on environment hints.
# Checks COLORFGBG first (set by xterm, rxvt, konsole, iTerm2, etc.),
# then falls back to TERM and finally "dark" as a safe default.
#
# COLORFGBG format: "foreground;background"
#   foreground 0  = black text on light bg  → light theme
#   background 0  = dark background         → dark theme
#   background 15 = light background        → light theme
# ---------------------------------------------------------------------------
_theme_detect_default() {
    if [[ -n "${COLORFGBG:-}" ]]; then
        # Extract background colour index (field after last semicolon)
        local bg
        bg=$(printf '%s' "$COLORFGBG" | awk -F';' '{print $NF}')
        if [[ "$bg" =~ ^[0-9]+$ ]]; then
            # Indices 0-6 are dark colours → dark terminal
            # Indices 7-15 are light colours → light terminal
            if (( bg <= 6 )); then
                printf '%s' "dark"
                return
            else
                printf '%s' "light"
                return
            fi
        fi
    fi

    # Fallback: check TERM for known light-background terminals
    case "${TERM:-}" in
        *-light|apple-terminal) printf '%s' "light"; return ;;
    esac

    printf '%s' "dark"
}

# ---------------------------------------------------------------------------
# _theme_load
#
# Reads the saved theme from the preferences file. If no preferences file
# exists, auto-detects using _theme_detect_default and saves the result.
# ---------------------------------------------------------------------------
_theme_load() {
    if [[ -f "$THEME_PREFS_FILE" ]]; then
        local saved
        saved=$(cat "$THEME_PREFS_FILE" 2>/dev/null | tr -d '[:space:]')
        case "$saved" in
            dark|light|mono)
                THEME_CURRENT="$saved"
                _theme_apply "$THEME_CURRENT"
                return
                ;;
        esac
    fi
    # No valid saved theme — auto-detect and save
    THEME_CURRENT=$(_theme_detect_default)
    _theme_save "$THEME_CURRENT"
    _theme_apply "$THEME_CURRENT"
}

# ---------------------------------------------------------------------------
# _theme_save  <theme_name>
#
# Persists the theme name to the preferences file.
# Creates the directory if it does not exist.
# ---------------------------------------------------------------------------
_theme_save() {
    local theme="$1"
    mkdir -p "$THEME_PREFS_DIR" 2>/dev/null || return
    printf '%s\n' "$theme" > "$THEME_PREFS_FILE" 2>/dev/null
}

# ---------------------------------------------------------------------------
# _theme_apply  <theme_name>
#
# Reassigns all global colour variables to the values for the requested
# theme. Also reinitialises the ANSI byte-length counters so vlen() stays
# accurate after the theme switch.
#
# Dark theme  — vivid colours designed for black/dark-grey backgrounds
# Light theme — darker/more saturated hues that remain readable on white
# Mono theme  — all colour variables set to empty string (no escape codes)
# ---------------------------------------------------------------------------
_theme_apply() {
    local theme="${1:-dark}"
    THEME_CURRENT="$theme"

    case "$theme" in
        dark)
            RED=$'\033[0;31m'
            GREEN=$'\033[0;32m'
            YELLOW=$'\033[1;33m'
            BLUE=$'\033[0;34m'
            CYAN=$'\033[0;36m'
            BOLD=$'\033[1m'
            DIM=$'\033[2m'
            NC=$'\033[0m'
            ;;
        light)
            RED=$'\033[1;31m'
            GREEN=$'\033[0;32m'
            YELLOW=$'\033[0;33m'
            BLUE=$'\033[1;34m'
            CYAN=$'\033[0;36m'
            BOLD=$'\033[1m'
            DIM=$'\033[0;90m'
            NC=$'\033[0m'
            ;;
        mono)
            RED=''
            GREEN=''
            YELLOW=''
            BLUE=''
            CYAN=''
            BOLD=$'\033[1m'
            DIM=$'\033[2m'
            NC=$'\033[0m'
            ;;
        *)
            _theme_apply "dark"
            return
            ;;
    esac

    # ----------------------------------------------------------------
    # Sync both color variable sets and recompute all _LEN_* constants.
    # This replaces the previous _init_ansi_lengths call which only
    # updated Set B lengths and left Set A (R G Y B C etc.) stale.
    # ----------------------------------------------------------------
    _theme_sync
}

# ==============================================================================
# _theme_sync
#
# Synchronises BOTH color variable sets after a theme change so every
# part of the TUI uses the same colors.
#
# PRISM uses two parallel naming conventions inherited from different
# development phases:
#
#   Set A (short names):  R G Y B M C W  BOLD DIM UL NC
#                         BR BG BY BB BM BC BW
#                         BOLD_R BOLD_G BOLD_Y BOLD_C BOLD_W
#   Set B (long names):   RED GREEN YELLOW BLUE CYAN  BOLD DIM NC
#
# _theme_apply updates Set B only. This function copies Set B into Set A
# so both sets always hold the same values after any theme change.
#
# Called by: _theme_apply (at the end), and main() after _theme_load.
# ==============================================================================
_theme_sync() {

    # ------------------------------------------------------------------
    # Copy Set B → Set A
    # BOLD, DIM, NC are shared names so no copy needed for those.
    # ------------------------------------------------------------------
    R="$RED"
    G="$GREEN"
    Y="$YELLOW"
    B="$BLUE"
    C="$CYAN"
    W="${W:-$'\033[37m'}"    # white — not in Set B, keep existing

    # Bright variants — derive from Set B values where possible
    # For dark theme: use bright ANSI variants
    # For light/mono: keep same as standard (brightness handled by base color)
    case "${THEME_CURRENT:-dark}" in
        dark)
            BR=$'\033[91m'   # Bright Red
            BG=$'\033[92m'   # Bright Green
            BY=$'\033[93m'   # Bright Yellow
            BB=$'\033[94m'   # Bright Blue
            BM=$'\033[95m'   # Bright Magenta
            BC=$'\033[96m'   # Bright Cyan
            BW=$'\033[97m'   # Bright White
            BOLD_R=$'\033[1;31m'
            BOLD_G=$'\033[1;32m'
            BOLD_Y=$'\033[1;33m'
            BOLD_C=$'\033[1;36m'
            BOLD_W=$'\033[1;37m'
            M=$'\033[35m'
            UL=$'\033[4m'
            ;;
        light)
            BR="$RED"        # Already bold/dark from _theme_apply
            BG="$GREEN"
            BY="$YELLOW"
            BB="$BLUE"
            BM=$'\033[0;35m'
            BC="$CYAN"
            BW=$'\033[0;37m'
            BOLD_R=$'\033[1;31m'
            BOLD_G=$'\033[0;32m'
            BOLD_Y=$'\033[0;33m'
            BOLD_C=$'\033[0;36m'
            BOLD_W=$'\033[1;37m'
            M=$'\033[0;35m'
            UL=$'\033[4m'
            ;;
        mono)
            BR="" BG="" BY="" BB="" BM="" BC="" BW=""
            BOLD_R="" BOLD_G="" BOLD_Y="" BOLD_C="" BOLD_W=""
            M="" UL=""
            R="" G="" Y="" B="" C="" W=""
            ;;
    esac

    # ------------------------------------------------------------------
    # Recompute ALL _LEN_* byte-length constants for the new values.
    # This keeps vlen() and _visible_len() accurate after a theme switch.
    # ------------------------------------------------------------------
    _LEN_R=${#R};       _LEN_G=${#G};       _LEN_Y=${#Y}
    _LEN_B=${#B};       _LEN_M=${#M};       _LEN_C=${#C}
    _LEN_W=${#W};       _LEN_BOLD=${#BOLD}; _LEN_DIM=${#DIM}
    _LEN_UL=${#UL};     _LEN_NC=${#NC}
    _LEN_BR=${#BR};     _LEN_BG=${#BG};     _LEN_BY=${#BY}
    _LEN_BB=${#BB};     _LEN_BM=${#BM};     _LEN_BC=${#BC}
    _LEN_BW=${#BW}
    _LEN_BOLD_R=${#BOLD_R}; _LEN_BOLD_G=${#BOLD_G}; _LEN_BOLD_Y=${#BOLD_Y}
    _LEN_BOLD_C=${#BOLD_C}; _LEN_BOLD_W=${#BOLD_W}
    _LEN_RED=$_LEN_R
    _LEN_GREEN=$_LEN_G; _LEN_YELLOW=$_LEN_Y
    _LEN_BLUE=$_LEN_B;  _LEN_CYAN=$_LEN_C

    # Safety guards — ensure no _LEN_* is zero in color mode
    if [[ "${_COLORS_ENABLED:-1}" -eq 1 && \
          "${THEME_CURRENT:-dark}" != "mono" ]]; then
        [[ $_LEN_NC   -eq 0 ]] && _LEN_NC=4
        [[ $_LEN_BOLD -eq 0 ]] && _LEN_BOLD=4
        [[ $_LEN_DIM  -eq 0 ]] && _LEN_DIM=4
        [[ $_LEN_UL   -eq 0 ]] && _LEN_UL=4
        [[ $_LEN_R    -eq 0 ]] && _LEN_R=5
        [[ $_LEN_G    -eq 0 ]] && _LEN_G=5
        [[ $_LEN_Y    -eq 0 ]] && _LEN_Y=5
        [[ $_LEN_B    -eq 0 ]] && _LEN_B=5
        [[ $_LEN_C    -eq 0 ]] && _LEN_C=5
        [[ $_LEN_RED  -eq 0 ]] && _LEN_RED=5
        _LEN_RED=$_LEN_R
    fi
}

# ---------------------------------------------------------------------------
# _theme_name_display  <theme_name>
#
# Returns a human-readable, coloured label for a theme name.
# Used in the menu and confirmation messages.
# ---------------------------------------------------------------------------
_theme_name_display() {
    case "$1" in
        dark)  printf '%b' "${BOLD}Dark${NC}  ${DIM}(vivid colours, dark background)${NC}" ;;
        light) printf '%b' "${BOLD}Light${NC} ${DIM}(darker colours, light background)${NC}" ;;
        mono)  printf '%b' "${BOLD}Mono${NC}  ${DIM}(no colour, accessibility mode)${NC}" ;;
        *)     printf '%s' "$1" ;;
    esac
}

# ==============================================================================
# _show_theme_swatch
#
# Prints a color swatch line using the currently active color variables.
# Called immediately after a theme is applied so the user can visually
# confirm the change took effect in their terminal.
#
# The swatch shows every color token using the ACTUAL escape codes that
# are now stored in R/G/Y/B/C/BOLD/DIM/NC after _theme_sync ran.
# If the theme applied correctly the user will see distinct colors.
# If all tokens look the same the terminal does not support that theme.
# ==============================================================================
_show_theme_swatch() {
    local theme="${1:-$THEME_CURRENT}"
    local inner=$(( COLS - 2 ))

    printf '+%s+\n' "$(rpt '-' $inner)"

    local label="  Active theme: ${BOLD}${theme}${NC}  |  Color swatch:  "
    local label_vlen
    label_vlen=$(_visible_len "$label")

    # Build the swatch tokens — each is 3 visible chars + 2 spaces
    local swatch=""
    case "$theme" in
        dark|light)
            swatch+="${R}${BOLD}RED${NC}  "
            swatch+="${G}${BOLD}GRN${NC}  "
            swatch+="${Y}${BOLD}YLW${NC}  "
            swatch+="${B}${BOLD}BLU${NC}  "
            swatch+="${C}${BOLD}CYN${NC}  "
            swatch+="${BOLD}BLD${NC}  "
            swatch+="${DIM}DIM${NC}"
            ;;
        mono)
            swatch+="${BOLD}BOLD${NC}  "
            swatch+="${DIM}DIM${NC}  "
            swatch+="plain"
            ;;
    esac

    local swatch_vlen
    swatch_vlen=$(_visible_len "$swatch")

    local total_vlen=$(( label_vlen + swatch_vlen ))
    local rpad=$(( inner - total_vlen ))
    [[ $rpad -lt 0 ]] && rpad=0

    printf "|%b%s%b%b%s%b%s|\n"    \
        ""     "$label"   ""        \
        ""     "$swatch"  ""        \
        "$(rpt ' ' $rpad)"

    printf '+%s+\n' "$(rpt '-' $inner)"
    echo ""

    # Confirmation message
    printf "  %b✓ Theme \"%s\" is now active.%b\n" \
        "$G" "$theme" "$NC"
    printf "  %bIf the swatch above shows no color change, your terminal\n" \
        "$DIM"
    printf "  may not support the requested color scheme.%b\n\n" \
        "$NC"
}

# ---------------------------------------------------------------------------
# show_theme_menu
#
# Interactive theme selection menu. Called from main_menu option 6.
# Displays the current theme, the auto-detected default, and all three
# options. Applies and saves the selection immediately.
# ---------------------------------------------------------------------------

show_theme_menu() {
    clear
    local inner=$(( COLS - 2 ))

    # ── Header ────────────────────────────────────────────────────────────
    printf '+%s+\n' "$(rpt '=' $inner)"
    bcenter "Colour Theme"
    printf '+%s+\n' "$(rpt '=' $inner)"

    # ── Status block ──────────────────────────────────────────────────────
    # Use a fixed label column width so values line up vertically.
    local detected; detected=$(_theme_detect_default)
    local _lw=16   # label column width

    _tline() {
        local label="$1" value="$2" note="$3"
        # Build the full content string in plain text first so we can
        # measure its length precisely before padding.
        local content
        content=$(printf '%-*s%s' "$_lw" "$label" "$value")
        [[ -n "$note" ]] && content+="  ($note)"
        # Pad to fill inner width minus the 2-space left indent
        local rp=$(( inner - 2 - ${#content} - 1 ))
        (( rp < 0 )) && rp=0
        printf '|  %s%s|\n' "$content" "$(rpt ' ' $rp)"
    }

    _tline "Active"         "${THEME_CURRENT:-dark}" ""
    _tline "Auto-detected"  "${detected}"            "from COLORFGBG / TERM"
    _tline "Saved to"       "${THEME_PREFS_FILE}"    ""
    printf '+%s+\n' "$(rpt '=' $inner)"

    # ── Table column layout ───────────────────────────────────────────────
    #
    # Total usable width inside borders = inner - 2 (left indent)
    #                                             - 1 (right space before |)
    #                                   = inner - 3
    #
    # Fixed columns:
    #   C_NUM    = 1   (#)
    #   C_NAME   = 10  (theme name)
    #   C_STATUS = 8   ("active" or blank)
    #
    # Gaps between columns: 2 spaces each, 3 gaps = 6 chars
    #
    # Remaining space goes entirely to the description column.
    #
    local usable=$(( inner - 3 ))
    local C_NUM=1 C_NAME=10 C_STATUS=8
    local gaps=6   # 3 gaps × 2 spaces
    local C_DESC=$(( usable - C_NUM - C_NAME - C_STATUS - gaps ))
    (( C_DESC < 20 )) && C_DESC=20

    # ── Column header ─────────────────────────────────────────────────────
    local header
    printf -v header '%-*s  %-*s  %-*s  %-*s' \
        $C_NUM    '#' \
        $C_NAME   'Theme' \
        $C_DESC   'Description' \
        $C_STATUS 'Status'

    local hlen=${#header}
    local hrp=$(( inner - 2 - hlen - 1 ))
    (( hrp < 0 )) && hrp=0

    printf '+%s+\n' "$(rpt '-' $inner)"
    printf '|  %s%s|\n' "$header" "$(rpt ' ' $hrp)"
    printf '+%s+\n' "$(rpt '-' $inner)"

    # ── Theme row helper ───────────────────────────────────────────────────
    # All arithmetic is done on plain-text strings so column positions
    # are exact. No ANSI codes inside the measured fields.
    _trow() {
        local num="$1" name="$2" desc="$3"

        local status_text=""
        [[ -n "$name" && "$THEME_CURRENT" == "$name" ]] && status_text="active"

        local name_cap=""
        [[ -n "$name" ]] && \
            name_cap=$(printf '%s' "$name" \
                | awk '{print toupper(substr($0,1,1)) substr($0,2)}')

        # Truncate description to C_DESC if needed
        if (( ${#desc} > C_DESC )); then
            desc="${desc:0:$(( C_DESC - 1 ))}~"
        fi

        local row
        printf -v row '%-*s  %-*s  %-*s  %-*s' \
            $C_NUM    "$num" \
            $C_NAME   "$name_cap" \
            $C_DESC   "$desc" \
            $C_STATUS "$status_text"

        # The row was built with exact field widths so its length should
        # equal usable. Compute right-padding defensively anyway.
        local rlen=${#row}
        local rrp=$(( inner - 2 - rlen - 1 ))
        (( rrp < 0 )) && rrp=0

        printf '|  %s%s|\n' "$row" "$(rpt ' ' $rrp)"
    }

    _trow "1" "dark"  "Vivid ANSI colours for dark/black terminal backgrounds"
    printf '+%s+\n' "$(rpt '-' $inner)"
    _trow "2" "light" "Darker hues for white or light-grey terminal backgrounds"
    printf '+%s+\n' "$(rpt '-' $inner)"
    _trow "3" "mono"  "No colour codes, bold/dim only — accessibility mode"
    printf '+%s+\n' "$(rpt '-' $inner)"
    _trow "4" ""      "Auto-detect — reset to terminal default (${detected})"
    printf '+%s+\n' "$(rpt '-' $inner)"
    _trow "5" ""      "Back to main menu"
    printf '+%s+\n' "$(rpt '=' $inner)"

    # ── Palette swatch ─────────────────────────────────────────────────────
    # The swatch line is the only line that uses ANSI codes.
    # We measure the visible character count independently and pad correctly.
    printf '+%s+\n' "$(rpt '-' $inner)"
    case "$THEME_CURRENT" in
        dark|light)
            # Build swatch tokens with known visible widths
            # Each token: 3 visible chars + 2 space separators = 5 visible each
            # Tokens: RED GRN YLW BLU CYN BLD DIM = 7 × 5 - 2 trailing = 33
            local swatch_label="Palette:  "
            local swatch_visible=$(( ${#swatch_label} + 33 ))
            local swatch_rp=$(( inner - 2 - swatch_visible - 1 ))
            (( swatch_rp < 0 )) && swatch_rp=0

            printf '|  %s' "$swatch_label"
            printf '%b' "${RED}${BOLD}RED${NC}  "
            printf '%b' "${GREEN}${BOLD}GRN${NC}  "
            printf '%b' "${YELLOW}${BOLD}YLW${NC}  "
            printf '%b' "${BLUE}${BOLD}BLU${NC}  "
            printf '%b' "${CYAN}${BOLD}CYN${NC}  "
            printf '%b' "${BOLD}BLD${NC}  "
            printf '%b' "${DIM}DIM${NC}"
            printf '%s|\n' "$(rpt ' ' $swatch_rp)"
            ;;
        mono)
            local mono_line="Palette:  BOLD  DIM  (no colour codes active)"
            local mono_rp=$(( inner - 2 - ${#mono_line} - 1 ))
            (( mono_rp < 0 )) && mono_rp=0
            printf '|  %s%s|\n' "$mono_line" "$(rpt ' ' $mono_rp)"
            ;;
    esac
    printf '+%s+\n' "$(rpt '=' $inner)"
    echo ""

    # ── Prompt ────────────────────────────────────────────────────────────
    local sel
    while true; do
        read -r -p "  Select [1-5]: " sel </dev/tty
        case "$sel" in
            1) _theme_apply "dark";  _theme_sync; _theme_save "dark"
                _show_theme_swatch "dark"
                sleep 1; return 0 ;;
            2) _theme_apply "light"; _theme_sync; _theme_save "light"
                _show_theme_swatch "light"
                sleep 1; return 0 ;;
            3) _theme_apply "mono";  _theme_sync; _theme_save "mono"
                _show_theme_swatch "mono"
                sleep 1; return 0 ;;
            4) local auto; auto=$(_theme_detect_default)
                _theme_apply "$auto"; _theme_sync; _theme_save "$auto"
                _show_theme_swatch "$auto"
                sleep 1; return 0 ;;
            5|""|q|Q) return 0 ;;
            *) printf '  Enter 1-5.\n' ;;
        esac
    done
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
declare -a S_CLEANUP_QUEUED=()   # 1 = cleanup already triggered for stream i
declare -a S_NETEM_IFACE=()


declare -a MTP_CLASSES=()    # traffic mix class definitions
declare -a MTP_TARGETS=()    # per-class target IPs
declare -a MTP_PORTS=()      # per-class base ports
declare -a MTP_DURATIONS=()  # per-class durations
declare -a MTP_BINDS=()      # per-class bind IPs
declare -a MTP_VRFS=()       # per-class VRFs

declare -a S_TARGET_DISPLAY=()

MTP_BASE_PORT=5201
MTP_PORT_MODE="auto"

_mtp_total_streams=0

STREAM_COUNT=0
SERVER_COUNT=0
FRAME_LINES=0
PROMPT_DSCP_NAME=""
PROMPT_DSCP_VAL=-1
SELECTED_IFACE=""
SELECTED_IP=""
SELECTED_VRF=""
BIDIR_SUPPORTED=0
_PREV_DYNAMIC_LINES=0
_LAST_FRAME_LINE_COUNT=0   # set by run_dashboard after each render

# Session context string — built once at startup, displayed in all reports
SESSION_HEADER=""

# ==============================================================================
# TEST SESSION NAMING
# Populated interactively before each test run via _prompt_session_name().
# All fields are plain ASCII — no ANSI codes — safe for log files and JSON.
#
# SESSION_NAME     : free-text label e.g. "baseline-Q1" or "post-change"
# SESSION_TAGS     : space-separated tags e.g. "pre-change production wan"
# SESSION_ID       : auto-generated unique ID: YYYYMMDD-HHMMSS-<4hex>
# SESSION_NOTE     : optional single-line operator note
# SESSION_RUN_TS   : epoch timestamp when the session was launched
# SESSION_HISTORY_FILE : path to the per-host JSON history file
# ==============================================================================
SESSION_NAME=""
SESSION_TAGS=""
SESSION_ID=""
SESSION_NOTE=""
SESSION_RUN_TS=""
SESSION_HISTORY_FILE="${HOME}/.config/prism/session_history.json"

# ==============================================================================
# JSON RESULTS EXPORT GLOBALS
# ==============================================================================

# Directory where JSON result files are written.
# Defaults to the directory containing the running script.
JSON_EXPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[[ -z "$JSON_EXPORT_DIR" || ! -d "$JSON_EXPORT_DIR" ]] && \
    JSON_EXPORT_DIR="$(pwd)"

# Array tracking every JSON export file created this run.
# Populated by _json_export_write(). Used by cleanup prompt.
declare -a JSON_EXPORT_FILES=()

# Per-stream per-second bandwidth sample ring buffers for JSON export.
# Each element is a colon-separated list of "timestamp:bps" pairs.
# Variable naming: _JSON_SAMPLES_<stream_idx>
# Populated by _json_sample_push() on every dashboard tick.
# Flushed to the export file by _json_export_write().

# Global flag: 1 = JSON export is enabled for the current session.
# Set to 0 to suppress export (e.g. server-only mode).
JSON_EXPORT_ENABLED=0

# ==============================================================================
# _json_sample_push  <stream_idx>  <bw_string>  <timestamp_epoch>
#
# Appends one per-second bandwidth sample to the in-memory ring buffer for
# a stream. Called from _render_client_frame on every dashboard tick so that
# a complete time-series is available for the JSON export.
#
# Storage format per entry: "EPOCH:BPS" colon-separated pairs,
# entries separated by pipe "|" for easy splitting in awk.
#
# Variable name: _JSON_SAMPLES_<idx>
#
# Maximum samples retained: 3600 (1 hour at 1 sample/sec).
# Older samples are trimmed from the front to enforce the limit.
# ==============================================================================
_json_sample_push() {
    local idx="$1"
    local bw_str="$2"
    local ts="${3:-$(date +%s)}"
    local varname="_JSON_SAMPLES_${idx}"

    # Convert bandwidth string to integer bps for storage
    local bps
    bps=$(_spark_bw_to_bps "$bw_str")
    [[ -z "$bps" || "$bps" == "0" ]] && bps=0

    local existing=""
    eval "existing=\"\${${varname}:-}\""

    local entry="${ts}:${bps}"

    local updated
    if [[ -z "$existing" ]]; then
        updated="$entry"
    else
        updated="${existing}|${entry}"
    fi

    # Trim to 3600 entries (1 hour)
    local count
    count=$(printf '%s' "$updated" | tr -cd '|' | wc -c)
    count=$(( count + 1 ))

    if (( count > 3600 )); then
        updated=$(printf '%s' "$updated" | cut -d'|' -f$(( count - 3599 ))-)
    fi

    eval "${varname}=\"\${updated}\""
}

# ==============================================================================
# _json_sample_clear  <stream_idx>
# Resets the per-stream sample buffer to empty.
# ==============================================================================
_json_sample_clear() {
    local idx="$1"
    local varname="_JSON_SAMPLES_${idx}"
    eval "${varname}=\"\""
}

# ==============================================================================
# _json_sample_get  <stream_idx>
# Returns the raw sample buffer string for a stream.
# ==============================================================================
_json_sample_get() {
    local idx="$1"
    local varname="_JSON_SAMPLES_${idx}"
    local val=""
    eval "val=\"\${${varname}:-}\""
    printf '%s' "$val"
}

# ==============================================================================
# _json_escape  <string>
#
# Escapes a string for safe embedding in a JSON value.
# Handles: backslash, double-quote, forward-slash, newline, carriage-return,
#          tab, and non-printable control characters.
# Compatible with Bash 3.2+ (no printf %q needed).
# ==============================================================================
_json_escape() {
    local s="$1"
    # Process in order: backslash must be first to avoid double-escaping
    s="${s//\\/\\\\}"          # \ → \\
    s="${s//\"/\\\"}"          # " → \"
    s="${s//$'\n'/\\n}"        # newline → \n
    s="${s//$'\r'/\\r}"        # carriage return → \r
    s="${s//$'\t'/\\t}"        # tab → \t
    # Strip remaining non-printable control characters (0x00-0x1F except \n\r\t)
    s=$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')
    printf '%s' "$s"
}

# ==============================================================================
# _json_export_write
#
# Writes a structured JSON results file for the current test session.
#
# FILE NAMING:
#   prism_<SESSION_ID>.json
#   Saved in JSON_EXPORT_DIR (directory of the running script).
#
# SCHEMA:
# {
#   "schema_version": "1.0",
#   "session": {
#     "id":        "20260425-143022-a3f1",
#     "name":      "baseline-Q1",
#     "tags":      ["pre-change", "wan"],
#     "note":      "Before firewall change",
#     "started":   1745000000,
#     "finished":  1745000120,
#     "duration_sec": 120,
#     "host":      "emea-edge-madrid",
#     "user":      "root",
#     "os":        "Linux 5.15.0-101-generic",
#     "iperf3":    "3.16.0",
#     "iperf3_bin": "/usr/bin/iperf3",
#     "mode":      "client"
#   },
#   "streams": [
#     {
#       "stream":      1,
#       "proto":       "TCP",
#       "target":      "10.0.0.1",
#       "port":        5201,
#       "bandwidth":   "unlimited",
#       "duration_sec": 60,
#       "dscp_name":   "EF",
#       "dscp_val":    46,
#       "parallel":    1,
#       "bidir":       false,
#       "reverse":     false,
#       "bind_ip":     "10.0.0.2",
#       "vrf":         "",
#       "ramp_enabled": false,
#       "status":      "DONE",
#       "summary": {
#         "sender_bw":    "940.12 Mbps",
#         "receiver_bw":  "938.50 Mbps",
#         "retransmits":  0,
#         "jitter_ms":    "",
#         "loss_pct":     "",
#         "rtt_min_ms":   "1.100",
#         "rtt_avg_ms":   "1.234",
#         "rtt_max_ms":   "1.890",
#         "rtt_jitter_ms":"0.123",
#         "rtt_loss_pct": "0%",
#         "rtt_samples":  60,
#         "cwnd_min_kb":  "90.1",
#         "cwnd_max_kb":  "128.0",
#         "cwnd_avg_kb":  "110.5",
#         "cwnd_final_kb":"125.0"
#       },
#       "samples": [
#         {"t": 1745000000, "bps": 985400320},
#         {"t": 1745000001, "bps": 987234560}
#       ]
#     }
#   ]
# }
#
# Parameters:
#   $1  mode  — "client" | "loopback" | "mtp"
#
# Returns:
#   Prints the full path of the written file to stdout.
#   Appends the path to JSON_EXPORT_FILES[].
# ==============================================================================
_json_export_write() {
    local mode="${1:-client}"

    # Require at least a session ID to have been generated
    [[ -z "$SESSION_ID" ]] && return 0
    [[ "$JSON_EXPORT_ENABLED" -ne 1 ]] && return 0

    local finished_ts
    finished_ts=$(date +%s)

    local duration_sec=$(( finished_ts - ${SESSION_RUN_TS:-$finished_ts} ))
    local iperf3_ver="${IPERF3_MAJOR}.${IPERF3_MINOR}.${IPERF3_PATCH}"
    local host_name
    host_name=$(hostname 2>/dev/null || printf 'unknown')
    local os_info
    os_info=$(uname -sr 2>/dev/null || printf 'unknown')

    # Construct output file path
    local outfile="${JSON_EXPORT_DIR}/prism_${SESSION_ID}.json"

    # ------------------------------------------------------------------
    # Build tags JSON array
    # ------------------------------------------------------------------
    local tags_json="[]"
    if [[ -n "$SESSION_TAGS" ]]; then
        local -a tag_arr=()
        local IFS_SAVE="$IFS"
        IFS=' ' read -ra tag_arr <<< "$SESSION_TAGS"
        IFS="$IFS_SAVE"
        if (( ${#tag_arr[@]} > 0 )); then
            tags_json="["
            local t
            for t in "${tag_arr[@]}"; do
                tags_json+="\"$(_json_escape "$t")\","
            done
            tags_json="${tags_json%,}]"
        fi
    fi

    # ------------------------------------------------------------------
    # Begin writing JSON — use a temporary file to ensure atomicity.
    # We write to <outfile>.tmp then rename to <outfile> so that a
    # Ctrl+C during writing never leaves a partial JSON file.
    # ------------------------------------------------------------------
    local tmpfile="${outfile}.tmp"

    # Open the JSON document
    {
        printf '{\n'
        printf '  "schema_version": "1.0",\n'

        # ── session block ────────────────────────────────────────────
        printf '  "session": {\n'
        printf '    "id":           "%s",\n'  "$(_json_escape "$SESSION_ID")"
        printf '    "name":         "%s",\n'  "$(_json_escape "${SESSION_NAME:-}")"
        printf '    "tags":         %s,\n'    "$tags_json"
        printf '    "note":         "%s",\n'  "$(_json_escape "${SESSION_NOTE:-}")"
        printf '    "started":      %s,\n'    "${SESSION_RUN_TS:-0}"
        printf '    "finished":     %s,\n'    "$finished_ts"
        printf '    "duration_sec": %s,\n'    "$duration_sec"
        printf '    "host":         "%s",\n'  "$(_json_escape "$host_name")"
        printf '    "user":         "%s",\n'  "$(_json_escape "${USER:-unknown}")"
        printf '    "os":           "%s",\n'  "$(_json_escape "$os_info")"
        printf '    "iperf3":       "%s",\n'  "$(_json_escape "$iperf3_ver")"
        printf '    "iperf3_bin":   "%s",\n'  "$(_json_escape "${IPERF3_BIN:-}")"
        printf '    "mode":         "%s"\n'   "$(_json_escape "$mode")"
        printf '  },\n'

        # ── streams array ────────────────────────────────────────────
        printf '  "streams": [\n'

        local i
        for (( i=0; i<STREAM_COUNT; i++ )); do
            local sn=$(( i + 1 ))

            # Stream configuration fields
            local st_proto="${S_PROTO[$i]:-TCP}"
            local st_target="${S_TARGET[$i]:-}"
            local st_port="${S_PORT[$i]:-0}"
            local st_bw="${S_BW[$i]:-unlimited}"
            local st_dur="${S_DURATION[$i]:-0}"
            local st_dscp_name="${S_DSCP_NAME[$i]:-}"
            local st_dscp_val="${S_DSCP_VAL[$i]:--1}"
            local st_parallel="${S_PARALLEL[$i]:-1}"
            local st_bidir="${S_BIDIR[$i]:-0}"
            local st_reverse="${S_REVERSE[$i]:-0}"
            local st_bind="${S_BIND[$i]:-}"
            local st_vrf="${S_VRF[$i]:-}"
            local st_ramp="${S_RAMP_ENABLED[$i]:-0}"
            local st_status="${S_STATUS_CACHE[$i]:-UNKNOWN}"

            # Normalize post-cleanup states
            case "$st_status" in
                CLEANED|CLEANUP_PENDING) st_status="DONE" ;;
            esac

            # Boolean values
            local bidir_bool="false"
            [[ "$st_bidir"   == "1" ]] && bidir_bool="true"
            local reverse_bool="false"
            [[ "$st_reverse" == "1" ]] && reverse_bool="true"
            local ramp_bool="false"
            [[ "$st_ramp"    == "1" ]] && ramp_bool="true"

            # Duration: 0 means unlimited
            local dur_display="$st_dur"
            [[ "$st_dur" == "0" ]] && dur_display=0

            # Summary fields
            local sum_sbw="${RESULT_SENDER_BW[$i]:-N/A}"
            local sum_rbw="${RESULT_RECEIVER_BW[$i]:-N/A}"
            local sum_rtx="${RESULT_RTX[$i]:-0}"
            local sum_jit="${RESULT_JITTER[$i]:-}"
            local sum_loss="${RESULT_LOSS_PCT[$i]:-}"

            # RTT fields
            local rtt_min="${S_RTT_MIN[$i]:-}"
            local rtt_avg="${S_RTT_AVG[$i]:-}"
            local rtt_max="${S_RTT_MAX[$i]:-}"
            local rtt_jit="${S_RTT_JITTER[$i]:-}"
            local rtt_loss="${S_RTT_LOSS[$i]:-}"
            local rtt_samp="${S_RTT_SAMPLES[$i]:-0}"
            [[ "$rtt_min"  == "---" || "$rtt_min"  == "???" ]] && rtt_min=""
            [[ "$rtt_avg"  == "---" || "$rtt_avg"  == "???" ]] && rtt_avg=""
            [[ "$rtt_max"  == "---" || "$rtt_max"  == "???" ]] && rtt_max=""
            [[ "$rtt_jit"  == "---" || "$rtt_jit"  == "???" ]] && rtt_jit=""
            [[ "$rtt_loss" == "---" || "$rtt_loss" == "???" ]] && rtt_loss=""

            # CWND fields
            local cwnd_min="${S_CWND_MIN[$i]:-}"
            local cwnd_max="${S_CWND_MAX[$i]:-}"
            local cwnd_fin="${S_CWND_FINAL[$i]:-}"
            local cwnd_avg
            cwnd_avg=$(_cwnd_avg "$i" 2>/dev/null || printf '')
            [[ "$cwnd_min" == "---" ]] && cwnd_min=""
            [[ "$cwnd_max" == "---" ]] && cwnd_max=""
            [[ "$cwnd_fin" == "---" ]] && cwnd_fin=""
            [[ "$cwnd_avg" == "---" ]] && cwnd_avg=""

            # RTX: only meaningful for TCP
            [[ "$st_proto" == "UDP" ]] && sum_rtx=""

            # Separator between stream objects
            [[ $i -gt 0 ]] && printf '    ,\n'

            printf '    {\n'
            printf '      "stream":       %d,\n'    "$sn"
            printf '      "proto":        "%s",\n'  "$(_json_escape "$st_proto")"
            printf '      "target":       "%s",\n'  "$(_json_escape "$st_target")"
            printf '      "port":         %s,\n'    "$st_port"
            printf '      "bandwidth":    "%s",\n'  "$(_json_escape "$st_bw")"
            printf '      "duration_sec": %s,\n'    "$dur_display"
            printf '      "dscp_name":    "%s",\n'  "$(_json_escape "$st_dscp_name")"
            printf '      "dscp_val":     %s,\n'    "$st_dscp_val"
            printf '      "parallel":     %s,\n'    "$st_parallel"
            printf '      "bidir":        %s,\n'    "$bidir_bool"
            printf '      "reverse":      %s,\n'    "$reverse_bool"
            printf '      "bind_ip":      "%s",\n'  "$(_json_escape "$st_bind")"
            printf '      "vrf":          "%s",\n'  "$(_json_escape "$st_vrf")"
            printf '      "ramp_enabled": %s,\n'    "$ramp_bool"
            printf '      "status":       "%s",\n'  "$(_json_escape "$st_status")"

            # summary sub-object
            printf '      "summary": {\n'
            printf '        "sender_bw":     "%s",\n'  "$(_json_escape "$sum_sbw")"
            printf '        "receiver_bw":   "%s",\n'  "$(_json_escape "$sum_rbw")"
            printf '        "retransmits":   "%s",\n'  "$(_json_escape "$sum_rtx")"
            printf '        "jitter_ms":     "%s",\n'  "$(_json_escape "$sum_jit")"
            printf '        "loss_pct":      "%s",\n'  "$(_json_escape "$sum_loss")"
            printf '        "rtt_min_ms":    "%s",\n'  "$(_json_escape "$rtt_min")"
            printf '        "rtt_avg_ms":    "%s",\n'  "$(_json_escape "$rtt_avg")"
            printf '        "rtt_max_ms":    "%s",\n'  "$(_json_escape "$rtt_max")"
            printf '        "rtt_jitter_ms": "%s",\n'  "$(_json_escape "$rtt_jit")"
            printf '        "rtt_loss_pct":  "%s",\n'  "$(_json_escape "$rtt_loss")"
            printf '        "rtt_samples":   %s,\n'    "$rtt_samp"
            printf '        "cwnd_min_kb":   "%s",\n'  "$(_json_escape "$cwnd_min")"
            printf '        "cwnd_max_kb":   "%s",\n'  "$(_json_escape "$cwnd_max")"
            printf '        "cwnd_avg_kb":   "%s",\n'  "$(_json_escape "$cwnd_avg")"
            printf '        "cwnd_final_kb": "%s"\n'   "$(_json_escape "$cwnd_fin")"
            printf '      },\n'

            # samples array — per-second bandwidth time-series
            printf '      "samples": [\n'
            local sample_buf
            sample_buf=$(_json_sample_get "$i")
            if [[ -n "$sample_buf" ]]; then
                local first_sample=1
                local entry
                # Split on pipe — each entry is "epoch:bps"
                local IFS_SAVE="$IFS"
                IFS='|'
                local -a sample_entries
                read -ra sample_entries <<< "$sample_buf"
                IFS="$IFS_SAVE"
                local entry
                for entry in "${sample_entries[@]}"; do
                    [[ -z "$entry" ]] && continue
                    local e_ts e_bps
                    e_ts="${entry%%:*}"
                    e_bps="${entry##*:}"
                    [[ -z "$e_ts"  || ! "$e_ts"  =~ ^[0-9]+$ ]] && continue
                    [[ -z "$e_bps" || ! "$e_bps" =~ ^[0-9]+$ ]] && continue
                    if [[ $first_sample -eq 0 ]]; then
                        printf ',\n'
                    fi
                    printf '        {"t":%s,"bps":%s}' "$e_ts" "$e_bps"
                    first_sample=0
                done
                printf '\n'
            fi
            printf '      ]\n'   # end samples
            printf '    }\n'     # end stream object
        done

        printf '  ]\n'   # end streams array
        printf '}\n'     # end root object

    } > "$tmpfile" 2>/dev/null

    # ------------------------------------------------------------------
    # Atomic rename: tmp → final
    # ------------------------------------------------------------------
    if mv "$tmpfile" "$outfile" 2>/dev/null; then
        JSON_EXPORT_FILES+=("$outfile")
        printf '%b  JSON results exported → %b%s%b\n' \
            "$GREEN" "$BOLD" "$outfile" "$NC"
        printf '%b  Schema: session + %d stream(s) + per-second samples%b\n' \
            "$DIM" "$STREAM_COUNT" "$NC"
    else
        rm -f "$tmpfile" 2>/dev/null
        printf '%b  WARNING: Could not write JSON export to %s%b\n' \
            "$YELLOW" "$outfile" "$NC"
    fi
}

# ==============================================================================
# _json_export_prompt_delete
#
# Called during cleanup (Ctrl+C, Ctrl+Z trap, or exit) when one or more
# JSON export files exist.
#
# Displays a formatted list of all JSON files created this session and
# asks the operator whether to delete them.
#
# Behavior:
#   Y / yes  — delete all files, print confirmation for each
#   N / no   — keep all files, print their paths
#   Enter    — default to KEEP (safe default — never auto-delete data)
#
# FIXES APPLIED:
#   1. Bash 3.2 compatibility: replaced ${answer^^} with tr-based
#      uppercase conversion. The ^^ operator requires Bash 4.0+ and
#      causes "bad substitution" on macOS default Bash 3.2.
#   2. Safe variable defaults: all variable expansions use ${var:-}
#      to prevent unbound variable errors under strict mode.
#   3. tty_echo used throughout so output reaches the terminal even
#      when stdout is redirected during signal handling.
#   4. Read guard: falls back to "N" when stdin is not a TTY so the
#      function never hangs in non-interactive environments.
#   5. File size display: uses portable wc -c with tr to strip
#      whitespace — compatible with both GNU and BSD wc.
#   6. Empty array guard: returns immediately when no files exist
#      so the function is safe to call unconditionally from cleanup().
#   7. jq hint: only printed for files that still exist on disk at
#      the time of display, not for already-deleted files.
#
# CALLED BY:
#   cleanup()  — on Ctrl+C, SIGTERM, SIGQUIT, SIGHUP, and normal exit
#
# GLOBALS READ:
#   JSON_EXPORT_FILES[]  — array of export file paths created this session
#   COLS                 — terminal width for separator line
#   JSON_EXPORT_DIR      — directory where export files are written
#
# GLOBALS MODIFIED:
#   JSON_EXPORT_FILES[]  — cleared after successful deletion (Y path)
# ==============================================================================
_json_export_prompt_delete() {

    # ── Guard: nothing to do if no files were created ────────────────────────
    [[ ${#JSON_EXPORT_FILES[@]} -eq 0 ]] && return 0

    # ── Build separator line ──────────────────────────────────────────────────
    local sep
    sep=$(rpt '=' $(( COLS - 2 )))

    # ── Header ───────────────────────────────────────────────────────────────
    tty_echo ""
    tty_echo "${BOLD}${CYAN}+${sep}+${NC}"
    tty_echo "${BOLD}${CYAN}  JSON Export Files — Cleanup${NC}"
    tty_echo "${BOLD}${CYAN}+${sep}+${NC}"
    tty_echo ""
    tty_echo "  The following JSON results file(s) were created this session:"
    tty_echo ""

    # ── File list with sizes ──────────────────────────────────────────────────
    local f sz
    for f in "${JSON_EXPORT_FILES[@]}"; do
        if [[ -f "$f" ]]; then
            # ── Portable file size: wc -c + tr strips BSD/GNU whitespace ──────
            sz=$(wc -c < "$f" 2>/dev/null | tr -d ' \t\n')
            tty_echo "    ${CYAN}${f}${NC}  ${DIM}(${sz:-0} bytes)${NC}"
        else
            tty_echo "    ${YELLOW}${f}${NC}  ${DIM}(already removed)${NC}"
        fi
    done

    tty_echo ""

    # ── Prompt ───────────────────────────────────────────────────────────────
    tty_echo "  ${BOLD}Delete these JSON file(s)?${NC}"
    tty_echo "    ${BOLD}${RED}Y${NC}  Delete all listed files"
    tty_echo "    ${BOLD}${GREEN}N${NC}  Keep all files  ${DIM}(default — press Enter)${NC}"
    tty_echo ""

    # ── Read answer ───────────────────────────────────────────────────────────
    # Read from /dev/tty directly so the prompt works during signal handling
    # when stdout/stdin may be redirected. Falls back to "N" (keep) when
    # the terminal is not available — never auto-deletes data.
    local answer=""
    if [[ -t 0 ]]; then
        read -r -p "  Choice [N]: " answer </dev/tty 2>/dev/null \
            || answer="N"
    else
        # Non-interactive environment — safe default is always KEEP
        answer="N"
        tty_echo "  ${DIM}Non-interactive environment detected. Defaulting to Keep.${NC}"
    fi

    # Apply default when operator just pressed Enter
    answer="${answer:-N}"

    # ── FIX: Bash 3.2 compatible uppercase conversion ─────────────────────────
    # The ${answer^^} operator requires Bash 4.0+ and causes:
    #   "bad substitution" on macOS default Bash 3.2.57
    # Solution: use tr for portable uppercase conversion.
    local answer_upper
    answer_upper=$(printf '%s' "$answer" | tr '[:lower:]' '[:upper:]')

    tty_echo ""

    # ── Branch on answer ──────────────────────────────────────────────────────
    case "$answer_upper" in

        # ── DELETE path ───────────────────────────────────────────────────────
        Y|YES)
            tty_echo "  ${BOLD}Deleting JSON export file(s)...${NC}"
            tty_echo ""

            local deleted=0
            local failed=0
            local skipped=0

            for f in "${JSON_EXPORT_FILES[@]}"; do

                # File already gone — skip silently
                if [[ ! -f "$f" ]]; then
                    tty_echo \
                        "    ${YELLOW}[SKIP   ]${NC}  ${f}  ${DIM}(already removed)${NC}"
                    (( skipped++ ))
                    continue
                fi

                # Attempt deletion
                if rm -f "$f" 2>/dev/null; then
                    tty_echo "    ${GREEN}[DELETED]${NC}  ${f}"
                    (( deleted++ ))
                else
                    tty_echo \
                        "    ${RED}[FAILED ]${NC}  ${f}" \
                        " ${DIM}(could not delete — check permissions)${NC}"
                    (( failed++ ))
                fi
            done

            tty_echo ""

            # ── Deletion summary ──────────────────────────────────────────────
            if (( deleted > 0 )); then
                tty_echo \
                    "  ${GREEN}✓ ${deleted} file(s) deleted successfully.${NC}"
            fi
            if (( skipped > 0 )); then
                tty_echo \
                    "  ${YELLOW}  ${skipped} file(s) were already removed.${NC}"
            fi
            if (( failed > 0 )); then
                tty_echo \
                    "  ${RED}✗ ${failed} file(s) could not be deleted.${NC}"
                tty_echo \
                    "  ${DIM}  Check permissions in: ${JSON_EXPORT_DIR:-$(pwd)}${NC}"
            fi

            # Clear the tracking array so cleanup() does not re-prompt
            JSON_EXPORT_FILES=()
            ;;

        # ── KEEP path (default) ───────────────────────────────────────────────
        *)
            tty_echo "  ${CYAN}JSON file(s) kept.${NC}"
            tty_echo ""
            tty_echo \
                "  ${DIM}Files are located in: ${JSON_EXPORT_DIR:-$(pwd)}${NC}"
            tty_echo ""
            tty_echo "  ${DIM}Analyse results with jq:${NC}"
            tty_echo ""

            # Only show jq hints for files that still exist on disk
            local hint_shown=0
            for f in "${JSON_EXPORT_FILES[@]}"; do
                if [[ -f "$f" ]]; then
                    tty_echo \
                        "    ${DIM}# View session summary and stream results${NC}"
                    tty_echo \
                        "    ${DIM}jq '.session,.streams[].summary' ${f}${NC}"
                    tty_echo ""
                    tty_echo \
                        "    ${DIM}# Extract per-second bandwidth time-series${NC}"
                    tty_echo \
                        "    ${DIM}jq '.streams[0].samples' ${f}${NC}"
                    tty_echo ""
                    tty_echo \
                        "    ${DIM}# List all stream sender bandwidths${NC}"
                    tty_echo \
                        "    ${DIM}jq '.streams[].summary.sender_bw' ${f}${NC}"
                    tty_echo ""
                    (( hint_shown++ ))
                    # Only show hints for the first existing file to avoid
                    # repeating the same jq patterns for every export file
                    (( hint_shown >= 1 )) && break
                fi
            done

            # If multiple files exist, list them all plainly
            if (( ${#JSON_EXPORT_FILES[@]} > 1 )); then
                tty_echo \
                    "  ${DIM}All export files this session:${NC}"
                for f in "${JSON_EXPORT_FILES[@]}"; do
                    [[ -f "$f" ]] && \
                        tty_echo "    ${DIM}${f}${NC}"
                done
                tty_echo ""
            fi
            ;;

    esac

    # ── Footer ────────────────────────────────────────────────────────────────
    tty_echo "${BOLD}${CYAN}+${sep}+${NC}"
    tty_echo ""
}

# ==============================================================================
# _generate_session_id
#
# Generates a unique session identifier in the format:
#   YYYYMMDD-HHMMSS-XXXX
#   where XXXX is a 4-character hex suffix derived from $RANDOM.
#
# The ID is deterministic-friendly (datestamp prefix) and collision-resistant
# (hex suffix) without requiring uuidgen or external tools.
#
# Examples:
#   20260425-143022-a3f1
#   20260425-143022-8c2d
# ==============================================================================
_generate_session_id() {
    local datestamp
    datestamp=$(date +'%Y%m%d-%H%M%S')
    local hex_suffix
    hex_suffix=$(printf '%04x' $(( RANDOM * RANDOM % 65536 )))
    printf '%s-%s' "$datestamp" "$hex_suffix"
}

# ==============================================================================
# _prompt_session_name
#
# Displays an interactive session naming panel before a test run.
# The operator can:
#   - Enter a free-text session name (or press Enter to use the auto-generated
#     ID as the name)
#   - Enter comma or space-separated tags (e.g. pre-change, production, wan)
#   - Enter an optional one-line note
#   - Skip all fields with Enter for a fully unnamed session
#
# All inputs are sanitized:
#   - Name: alphanumeric, hyphens, underscores, dots, spaces (max 64 chars)
#   - Tags: each tag alphanumeric + hyphens + underscores (max 8 tags)
#   - Note: printable ASCII only (max 120 chars)
#
# Populates globals:
#   SESSION_NAME     SESSION_TAGS     SESSION_ID
#   SESSION_NOTE     SESSION_RUN_TS
#
# Called by: run_client_mode, run_server_mode, run_loopback_mode,
#            run_mixed_traffic_mode — immediately before launch.
# ==============================================================================
_prompt_session_name() {
    local inner=$(( COLS - 2 ))
    SESSION_ID=$(_generate_session_id)
    SESSION_RUN_TS=$(date +%s)

    # ------------------------------------------------------------------
    # Header
    # ------------------------------------------------------------------
    printf '\n'
    printf '+%s+\n' "$(rpt '=' $inner)"

    # Centered title using _visible_len for ANSI-safe centering
    local _title="${BOLD}Test Session Naming${NC}  ${DIM}(optional — press Enter to skip each field)${NC}"
    local _title_vlen
    _title_vlen=$(_visible_len "$_title")
    local _tlpad=$(( (inner - _title_vlen) / 2 ))
    local _trpad=$(( inner - _title_vlen - _tlpad ))
    [[ $_tlpad -lt 0 ]] && _tlpad=0
    [[ $_trpad -lt 0 ]] && _trpad=0
    printf "|%s%b%s|\n" "$(rpt ' ' $_tlpad)" "$_title" "$(rpt ' ' $_trpad)"

    printf '+%s+\n' "$(rpt '=' $inner)"

    # ------------------------------------------------------------------
    # Auto-generated ID display
    # ------------------------------------------------------------------
    local id_line="  ${DIM}Session ID:${NC}  ${CYAN}${BOLD}${SESSION_ID}${NC}"
    local id_vlen
    id_vlen=$(_visible_len "$id_line")
    local id_rpad=$(( inner - id_vlen ))
    [[ $id_rpad -lt 0 ]] && id_rpad=0
    printf "|%b%s|\n" "$id_line" "$(rpt ' ' $id_rpad)"

    printf '+%s+\n' "$(rpt '-' $inner)"

    # ------------------------------------------------------------------
    # Tag suggestion helper
    # ------------------------------------------------------------------
    local tag_examples="  ${DIM}Suggested tags:  pre-change  post-change  baseline  regression"
    local tag_examples2="${NC}${DIM}                  production  staging  wan  datacenter  loopback${NC}"
    local te1_vlen
    te1_vlen=$(_visible_len "$tag_examples")
    local te2_vlen
    te2_vlen=$(_visible_len "$tag_examples2")
    local te1_rpad=$(( inner - te1_vlen ))
    local te2_rpad=$(( inner - te2_vlen ))
    [[ $te1_rpad -lt 0 ]] && te1_rpad=0
    [[ $te2_rpad -lt 0 ]] && te2_rpad=0
    printf "|%b%s|\n" "$tag_examples"  "$(rpt ' ' $te1_rpad)"
    printf "|%b%s|\n" "$tag_examples2" "$(rpt ' ' $te2_rpad)"

    printf '+%s+\n' "$(rpt '-' $inner)"
    printf '\n'

    # ------------------------------------------------------------------
    # Field 1: Session Name
    # ------------------------------------------------------------------
    local raw_name=""
    printf "  %b%s%b\n" "${BOLD}" "Session Name" "${NC}"
    printf "  %b%s%b\n" "${DIM}" \
        "Free-text label for this test run. Used in reports and history." "${NC}"
    printf "  %b%s%b\n" "${DIM}" \
        "Examples: baseline-Q1  post-firewall-change  WAN-link-test-2026" "${NC}"
    printf '\n'

    while true; do
        read -r -p "  Name [${SESSION_ID}]: " raw_name </dev/tty
        raw_name="${raw_name:-}"

        # Empty → use auto-generated ID as name
        if [[ -z "$raw_name" ]]; then
            SESSION_NAME="$SESSION_ID"
            printf "  %b→ Using auto-generated ID as session name.%b\n" \
                "$DIM" "$NC"
            break
        fi

        # Sanitize: allow alphanumeric, hyphen, underscore, dot, space
        local sanitized
        sanitized=$(printf '%s' "$raw_name" \
            | sed 's/[^a-zA-Z0-9._/ -]//g' \
            | sed 's/^[[:space:]]*//' \
            | sed 's/[[:space:]]*$//')

        # Enforce max length of 64 chars
        if (( ${#sanitized} > 64 )); then
            sanitized="${sanitized:0:64}"
            printf "  %bName truncated to 64 characters.%b\n" "$YELLOW" "$NC"
        fi

        if [[ -z "$sanitized" ]]; then
            printf "  %bName contains no valid characters. Using auto-generated ID.%b\n" \
                "$YELLOW" "$NC"
            SESSION_NAME="$SESSION_ID"
            break
        fi

        SESSION_NAME="$sanitized"
        printf "  %b✓ Name set to: %b%s%b\n" "$GREEN" "$BOLD" "$SESSION_NAME" "$NC"
        break
    done

    printf '\n'

    # ------------------------------------------------------------------
    # Field 2: Tags
    # ------------------------------------------------------------------
    local raw_tags=""
    printf "  %b%s%b\n" "${BOLD}" "Tags" "${NC}"
    printf "  %b%s%b\n" "${DIM}" \
        "Space or comma-separated keywords. Max 8 tags, each max 32 chars." "${NC}"
    printf '\n'

    read -r -p "  Tags [none]: " raw_tags </dev/tty
    raw_tags="${raw_tags:-}"

    SESSION_TAGS=""
    if [[ -n "$raw_tags" ]]; then
        # Normalize: replace commas with spaces, collapse whitespace
        local normalized_tags
        normalized_tags=$(printf '%s' "$raw_tags" \
            | tr ',' ' ' \
            | tr -s ' ')

        local -a tag_array=()
        local tag
        # Read each whitespace-separated word as a tag
        local IFS_SAVE="$IFS"
        IFS=' '
        read -ra tag_array <<< "$normalized_tags"
        IFS="$IFS_SAVE"

        local valid_tags=()
        local skipped=0
        for tag in "${tag_array[@]}"; do
            # Sanitize tag: alphanumeric, hyphens, underscores only
            local clean_tag
            clean_tag=$(printf '%s' "$tag" \
                | sed 's/[^a-zA-Z0-9_-]//g')
            [[ -z "$clean_tag" ]] && continue

            # Enforce max tag length
            if (( ${#clean_tag} > 32 )); then
                clean_tag="${clean_tag:0:32}"
            fi

            # Enforce max 8 tags
            if (( ${#valid_tags[@]} >= 8 )); then
                (( skipped++ ))
                continue
            fi

            valid_tags+=("$clean_tag")
        done

        if (( ${#valid_tags[@]} > 0 )); then
            SESSION_TAGS="${valid_tags[*]}"
            printf "  %b✓ Tags set: %b" "$GREEN" "$BOLD"
            local t
            for t in "${valid_tags[@]}"; do
                printf "[%s] " "$t"
            done
            printf "%b\n" "$NC"
            if (( skipped > 0 )); then
                printf "  %b%d tag(s) skipped (limit 8).%b\n" \
                    "$YELLOW" "$skipped" "$NC"
            fi
        else
            printf "  %bNo valid tags extracted.%b\n" "$DIM" "$NC"
        fi
    else
        printf "  %b→ No tags set.%b\n" "$DIM" "$NC"
    fi

    printf '\n'

    # ------------------------------------------------------------------
    # Field 3: Note
    # ------------------------------------------------------------------
    local raw_note=""
    printf "  %b%s%b\n" "${BOLD}" "Note" "${NC}"
    printf "  %b%s%b\n" "${DIM}" \
        "Optional one-line operator note. Max 120 printable characters." "${NC}"
    printf '\n'

    read -r -p "  Note [none]: " raw_note </dev/tty
    raw_note="${raw_note:-}"

    SESSION_NOTE=""
    if [[ -n "$raw_note" ]]; then
        # Strip non-printable characters
        local clean_note
        clean_note=$(printf '%s' "$raw_note" \
            | tr -cd '[:print:]' \
            | sed 's/^[[:space:]]*//' \
            | sed 's/[[:space:]]*$//')

        if (( ${#clean_note} > 120 )); then
            clean_note="${clean_note:0:120}"
            printf "  %bNote truncated to 120 characters.%b\n" "$YELLOW" "$NC"
        fi

        if [[ -n "$clean_note" ]]; then
            SESSION_NOTE="$clean_note"
            printf "  %b✓ Note set.%b\n" "$GREEN" "$NC"
        else
            printf "  %bNote contains no printable characters. Skipped.%b\n" \
                "$DIM" "$NC"
        fi
    else
        printf "  %b→ No note set.%b\n" "$DIM" "$NC"
    fi

    printf '\n'

    # ------------------------------------------------------------------
    # Summary confirmation box
    # ------------------------------------------------------------------
    printf '+%s+\n' "$(rpt '=' $inner)"

    local sum_title="${BOLD}Session Summary${NC}"
    local sum_vlen
    sum_vlen=$(_visible_len "$sum_title")
    local sum_lpad=$(( (inner - sum_vlen) / 2 ))
    local sum_rpad=$(( inner - sum_vlen - sum_lpad ))
    [[ $sum_lpad -lt 0 ]] && sum_lpad=0
    [[ $sum_rpad -lt 0 ]] && sum_rpad=0
    printf "|%s%b%s|\n" "$(rpt ' ' $sum_lpad)" "$sum_title" "$(rpt ' ' $sum_rpad)"

    printf '+%s+\n' "$(rpt '-' $inner)"

    # Helper: print a summary field row
    # Layout: "|  LABEL_COL  VALUE ... |"
    local _FL=12   # fixed label column width
    _sum_row() {
        local lbl="$1"
        local val="$2"
        local val_color="${3:-$NC}"
        local row_plain
        row_plain=$(printf '  %-*s  %s' "$_FL" "$lbl" "$val")
        local row_vlen=${#row_plain}
        local row_rpad=$(( inner - row_vlen - 1 ))
        [[ $row_rpad -lt 0 ]] && row_rpad=0
        printf "|  %-*s  %b%s%b%s|\n" \
            "$_FL" "$lbl" \
            "$val_color" "$val" "$NC" \
            "$(rpt ' ' $row_rpad)"
    }

    _sum_row "ID"      "$SESSION_ID"    "$CYAN"
    _sum_row "Name"    "$SESSION_NAME"  "$BOLD"
    _sum_row "Tags"    "${SESSION_TAGS:-none}"  "$YELLOW"
    _sum_row "Note"    "${SESSION_NOTE:-none}"  "$DIM"
    _sum_row "Started" "$(date +'%Y-%m-%d %H:%M:%S')"  "$DIM"

    printf '+%s+\n' "$(rpt '=' $inner)"
    printf '\n'
}

# ==============================================================================
# _session_append_history
#
# Appends a completed test session record to the per-host JSON history file.
#
# Called by: run_client_mode, run_loopback_mode, run_mixed_traffic_mode
#            immediately AFTER display_results_table() so final BW values
#            are available.
#
# JSON record format (one object per line for easy grep/jq processing):
# {
#   "id":        "20260425-143022-a3f1",
#   "name":      "baseline-Q1",
#   "tags":      ["pre-change", "wan"],
#   "note":      "Before firewall policy update",
#   "started":   1745000000,
#   "finished":  1745000120,
#   "host":      "emea-edge-madrid",
#   "user":      "root",
#   "os":        "Linux 5.15.0-101-generic",
#   "iperf3":    "3.16.0",
#   "mode":      "client",
#   "streams":   2,
#   "results": [
#     {
#       "stream": 1,
#       "proto":  "TCP",
#       "target": "10.0.0.1",
#       "port":   5201,
#       "dscp":   "EF",
#       "sender_bw":   "940.12 Mbps",
#       "receiver_bw": "938.50 Mbps",
#       "rtt_avg_ms":  "1.234",
#       "loss_pct":    "0%",
#       "status":      "DONE"
#     }
#   ]
# }
#
# The file is a JSON Lines file (one complete JSON object per line).
# This format is directly consumable by jq, Python json.loads(), and
# any log aggregation tool without requiring a JSON array wrapper.
#
# Parameters:
#   $1  mode   — "client" | "server" | "loopback" | "mtp"
# ==============================================================================
_session_append_history() {
    local mode="${1:-client}"

    # Skip if no session was named (SESSION_ID is empty)
    [[ -z "$SESSION_ID" ]] && return 0

    local finished_ts
    finished_ts=$(date +%s)

    local iperf3_ver="${IPERF3_MAJOR}.${IPERF3_MINOR}.${IPERF3_PATCH}"
    local host_name
    host_name=$(hostname 2>/dev/null || printf 'unknown')
    local os_info
    os_info=$(uname -sr 2>/dev/null || printf 'unknown')

    # ------------------------------------------------------------------
    # Build tags JSON array
    # ------------------------------------------------------------------
    local tags_json="[]"
    if [[ -n "$SESSION_TAGS" ]]; then
        local -a tag_arr=()
        local t
        local IFS_SAVE="$IFS"
        IFS=' '
        read -ra tag_arr <<< "$SESSION_TAGS"
        IFS="$IFS_SAVE"
        if (( ${#tag_arr[@]} > 0 )); then
            tags_json="["
            for t in "${tag_arr[@]}"; do
                # Escape any double-quotes in tag (defensive)
                local safe_t="${t//\"/\\\"}"
                tags_json+="\"${safe_t}\","
            done
            # Remove trailing comma and close array
            tags_json="${tags_json%,}]"
        fi
    fi

    # ------------------------------------------------------------------
    # Escape a string for JSON embedding
    # Handles: backslash, double-quote, newline, tab
    # ------------------------------------------------------------------
    _json_str() {
        local s="$1"
        # Escape backslash first, then double-quote, then control chars
        s="${s//\\/\\\\}"
        s="${s//\"/\\\"}"
        s="${s//$'\n'/\\n}"
        s="${s//$'\t'/\\t}"
        printf '%s' "$s"
    }

    local safe_name;  safe_name=$(_json_str "${SESSION_NAME:-}")
    local safe_note;  safe_note=$(_json_str "${SESSION_NOTE:-}")
    local safe_host;  safe_host=$(_json_str "$host_name")
    local safe_os;    safe_os=$(_json_str "$os_info")
    local safe_bin;   safe_bin=$(_json_str "${IPERF3_BIN:-}")

    # ------------------------------------------------------------------
    # Build results array
    # ------------------------------------------------------------------
    local results_json="["
    local i
    local first_result=1

    for (( i=0; i<STREAM_COUNT; i++ )); do
        local sn=$(( i + 1 ))
        local r_proto="${S_PROTO[$i]:-TCP}"
        local r_target="${S_TARGET[$i]:-}"
        local r_port="${S_PORT[$i]:-0}"
        local r_dscp="${S_DSCP_NAME[$i]:-}"
        local r_sbw="${RESULT_SENDER_BW[$i]:-N/A}"
        local r_rbw="${RESULT_RECEIVER_BW[$i]:-N/A}"
        local r_status="${S_STATUS_CACHE[$i]:-UNKNOWN}"
        local r_rtt_avg="${S_RTT_AVG[$i]:-}"
        local r_loss="${S_RTT_LOSS[$i]:-}"

        # Fallback RTT and loss from results arrays
        [[ -z "$r_rtt_avg" || "$r_rtt_avg" == "---" ]] && r_rtt_avg="N/A"
        [[ -z "$r_loss"    || "$r_loss"    == "---" ]] && r_loss="N/A"

        # Map post-cleanup states to their human-readable equivalents
        case "$r_status" in
            CLEANED|CLEANUP_PENDING) r_status="DONE" ;;
        esac

        local safe_tgt;  safe_tgt=$(_json_str "$r_target")
        local safe_dscp; safe_dscp=$(_json_str "$r_dscp")
        local safe_sbw;  safe_sbw=$(_json_str "$r_sbw")
        local safe_rbw;  safe_rbw=$(_json_str "$r_rbw")

        [[ $first_result -eq 0 ]] && results_json+=","
        first_result=0

        results_json+=$(printf \
            '{"stream":%d,"proto":"%s","target":"%s","port":%s,"dscp":"%s","sender_bw":"%s","receiver_bw":"%s","rtt_avg_ms":"%s","loss_pct":"%s","status":"%s"}' \
            "$sn" \
            "$r_proto" \
            "$safe_tgt" \
            "$r_port" \
            "$safe_dscp" \
            "$safe_sbw" \
            "$safe_rbw" \
            "$r_rtt_avg" \
            "$r_loss" \
            "$r_status")
    done
    results_json+="]"

    # ------------------------------------------------------------------
    # Assemble the full JSON record (single line)
    # ------------------------------------------------------------------
    local json_record
    json_record=$(printf \
        '{"id":"%s","name":"%s","tags":%s,"note":"%s","started":%s,"finished":%s,"host":"%s","user":"%s","os":"%s","iperf3":"%s","iperf3_bin":"%s","mode":"%s","streams":%d,"results":%s}' \
        "$SESSION_ID" \
        "$safe_name" \
        "$tags_json" \
        "$safe_note" \
        "$SESSION_RUN_TS" \
        "$finished_ts" \
        "$safe_host" \
        "${USER:-unknown}" \
        "$safe_os" \
        "$iperf3_ver" \
        "$safe_bin" \
        "$mode" \
        "$STREAM_COUNT" \
        "$results_json")

    # ------------------------------------------------------------------
    # Write to history file
    # Creates the directory and file if they don't exist.
    # Appends one JSON line per session (JSON Lines format).
    # ------------------------------------------------------------------
    local history_dir
    history_dir=$(dirname "$SESSION_HISTORY_FILE")
    mkdir -p "$history_dir" 2>/dev/null

    if printf '%s\n' "$json_record" >> "$SESSION_HISTORY_FILE" 2>/dev/null; then
        printf '%b  Session history saved → %s%b\n' \
            "$DIM" "$SESSION_HISTORY_FILE" "$NC"
    else
        printf '%b  WARNING: Could not write session history to %s%b\n' \
            "$YELLOW" "$SESSION_HISTORY_FILE" "$NC"
    fi
}

# ==============================================================================
# _print_session_name_header
#
# Renders the session name, tags, and note as a header block inside the
# standard PRISM box style. Called at the top of display_results_table()
# and in all mode summary headers when a session name has been set.
#
# Only renders when SESSION_NAME is non-empty and differs from SESSION_ID
# (i.e. the operator actually provided a meaningful name).
# Always renders the ID even for unnamed sessions so logs are traceable.
# ==============================================================================
_print_session_name_header() {
    local inner=$(( COLS - 2 ))

    printf '+%s+\n' "$(rpt '=' $inner)"

    # ------------------------------------------------------------------
    # ID line — always shown
    # ------------------------------------------------------------------
    local id_str="Session  ${CYAN}${BOLD}${SESSION_ID}${NC}"
    [[ -n "$SESSION_NAME" && "$SESSION_NAME" != "$SESSION_ID" ]] && \
        id_str+="  ${DIM}→${NC}  ${BOLD}${SESSION_NAME}${NC}"

    local id_vlen
    id_vlen=$(_visible_len "$id_str")
    local id_lpad=2
    local id_rpad=$(( inner - id_lpad - id_vlen ))
    [[ $id_rpad -lt 0 ]] && id_rpad=0
    printf "|%s%b%s|\n" \
        "$(rpt ' ' $id_lpad)" "$id_str" "$(rpt ' ' $id_rpad)"

    # ------------------------------------------------------------------
    # Tags line — only when tags are set
    # ------------------------------------------------------------------
    if [[ -n "$SESSION_TAGS" ]]; then
        local tags_str="${DIM}Tags:${NC} "
        local t
        local IFS_SAVE="$IFS"
        IFS=' '
        local -a t_arr
        read -ra t_arr <<< "$SESSION_TAGS"
        IFS="$IFS_SAVE"
        for t in "${t_arr[@]}"; do
            tags_str+="${CYAN}[${t}]${NC} "
        done
        local tags_vlen
        tags_vlen=$(_visible_len "$tags_str")
        local tags_rpad=$(( inner - 2 - tags_vlen ))
        [[ $tags_rpad -lt 0 ]] && tags_rpad=0
        printf "|  %b%s|\n" "$tags_str" "$(rpt ' ' $tags_rpad)"
    fi

    # ------------------------------------------------------------------
    # Note line — only when note is set
    # ------------------------------------------------------------------
    if [[ -n "$SESSION_NOTE" ]]; then
        local note_str="${DIM}Note:${NC}  ${SESSION_NOTE}"
        # Truncate if note is too long for the box
        local note_vlen
        note_vlen=$(_visible_len "$note_str")
        local note_max=$(( inner - 4 ))
        if (( note_vlen > note_max )); then
            # Truncate the raw note text, then rebuild
            local trunc_len=$(( ${#SESSION_NOTE} - (note_vlen - note_max) - 1 ))
            [[ $trunc_len -lt 0 ]] && trunc_len=0
            note_str="${DIM}Note:${NC}  ${SESSION_NOTE:0:$trunc_len}~"
            note_vlen=$(_visible_len "$note_str")
        fi
        local note_rpad=$(( inner - 2 - note_vlen ))
        [[ $note_rpad -lt 0 ]] && note_rpad=0
        printf "|  %b%s|\n" "$note_str" "$(rpt ' ' $note_rpad)"
    fi

    printf '+%s+\n' "$(rpt '=' $inner)"
    printf '\n'
}

# ==============================================================================
# CAPABILITY MATRIX GLOBALS
# Populated by _check_capabilities() at startup.
# Values are ANSI-colored strings used directly in the TUI renderer.
# ==============================================================================
CAP_RAMP=""
CAP_BIDIR=""
CAP_VRF=""
CAP_SNIFF=""
CAP_CWND=""
CAP_MTP=""
CAP_RAMP_REASON=""
CAP_BIDIR_REASON=""
CAP_VRF_REASON=""
CAP_SNIFF_REASON=""
CAP_CWND_REASON=""
CAP_MTP_REASON=""

# ==============================================================================
# _check_capabilities (Fixed v3)
#
# KEY FIX: _cap_badge now stores ONLY the ANSI color codes wrapped around
# the raw text. The raw text is stored SEPARATELY in CAP_X_RAW.
# _cm_row prints them independently — colored badge for display, raw badge
# for arithmetic. This eliminates the double-print bug.
# ==============================================================================
_check_capabilities() {

    # Raw badge strings — exactly 8 visible characters each.
    # These are used for:
    #   (a) width arithmetic in _cm_row padding calculations
    #   (b) the legend row rendering
    # They are NEVER printed directly inside _cm_row.
    local RAW_OK="[  OK  ]"
    local RAW_WARN="[ WARN ]"
    local RAW_OFF="[ OFF  ]"

    # _cap_badge: returns ONLY the ANSI color code pair (prefix + suffix).
    # The raw text is stored separately. This prevents double-printing.
    # Usage: CAP_X_COLOR=$(_cap_badge ok)
    _cap_badge() {
        case "$1" in
            ok)   printf "%s"  "${G}"  ;;
            warn) printf "%s"  "${Y}"  ;;
            off)  printf "%s"  "${R}"  ;;
        esac
    }

    # ------------------------------------------------------------------
    # 1. TCP Ramp-Up (requires root + tc/iproute2)
    # ------------------------------------------------------------------
    if [[ $EUID -eq 0 ]] && command -v tc >/dev/null 2>&1; then
        CAP_RAMP_COLOR="$(_cap_badge ok)"
        CAP_RAMP_RAW="$RAW_OK"
        CAP_RAMP_REASON="root + tc (iproute2) confirmed"
    elif command -v tc >/dev/null 2>&1; then
        CAP_RAMP_COLOR="$(_cap_badge warn)"
        CAP_RAMP_RAW="$RAW_WARN"
        CAP_RAMP_REASON="tc found but requires root privileges"
    else
        CAP_RAMP_COLOR="$(_cap_badge off)"
        CAP_RAMP_RAW="$RAW_OFF"
        CAP_RAMP_REASON="Install iproute2 and run as root"
    fi

    # ------------------------------------------------------------------
    # 2. Bidir Support (requires iperf3 >= 3.7)
    # ------------------------------------------------------------------
    if command -v iperf3 >/dev/null 2>&1; then
        local v_full v_major v_minor
        v_full=$(iperf3 -v 2>&1 | head -n1 | awk '{print $2}')
        v_major=$(echo "$v_full" | cut -d. -f1)
        v_minor=$(echo "$v_full" | cut -d. -f2)
        if [[ "$v_major" -gt 3 ]] || \
           [[ "$v_major" -eq 3 && "$v_minor" -ge 7 ]]; then
            CAP_BIDIR_COLOR="$(_cap_badge ok)"
            CAP_BIDIR_RAW="$RAW_OK"
            CAP_BIDIR_REASON="iperf3 v${v_full} supports --bidir"
        else
            CAP_BIDIR_COLOR="$(_cap_badge off)"
            CAP_BIDIR_RAW="$RAW_OFF"
            CAP_BIDIR_REASON="iperf3 v${v_full} detected, upgrade to v3.7+"
        fi
    else
        CAP_BIDIR_COLOR="$(_cap_badge off)"
        CAP_BIDIR_RAW="$RAW_OFF"
        CAP_BIDIR_REASON="iperf3 not found in PATH"
    fi

    # ------------------------------------------------------------------
    # 3. VRF Orchestration (requires root + kernel VRF)
    # ------------------------------------------------------------------
    if [[ $EUID -eq 0 ]]; then
        if ip vrf show >/dev/null 2>&1; then
            CAP_VRF_COLOR="$(_cap_badge ok)"
            CAP_VRF_RAW="$RAW_OK"
            CAP_VRF_REASON="root + kernel VRF support confirmed"
        else
            CAP_VRF_COLOR="$(_cap_badge warn)"
            CAP_VRF_RAW="$RAW_WARN"
            CAP_VRF_REASON="root ok, kernel VRF module not loaded"
        fi
    else
        CAP_VRF_COLOR="$(_cap_badge off)"
        CAP_VRF_RAW="$RAW_OFF"
        CAP_VRF_REASON="Requires root privileges"
    fi

    # ------------------------------------------------------------------
    # 4. DSCP / Packet Sniffing (requires root + tcpdump)
    # ------------------------------------------------------------------
    if [[ $EUID -eq 0 ]] && command -v tcpdump >/dev/null 2>&1; then
        CAP_SNIFF_COLOR="$(_cap_badge ok)"
        CAP_SNIFF_RAW="$RAW_OK"
        CAP_SNIFF_REASON="root + tcpdump confirmed"
    elif command -v tcpdump >/dev/null 2>&1; then
        CAP_SNIFF_COLOR="$(_cap_badge warn)"
        CAP_SNIFF_RAW="$RAW_WARN"
        CAP_SNIFF_REASON="tcpdump found but requires root privileges"
    else
        CAP_SNIFF_COLOR="$(_cap_badge off)"
        CAP_SNIFF_RAW="$RAW_OFF"
        CAP_SNIFF_REASON="Install tcpdump and run as root"
    fi

    # ------------------------------------------------------------------
    # 5. TCP CWND Tracking (standard iperf3 verbose)
    # ------------------------------------------------------------------
    if command -v iperf3 >/dev/null 2>&1; then
        CAP_CWND_COLOR="$(_cap_badge ok)"
        CAP_CWND_RAW="$RAW_OK"
        CAP_CWND_REASON="Standard iperf3 verbose log parsing"
    else
        CAP_CWND_COLOR="$(_cap_badge off)"
        CAP_CWND_RAW="$RAW_OFF"
        CAP_CWND_REASON="iperf3 not found in PATH"
    fi

    # ------------------------------------------------------------------
    # 6. Mixed Traffic Pattern — MTP (requires iperf3 + awk)
    # ------------------------------------------------------------------
    if command -v iperf3 >/dev/null 2>&1 && \
       command -v awk    >/dev/null 2>&1; then
        CAP_MTP_COLOR="$(_cap_badge ok)"
        CAP_MTP_RAW="$RAW_OK"
        CAP_MTP_REASON="iperf3 + awk confirmed"
    else
        CAP_MTP_COLOR="$(_cap_badge off)"
        CAP_MTP_RAW="$RAW_OFF"
        CAP_MTP_REASON="Requires iperf3 and awk in PATH"
    fi

    # ------------------------------------------------------------------
    # 7. DNS Resolution (FQDN support)
    # ------------------------------------------------------------------
    local _dns_tool=""
    if   command -v getent  >/dev/null 2>&1; then _dns_tool="getent"
    elif command -v dig     >/dev/null 2>&1; then _dns_tool="dig"
    elif command -v host    >/dev/null 2>&1; then _dns_tool="host"
    elif command -v nslookup>/dev/null 2>&1; then _dns_tool="nslookup"
    elif command -v python3 >/dev/null 2>&1; then _dns_tool="python3"
    elif command -v python2 >/dev/null 2>&1; then _dns_tool="python2"
    fi

    if [[ -n "$_dns_tool" ]]; then
        CAP_DNS_COLOR="$(_cap_badge ok)"
        CAP_DNS_RAW="$RAW_OK"
        CAP_DNS_REASON="FQDN resolution via ${_dns_tool}"
    else
        CAP_DNS_COLOR="$(_cap_badge warn)"
        CAP_DNS_RAW="$RAW_WARN"
        CAP_DNS_REASON="No resolver found — IPv4 only (no getent/dig/host)"
    fi
}


# ==============================================================================
# _print_capability_matrix (Fixed v3)
#
# COLUMN GEOMETRY (total box width = 80):
#
#   +--80 chars total----------------------------------------------------------+
#   |sp| C1=28 |sp|sp| C2=8 |sp|sp| C3=36 |sp|
#   +--------------------------------------------------------------------------+
#
#   Border breakdown per row:
#     "| " + 28 + " | " + 8 + " | " + 36 + " |"
#      2  +  28 +  3  +  8  +  3  +  36  +  2  = 82 ... adjusted below
#
#   Actual chosen widths that sum to exactly 80:
#     "| " + C1(24) + " | " + C2(8) + " | " + C3(38) + " |"
#      2   +   24   +  3   +    8   +  3   +    38   +  2  = 80 ✓
#
# KEY FIXES:
#   1. _cm_row prints the color code, then the raw badge text, then NC.
#      No double printing. No separate badge_color variable needed.
#   2. C3 widened to 38 so the longest reason strings fit without truncation.
#   3. Legend row rebuilt with exact character accounting to fill 80 chars.
#   4. All padding uses _visible_len() for ANSI-safe arithmetic.
# ==============================================================================
_print_capability_matrix() {

    _check_capabilities

    # ------------------------------------------------------------------
    # Box geometry — all arithmetic derives from these four constants.
    # Change W to resize the entire matrix cleanly.
    # ------------------------------------------------------------------
    local W=80          # Total box width  (including left + right border chars)
    local C1=24         # Feature name column  (visible chars)
    local C2=8          # Status badge column  (visible chars, matches badge width)
    local C3=38         # Requirement/Note column (visible chars)
    # Verify: 2 + C1 + 3 + C2 + 3 + C3 + 2 = 2+24+3+8+3+38+2 = 80 ✓

    local INNER=$(( W - 2 ))   # 78 — usable space between outer border pipes

    # ------------------------------------------------------------------
    # _cm_rule <left> <fill> <right>
    # Draws a full-width horizontal rule.
    # ------------------------------------------------------------------
    _cm_rule() {
        printf "%s%s%s\n" "$1" "$(rpt "$2" $((W - 2)))" "$3"
    }

    # ------------------------------------------------------------------
    # _cm_row <feature> <badge_color_code> <badge_raw_text> <reason>
    #
    # Prints one data row. Badge is rendered as:
    #   <color_code><raw_text><NC>
    # Padding is calculated from ${#badge_raw_text} only (no ANSI bytes).
    #
    # EXAMPLE CALL:
    #   _cm_row "TCP Ramp-Up (TBF)" "$CAP_RAMP_COLOR" "$CAP_RAMP_RAW" \
    #           "$CAP_RAMP_REASON"
    # ------------------------------------------------------------------
    _cm_row() {
        local feat="$1"
        local badge_color="$2"
        local badge_raw="$3"
        local reason="$4"

        # Truncate inputs to their column widths as a last-resort safety net.
        # Correct geometry means this should never activate.
        feat="${feat:0:$C1}"
        reason="${reason:0:$C3}"

        # Calculate right-padding for each column
        local feat_pad=$(( C1 - ${#feat} ))
        local badge_pad=$(( C2 - ${#badge_raw} ))
        local reason_pad=$(( C3 - ${#reason} ))

        # Guard against negative padding (should never happen with correct C*)
        [[ $feat_pad   -lt 0 ]] && feat_pad=0
        [[ $badge_pad  -lt 0 ]] && badge_pad=0
        [[ $reason_pad -lt 0 ]] && reason_pad=0

        # Print the row:
        #   "| " FEATURE_PADDED " | " COLOR+RAW_BADGE+NC+PAD " | " REASON_PADDED " |"
        printf "| %s%s | %s%s%s%s | %s%s |\n"        \
            "$feat"        "$(rpt ' ' $feat_pad)"     \
            "$badge_color" "$badge_raw" "${NC}"        \
            "$(rpt ' ' $badge_pad)"                    \
            "$reason"      "$(rpt ' ' $reason_pad)"
    }

    # ------------------------------------------------------------------
    # _cm_col_sep
    # Prints the column separator row between header and data rows.
    # ------------------------------------------------------------------
    _cm_col_sep() {
        printf "|%s|%s|%s|\n"                 \
            "$(rpt '-' $(( C1 + 2 )))"        \
            "$(rpt '-' $(( C2 + 2 )))"        \
            "$(rpt '-' $(( C3 + 2 )))"
    }

    # ------------------------------------------------------------------
    # Begin rendering
    # ------------------------------------------------------------------
    echo ""
    _cm_rule "+" "=" "+"

    # -- Title row (centered) --
    local title="PRISM  PRE-FLIGHT CAPABILITY MATRIX"
    local tlen=${#title}
    local tlpad=$(( (INNER - tlen) / 2 ))
    local trpad=$(( INNER - tlen - tlpad ))
    printf "|%s%b%s%b%s|\n"                   \
        "$(rpt ' ' $tlpad)"                    \
        "${BOLD_W}" "$title" "${NC}"           \
        "$(rpt ' ' $trpad)"

    # -- Context line (host / user / OS) --
    local ctx="host:$(hostname)  user:${USER}  os:$(uname -sr)"
    # Trim context if it exceeds inner width minus 2 spaces for padding
    local ctx_max=$(( INNER - 2 ))
    [[ ${#ctx} -gt $ctx_max ]] && ctx="${ctx:0:$ctx_max}"
    local ctx_pad=$(( ctx_max - ${#ctx} ))
    printf "| %b%s%b%s |\n"                   \
        "${DIM}" "$ctx" "${NC}"               \
        "$(rpt ' ' $ctx_pad)"

    _cm_rule "+" "-" "+"

    # -- Column header row --
    local h1="Feature"
    local h2="Status"
    local h3="Requirement / Note"
    printf "| %b%s%b%s | %b%s%b%s | %b%s%b%s |\n"  \
        "${BOLD}" "$h1" "${NC}" "$(rpt ' ' $(( C1 - ${#h1} )))"  \
        "${BOLD}" "$h2" "${NC}" "$(rpt ' ' $(( C2 - ${#h2} )))"  \
        "${BOLD}" "$h3" "${NC}" "$(rpt ' ' $(( C3 - ${#h3} )))"

    _cm_col_sep

    # -- Data rows --
    _cm_row "TCP Ramp-Up (TBF)"   \
            "$CAP_RAMP_COLOR"  "$CAP_RAMP_RAW"  "$CAP_RAMP_REASON"

    _cm_row "Bidir Streams"       \
            "$CAP_BIDIR_COLOR" "$CAP_BIDIR_RAW" "$CAP_BIDIR_REASON"

    _cm_row "VRF Orchestration"   \
            "$CAP_VRF_COLOR"   "$CAP_VRF_RAW"   "$CAP_VRF_REASON"

    _cm_row "DSCP Verification"   \
            "$CAP_SNIFF_COLOR" "$CAP_SNIFF_RAW" "$CAP_SNIFF_REASON"

    _cm_row "TCP CWND Tracking"   \
            "$CAP_CWND_COLOR"  "$CAP_CWND_RAW"  "$CAP_CWND_REASON"

    _cm_row "Mixed Traffic (MTP)" \
            "$CAP_MTP_COLOR"   "$CAP_MTP_RAW"   "$CAP_MTP_REASON"

    _cm_row "FQDN Resolution"     \
            "$CAP_DNS_COLOR"   "$CAP_DNS_RAW"   "$CAP_DNS_REASON"

    _cm_rule "+" "-" "+"

    # -- Legend row --
    # Layout inside the box (INNER=78 chars):
    #   " " + badge(8) + " " + label + "   " + badge(8) + " " + label + ...
    # We build the legend string, measure its visible length, then right-pad.
    local leg
    leg=" ${G}[  OK  ]${NC} Ready"
    leg="${leg}   ${Y}[ WARN ]${NC} Needs change"
    leg="${leg}   ${R}[ OFF  ]${NC} Not available"

    # Use _visible_len to get the printable length (strips ANSI codes)
    local leg_vlen
    leg_vlen=$(_visible_len "$leg")
    local leg_pad=$(( INNER - leg_vlen - 1 ))
    [[ $leg_pad -lt 0 ]] && leg_pad=0

    printf "|%b%s%b%s|\n" "" "$leg" "" "$(rpt ' ' $leg_pad)"

    _cm_rule "+" "=" "+"
    echo ""
}

# =============================================================================
# COLOUR THEME ENGINE
# =============================================================================
#
# Three themes are supported:
#   dark        — default, optimised for dark terminal backgrounds
#   light       — adjusted colours for light terminal backgrounds
#   mono        — monochrome / accessibility mode, no colour codes
#
# The active theme is stored in ~/.config/iperf3-streams/theme
# Auto-detection uses COLORFGBG (set by many terminals: "15;0" = dark,
# "0;15" = light). Falls back to "dark" when COLORFGBG is unset.
#
# All colour variables (RED, GREEN, etc.) are reassigned when the theme
# changes so every existing printf/bleft call inherits the new values
# without modification.

THEME_CURRENT=""                          # active theme name
THEME_PREFS_DIR="${HOME}/.config/prism"
THEME_PREFS_FILE="${THEME_PREFS_DIR}/theme"


# Live CWND fields (updated every dashboard tick from stream log)
# cwnd values are in KBytes as reported by iperf3 TCP verbose output.
# Format: [  5]  0.00-1.00  sec  128 KBytes  1.05 Mbits/sec  0  90.5 KBytes
#                                                              ^   ^^^^^^^^^
#                                                           retr    cwnd
declare -a S_CWND_CURRENT=()    # most recent cwnd value in KBytes (float string)
declare -a S_CWND_MIN=()        # minimum cwnd seen during stream
declare -a S_CWND_MAX=()        # maximum cwnd seen during stream
declare -a S_CWND_FINAL=()      # last cwnd value at stream end
declare -a S_CWND_SAMPLES=()    # number of cwnd samples collected
declare -a S_CWND_SUM=()        # running sum for average calculation

# Per-stream traffic ramp-up profile fields
# When S_RAMP_ENABLED[$i]=1 the stream starts at near-zero bandwidth,
# linearly ramps to S_BW[$i] over S_RAMP_UP[$i] seconds, holds at full
# rate for the test duration, then ramps down over S_RAMP_DOWN[$i] seconds.
#
# The ramp engine runs as a background process writing bandwidth commands
# to the iperf3 process via the tc token bucket shaper (TCP) or by
# relaunching iperf3 with escalating -b values (UDP).
#
# Timeline ring buffer stores normalised throughput levels (0-8) for
# ASCII sparkline rendering. One sample per dashboard tick (1 sec).
#   _RAMP_TIMELINE_<idx>   colon-separated ring of level values

declare -a S_RAMP_ENABLED=()   # 1 = ramp profile active for this stream
declare -a S_RAMP_UP=()        # ramp-up duration in seconds
declare -a S_RAMP_DOWN=()      # ramp-down duration in seconds
declare -a S_RAMP_STEPS=()     # number of steps in each ramp phase
declare -a S_RAMP_PHASE=()     # current phase: RAMPUP|HOLD|RAMPDOWN|DONE
declare -a S_RAMP_PHASE_TS=()  # epoch timestamp when current phase started
declare -a S_RAMP_BW_CURRENT=()  # current effective bandwidth string
declare -a S_RAMP_BW_TARGET=()   # final target bandwidth string
declare -a S_RAMP_IFACE=()     # egress interface for tc shaping (TCP)
declare -a S_RAMP_TC_ACTIVE=() # 1 = tc qdisc installed for this stream
declare -a S_RAMP_TIMELINE_SNAPSHOT=()  # frozen curve string captured at stream end

# When a stream is configured for bidirectional simultaneous testing, a second
# iperf3 process is launched with --reverse (-R) alongside the forward stream.
# Both processes run in parallel for the full test duration.
#
#   S_BIDIR[$i]        1 = bidirectional enabled, 0 = unidirectional
#   BIDIR_PIDS[$i]     PID of the reverse iperf3 process
#   BIDIR_LOGFILES[$i] log file path for the reverse process
#   S_BIDIR_BW[$i]     current live RX bandwidth string (from reverse log)
#   S_BIDIR_SPARK[$i]  sparkline variable name suffix for reverse direction
#
# Sparkline ring buffers for reverse direction follow the same naming as
# the forward direction but use role prefix "r" instead of "c":
#   _SPARK_r_<idx>

declare -a S_BIDIR=()
declare -a BIDIR_PIDS=()
declare -a BIDIR_LOGFILES=()
declare -a S_BIDIR_BW=()


# Parallel ping process tracking and live RTT state per client stream.
# One background ping process runs alongside each iperf3 client stream.
# RTT values are parsed from the ping log on every dashboard tick.

declare -a PING_PIDS=()          # background ping process PIDs (one per stream)
declare -a PING_LOGFILES=()      # ping output log files (one per stream)

# Live RTT fields (updated every dashboard tick from ping log)
declare -a S_RTT_MIN=()          # minimum RTT ms  (string, e.g. "1.234")
declare -a S_RTT_AVG=()          # average RTT ms
declare -a S_RTT_MAX=()          # maximum RTT ms
declare -a S_RTT_JITTER=()       # jitter ms (mdev/stddev from ping summary)
declare -a S_RTT_LOSS=()         # packet loss percentage string  e.g. "0%"
declare -a S_RTT_SAMPLES=()      # number of RTT samples collected so far

# =============================================================================
# SECTION 9 — SPARKLINE ENGINE
# =============================================================================
#
# Each stream (client) and each server listener maintains an independent
# bandwidth history ring buffer stored as a colon-separated string in an
# ordinary shell variable — fully Bash 3.2 compatible, no arrays required.
#
# Variable naming:
#   _SPARK_c_<idx>   client stream (0-based index)
#   _SPARK_s_<idx>   server listener (0-based index)
#
# Ring buffer depth  : _SPARK_DEPTH = 10  (10 seconds at 1 tick/sec)
# Rendered bar width : _SPARK_WIDTH = 10  (always exactly 10 printable chars)
#
# Block characters (U+2581–U+2588), stored as awk octal escapes so they
# render correctly on any platform regardless of locale:
#   ▁ \342\226\201   ▂ \342\226\202   ▃ \342\226\203   ▄ \342\226\204
#   ▅ \342\226\205   ▆ \342\226\206   ▇ \342\226\207   █ \342\226\210
#
# When fewer than _SPARK_WIDTH samples exist, the bar is left-padded with
# '·' dots so the rendered field is always exactly _SPARK_WIDTH chars wide.
#
# API:
#   _spark_push   <role> <idx> <bw_string>   append one live BW sample
#   _spark_clear  <role> <idx>               reset buffer to empty
#   _spark_render <role> <idx>               print the sparkline bar string
# =============================================================================

readonly _SPARK_DEPTH=10    # seconds of history retained per buffer
readonly _SPARK_WIDTH=10    # printable characters rendered per bar

# ---------------------------------------------------------------------------
# _spark_bw_to_bps  <bw_string>
#
# Converts a human-readable bandwidth string (e.g. "94.40 Mbps") to an
# integer bps value for numeric storage in the ring buffer.
# Returns "0" on any parse failure.
# ---------------------------------------------------------------------------
_spark_bw_to_bps() {
    local raw="$1"
    [[ -z "$raw" || "$raw" == "---" || "$raw" == "N/A" ]] && { printf '0'; return; }
    printf '%s' "$raw" | awk '
    {
        val  = $1 + 0
        unit = $2
        if      (unit ~ /[Gg]bps/) bps = val * 1e9
        else if (unit ~ /[Mm]bps/) bps = val * 1e6
        else if (unit ~ /[Kk]bps/) bps = val * 1e3
        else                       bps = val
        printf "%d", bps
    }'
}

# ---------------------------------------------------------------------------
# _ramp_bw_to_bps  <bw_string>
#
# Converts a bandwidth string with unit suffix to integer bps.
# Accepts: 100M  500K  1G  10  (bare integer = bps)
# Returns integer bps string or "0" on failure.
# ---------------------------------------------------------------------------
_ramp_bw_to_bps() {
    local raw="$1"
    [[ -z "$raw" || "$raw" == "0" || "$raw" == "---" ]] && { printf '0'; return; }
    printf '%s' "$raw" | awk '
    {
        # Strip trailing unit suffix from the value
        val = $1 + 0
        unit = toupper($1)
        gsub(/[0-9.]/,"",unit)       # isolate the suffix letters
        if      (unit ~ /G/) bps = val * 1e9
        else if (unit ~ /M/) bps = val * 1e6
        else if (unit ~ /K/) bps = val * 1e3
        else                 bps = val
        printf "%d", bps
    }'
}

# ---------------------------------------------------------------------------
# _ramp_bps_to_bw  <bps_integer>
#
# Converts an integer bps value to a human-readable bandwidth string
# suitable for passing to iperf3 -b or tc tbf rate.
# Returns e.g. "94M", "512K", "1G"
# ---------------------------------------------------------------------------
_ramp_bps_to_bw() {
    local bps="$1"
    [[ -z "$bps" || "$bps" == "0" ]] && { printf '1K'; return; }
    awk -v b="$bps" 'BEGIN {
        if      (b >= 1e9) printf "%.0fG", b/1e9
        else if (b >= 1e6) printf "%.0fM", b/1e6
        else if (b >= 1e3) printf "%.0fK", b/1e3
        else               printf "%.0f",  b
    }'
}

# ---------------------------------------------------------------------------
# _ramp_timeline_push  <idx>  <bw_current_string>  <bw_target_bps>
#
# Appends one normalised level (0-8) to the ramp timeline ring buffer.
# The level is computed relative to the target bandwidth so the curve
# accurately reflects the ramp shape.
# Ring depth: _RAMP_TIMELINE_DEPTH samples (matches test duration window).
# ---------------------------------------------------------------------------
readonly _RAMP_TIMELINE_DEPTH=60   # retain up to 60 seconds of history

_ramp_timeline_push() {
    local idx="$1"
    local bw_cur_str="$2"
    local bw_target_bps="$3"

    local varname="_RAMP_TIMELINE_${idx}"

    # Convert current BW to bps
    local cur_bps
    cur_bps=$(_ramp_bw_to_bps "$bw_cur_str")

    # Normalise to level 0-8
    local level=0
    if [[ -n "$bw_target_bps" ]] && (( bw_target_bps > 0 )) && \
       [[ -n "$cur_bps" ]] && (( cur_bps > 0 )); then
        level=$(awk -v c="$cur_bps" -v t="$bw_target_bps" '
            BEGIN {
                ratio = c / t
                if (ratio > 1) ratio = 1
                lvl = int(ratio * 8 + 0.5)
                if (lvl < 0) lvl = 0
                if (lvl > 8) lvl = 8
                print lvl
            }')
    fi

    local existing=""
    eval "existing=\"\${${varname}:-}\""

    local updated
    if [[ -z "$existing" ]]; then
        updated="$level"
    else
        updated="${existing}:${level}"
    fi

    # Trim to depth
    local trimmed
    trimmed=$(printf '%s' "$updated" | awk -v d="$_RAMP_TIMELINE_DEPTH" '
        BEGIN { FS=":"; OFS=":" }
        {
            n = split($0, a, ":")
            start = (n > d) ? n - d + 1 : 1
            out = ""
            for (i=start; i<=n; i++) out = (out=="") ? a[i] : out ":" a[i]
            print out
        }')

    eval "${varname}=\"\${trimmed}\""
}

# ---------------------------------------------------------------------------
# _ramp_timeline_render  <idx>  <width>
#
# Renders the ramp timeline as a fixed-width ASCII curve.
#
# Characters used (ascending intensity):
#   0 = · (no traffic)
#   1 = ▁   2 = ▂   3 = ▃   4 = ▄
#   5 = ▅   6 = ▆   7 = ▇   8 = █
#
# Left-pads with '·' when fewer than <width> samples exist so the field
# is always exactly <width> printable characters wide.
# ---------------------------------------------------------------------------
_ramp_timeline_render() {
    local idx="$1"
    local width="${2:-30}"
    local varname="_RAMP_TIMELINE_${idx}"
    local buf=""
    eval "buf=\"\${${varname}:-}\""

    if [[ -z "$buf" ]]; then
        local d="" k
        for (( k=0; k<width; k++ )); do d+='·'; done
        printf '%s' "$d"
        return
    fi

    printf '%s' "$buf" | awk \
        -v width="$width" \
        'BEGIN {
            FS = ":"
            ch[0] = "\302\267"        # · U+00B7 middle dot
            ch[1] = "\342\226\201"    # ▁ U+2581
            ch[2] = "\342\226\202"    # ▂ U+2582
            ch[3] = "\342\226\203"    # ▃ U+2583
            ch[4] = "\342\226\204"    # ▄ U+2584
            ch[5] = "\342\226\205"    # ▅ U+2585
            ch[6] = "\342\226\206"    # ▆ U+2586
            ch[7] = "\342\226\207"    # ▇ U+2587
            ch[8] = "\342\226\210"    # █ U+2588
        }
        {
            n = split($0, a, ":")
            # Take only the last <width> samples
            start = (n > width) ? n - width + 1 : 1
            out = ""
            for (i = start; i <= n; i++) {
                lvl = int(a[i] + 0)
                if (lvl < 0) lvl = 0
                if (lvl > 8) lvl = 8
                out = out ch[lvl]
            }
            # Left-pad with dots
            dots_needed = width - (n - start + 1)
            dots = ""
            for (i = 1; i <= dots_needed; i++) dots = dots ch[0]
            printf "%s%s", dots, out
        }'
}

# ---------------------------------------------------------------------------
# _ramp_timeline_clear  <idx>
# Resets the timeline ring buffer to empty.
# ---------------------------------------------------------------------------
_ramp_timeline_clear() {
    local idx="$1"
    local varname="_RAMP_TIMELINE_${idx}"
    eval "${varname}=\"\""
}

# ---------------------------------------------------------------------------
# _ramp_apply_tc  <idx>  <rate_bps>
#
# Installs or updates a tc tbf (Token Bucket Filter) qdisc on the egress
# interface for stream <idx> to shape TCP traffic to <rate_bps> bps.
#
# Uses S_RAMP_IFACE[$idx] which is resolved once during ramp setup.
# Called from _ramp_tick on every ramp step for TCP streams.
#
# Burst and latency parameters:
#   burst  = rate * 10ms  (minimum 4096 bytes per tc requirement)
#   latency = 50ms        (maximum queuing delay tolerated)
# ---------------------------------------------------------------------------
_ramp_apply_tc() {
    local idx="$1"
    local rate_bps="$2"
    local iface="${S_RAMP_IFACE[$idx]:-}"

    [[ -z "$iface" || "$iface" == "lo" || "$iface" == "lo0" ]] && return 0
    [[ "$OS_TYPE" == "macos" ]] && return 0
    (( IS_ROOT == 0 )) && return 0

    # Minimum rate guard — tc requires at least 1 bit/s
    (( rate_bps < 1000 )) && rate_bps=1000

    # Calculate burst: rate * 10ms, minimum 4096 bytes
    local burst_bytes
    burst_bytes=$(awk -v r="$rate_bps" 'BEGIN { b=int(r*0.01/8); print (b<4096)?4096:b }')

    # Remove existing qdisc (suppress error if none exists)
    tc qdisc del dev "$iface" root 2>/dev/null || true

    # Install tbf
    tc qdisc add dev "$iface" root tbf \
        rate "${rate_bps}bit" \
        burst "${burst_bytes}" \
        latency 50ms 2>/dev/null

    S_RAMP_TC_ACTIVE[$idx]=1
}

# ---------------------------------------------------------------------------
# _ramp_remove_tc  <idx>
#
# Removes the tc tbf qdisc installed by _ramp_apply_tc.
# Called when the ramp completes (DONE phase) or stream cleanup runs.
# ---------------------------------------------------------------------------
_ramp_remove_tc() {
    local idx="$1"
    local iface="${S_RAMP_IFACE[$idx]:-}"

    [[ -z "$iface" || "${S_RAMP_TC_ACTIVE[$idx]:-0}" != "1" ]] && return 0
    [[ "$OS_TYPE" == "macos" ]] && return 0

    tc qdisc del dev "$iface" root 2>/dev/null || true
    S_RAMP_TC_ACTIVE[$idx]=0
}

# ---------------------------------------------------------------------------
# _ramp_setup  <idx>
#
# Initialises the ramp engine for stream <idx>.
# Resolves the egress interface, installs initial tc shaping at near-zero
# rate, and sets phase to RAMPUP.
#
# Called from launch_clients after the iperf3 process is launched so the
# PID and logfile are known.
# ---------------------------------------------------------------------------
_ramp_setup() {
    local idx="$1"

    [[ "${S_RAMP_ENABLED[$idx]:-0}" != "1" ]] && return 0

    local target_bw="${S_BW[$idx]:-}"
    local proto="${S_PROTO[$idx]:-TCP}"

    # For UDP: target BW is required; for TCP we use tc shaping
    # TCP streams with no BW limit: use a sensible default for shaping
    if [[ "$proto" == "TCP" && -z "$target_bw" ]]; then
        # Default to 100M for shapeable TCP when no limit configured
        target_bw="100M"
    fi

    S_RAMP_BW_TARGET[$idx]="$target_bw"

    # Resolve egress interface for tc shaping (TCP only)
    if [[ "$proto" == "TCP" && "$OS_TYPE" == "linux" && IS_ROOT -eq 1 ]]; then
        local oif=""
        local stream_vrf="${S_VRF[$idx]:-}"
        local stream_target="${S_TARGET[$idx]:-}"

        if [[ -n "$stream_vrf" ]]; then
            oif=$(ip route get vrf "${stream_vrf}" "${stream_target}" \
                2>/dev/null | grep -oE '\bdev [^ ]+' | awk '{print $2}' | head -1)
            [[ -z "$oif" ]] && \
                oif=$(ip vrf exec "${stream_vrf}" ip route get \
                    "${stream_target}" 2>/dev/null \
                    | grep -oE '\bdev [^ ]+' | awk '{print $2}' | head -1)
        else
            oif=$(ip route get "${stream_target}" 2>/dev/null \
                | grep -oE '\bdev [^ ]+' | awk '{print $2}' | head -1)
        fi

        # Reject loopback — cannot shape loopback
        if [[ -n "$oif" && "$oif" != "lo" && ! "$oif" =~ ^lo[0-9] ]]; then
            S_RAMP_IFACE[$idx]="$oif"
        else
            S_RAMP_IFACE[$idx]=""
        fi
    else
        S_RAMP_IFACE[$idx]=""
    fi

    # Set initial phase
    S_RAMP_PHASE[$idx]="RAMPUP"
    S_RAMP_PHASE_TS[$idx]=$(date +%s)
    S_RAMP_TC_ACTIVE[$idx]=0

    # Apply initial near-zero rate for TCP streams
    if [[ "$proto" == "TCP" && -n "${S_RAMP_IFACE[$idx]}" ]]; then
        local min_bps=8000    # 8 Kbps floor — enough for TCP handshake
        _ramp_apply_tc "$idx" "$min_bps"
        S_RAMP_BW_CURRENT[$idx]=$(_ramp_bps_to_bw "$min_bps")
    else
        S_RAMP_BW_CURRENT[$idx]="0"
    fi

    # Push initial zero sample to timeline
    local target_bps
    target_bps=$(_ramp_bw_to_bps "$target_bw")
    _ramp_timeline_push "$idx" "0" "$target_bps"
}

# ---------------------------------------------------------------------------
# _ramp_tick  <idx>
#
# Called once per dashboard tick for every stream that has ramp enabled.
# Computes the current target rate based on elapsed time and phase, then
# applies it via tc (TCP) or updates S_RAMP_BW_CURRENT (UDP display).
#
# Phase transitions:
#   RAMPUP    → linearly increase from 0 to target over S_RAMP_UP seconds
#   HOLD      → maintain target rate for the test duration
#   RAMPDOWN  → linearly decrease from target to 0 over S_RAMP_DOWN seconds
#   DONE      → remove tc shaping, mark complete
# ---------------------------------------------------------------------------
_ramp_tick() {
    local idx="$1"

    [[ "${S_RAMP_ENABLED[$idx]:-0}" != "1" ]] && return 0
    [[ "${S_RAMP_PHASE[$idx]:-DONE}" == "DONE" ]] && return 0

    local now
    now=$(date +%s)

    local phase="${S_RAMP_PHASE[$idx]}"
    local phase_ts="${S_RAMP_PHASE_TS[$idx]:-$now}"
    local elapsed=$(( now - phase_ts ))

    local target_bw="${S_RAMP_BW_TARGET[$idx]:-100M}"
    local target_bps
    target_bps=$(_ramp_bw_to_bps "$target_bw")

    local ramp_up="${S_RAMP_UP[$idx]:-10}"
    local ramp_down="${S_RAMP_DOWN[$idx]:-5}"
    local proto="${S_PROTO[$idx]:-TCP}"

    local effective_bps=$target_bps
    local new_phase="$phase"

    case "$phase" in

        RAMPUP)
            if (( elapsed >= ramp_up )); then
                # Ramp-up complete — transition to HOLD
                effective_bps=$target_bps
                new_phase="HOLD"
                S_RAMP_PHASE_TS[$idx]=$now
            else
                # Linear interpolation: min 1% to avoid zero
                effective_bps=$(awk \
                    -v t="$target_bps" \
                    -v e="$elapsed" \
                    -v r="$ramp_up" \
                    'BEGIN {
                        ratio = e / r
                        if (ratio < 0.01) ratio = 0.01
                        bps = int(t * ratio)
                        if (bps < 8000) bps = 8000
                        print bps
                    }')
            fi
            ;;

        HOLD)
            effective_bps=$target_bps
            # Check if the stream duration has elapsed to trigger ramp-down
            local stream_dur="${S_DURATION[$idx]:-0}"
            local stream_start="${S_START_TS[$idx]:-$now}"
            local total_elapsed=$(( now - stream_start ))

            # Ramp-down starts when (total - ramp_down) seconds have elapsed
            if (( stream_dur > 0 )) && \
               (( total_elapsed >= stream_dur - ramp_down )) && \
               (( ramp_down > 0 )); then
                new_phase="RAMPDOWN"
                S_RAMP_PHASE_TS[$idx]=$now
            fi
            ;;

        RAMPDOWN)
            if (( elapsed >= ramp_down )); then
                # Ramp-down complete
                effective_bps=8000    # floor — keep TCP alive for clean exit
                new_phase="DONE"
            else
                # Linear decrease from target to floor
                effective_bps=$(awk \
                    -v t="$target_bps" \
                    -v e="$elapsed" \
                    -v r="$ramp_down" \
                    'BEGIN {
                        ratio = 1.0 - (e / r)
                        if (ratio < 0.01) ratio = 0.01
                        bps = int(t * ratio)
                        if (bps < 8000) bps = 8000
                        print bps
                    }')
            fi
            ;;

        DONE)
            _ramp_remove_tc "$idx"
            return 0
            ;;
    esac

    # Apply rate
    if [[ "$proto" == "TCP" && -n "${S_RAMP_IFACE[$idx]}" ]]; then
        _ramp_apply_tc "$idx" "$effective_bps"
    fi

    # Update state
    S_RAMP_PHASE[$idx]="$new_phase"
    S_RAMP_BW_CURRENT[$idx]=$(_ramp_bps_to_bw "$effective_bps")

    # Remove tc when DONE
    if [[ "$new_phase" == "DONE" ]]; then
        _ramp_remove_tc "$idx"
    fi

    # Push to timeline
    _ramp_timeline_push "$idx" "${S_RAMP_BW_CURRENT[$idx]}" "$target_bps"
}

# ---------------------------------------------------------------------------
# _spark_push  <role> <idx> <bw_string>
#
# Appends one bandwidth sample to the ring buffer for role ("c"=client,
# "s"=server) and 0-based index.  Enforces _SPARK_DEPTH by trimming oldest.
# ---------------------------------------------------------------------------
_spark_push() {
    local role="$1" idx="$2" bw_str="$3"
    local varname="_SPARK_${role}_${idx}"

    local bps; bps=$(_spark_bw_to_bps "$bw_str")

    local existing=""
    eval "existing=\"\${${varname}:-}\""

    local updated
    if [[ -z "$existing" ]]; then
        updated="$bps"
    else
        updated="${existing}:${bps}"
    fi

    # Trim to _SPARK_DEPTH entries
    local trimmed
    trimmed=$(printf '%s' "$updated" | awk -v depth="$_SPARK_DEPTH" '
        BEGIN { FS = ":"; OFS = ":" }
        {
            n = split($0, a, ":")
            start = (n > depth) ? n - depth + 1 : 1
            out = ""
            for (i = start; i <= n; i++) {
                out = (out == "") ? a[i] : out ":" a[i]
            }
            print out
        }')

    eval "${varname}=\"\${trimmed}\""
}

# ---------------------------------------------------------------------------
# _spark_clear  <role>  <idx>
#
# Resets the ring buffer to empty.
# Called when a server listener transitions to RUNNING (new client connect).
# ---------------------------------------------------------------------------
_spark_clear() {
    local role="$1" idx="$2"
    local varname="_SPARK_${role}_${idx}"
    eval "${varname}=\"\""
}

# ---------------------------------------------------------------------------
# _spark_render  <role>  <idx>
#
# Renders exactly _SPARK_WIDTH printable characters as a FILLED AREA
# (mountain) sparkline graph.
#
# Algorithm:
#   1. Find min and max of all samples in the current window.
#   2. Normalise each sample to [0.0, 1.0] relative to the window range.
#      This is the key difference from a simple bar graph — even small
#      fluctuations within a narrow absolute range are fully amplified to
#      use the entire 8-level display height, making trends always visible.
#   3. Map normalised value to one of 8 filled block levels (U+2581–U+2588).
#   4. Left-pad with '·' when fewer than _SPARK_WIDTH samples exist.
#
# Dynamic range normalisation rules:
#   range == 0, max > 0   → flat mid-height (▄, level 4) — stable traffic
#   range == 0, max == 0  → flat floor (▁, level 1)      — no traffic
#   range > 0             → normalise to [1, 8] linearly
#
# The filled area gives:
#   - Immediate spike/drop visibility (tall vs short filled column)
#   - Trend shape readable at a glance (rising/falling/stable regions)
#   - Zero traffic clearly distinguishable from low traffic
#   - High traffic clearly distinguishable from medium traffic
#   - Works correctly for both Kbps and Gbps ranges without configuration
# ---------------------------------------------------------------------------

_spark_render() {
    local role="$1" idx="$2"
    local varname="_SPARK_${role}_${idx}"
    local buf=""
    eval "buf=\"\${${varname}:-}\""

    # Empty buffer — return dot padding without invoking awk
    if [[ -z "$buf" ]]; then
        local d="" k
        for (( k=0; k<_SPARK_WIDTH; k++ )); do d+='·'; done
        printf '%s' "$d"
        return
    fi

    printf '%s' "$buf" | awk \
        -v width="$_SPARK_WIDTH" \
        'BEGIN {
            FS = ":"

            # Filled block characters U+2581–U+2588 as octal escapes.
            # Each character fills the cell from the bottom to the given
            # fraction of the full cell height, creating a solid area.
            #
            #   blocks[1] = ▁  U+2581  one eighth    (floor / near-zero)
            #   blocks[2] = ▂  U+2582  one quarter
            #   blocks[3] = ▃  U+2583  three eighths
            #   blocks[4] = ▄  U+2584  half
            #   blocks[5] = ▅  U+2585  five eighths
            #   blocks[6] = ▆  U+2586  three quarters
            #   blocks[7] = ▇  U+2587  seven eighths
            #   blocks[8] = █  U+2588  full block    (maximum)
            #
            blocks[1] = "\342\226\201"
            blocks[2] = "\342\226\202"
            blocks[3] = "\342\226\203"
            blocks[4] = "\342\226\204"
            blocks[5] = "\342\226\205"
            blocks[6] = "\342\226\206"
            blocks[7] = "\342\226\207"
            blocks[8] = "\342\226\210"
        }
        {
            n = split($0, vals, ":")

            # ── Step 1: find min and max of the current window ────────────
            min_v = vals[1] + 0
            max_v = vals[1] + 0
            for (i = 2; i <= n; i++) {
                v = vals[i] + 0
                if (v < min_v) min_v = v
                if (v > max_v) max_v = v
            }
            range = max_v - min_v

            # ── Step 2: build filled area string ──────────────────────────
            area = ""
            for (i = 1; i <= n; i++) {
                v = vals[i] + 0

                if (range == 0) {
                    # Flat signal within this window:
                    #   non-zero → mid height (▄) shows stable active traffic
                    #   zero     → floor (▁) shows connection idle / no data
                    lvl = (max_v > 0) ? 4 : 1
                } else {
                    # Dynamic range normalisation:
                    # Map [min_v, max_v] linearly onto levels [1, 8].
                    # This ensures the full height of the sparkline field is
                    # always used, making even small fluctuations visible.
                    #
                    # Formula: lvl = round( (v - min_v) / range * 7 ) + 1
                    # Result:  min_v → 1 (▁),  max_v → 8 (█)
                    lvl = int((v - min_v) / range * 7 + 0.5) + 1
                    if (lvl < 1) lvl = 1
                    if (lvl > 8) lvl = 8
                }

                area = area blocks[lvl]
            }

            # ── Step 3: left-pad with dots to reach target width ──────────
            dots_needed = width - n
            dots = ""
            for (i = 1; i <= dots_needed; i++) dots = dots "·"

            printf "%s%s", dots, area
        }'
}


# ---------------------------------------------------------------------------
# _extract_bw_from_line  <line>
#
# Extracts the bandwidth value and unit from a single iperf3 interval line.
# Handles all known iperf3 output formats:
#
#   Standard:   [  5]  0.00-1.00  sec  112 MBytes   940 Mbits/sec
#   TCP bidir:  [  5][TX-C]  0.00-1.00  sec  131 KBytes  1.07 Mbits/sec  0  90.5 KBytes
#   UDP:        [  5]  0.00-1.00  sec  128 KBytes  1.05 Mbits/sec  0.022 ms  0/128
#
# Strategy: scan all fields for a unit token ending in "bits/sec".
# The field immediately before it is the numeric value.
# This is position-independent and handles any number of extra fields.
#
# Returns normalised bandwidth string e.g. "1.07 Mbps" or "" on failure.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# _extract_bw_from_line  <line>
#
# Extracts the bandwidth value and unit from a single iperf3 interval line.
# Handles all iperf3 output formats including TCP bidir with extra fields:
#
#   [  5][TX-C]  0.00-1.00  sec  128 KBytes  1.05 Mbits/sec    5   2.63 KBytes
#   [  7][RX-C]  0.00-1.00  sec  128 KBytes  1.05 Mbits/sec
#   [SUM]  0.00-1.00  sec  1.12 GBytes   963 Mbits/sec
#   [  5]  0.00-1.00  sec  112 MBytes   940 Mbits/sec
#
# Strategy: scan all fields for a token ending in "bits/sec".
# The field immediately before it is the numeric bandwidth value.
#
# Portability: uses only basic awk string matching (~), no ERE grouping,
# compatible with BSD awk (macOS), gawk, mawk, and nawk.
# ---------------------------------------------------------------------------
_extract_bw_from_line() {
    local line="$1"
    [[ -z "$line" ]] && { printf '%s' ''; return; }

    local result
    result=$(printf '%s\n' "$line" | awk '
    {
        for (i = 1; i <= NF; i++) {
            # Match unit tokens ending in bits/sec:
            #   bits/sec  Kbits/sec  Mbits/sec  Gbits/sec  (and lowercase)
            # Use two separate checks to avoid ERE grouping — portable on
            # BSD awk (macOS), gawk, mawk, nawk.
            if ($i == "bits/sec"  || \
                $i == "Kbits/sec" || $i == "kbits/sec" || \
                $i == "Mbits/sec" || $i == "mbits/sec" || \
                $i == "Gbits/sec" || $i == "gbits/sec" || \
                $i == "bits/s"    || \
                $i == "Kbits/s"   || $i == "kbits/s"   || \
                $i == "Mbits/s"   || $i == "mbits/s"   || \
                $i == "Gbits/s"   || $i == "gbits/s") {
                if (i > 1 && $(i-1) ~ /^[0-9][0-9]*(\.[0-9][0-9]*)?$/) {
                    print $(i-1) " " $i
                    exit
                }
            }
        }
    }')

    if [[ -n "$result" ]]; then
        _normalise_text_bw "$result"
    else
        printf '%s' ''
    fi
}

# =============================================================================
# SECTION 1 — PRIMITIVES
# =============================================================================

vlen() {
    local text="$1"
    local total=${#text}
    local plain="$text"
    local ansi_bytes=0
    local temp count

    # For each colour variable: only strip and count if the variable is
    # non-empty. When a theme sets colour variables to "" (e.g. mono theme),
    # skipping the substitution avoids two separate bugs:
    #   1. ${plain//$EMPTY_VAR/} with an empty pattern removes every
    #      character in Bash, producing a completely wrong length.
    #   2. Division by _LEN_* = 0 causes a division-by-zero arithmetic error.

    if [[ -n "$RED" ]]; then
        temp="${plain//$RED/}"
        count=$(( (${#plain} - ${#temp}) / _LEN_RED ))
        ansi_bytes=$(( ansi_bytes + count * _LEN_RED ))
        plain="$temp"
    fi

    if [[ -n "$GREEN" ]]; then
        temp="${plain//$GREEN/}"
        count=$(( (${#plain} - ${#temp}) / _LEN_GREEN ))
        ansi_bytes=$(( ansi_bytes + count * _LEN_GREEN ))
        plain="$temp"
    fi

    if [[ -n "$YELLOW" ]]; then
        temp="${plain//$YELLOW/}"
        count=$(( (${#plain} - ${#temp}) / _LEN_YELLOW ))
        ansi_bytes=$(( ansi_bytes + count * _LEN_YELLOW ))
        plain="$temp"
    fi

    if [[ -n "$BLUE" ]]; then
        temp="${plain//$BLUE/}"
        count=$(( (${#plain} - ${#temp}) / _LEN_BLUE ))
        ansi_bytes=$(( ansi_bytes + count * _LEN_BLUE ))
        plain="$temp"
    fi

    if [[ -n "$CYAN" ]]; then
        temp="${plain//$CYAN/}"
        count=$(( (${#plain} - ${#temp}) / _LEN_CYAN ))
        ansi_bytes=$(( ansi_bytes + count * _LEN_CYAN ))
        plain="$temp"
    fi

    if [[ -n "$BOLD" ]]; then
        temp="${plain//$BOLD/}"
        count=$(( (${#plain} - ${#temp}) / _LEN_BOLD ))
        ansi_bytes=$(( ansi_bytes + count * _LEN_BOLD ))
        plain="$temp"
    fi

    if [[ -n "$NC" ]]; then
        temp="${plain//$NC/}"
        count=$(( (${#plain} - ${#temp}) / _LEN_NC ))
        ansi_bytes=$(( ansi_bytes + count * _LEN_NC ))
        plain="$temp"
    fi

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

# ==============================================================================
# _resolve_fqdn  <hostname>
#
# Resolves a Fully Qualified Domain Name (FQDN) or short hostname to its
# first IPv4 address using the best available resolver on the system.
#
# Resolution chain (tried in order until one succeeds):
#   1. getent hosts       — glibc resolver, respects /etc/hosts + DNS
#                           Available: Linux (glibc), not macOS
#   2. dig +short A       — BIND dig utility, returns first A record
#                           Available: Linux (bind-utils), macOS with bind
#   3. host -t A          — host utility, part of bind-utils
#                           Available: Linux, macOS
#   4. nslookup           — legacy resolver, available almost everywhere
#                           Available: Linux, macOS, minimal containers
#   5. python3 socket     — Python fallback, uses system resolver
#                           Available: wherever Python 3 is installed
#   6. python2 socket     — Python 2 fallback
#                           Available: older systems
#
# Returns:
#   Prints the first resolved IPv4 address string (e.g. "93.184.216.34")
#   Returns exit code 0 on success, 1 on failure.
#
# Does NOT print to stdout on failure — callers check exit code and
# handle the error message themselves.
# ==============================================================================
_resolve_fqdn() {
    local hostname="$1"
    local resolved=""

    # ------------------------------------------------------------------
    # Method 1: getent hosts (Linux glibc — most reliable on Linux)
    # getent respects /etc/hosts, /etc/nsswitch.conf, and DNS.
    # Output format: "IP    hostname aliases..."
    # We take the first field of the first matching line.
    # ------------------------------------------------------------------
    if command -v getent >/dev/null 2>&1; then
        resolved=$(getent hosts "$hostname" 2>/dev/null \
            | awk 'NR==1 {print $1}' \
            | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' \
            | head -1)
        if [[ -n "$resolved" ]]; then
            printf '%s' "$resolved"
            return 0
        fi
    fi

    # ------------------------------------------------------------------
    # Method 2: dig +short A (most precise — only returns A records)
    # +short suppresses all decorative output.
    # We filter to ensure we only accept dotted-quad IPv4.
    # ------------------------------------------------------------------
    if command -v dig >/dev/null 2>&1; then
        resolved=$(dig +short A "$hostname" 2>/dev/null \
            | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' \
            | head -1)
        if [[ -n "$resolved" ]]; then
            printf '%s' "$resolved"
            return 0
        fi
    fi

    # ------------------------------------------------------------------
    # Method 3: host -t A (available on most Linux distros and macOS)
    # Output format: "hostname has address IP"
    # ------------------------------------------------------------------
    if command -v host >/dev/null 2>&1; then
        resolved=$(host -t A "$hostname" 2>/dev/null \
            | grep -E 'has address' \
            | awk '{print $NF}' \
            | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' \
            | head -1)
        if [[ -n "$resolved" ]]; then
            printf '%s' "$resolved"
            return 0
        fi
    fi

    # ------------------------------------------------------------------
    # Method 4: nslookup (legacy but universally available)
    # Output format varies — we grep for "Address:" lines after the
    # server section (skip the first Address: which is the DNS server).
    # ------------------------------------------------------------------
    if command -v nslookup >/dev/null 2>&1; then
        resolved=$(nslookup "$hostname" 2>/dev/null \
            | awk '/^Name:/{found=1} found && /^Address:/{print $2; exit}' \
            | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' \
            | head -1)
        if [[ -n "$resolved" ]]; then
            printf '%s' "$resolved"
            return 0
        fi
    fi

    # ------------------------------------------------------------------
    # Method 5: python3 socket.gethostbyname (portable Python fallback)
    # Uses the system's native resolver stack.
    # ------------------------------------------------------------------
    if command -v python3 >/dev/null 2>&1; then
        resolved=$(python3 -c \
            "import socket; print(socket.gethostbyname('${hostname//\'/}'))" \
            2>/dev/null \
            | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$')
        if [[ -n "$resolved" ]]; then
            printf '%s' "$resolved"
            return 0
        fi
    fi

    # ------------------------------------------------------------------
    # Method 6: python2 socket.gethostbyname (older system fallback)
    # ------------------------------------------------------------------
    if command -v python2 >/dev/null 2>&1; then
        resolved=$(python2 -c \
            "import socket; print socket.gethostbyname('${hostname//\'/}')" \
            2>/dev/null \
            | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$')
        if [[ -n "$resolved" ]]; then
            printf '%s' "$resolved"
            return 0
        fi
    fi

    # All methods failed
    return 1
}

# ==============================================================================
# _validate_and_resolve_target  <input>  <out_ip_var>  <out_display_var>
#
# Validates and resolves a target address entered by the operator.
# Accepts both IPv4 addresses and FQDNs/hostnames.
#
# Parameters:
#   $1  input           — raw operator input (IPv4 or FQDN)
#   $2  out_ip_var      — name of variable to store the resolved IPv4
#   $3  out_display_var — name of variable to store the display string
#                         Format: "FQDN (IP)" for FQDNs, "IP" for plain IPv4
#
# Return codes:
#   0  — valid and resolved, out_ip_var and out_display_var populated
#   1  — invalid format or DNS resolution failed
#   2  — resolved but address is reserved/non-routable (loopback etc.)
#
# Side effects:
#   Prints informational messages to stdout during resolution.
#   Does NOT prompt — caller handles all prompting.
#
# FQDN validation rules:
#   - 1–253 characters total
#   - Labels separated by dots
#   - Each label: 1–63 chars, alphanumeric + hyphens, no leading/trailing hyphen
#   - Must contain at least one dot (to distinguish from single-word hostnames)
#     OR be a resolvable single-label name
#   - Pure IPv4 inputs bypass DNS lookup entirely
# ==============================================================================
_validate_and_resolve_target() {
    local input="$1"
    local out_ip_var="$2"
    local out_display_var="$3"

    # ------------------------------------------------------------------
    # Strip leading/trailing whitespace
    # ------------------------------------------------------------------
    input="${input#"${input%%[![:space:]]*}"}"
    input="${input%"${input##*[![:space:]]}"}"

    [[ -z "$input" ]] && return 1

    # ------------------------------------------------------------------
    # PATH A: Pure IPv4 address
    # If it looks like an IPv4, validate it directly without DNS.
    # ------------------------------------------------------------------
    if [[ "$input" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # Validate each octet
        local o1 o2 o3 o4
        IFS='.' read -r o1 o2 o3 o4 <<< "$input"
        local octet_valid=1
        local o
        for o in "$o1" "$o2" "$o3" "$o4"; do
            if [[ ! "$o" =~ ^[0-9]+$ ]] || (( 10#$o > 255 )); then
                octet_valid=0
                break
            fi
        done

        if (( octet_valid == 0 )); then
            return 1
        fi

        # Reserved address checks (same logic as before, factored out)
        local _reserved=0
        local _reserved_reason=""

        if   (( 10#$o1 == 0 )); then
            _reserved=1
            _reserved_reason="0.0.0.0/8 is the 'this network' range (RFC 1122)"
        elif (( 10#$o1 == 127 )); then
            _reserved=1
            _reserved_reason="127.0.0.0/8 is the loopback range — use Loopback Test mode instead"
        elif (( 10#$o1 == 169 && 10#$o2 == 254 )); then
            _reserved=1
            _reserved_reason="169.254.0.0/16 is the link-local (APIPA) range (RFC 3927)"
        elif (( 10#$o1 == 192 && 10#$o2 == 0 && 10#$o3 == 2 )); then
            _reserved=1
            _reserved_reason="192.0.2.0/24 is TEST-NET-1 (RFC 5737)"
        elif (( 10#$o1 == 198 && 10#$o2 == 51 && 10#$o3 == 100 )); then
            _reserved=1
            _reserved_reason="198.51.100.0/24 is TEST-NET-2 (RFC 5737)"
        elif (( 10#$o1 == 203 && 10#$o2 == 0 && 10#$o3 == 113 )); then
            _reserved=1
            _reserved_reason="203.0.113.0/24 is TEST-NET-3 (RFC 5737)"
        elif (( 10#$o1 == 198 && ( 10#$o2 == 18 || 10#$o2 == 19 ) )); then
            _reserved=1
            _reserved_reason="198.18.0.0/15 is the benchmarking range (RFC 2544)"
        elif (( 10#$o1 >= 224 && 10#$o1 <= 239 )); then
            _reserved=1
            _reserved_reason="${input} is in the multicast range (224.0.0.0/4)"
        elif (( 10#$o1 >= 240 && 10#$o1 <= 254 )); then
            _reserved=1
            _reserved_reason="${input} is in the reserved range (240.0.0.0/4)"
        elif (( 10#$o1 == 255 )); then
            _reserved=1
            _reserved_reason="255.x.x.x is a broadcast/reserved range"
        elif (( 10#$o4 == 0 )); then
            _reserved=1
            _reserved_reason="${input} ends in .0 — typically a network address"
        elif (( 10#$o4 == 255 )); then
            _reserved=1
            _reserved_reason="${input} ends in .255 — typically a broadcast address"
        fi

        if (( _reserved )); then
            printf '%b  Reason: %s.%b\n' "$YELLOW" "$_reserved_reason" "$NC"
            # Write to out vars anyway so caller can display the error
            printf -v "$out_ip_var"      '%s' "$input"
            printf -v "$out_display_var" '%s' "$input"
            return 2
        fi

        # Valid unicast IPv4
        printf -v "$out_ip_var"      '%s' "$input"
        printf -v "$out_display_var" '%s' "$input"
        return 0
    fi

    # ------------------------------------------------------------------
    # PATH B: FQDN / Hostname
    # Validate the syntax before attempting DNS resolution.
    # ------------------------------------------------------------------

    # Basic FQDN syntax validation:
    #   - Total length 1-253 characters
    #   - Each label: 1-63 chars, [A-Za-z0-9-], no leading/trailing hyphen
    #   - At least one dot separating labels OR resolvable single label

    local fqdn_valid=1

    # Length check
    if (( ${#input} == 0 || ${#input} > 253 )); then
        fqdn_valid=0
    fi

    # Character set check — allow alphanumeric, hyphen, dot
    # Reject anything containing characters outside [A-Za-z0-9.-]
    if [[ $fqdn_valid -eq 1 ]]; then
        if [[ ! "$input" =~ ^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$ ]]; then
            fqdn_valid=0
        fi
    fi

    # Per-label validation (each label between dots must be 1-63 chars,
    # must not start or end with a hyphen)
    if [[ $fqdn_valid -eq 1 ]]; then
        local IFS_SAVE="$IFS"
        IFS='.'
        local -a labels
        read -ra labels <<< "$input"
        IFS="$IFS_SAVE"

        local label
        for label in "${labels[@]}"; do
            if (( ${#label} == 0 || ${#label} > 63 )); then
                fqdn_valid=0
                break
            fi
            # No leading or trailing hyphen
            if [[ "$label" =~ ^- || "$label" =~ -$ ]]; then
                fqdn_valid=0
                break
            fi
        done
    fi

    if (( fqdn_valid == 0 )); then
        return 1
    fi

    # ------------------------------------------------------------------
    # DNS Resolution
    # ------------------------------------------------------------------
    printf '  %bResolving %b%s%b...' "$DIM" "$BOLD" "$input" "$NC"

    local resolved_ip
    if resolved_ip=$(_resolve_fqdn "$input"); then
        printf ' %b✓ %s%b\n' "$GREEN" "$resolved_ip" "$NC"

        # Validate the resolved IP is a usable unicast address
        # (re-use PATH A logic by recursing with the IP)
        local _check_ip _check_disp
        local rc
        _validate_and_resolve_target "$resolved_ip" "_check_ip" "_check_disp"
        rc=$?

        if (( rc == 2 )); then
            # Reserved address returned from DNS (e.g. RFC 5737 test range)
            printf '%b  DNS resolved to reserved address %s — cannot use.%b\n' \
                "$RED" "$resolved_ip" "$NC"
            return 2
        fi

        if (( rc != 0 )); then
            printf '%b  DNS resolved to invalid address %s.%b\n' \
                "$RED" "$resolved_ip" "$NC"
            return 1
        fi

        # Loopback special case — redirect to loopback mode
        local _r1
        _r1="${resolved_ip%%.*}"
        if (( 10#$_r1 == 127 )); then
            printf '%b  %s resolves to loopback (%s).%b\n' \
                "$YELLOW" "$input" "$resolved_ip" "$NC"
            printf '%b  Use Loopback Test mode (option 4) for local tests.%b\n' \
                "$YELLOW" "$NC"
            return 2
        fi

        # Success — store resolved IP and display string
        printf -v "$out_ip_var"      '%s' "$resolved_ip"
        printf -v "$out_display_var" '%s' "${input} (${resolved_ip})"
        return 0
    else
        printf ' %bFAILED%b\n' "$RED" "$NC"
        printf '  %bCould not resolve "%s" — check spelling and DNS configuration.%b\n' \
            "$RED" "$input" "$NC"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# _all_streams_loopback
#
# Returns 0 (true) when every configured client stream targets a loopback
# address (127.x.x.x or ::1).  Used to suppress features that are not
# applicable during loopback validation tests, such as DSCP verification
# and the RTT hint row.
# Returns 1 (false) when at least one stream targets a non-loopback address.
# ---------------------------------------------------------------------------
_all_streams_loopback() {
    (( STREAM_COUNT == 0 )) && return 0
    local i
    for (( i=0; i<STREAM_COUNT; i++ )); do
        local t="${S_TARGET[$i]:-}"
        # If any stream is NOT loopback, return false immediately
        if [[ ! "$t" =~ ^127\. && "$t" != "::1" ]]; then
            return 1
        fi
    done
    return 0
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
    local t="${1:-PRISM}"
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

# ---------------------------------------------------------------------------
# _build_session_header
#
# Builds the one-line session context string and stores it in SESSION_HEADER.
# Called once from main() after iperf3 version detection completes so all
# fields are available.
#
# Format:
#   host:<hostname>  user:<username>  date:<YYYY-MM-DD HH:MM>
#   iperf3:<version>  os:<kernel>
#
# All fields are plain ASCII — no ANSI codes — so the string can be safely
# written to log files and embedded in printf format strings.
# ---------------------------------------------------------------------------
_build_session_header() {
    local h u d v o
    h="host:$(hostname)"
    u="user:$USER"
    d="date:$(date +'%Y-%m-%d %H:%M')"
    v="iperf3:$(iperf3 -v | head -n1 | awk '{print $2}')"
    # Get kernel version and simplify
    o="os:$(uname -sr)"

    # Export as a single string for the logic to evaluate
    SESSION_HEADER_RAW="$h  $u  $d  $v  $o"
}

# ---------------------------------------------------------------------------
# _print_session_header  [<context_label>]
#
# Renders SESSION_HEADER inside the standard box-drawing frame.
# Optional <context_label> (e.g. "Client Mode") is appended on the right.
#
# Alignment guarantee:
#   The session line is built as plain text first, its visible length is
#   measured, and padding is added so the right border lands exactly at
#   COLS - 1. ANSI colour codes are applied after measurement so vlen()
#   is not needed here.
#
# Called at the top of every mode function and results table.
# ---------------------------------------------------------------------------
_print_session_header() {
    local term_width=78  # Standard PRISM box width
    local inner_width=$((term_width - 4)) # Space between '|  ' and '  |'

    _build_session_header

    echo "+$(rpt '-' $((term_width - 2)))+"

    if [ ${#SESSION_HEADER_RAW} -le $inner_width ]; then
        # Single Line Mode
        local rp=$((inner_width - ${#SESSION_HEADER_RAW}))
        printf "|  %b%s%b%s  |\n" "$DIM" "$SESSION_HEADER_RAW" "$NC" "$(rpt ' ' $rp)"
    else
        # Multi-Line Mode (Splits host/user/date and iperf3/os)
        local line1="host:$(hostname)  user:$USER  date:$(date +'%Y-%m-%d %H:%M')"
        local line2="iperf3:$(iperf3 -v | head -n1 | awk '{print $2}')  os:$(uname -sr)"

        # Calculate padding for Line 1
        local rp1=$((inner_width - ${#line1}))
        [ $rp1 -lt 0 ] && rp1=0
        printf "|  %b%s%b%s  |\n" "$DIM" "$line1" "$NC" "$(rpt ' ' $rp1)"

        # Calculate padding for Line 2
        local rp2=$((inner_width - ${#line2}))
        [ $rp2 -lt 0 ] && rp2=0
        printf "|  %b%s%b%s  |\n" "$DIM" "$line2" "$NC" "$(rpt ' ' $rp2)"
    fi

    echo "+$(rpt '-' $((term_width - 2)))+"
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

# ---------------------------------------------------------------------------
# _parse_bidir_bw_from_log  <logfile>  <direction>
#
# Parses bandwidth from an iperf3 --bidir log file (client side).
#
# iperf3 --bidir client log formats:
#
#   iperf3 >= 3.7 compound format (stream ID + role in adjacent brackets):
#     [  5][TX-C]   0.00-1.00   sec   112 MBytes   940 Mbits/sec
#     [  8][RX-C]   0.00-1.00   sec   108 MBytes   906 Mbits/sec
#     [SUM][TX-C]   0.00-1.00   sec   ...   (parallel streams)
#     [SUM][RX-C]   0.00-1.00   sec   ...   (parallel streams)
#
#   Standalone role format (some builds):
#     [TX-C]   0.00-1.00   sec   112 MBytes   940 Mbits/sec
#     [RX-C]   0.00-1.00   sec   108 MBytes   906 Mbits/sec
#
# direction "tx" → look for [TX-C] tagged lines (client transmit)
# direction "rx" → look for [RX-C] tagged lines (client receive)
#
# SUM lines are always preferred over individual stream lines because they
# carry the correct aggregate bandwidth for parallel (-P) connections.
# ---------------------------------------------------------------------------

_parse_bidir_bw_from_log() {
    local logfile="$1"
    local direction="${2:-tx}"

    [[ ! -f "$logfile" || ! -s "$logfile" ]] && { printf '%s' '---'; return; }

    local role
    case "$direction" in
        tx) role="TX-C" ;;
        rx) role="RX-C" ;;
        *)  role="TX-C" ;;
    esac

    local ll=""

    # ── Priority 1: [SUM][TX-C] / [SUM][RX-C] — parallel bidir ───────────
    # Prefer SUM lines for parallel streams — they carry the aggregate.
    # Do NOT skip zero-value lines here: the SUM line is authoritative.
    if [[ -z "$ll" ]]; then
        ll=$(grep -E "\[SUM\]\[${role}\]" "$logfile" 2>/dev/null \
            | grep -E '[0-9.]+-[0-9.]+[[:space:]]+sec' \
            | grep -vE '[[:space:]](sender|receiver)[[:space:]]*$' \
            | tail -1)
    fi

    # ── Priority 2: [ N][TX-C] / [ N][RX-C] — single stream compound ──────
    # Matches:  [  5][TX-C]   0.00-1.00   sec   112 MBytes   940 Mbits/sec
    # The ]\[ pattern matches the junction between the two bracket fields.
    # We take the LAST non-summary interval line regardless of bandwidth value.
    # Earlier versions skipped 0.00 lines but this caused TCP streams to show
    # --- during slow-start. We rely on tail -1 to get the most recent line.
    if [[ -z "$ll" ]]; then
        ll=$(grep -E "\]\[${role}\]" "$logfile" 2>/dev/null \
            | grep -E '[0-9.]+-[0-9.]+[[:space:]]+sec' \
            | grep -vE '[[:space:]](sender|receiver)[[:space:]]*$' \
            | grep -vE '^\[SUM\]' \
            | tail -1)
    fi

    # ── Priority 3: standalone ^[TX-C] / ^[RX-C] — older iperf3 format ───
    if [[ -z "$ll" ]]; then
        ll=$(grep -E "^\[${role}\]" "$logfile" 2>/dev/null \
            | grep -E '[0-9.]+-[0-9.]+[[:space:]]+sec' \
            | grep -vE '[[:space:]](sender|receiver)[[:space:]]*$' \
            | tail -1)
    fi

    # ── Priority 4: [TX] / [RX] without -C suffix — older builds ──────────
    local role_short
    case "$direction" in
        tx) role_short="TX" ;;
        rx) role_short="RX" ;;
    esac
    if [[ -z "$ll" ]]; then
        ll=$(grep -E "\]\[${role_short}\]|^\[${role_short}\]" \
             "$logfile" 2>/dev/null \
            | grep -E '[0-9.]+-[0-9.]+[[:space:]]+sec' \
            | grep -vE '[[:space:]](sender|receiver)[[:space:]]*$' \
            | tail -1)
    fi

    # ── Priority 5: plain SUM — parallel streams, unidirectional ──────────
    if [[ -z "$ll" ]]; then
        ll=$(grep -E '^\[SUM\][[:space:]]+[0-9.]+-[0-9.]+[[:space:]]+sec' \
             "$logfile" 2>/dev/null \
             | grep -vE '[[:space:]](sender|receiver)[[:space:]]*$' \
             | tail -1)
    fi

    # ── Priority 6: plain stream-ID — single stream, unidirectional ───────
    # Also catches compound-bracket lines that slipped past priorities 1-4
    # because the role tag was absent or in an unexpected format.
    if [[ -z "$ll" ]]; then
        ll=$(grep -E '^\[[[:space:]]*[0-9]+\][[:space:]]+[0-9.]+-[0-9.]+[[:space:]]+sec' \
             "$logfile" 2>/dev/null \
             | grep -vE '[[:space:]](sender|receiver)[[:space:]]*$' \
             | tail -1)
    fi

    [[ -z "$ll" ]] && { printf '%s' '---'; return; }

    local result
    result=$(_extract_bw_from_line "$ll")
    if [[ -n "$result" && "$result" != "---" ]]; then
        printf '%s' "$result"
    else
        printf '%s' '---'
    fi
}

# ---------------------------------------------------------------------------
# _parse_srv_live_bw  <logfile>
#
# Parses the most recent per-interval bandwidth line from a server log.
#
# iperf3 server log formats in priority order:
#
#   [SUM][RX-S]  (parallel streams, bidir server receive — highest priority)
#   [SUM][TX-S]  (parallel streams, bidir server transmit)
#   [RX-S]       (single stream, bidir server receive)
#   [TX-S]       (single stream, bidir server transmit)
#   [SUM]        (parallel streams, unidirectional)
#   [  N]        (single stream, unidirectional)
#
# [SUM] lines must be checked before bare stream-ID lines because individual
# stream lines for parallel connections each carry a fraction of the total
# bandwidth. The [SUM] line carries the aggregate value.
#
# For bidir sessions the bare [RX-S] per-stream lines often carry 0 bps
# while [SUM][RX-S] carries the correct aggregate. Always prefer SUM.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# _parse_srv_live_bw  <logfile>
#
# Parses live per-interval bandwidth from an iperf3 server log.
#
# iperf3 server log line formats observed in practice:
#
#   Standard unidirectional (single stream):
#     [  5]   0.00-1.00   sec   112 MBytes   940 Mbits/sec
#
#   Standard unidirectional (parallel, SUM line):
#     [SUM]   0.00-1.00   sec   112 MBytes   940 Mbits/sec
#
#   Bidirectional --bidir (stream ID and role combined):
#     [  5][RX-S]   0.00-1.00   sec  0.00 Bytes  0.00 bits/sec
#     [  8][TX-S]   0.00-1.00   sec   128 KBytes  1.05 Mbits/sec
#
#   Bidirectional --bidir (parallel, SUM lines):
#     [SUM][RX-S]   0.00-1.00   sec  ...
#     [SUM][TX-S]   0.00-1.00   sec  ...
#
# Direction priority for server dashboard:
#   TX-S  (server transmitting to client) is the active traffic direction
#   in a bidir session where the client sends --reverse data. This is what
#   shows meaningful non-zero bandwidth on the server side.
#   RX-S  lines are zero when the client is not sending in that direction.
#
# The function tries TX-S first, then RX-S, then falls back to plain lines.
# ---------------------------------------------------------------------------
_parse_srv_live_bw() {
    local logfile="$1"
    [[ ! -f "$logfile" || ! -s "$logfile" ]] && { printf '%s' '---'; return; }

    local ll=""

    # ── Priority 1: [SUM][TX-S] — parallel bidir, server transmit ─────────
    # The SUM line aggregates all parallel streams. Always prefer SUM over
    # individual stream lines to get the correct total bandwidth.
    if [[ -z "$ll" ]]; then
        ll=$(grep -E '\[SUM\]\[TX-S\]' "$logfile" 2>/dev/null \
            | grep -E '[0-9.]+-[0-9.]+[[:space:]]+sec' \
            | grep -vE '[[:space:]](sender|receiver)[[:space:]]*$' \
            | tail -1)
    fi

    # ── Priority 2: [SUM][RX-S] — parallel bidir, server receive ──────────
    if [[ -z "$ll" ]]; then
        ll=$(grep -E '\[SUM\]\[RX-S\]' "$logfile" 2>/dev/null \
            | grep -E '[0-9.]+-[0-9.]+[[:space:]]+sec' \
            | grep -vE '[[:space:]](sender|receiver)[[:space:]]*$' \
            | tail -1)
    fi

    # ── Priority 3: [N][TX-S] — single stream bidir, server transmit ──────
    # Format: [  8][TX-S]   0.00-1.00   sec   128 KBytes  1.05 Mbits/sec
    # The stream-ID bracket [ N] is followed immediately by [TX-S].
    # We match any line containing ][TX-S] to handle varying ID widths.
    if [[ -z "$ll" ]]; then
        ll=$(grep -E '\]\[TX-S\]' "$logfile" 2>/dev/null \
            | grep -E '[0-9.]+-[0-9.]+[[:space:]]+sec' \
            | grep -vE '[[:space:]](sender|receiver)[[:space:]]*$' \
            | grep -vE '^\[SUM\]' \
            | tail -1)
    fi

    # ── Priority 4: [N][RX-S] — single stream bidir, server receive ───────
    # Only use if TX-S produced nothing (e.g. purely one-directional bidir).
    if [[ -z "$ll" ]]; then
        ll=$(grep -E '\]\[RX-S\]' "$logfile" 2>/dev/null \
            | grep -E '[0-9.]+-[0-9.]+[[:space:]]+sec' \
            | grep -vE '[[:space:]](sender|receiver)[[:space:]]*$' \
            | grep -vE '^\[SUM\]' \
            | tail -1)
    fi

    # ── Priority 5: [SUM] — parallel streams, unidirectional ──────────────
    if [[ -z "$ll" ]]; then
        ll=$(grep -E '^\[SUM\][[:space:]]+[0-9.]+-[0-9.]+[[:space:]]+sec' \
             "$logfile" 2>/dev/null \
             | grep -vE '[[:space:]](sender|receiver)[[:space:]]*$' \
             | tail -1)
    fi

    # ── Priority 6: plain stream-ID — single stream, unidirectional ───────
    if [[ -z "$ll" ]]; then
        ll=$(grep -E '^\[[[:space:]]*[0-9]+\][[:space:]]+[0-9.]+-[0-9.]+[[:space:]]+sec' \
             "$logfile" 2>/dev/null \
             | grep -vE '[[:space:]](sender|receiver)[[:space:]]*$' \
             | tail -1)
    fi

    [[ -z "$ll" ]] && { printf '%s' '---'; return; }

    # ── Extract bandwidth value and unit from matched line ─────────────────
    # The awk scans all fields for a unit token matching bits/sec variants
    # and returns the preceding numeric field paired with the unit.
    local result
    result=$(_extract_bw_from_line "$ll")
    if [[ -n "$result" && "$result" != "---" ]]; then
        printf '%s' "$result"
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

    local sbw="" rbw=""

    if [[ "${S_BIDIR[$idx]:-0}" == "1" && (( BIDIR_SUPPORTED == 1 )) ]]; then
        # ── --bidir log: TX summary in [TX-C] receiver line ───────────────
        # iperf3 --bidir final summary lines are tagged with [TX-C] and
        # [RX-C] and include "sender" / "receiver" labels.
        local tx_sum_line rx_sum_line

        tx_sum_line=$(grep -E '\[TX-C\].*receiver' "$lf" 2>/dev/null | tail -1)
        [[ -z "$tx_sum_line" ]] && \
            tx_sum_line=$(grep -E '\[TX-C\].*sender' "$lf" 2>/dev/null | tail -1)

        rx_sum_line=$(grep -E '\[RX-C\].*receiver' "$lf" 2>/dev/null | tail -1)
        [[ -z "$rx_sum_line" ]] && \
            rx_sum_line=$(grep -E '\[RX-C\].*sender' "$lf" 2>/dev/null | tail -1)

        if [[ -n "$tx_sum_line" ]]; then
            sbw=$(printf '%s\n' "$tx_sum_line" \
                | awk '{for(i=1;i<=NF;i++) if($i~/[KMG]?bits\/sec/) print $(i-1),$i}' \
                | head -1)
            [[ -n "$sbw" ]] && sbw=$(_normalise_text_bw "$sbw")
        fi

        if [[ -n "$rx_sum_line" ]]; then
            rbw=$(printf '%s\n' "$rx_sum_line" \
                | awk '{for(i=1;i<=NF;i++) if($i~/[KMG]?bits\/sec/) print $(i-1),$i}' \
                | head -1)
            [[ -n "$rbw" ]] && rbw=$(_normalise_text_bw "$rbw")
        fi

        # Fallback to live parsing if summary not yet available
        [[ -z "$sbw" || "$sbw" == "---" ]] && \
            sbw=$(_parse_bidir_bw_from_log "$lf" "tx")
        [[ -z "$rbw" || "$rbw" == "---" ]] && \
            rbw=$(_parse_bidir_bw_from_log "$lf" "rx")
    else
        # ── Standard log ──────────────────────────────────────────────────
        sbw=$(parse_final_bw_from_log "$lf" "sender")
        rbw=$(parse_final_bw_from_log "$lf" "receiver")
        [[ -z "$sbw" || "$sbw" == "---" ]] && \
            sbw=$(parse_live_bandwidth_from_log "$lf")
        [[ -z "$rbw" || "$rbw" == "---" ]] && rbw="$sbw"
    fi

    S_FINAL_SENDER_BW[$idx]="${sbw:-N/A}"
    S_FINAL_RECEIVER_BW[$idx]="${rbw:-N/A}"

    # Capture final cwnd from the last interval line
    if [[ "${S_PROTO[$idx]:-TCP}" == "TCP" && -f "$lf" && -s "$lf" ]]; then
        local final_cwnd_line
        final_cwnd_line=$(grep -E '[0-9.]+-[0-9.]+[[:space:]]+sec' "$lf" \
            2>/dev/null \
            | grep -vE '[[:space:]](sender|receiver)[[:space:]]*$' \
            | grep -E '[[:space:]][0-9]+(\.[0-9]+)?[[:space:]]+KBytes[[:space:]]*$' \
            | tail -1)
        if [[ -n "$final_cwnd_line" ]]; then
            local fv
            fv=$(printf '%s\n' "$final_cwnd_line" | awk '
                { if ($NF == "KBytes" && $(NF-1)+0 > 0)
                    printf "%.1f", $(NF-1)+0 }')
            [[ -n "$fv" && "$fv" != "0.0" ]] && S_CWND_FINAL[$idx]="$fv"
        fi
    fi
}

# =============================================================================
# SECTION 4 — CLEANUP AND SIGNALS
# =============================================================================

tty_echo() { printf '%b\n' "$1" >/dev/tty 2>/dev/null || printf '%b\n' "$1"; }

cleanup() {
    [[ $CLEANUP_DONE -eq 1 ]] && return 0
    CLEANUP_DONE=1
    local sn="${1:-EXIT}"

    # ── Ensure cursor is on a clean line before printing cleanup output ──
    # printf '\n' to /dev/tty guarantees we start at column 0 even if the
    # last character written to the terminal was not a newline.
    printf '\n' >/dev/tty 2>/dev/null

    # ── Restore cursor visibility (defensive — signal may fire mid-render) ─
    printf '\033[?25h' >/dev/tty 2>/dev/null

    local sep; sep=$(rpt '=' $(( COLS - 2 )))
    tty_echo ""
    tty_echo "${BOLD}${CYAN}+${sep}+${NC}"
    tty_echo "${BOLD}${CYAN}  PRISM — Cleanup  [signal: ${sn}]${NC}"
    tty_echo "${BOLD}${CYAN}+${sep}+${NC}"

    local killed=0 already=0

    # ── Client stream teardown ────────────────────────────────────────────
    if (( ${#STREAM_PIDS[@]} > 0 )); then
        tty_echo ""; tty_echo "${BOLD}  Client Streams:${NC}"
        local i
        for i in "${!STREAM_PIDS[@]}"; do
            local pid="${STREAM_PIDS[$i]}"
            local lbl="stream $((i+1)) [${S_PROTO[$i]:-?}->${S_TARGET[$i]:-?}:${S_PORT[$i]:-?}]"
            if [[ -z "$pid" || "$pid" == "0" ]]; then
                tty_echo "    ${YELLOW}[SKIP ]${NC}  $lbl  -- no PID"
                continue
            fi
            if kill -0 "$pid" 2>/dev/null; then
                kill -TERM "$pid" 2>/dev/null
                local w=0
                while kill -0 "$pid" 2>/dev/null && (( w < 6 )); do
                    sleep 0.5; (( w++ ))
                done
                if kill -0 "$pid" 2>/dev/null; then
                    kill -KILL "$pid" 2>/dev/null
                    wait "$pid" 2>/dev/null
                    tty_echo "    ${RED}[KILLED]${NC}  PID $pid  $lbl"
                else
                    wait "$pid" 2>/dev/null
                    tty_echo "    ${GREEN}[STOP  ]${NC}  PID $pid  $lbl"
                fi
                (( killed++ ))
            else
                wait "$pid" 2>/dev/null
                tty_echo "    ${CYAN}[DONE  ]${NC}  PID $pid  $lbl  (already exited)"
                (( already++ ))
            fi
        done
    fi

    # ── RTT ping teardown ─────────────────────────────────────────────────
    if (( ${#PING_PIDS[@]} > 0 )); then
        tty_echo ""; tty_echo "${BOLD}  RTT Ping Processes:${NC}"
        local i
        for i in "${!PING_PIDS[@]}"; do
            local pid="${PING_PIDS[$i]}"
            [[ -z "$pid" || "$pid" == "0" ]] && continue
            if kill -0 "$pid" 2>/dev/null; then
                kill -TERM "$pid" 2>/dev/null
                wait "$pid" 2>/dev/null
                tty_echo "    ${GREEN}[STOP  ]${NC}  PID $pid  rtt-ping stream $((i+1))"
            fi
        done
    fi

    # ── Bidir reverse process teardown ────────────────────────────────────
    if (( ${#BIDIR_PIDS[@]} > 0 )); then
        tty_echo ""; tty_echo "${BOLD}  Bidirectional RX Processes:${NC}"
        local i
        for i in "${!BIDIR_PIDS[@]}"; do
            local pid="${BIDIR_PIDS[$i]}"
            [[ -z "$pid" || "$pid" == "0" ]] && continue
            if kill -0 "$pid" 2>/dev/null; then
                kill -TERM "$pid" 2>/dev/null
                wait "$pid" 2>/dev/null
                tty_echo "    ${GREEN}[STOP  ]${NC}  PID $pid  bidir-rx stream $((i+1))"
            else
                wait "$pid" 2>/dev/null
                tty_echo "    ${CYAN}[DONE  ]${NC}  PID $pid  bidir-rx stream $((i+1))  (already exited)"
            fi
        done
    fi

    # ── Server listener teardown ──────────────────────────────────────────
    if (( ${#SERVER_PIDS[@]} > 0 )); then
        tty_echo ""; tty_echo "${BOLD}  Server Listeners:${NC}"
        local i
        for i in "${!SERVER_PIDS[@]}"; do
            local pid="${SERVER_PIDS[$i]}"
            local lbl="listener $((i+1)) [port ${SRV_PORT[$i]:-?} bind ${SRV_BIND[$i]:-0.0.0.0}]"
            if [[ -z "$pid" || "$pid" == "0" ]]; then
                tty_echo "    ${YELLOW}[SKIP ]${NC}  $lbl  -- no PID"
                continue
            fi
            if kill -0 "$pid" 2>/dev/null; then
                kill -TERM "$pid" 2>/dev/null
                local w=0
                while kill -0 "$pid" 2>/dev/null && (( w < 6 )); do
                    sleep 0.5; (( w++ ))
                done
                if kill -0 "$pid" 2>/dev/null; then
                    kill -KILL "$pid" 2>/dev/null
                    wait "$pid" 2>/dev/null
                    tty_echo "    ${RED}[KILLED]${NC}  PID $pid  $lbl"
                else
                    wait "$pid" 2>/dev/null
                    tty_echo "    ${GREEN}[STOP  ]${NC}  PID $pid  $lbl"
                fi
                (( killed++ ))
            else
                wait "$pid" 2>/dev/null
                tty_echo "    ${CYAN}[DONE  ]${NC}  PID $pid  $lbl  (already exited)"
                (( already++ ))
            fi
        done
    fi

    # ── tc netem teardown ─────────────────────────────────────────────────
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

    # ── Temporary file deletion ───────────────────────────────────────────
    tty_echo ""; tty_echo "${BOLD}  Temporary Files:${NC}"
    if [[ -n "$TMPDIR" && -d "$TMPDIR" ]]; then
        local fc=0
        while IFS= read -r -d '' fp; do
            local fsz; fsz=$(wc -c < "$fp" 2>/dev/null)
            fsz="${fsz// /}"
            tty_echo "    ${CYAN}[DEL]${NC}  $fp  (${fsz:-0} bytes)"
            (( fc++ ))
        done < <(find "$TMPDIR" -maxdepth 3 -type f -print0 2>/dev/null)
        (( fc == 0 )) && \
            tty_echo "    ${YELLOW}[INFO ]${NC}  No files in $TMPDIR"
        rm -rf "$TMPDIR" 2>/dev/null \
            && tty_echo "    ${GREEN}[REMOVED]${NC}  $TMPDIR" \
            || tty_echo "    ${RED}[ERROR  ]${NC}  Cannot remove $TMPDIR"
    else
        tty_echo "    ${YELLOW}[INFO ]${NC}  Temp dir not found or already removed"
    fi

    # ── JSON export cleanup prompt ────────────────────────────────────────
    _json_export_prompt_delete

    # ── Summary ───────────────────────────────────────────────────────────
    tty_echo ""
    tty_echo "${BOLD}${CYAN}+${sep}+${NC}"
    tty_echo "  ${GREEN}Processes stopped : ${killed}${NC}"
    tty_echo "  ${CYAN}Already exited    : ${already}${NC}"
    tty_echo "${BOLD}${GREEN}  Cleanup complete. All resources released.${NC}"
    tty_echo "${BOLD}${CYAN}+${sep}+${NC}"
    tty_echo ""
}

# =============================================================================
# _trap_cursor_exit
#
# Moves the terminal cursor to a clean line below the last rendered dashboard
# frame before any cleanup text is printed.
#
# Uses _LAST_FRAME_LINE_COUNT (updated after every render tick by run_dashboard)
# to calculate the exact downward distance from the saved frame anchor.
#
# Sequence:
#   \033[u   — restore cursor to saved frame anchor (top of dashboard)
#   \033[NB  — move down N lines (past the full frame)
#   \033[J   — erase from cursor to end of screen (remove ghost content)
#   \033[?25h — restore cursor visibility
#   \n       — one blank line before cleanup text
#
# Goes directly to /dev/tty so it works even when stdout is redirected.
# =============================================================================

_trap_cursor_exit() {
    local _lines="${_LAST_FRAME_LINE_COUNT:-0}"
    if (( _lines > 0 )); then
        printf '\033[u\033[%dB\033[J\033[?25h\n' "$_lines" >/dev/tty 2>/dev/null
    else
        printf '\033[?25h\n\n' >/dev/tty 2>/dev/null
    fi
}

# =============================================================================
# _trap_int / _trap_term / _trap_quit / _trap_hup
#
# If a render is in progress (_RENDER_LOCK=1) the signal is deferred by
# storing its name in _DEFERRED_SIGNAL. run_dashboard dispatches it at the
# safe point between ticks.
#
# If no render is in progress the signal is handled immediately.
# =============================================================================
_trap_int() {
    if (( _RENDER_LOCK == 1 )); then
        _DEFERRED_SIGNAL="INT"
        return
    fi
    _trap_cursor_exit
    tty_echo "${BOLD}${YELLOW}  PRISM [SIGINT]  Ctrl+C — stopping...${NC}"
    cleanup "SIGINT (Ctrl+C)"
    exit 130
}

_trap_term() {
    if (( _RENDER_LOCK == 1 )); then
        _DEFERRED_SIGNAL="TERM"
        return
    fi
    _trap_cursor_exit
    tty_echo "${BOLD}${YELLOW}  PRISM [SIGTERM] Stopping...${NC}"
    cleanup "SIGTERM"
    exit 143
}

_trap_quit() {
    if (( _RENDER_LOCK == 1 )); then
        _DEFERRED_SIGNAL="QUIT"
        return
    fi
    _trap_cursor_exit
    tty_echo "${BOLD}${YELLOW}  PRISM [SIGQUIT] Ctrl+\\ — stopping...${NC}"
    cleanup "SIGQUIT"
    exit 131
}

_trap_hup() {
    if (( _RENDER_LOCK == 1 )); then
        _DEFERRED_SIGNAL="HUP"
        return
    fi
    _trap_cursor_exit
    tty_echo "${BOLD}${YELLOW}  PRISM [SIGHUP]  Terminal closed — stopping...${NC}"
    cleanup "SIGHUP"
    exit 129
}

_trap_tstp() {
    # Ctrl+Z is always blocked regardless of render state
    printf '\033[?25h' >/dev/tty 2>/dev/null
    tty_echo "${BOLD}${YELLOW}  PRISM [Ctrl+Z blocked]${NC}  Backgrounding will orphan iperf3 processes."
    tty_echo "${YELLOW}  Use Ctrl+C to stop cleanly.${NC}"
}

_trap_exit() {
    local ec=$?
    (( CLEANUP_DONE == 0 )) && cleanup "exit (code ${ec})"
}

register_traps() {
    trap '_trap_exit' EXIT
    trap '_trap_int'  INT
    trap '_trap_term' TERM
    trap '_trap_quit' QUIT
    trap '_trap_hup'  HUP
    trap '_trap_tstp' TSTP
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
    printf '%b\n' "${RED}PRISM ERROR: iperf3 not found.${NC}"
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
    # --bidir flag available in iperf3 >= 3.7
    "$IPERF3_BIN" --help 2>&1 | grep -q '\-\-bidir' \
        && BIDIR_SUPPORTED=1 || BIDIR_SUPPORTED=0
    # Also accept version check as fallback
    (( BIDIR_SUPPORTED == 0 )) && version_ge 3 7 && BIDIR_SUPPORTED=1
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

    S_RAMP_ENABLED=(); S_RAMP_UP=();      S_RAMP_DOWN=()
    S_RAMP_STEPS=();   S_RAMP_PHASE=();   S_RAMP_PHASE_TS=()
    S_RAMP_BW_CURRENT=(); S_RAMP_BW_TARGET=()
    S_RAMP_IFACE=();   S_RAMP_TC_ACTIVE=()

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

        # ── Target ───────────────────────────────────────────────────────────

        local tprompt
        [[ -n "$lt" ]] \
            && tprompt="  Target server IP or FQDN [$lt]" \
            || tprompt="  Target server IP or FQDN"
        local tgt tgt_display
        while true; do
            read -r -p "${tprompt}: " tgt </dev/tty
            tgt="${tgt:-$lt}"

            # ── Empty input ───────────────────────────────────────────────
            if [[ -z "$tgt" ]]; then
                printf '%b\n' "${RED}  Target is required. Enter an IPv4 address or FQDN.${NC}"
                continue
            fi

            # ── Validate and resolve (IPv4 or FQDN) ──────────────────────
            local _resolved_ip _resolved_display
            local _resolve_rc
            _validate_and_resolve_target "$tgt" "_resolved_ip" "_resolved_display"
            _resolve_rc=$?

            case $_resolve_rc in
                0)
                    # Valid and usable
                    tgt_display="$_resolved_display"
                    tgt="$_resolved_ip"
                    printf '  %b✓ Target set: %b%s%b\n' \
                        "$GREEN" "$BOLD" "$tgt_display" "$NC"
                    break
                    ;;
                1)
                    # Invalid format or DNS failed
                    printf '%b\n' \
                        "${RED}  '${tgt}' is not a valid IPv4 address or resolvable FQDN.${NC}"
                    printf '%b\n' \
                        "${RED}  Examples: 192.168.1.10  iperf3.moji.fr  my-server.example.com${NC}"
                    continue
                    ;;
                2)
                    # Reserved or loopback — already printed reason
                    printf '%b\n' \
                        "${RED}  Enter a valid unicast IP address or FQDN.${NC}"
                    continue
                    ;;
            esac
        done

        lt="$tgt"
        S_TARGET+=("$tgt")
        S_TARGET_DISPLAY+=("$tgt_display")

        # Store display name for use in stream summary and dashboard
        # The internal target is always the resolved IPv4

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

        local rev=0

        # Only prompt for reverse mode if bidirectional is not going to be
        # enabled. The reverse and bidir flags are mutually exclusive in iperf3.
        # Bidir is configured after this block — if the user enables bidir,
        # any reverse setting here is ignored in build_client_command().

        local ri; read -r -p "  Reverse mode -R? [no]: " ri </dev/tty
        [[ "$ri" =~ ^[Yy] ]] && rev=1
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
        local nofq=0
        if [[ "$OS_TYPE" == "linux" ]]; then
            (( NOFQ_SUPPORTED )) && {
                local nfi; read -r -p "  Disable FQ socket pacing? [no]: " nfi </dev/tty
                [[ "$nfi" =~ ^[Yy] ]] && nofq=1
            }
        fi
        S_NOFQ+=("$nofq")

        # ── Bidirectional simultaneous test ───────────
        local bidir=0
        echo ""
        printf '%b\n' "${CYAN}  -- Bidirectional Test --${NC}"
        local bdi
        read -r -p "  Enable bidirectional simultaneous test (TX + RX)? [y/N]: " \
            bdi </dev/tty
        if [[ "$bdi" =~ ^[Yy] ]]; then
            bidir=1

            # If reverse mode was previously enabled, clear it now.
            # --bidir and -R are mutually exclusive in iperf3 >= 3.7.
            # --bidir supersedes -R since it measures both directions.

            if (( rev == 1 )); then
                S_REVERSE[-1]=0
                rev=0
                printf '%b\n' \
                    "${YELLOW}  NOTE: Reverse mode (-R) cleared â --bidir supersedes it.${NC}"
                printf '%b\n' \
                    "${YELLOW}        --bidir measures both TX and RX simultaneously.${NC}"
            fi

            if (( BIDIR_SUPPORTED )); then
                printf '%b\n' \
                    "${GREEN}  Bidirectional enabled via --bidir flag (iperf3 >= 3.7).${NC}"
                printf '%b\n' \
                    "${GREEN}  Both TX and RX run in a single iperf3 connection.${NC}"
            else
                printf '%b\n' \
                    "${YELLOW}  WARNING: iperf3 < 3.7 detected — --bidir not supported.${NC}"
                printf '%b\n' \
                    "${YELLOW}  Bidirectional will use two separate connections.${NC}"
                printf '%b\n' \
                    "${YELLOW}  Ensure the server is running iperf3 >= 3.7 or${NC}"
                printf '%b\n' \
                    "${YELLOW}  configure a second server port for the reverse stream.${NC}"
            fi
        else
            printf '%b\n' "${DIM}  Unidirectional — TX only.${NC}"
        fi
        S_BIDIR+=("$bidir")

        # ── Traffic Ramp-Up Profile ───────────────────────────────────────
        local ramp_enabled=0 ramp_up_secs=0 ramp_down_secs=0

        echo ""
        printf '%b\n' "${CYAN}  -- Traffic Ramp-Up Profile --${NC}"
        printf '%b\n' "${DIM}  Ramp from zero to target BW, hold, then ramp down.${NC}"
        printf '%b\n' "${DIM}  Requires iperf3 duration > 0 and root for TCP tc shaping.${NC}"
        echo ""

        local ramp_inp
        read -r -p "  Enable ramp-up profile? [y/N]: " ramp_inp </dev/tty
        if [[ "$ramp_inp" =~ ^[Yy] ]]; then
            ramp_enabled=1

            # Ramp-up duration
            while true; do
                read -r -p "  Ramp-up duration (seconds) [10]: " \
                    ramp_up_secs </dev/tty
                ramp_up_secs="${ramp_up_secs:-10}"
                if [[ "$ramp_up_secs" =~ ^[0-9]+$ ]] && \
                   (( ramp_up_secs >= 1 && ramp_up_secs <= 300 )); then
                    break
                fi
                printf '%b\n' "${RED}  Enter 1-300 seconds.${NC}"
            done

            # Ramp-down duration
            while true; do
                read -r -p "  Ramp-down duration (seconds) [5]: " \
                    ramp_down_secs </dev/tty
                ramp_down_secs="${ramp_down_secs:-5}"
                if [[ "$ramp_down_secs" =~ ^[0-9]+$ ]] && \
                   (( ramp_down_secs >= 0 && ramp_down_secs <= 300 )); then
                    break
                fi
                printf '%b\n' "${RED}  Enter 0-300 seconds (0 = no ramp-down).${NC}"
            done

            # Sanity check: ramp phases must not exceed stream duration
            if (( dval > 0 )); then
                local ramp_total=$(( ramp_up_secs + ramp_down_secs ))
                if (( ramp_total >= dval )); then
                    printf '%b\n' \
                        "${YELLOW}  WARNING: ramp up+down (${ramp_total}s)" \
                        ">= stream duration (${dval}s). Hold phase will be skipped.${NC}"
                fi
            fi

            if (( IS_ROOT == 0 )); then
                printf '%b\n' \
                    "${YELLOW}  WARNING: TCP ramp requires root (tc tbf shaping).${NC}"
                printf '%b\n' \
                    "${YELLOW}           UDP ramp uses iperf3 -b stepping (no root needed).${NC}"
            fi

            printf '%b\n' \
                "${GREEN}  Ramp profile: +${ramp_up_secs}s ↑  hold  ${ramp_down_secs}s ↓${NC}"
        else
            printf '%b\n' "${DIM}  No ramp profile — full bandwidth from start.${NC}"
        fi

        S_RAMP_ENABLED+=("$ramp_enabled")
        S_RAMP_UP+=("$ramp_up_secs")
        S_RAMP_DOWN+=("$ramp_down_secs")
        S_RAMP_STEPS+=(20)    # fixed 20 steps per ramp phase

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


# ==============================================================================
# show_stream_summary  <mode>
#
# ALIGNMENT FIXES:
#   1. C_TGT is now DYNAMIC — computed from the longest target display string
#      across all streams so the column is always wide enough without overflow.
#   2. The separator line width is recomputed from the actual column widths.
#   3. The "resolved:" annotation is suppressed when the full FQDN+IP string
#      already fits in the Target column (no truncation needed).
#   4. A hard cap prevents C_TGT from making the row wider than the terminal.
#   5. When the full display string cannot fit even in the dynamic column,
#      a dedicated "↳ FQDN (IP)" continuation line is printed instead of
#      truncating with ~.
# ==============================================================================
show_stream_summary() {
    local mode="${1:-client}"

    echo ""
    print_header "Stream Configuration Summary"
    _print_session_header
    echo ""

    # ------------------------------------------------------------------
    # CLIENT MODE
    # ------------------------------------------------------------------
    if [[ "$mode" == "client" ]]; then

        # ── Fixed column widths ─────────────────────────────────────────
        local C_SN=3       # stream number
        local C_PROTO=5    # protocol
        local C_PORT=6     # port
        local C_BW=11      # bandwidth
        local C_DUR=5      # duration
        local C_DSCP=5     # DSCP name
        local C_VRF=6      # VRF

        # ── Dynamic C_TGT ───────────────────────────────────────────────
        # Start with the header label width as the minimum.
        local C_TGT=6   # minimum width = length of "Target"

        # Measure the longest target display string across all streams
        local i
        for (( i=0; i<STREAM_COUNT; i++ )); do
            local _tgt_candidate="${S_TARGET_DISPLAY[$i]:-${S_TARGET[$i]:-?}}"
            if (( ${#_tgt_candidate} > C_TGT )); then
                C_TGT=${#_tgt_candidate}
            fi
        done

        # ── Hard cap: prevent row overflow ──────────────────────────────
        # Total row width = 2(indent) + C_SN+2 + C_PROTO+2 + C_TGT+2 +
        #                   C_PORT+2 + C_BW+2 + C_DUR+2 + C_DSCP+2 + C_VRF
        # Solve for max C_TGT:
        local _fixed_cols=$(( C_SN + 2 + C_PROTO + 2 + C_PORT + 2 + \
                              C_BW + 2 + C_DUR + 2 + C_DSCP + 2 + C_VRF ))
        # Available for target = COLS - 2(indent) - _fixed_cols
        local _max_tgt=$(( COLS - 2 - _fixed_cols ))
        (( _max_tgt < 20 )) && _max_tgt=20
        (( C_TGT > _max_tgt )) && C_TGT=$_max_tgt

        # ── Column header ───────────────────────────────────────────────
        printf '  %-*s  %-*s  %-*s  %*s  %-*s  %-*s  %-*s  %-*s\n' \
            "$C_SN"    "#" \
            "$C_PROTO" "Proto" \
            "$C_TGT"   "Target" \
            "$C_PORT"  "Port" \
            "$C_BW"    "Bandwidth" \
            "$C_DUR"   "Dur" \
            "$C_DSCP"  "DSCP" \
            "$C_VRF"   "VRF"

        # ── Separator ───────────────────────────────────────────────────
        local _sep_len=$(( C_SN + 2 + C_PROTO + 2 + C_TGT + 2 + \
                           C_PORT + 2 + C_BW + 2 + C_DUR + 2 + \
                           C_DSCP + 2 + C_VRF ))
        printf '  %s\n' "$(rpt '-' $_sep_len)"

        # ── Data rows ───────────────────────────────────────────────────
        for (( i=0; i<STREAM_COUNT; i++ )); do
            local sn=$(( i + 1 ))

            # Duration display
            local dd
            (( S_DURATION[$i] == 0 )) && dd="inf" || dd="${S_DURATION[$i]}s"

            # VRF display
            local vrf_disp="${S_VRF[$i]:-GRT}"
            [[ "$OS_TYPE" == "macos" ]] && vrf_disp="N/A"
            if (( ${#vrf_disp} > C_VRF )); then
                vrf_disp="${vrf_disp:0:$(( C_VRF - 1 ))}~"
            fi

            # Bandwidth display
            local bw_show="${S_BW[$i]:-unlimited}"
            if (( ${#bw_show} > C_BW )); then
                bw_show="${bw_show:0:$(( C_BW - 1 ))}~"
            fi

            # DSCP display
            local dscp_show="${S_DSCP_NAME[$i]:-none}"
            if (( ${#dscp_show} > C_DSCP )); then
                dscp_show="${dscp_show:0:$(( C_DSCP - 1 ))}~"
            fi

            # ── Target: fits in C_TGT? ──────────────────────────────────
            # The raw display string (e.g. "iperf.he.net (216.218.207.42)")
            local tgt_full="${S_TARGET_DISPLAY[$i]:-${S_TARGET[$i]:-?}}"
            local tgt_col   # what goes in the table column
            local need_cont=0  # whether a continuation line is needed

            if (( ${#tgt_full} <= C_TGT )); then
                # Full string fits — use it directly, no continuation needed
                tgt_col="$tgt_full"
                need_cont=0
            else
                # Even the dynamic column is not wide enough.
                # Show a placeholder in the column and print the full
                # string on a dedicated continuation line below.
                tgt_col="$(rpt '─' "$C_TGT")"
                need_cont=1
            fi

            # ── Main row ─────────────────────────────────────────────────
            printf '  %-*s  %-*s  %-*s  %*s  %-*s  %-*s  %-*s  %-*s\n' \
                "$C_SN"    "$sn" \
                "$C_PROTO" "${S_PROTO[$i]}" \
                "$C_TGT"   "$tgt_col" \
                "$C_PORT"  "${S_PORT[$i]}" \
                "$C_BW"    "$bw_show" \
                "$C_DUR"   "$dd" \
                "$C_DSCP"  "$dscp_show" \
                "$C_VRF"   "$vrf_disp"

            # ── Continuation line (only when target did not fit) ─────────
            # Indented to align under the Target column.
            # Layout: 2(indent) + C_SN + 2 + C_PROTO + 2 = target_indent
            if (( need_cont == 1 )); then
                local _tgt_indent=$(( 2 + C_SN + 2 + C_PROTO + 2 ))
                local _tgt_avail=$(( COLS - _tgt_indent - 2 ))
                (( _tgt_avail < 20 )) && _tgt_avail=20

                local cont_str="$tgt_full"
                # Last-resort truncation only if terminal is extremely narrow
                if (( ${#cont_str} > _tgt_avail )); then
                    cont_str="${cont_str:0:$(( _tgt_avail - 1 ))}~"
                fi
                printf '%*s%b↳ %s%b\n' \
                    "$_tgt_indent" "" \
                    "$CYAN" "$cont_str" "$NC"
            fi

            # ── TCP / flag / netem annotations ──────────────────────────
            local ex=""
            [[ -n "${S_CCA[$i]}"    ]] && ex+=" CCA:${S_CCA[$i]}"
            [[ -n "${S_WINDOW[$i]}" ]] && ex+=" Win:${S_WINDOW[$i]}"
            [[ -n "${S_MSS[$i]}"    ]] && ex+=" MSS:${S_MSS[$i]}"
            (( S_REVERSE[$i]  == 1 )) && ex+=" [REV]"
            (( S_PARALLEL[$i] >  1 )) && ex+=" P:${S_PARALLEL[$i]}"
            if [[ "$OS_TYPE" == "linux" ]]; then
                [[ -n "${S_DELAY[$i]}"  ]] && ex+=" delay:${S_DELAY[$i]}ms"
                [[ -n "${S_JITTER[$i]}" ]] && ex+=" jitter:${S_JITTER[$i]}ms"
                [[ -n "${S_LOSS[$i]}"   ]] && ex+=" loss:${S_LOSS[$i]}%"
            fi
            [[ "${S_BIDIR[$i]:-0}" == "1" ]] && \
                ex+=" ${GREEN}[BIDIR TX+RX]${NC}"
            [[ -n "$ex" ]] && \
                printf '%b    %s%b\n' "$CYAN" "$ex" "$NC"

            # ── Ramp profile annotation ──────────────────────────────────
            if [[ "${S_RAMP_ENABLED[$i]:-0}" == "1" ]]; then
                printf '%b    ramp: +%ds →  hold  %ds ←  (target: %s)%b\n' \
                    "$CYAN" \
                    "${S_RAMP_UP[$i]:-0}" \
                    "${S_RAMP_DOWN[$i]:-0}" \
                    "${S_BW[$i]:-unlimited}" \
                    "$NC"
            fi

            # ── FQDN resolved annotation ─────────────────────────────────
            # Only printed when:
            #   (a) a display name exists (FQDN was resolved), AND
            #   (b) the display name is different from the raw IP, AND
            #   (c) we did NOT already print a continuation line above
            #       (to avoid showing the same info twice)
            if (( need_cont == 0 )) && \
               [[ -n "${S_TARGET_DISPLAY[$i]:-}" ]] && \
               [[ "${S_TARGET_DISPLAY[$i]}" != "${S_TARGET[$i]:-}" ]]; then
                printf '%b    resolved: %s → %s%b\n' \
                    "$DIM" \
                    "${S_TARGET_DISPLAY[$i]%% (*}" \
                    "${S_TARGET[$i]}" \
                    "$NC"
            fi
        done

        # ── Footer separator ─────────────────────────────────────────────
        printf '  %s\n' "$(rpt '-' $_sep_len)"

    # ------------------------------------------------------------------
    # SERVER MODE
    # ------------------------------------------------------------------
    else

        # ── Column widths ────────────────────────────────────────────────
        local C_SN=3
        local C_PORT=7
        local C_BIND=18
        local C_VRF=12
        local C_ONEOFF=6

        # ── Column header ────────────────────────────────────────────────
        printf '  %-*s  %*s  %-*s  %-*s  %-*s\n' \
            "$C_SN"     "#" \
            "$C_PORT"   "Port" \
            "$C_BIND"   "Bind IP" \
            "$C_VRF"    "VRF" \
            "$C_ONEOFF" "1-off"

        local _srv_sep=$(( C_SN + 2 + C_PORT + 2 + C_BIND + 2 + \
                           C_VRF + 2 + C_ONEOFF ))
        printf '  %s\n' "$(rpt '-' $_srv_sep)"

        # ── Data rows ────────────────────────────────────────────────────
        local i
        for (( i=0; i<SERVER_COUNT; i++ )); do
            local sn=$(( i + 1 ))
            local oo="no"
            (( SRV_ONEOFF[$i] )) && oo="yes"

            local vrf_disp="${SRV_VRF[$i]:-GRT}"
            [[ "$OS_TYPE" == "macos" ]] && vrf_disp="N/A"

            local bind_disp="${SRV_BIND[$i]:-0.0.0.0}"

            if (( ${#bind_disp} > C_BIND )); then
                bind_disp="${bind_disp:0:$(( C_BIND - 1 ))}~"
            fi
            if (( ${#vrf_disp} > C_VRF )); then
                vrf_disp="${vrf_disp:0:$(( C_VRF - 1 ))}~"
            fi

            printf '  %-*s  %*s  %-*s  %-*s  %-*s\n' \
                "$C_SN"     "$sn" \
                "$C_PORT"   "${SRV_PORT[$i]}" \
                "$C_BIND"   "$bind_disp" \
                "$C_VRF"    "$vrf_disp" \
                "$C_ONEOFF" "$oo"
        done

        printf '  %s\n' "$(rpt '-' $_srv_sep)"

    fi

    echo ""
}

# ---------------------------------------------------------------------------
# _rtt_launch  <stream_idx>
#
# Starts a continuous background ping (1 packet/sec, indefinite) targeting
# the same IP as the iperf3 stream.  The full output is written to a log
# file that _rtt_parse reads on every tick.
#
# The ping is launched AFTER the iperf3 client so it does not consume any
# connection setup time.  It runs until _rtt_stop is called or the script
# exits via the cleanup trap.
# ---------------------------------------------------------------------------
_rtt_launch() {
    local idx="$1"
    local target="${S_TARGET[$idx]:-}"
    local vrf="${S_VRF[$idx]:-}"
    local bind_ip="${S_BIND[$idx]:-}"
    local logfile="${TMPDIR}/rtt_${idx}.log"

    # Initialise state arrays for this index
    PING_LOGFILES[$idx]="$logfile"
    S_RTT_MIN[$idx]="---"
    S_RTT_AVG[$idx]="---"
    S_RTT_MAX[$idx]="---"
    S_RTT_JITTER[$idx]="---"
    S_RTT_LOSS[$idx]="---"
    S_RTT_SAMPLES[$idx]="0"

    # Do not launch ping for loopback targets — RTT is always <0.1 ms and
    # the values add no diagnostic value for loopback validation tests.
    if [[ "$target" =~ ^127\. || "$target" == "::1" ]]; then
        PING_PIDS[$idx]=0
        return 0
    fi

    # Build the ping command appropriate for the platform and stream config
    local ping_cmd=""

    if [[ "$OS_TYPE" == "linux" ]]; then
        # Base: continuous ping, 1 packet/sec, numeric output
        ping_cmd="ping -i 1 -n"

        # Source bind IP — forces ping to use the same interface as iperf3
        if [[ -n "$bind_ip" && "$bind_ip" != "0.0.0.0" ]]; then
            ping_cmd+=" -I ${bind_ip}"
        fi

        ping_cmd+=" ${target}"

        # VRF: wrap the entire ping command with ip vrf exec
        if [[ -n "$vrf" ]]; then
            ping_cmd="ip vrf exec ${vrf} ${ping_cmd}"
        fi

    else
        # macOS: no VRF support, -S for source address, -n numeric
        ping_cmd="ping -i 1 -n"
        if [[ -n "$bind_ip" && "$bind_ip" != "0.0.0.0" ]]; then
            ping_cmd+=" -S ${bind_ip}"
        fi
        ping_cmd+=" ${target}"
    fi

    # Launch ping in background, capturing all output to the log file
    eval "$ping_cmd" > "$logfile" 2>&1 &
    PING_PIDS[$idx]=$!
}

# ---------------------------------------------------------------------------
# _rtt_parse  <stream_idx>
#
# Reads the ping log for the given stream and extracts the latest RTT
# statistics.  Called on every dashboard tick (once per second).
#
# Parsing strategy:
#   1. Count total reply lines to get sample count.
#   2. Extract the RTT from the most recent reply line for the "last" value.
#   3. Compute running min/avg/max/jitter by scanning all reply lines
#      accumulated so far.  This approach works correctly even when the
#      ping process has not yet printed a summary line (which only appears
#      after ping is killed).
#
# The jitter (mdev) is calculated as the mean absolute deviation of the
# individual RTT samples from their mean — this is the same metric that
# ping itself prints in its summary line.
#
# All calculations are performed in awk to avoid spawning bc or python.
# ---------------------------------------------------------------------------
_rtt_parse() {
    local idx="$1"
    local logfile="${PING_LOGFILES[$idx]:-}"

    [[ -z "$logfile" || ! -f "$logfile" || ! -s "$logfile" ]] && return

    # Use awk to parse all RTT data from the ping output in a single pass
    local result
    result=$(awk '
    BEGIN {
        count = 0
        sum   = 0
        min_v = -1
        max_v = 0
        loss_pct = "---"
    }

    # Match individual reply lines containing RTT.
    # Linux format:  64 bytes from 10.0.0.1: icmp_seq=1 ttl=64 time=1.23 ms
    # macOS format:  64 bytes from 10.0.0.1: icmp_seq=0 ttl=64 time=1.234 ms
    /bytes from .* time=/ {
        # Extract the time value after "time="
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^time=/) {
                sub(/^time=/, "", $i)
                rtt = $i + 0
                count++
                sum += rtt
                if (min_v < 0 || rtt < min_v) min_v = rtt
                if (rtt > max_v) max_v = rtt
                rtts[count] = rtt
            }
        }
    }

    # Match packet loss summary line (printed when ping is killed/ends)
    # Linux:  3 packets transmitted, 3 received, 0% packet loss
    # macOS:  3 packets transmitted, 3 packets received, 0.0% packet loss
    /packet loss/ {
        match($0, /[0-9.]+% packet loss/)
        if (RSTART > 0) {
            loss_pct = substr($0, RSTART, RLENGTH)
            # Strip "packet loss" leaving just the percentage
            sub(/ packet loss/, "", loss_pct)
        }
    }

    END {
        if (count == 0) {
            print "---:---:---:---:---:0"
            exit
        }

        avg = sum / count

        # Calculate mdev (mean absolute deviation) for jitter
        mdev_sum = 0
        for (i = 1; i <= count; i++) {
            diff = rtts[i] - avg
            if (diff < 0) diff = -diff
            mdev_sum += diff
        }
        mdev = (count > 0) ? mdev_sum / count : 0

        # Format: min:avg:max:jitter:loss:count
        printf "%.3f:%.3f:%.3f:%.3f:%s:%d",
            min_v, avg, max_v, mdev,
            (loss_pct == "---" ? "0%" : loss_pct),
            count
    }
    ' "$logfile" 2>/dev/null)

    [[ -z "$result" ]] && return

    # Split the colon-separated result into individual fields
    local rtt_min rtt_avg rtt_max rtt_jitter rtt_loss rtt_count
    IFS=':' read -r rtt_min rtt_avg rtt_max rtt_jitter rtt_loss rtt_count <<< "$result"

    S_RTT_MIN[$idx]="${rtt_min:-???}"
    S_RTT_AVG[$idx]="${rtt_avg:-???}"
    S_RTT_MAX[$idx]="${rtt_max:-???}"
    S_RTT_JITTER[$idx]="${rtt_jitter:-???}"
    S_RTT_LOSS[$idx]="${rtt_loss:-???}"
    S_RTT_SAMPLES[$idx]="${rtt_count:-0}"
}


# ---------------------------------------------------------------------------
# _cwnd_parse  <stream_idx>
#
# Parses the congestion window (cwnd) from the iperf3 TCP stream log.
#
# iperf3 TCP verbose output format (per-interval line):
#   [  5]   0.00-1.00   sec   128 KBytes  1.05 Mbits/sec    0   90.5 KBytes
#                                                            ^    ^^^^^^^^^
#                                                         retr      cwnd
#
# The cwnd field is the LAST field on TCP interval lines reported in
# KBytes. UDP lines do not have a cwnd field and are safely ignored.
# For --bidir streams the [TX-C] tagged lines carry the cwnd for TX.
#
# Called once per dashboard tick for each CONNECTED TCP stream.
# ---------------------------------------------------------------------------
_cwnd_parse() {
    local idx="$1"
    local logfile="${S_LOGFILE[$idx]:-}"

    [[ -z "$logfile" || ! -f "$logfile" || ! -s "$logfile" ]] && return
    [[ "${S_PROTO[$idx]:-TCP}" != "TCP" ]] && return

    # Extract the most recent interval line that ends with "NNN KBytes"
    # (the cwnd field). Both plain and --bidir [TX-C] tagged lines match.
    local last_line
    last_line=$(grep -E '[0-9.]+-[0-9.]+[[:space:]]+sec' "$logfile" 2>/dev/null \
        | grep -vE '[[:space:]](sender|receiver)[[:space:]]*$' \
        | grep -E '[[:space:]][0-9]+(\.[0-9]+)?[[:space:]]+KBytes[[:space:]]*$' \
        | tail -1)

    [[ -z "$last_line" ]] && return

    # Extract cwnd: second-to-last field when last field is "KBytes"
    local cwnd_val
    cwnd_val=$(printf '%s\n' "$last_line" | awk '
        { if ($NF == "KBytes" && $(NF-1)+0 > 0) printf "%.1f", $(NF-1)+0 }')

    [[ -z "$cwnd_val" || "$cwnd_val" == "0.0" ]] && return

    # Update current value
    S_CWND_CURRENT[$idx]="$cwnd_val"
    S_CWND_SAMPLES[$idx]=$(( ${S_CWND_SAMPLES[$idx]:-0} + 1 ))

    # Running sum for average
    local prev_sum="${S_CWND_SUM[$idx]:-0}"
    S_CWND_SUM[$idx]=$(awk -v s="$prev_sum" -v v="$cwnd_val" \
        'BEGIN { printf "%.1f", s + v }')

    # Update min
    local cur_min="${S_CWND_MIN[$idx]:-}"
    if [[ -z "$cur_min" || "$cur_min" == "---" ]]; then
        S_CWND_MIN[$idx]="$cwnd_val"
    else
        S_CWND_MIN[$idx]=$(awk -v a="$cur_min" -v b="$cwnd_val" \
            'BEGIN { printf "%.1f", (b < a) ? b : a }')
    fi

    # Update max
    local cur_max="${S_CWND_MAX[$idx]:-0}"
    S_CWND_MAX[$idx]=$(awk -v a="$cur_max" -v b="$cwnd_val" \
        'BEGIN { printf "%.1f", (b > a) ? b : a }')

    # Always update final to most recent value
    S_CWND_FINAL[$idx]="$cwnd_val"
}

# ---------------------------------------------------------------------------
# _cwnd_avg  <stream_idx>
#
# Returns the running average cwnd as a formatted float string.
# Safe to call at any time — returns "---" when no samples exist.
# ---------------------------------------------------------------------------
_cwnd_avg() {
    local idx="$1"
    local samples="${S_CWND_SAMPLES[$idx]:-0}"
    local sum="${S_CWND_SUM[$idx]:-0}"

    if (( samples == 0 )); then
        printf '%s' "---"
        return
    fi

    awk -v s="$sum" -v n="$samples" \
        'BEGIN { printf "%.1f", s / n }'
}

# ---------------------------------------------------------------------------
# _cleanup_stream_procs  <stream_index>
#
# Phase 1 cleanup: terminates all processes associated with a finished stream.
# Called immediately when a stream reaches DONE or FAILED state during the
# dashboard loop.
#
# Does NOT delete log files — those are needed by parse_final_results() and
# display_results_table() which run after the dashboard exits.
# File deletion is handled separately by _cleanup_stream_files() which is
# called from run_client_mode() after results have been displayed.
#
# After this function completes:
#   STREAM_PIDS[$idx] = 0
#   PING_PIDS[$idx]   = 0
#   BIDIR_PIDS[$idx]  = 0
#   S_STATUS_CACHE[$idx] = "CLEANED"
#   G_LAST_NOTIFY updated with timestamped message
# ---------------------------------------------------------------------------
_cleanup_stream_procs() {
    local idx="$1"
    local sn=$(( idx + 1 ))
    local label="Stream-${sn}"
    local _log_file="/tmp/iperf3_streams_events.log"

    _cs_log() {
        printf '[%s]  %s\n' "$(date +%T)" "$*" >> "$_log_file"
    }

    # ── Guarantee CLEANED is always set when this function exits ──────────
    # If any step below fails silently (subprocess error, timeout, etc.)
    # the trap ensures the state machine can still progress to exit.
    # Without this, a failed step leaves S_STATUS_CACHE in CLEANUP_PENDING
    # or DONE forever, causing the dashboard to loop indefinitely.
    local _cleanup_idx="$idx"
    trap 'S_STATUS_CACHE[$_cleanup_idx]="CLEANED"' RETURN

    # ─────────────── 1. Terminate iperf3 client process ────────────────────────────────
    local cpid="${STREAM_PIDS[$idx]:-0}"
    if [[ "$cpid" != "0" && "$cpid" =~ ^[0-9]+$ ]]; then
        if kill -0 "$cpid" 2>/dev/null; then
            kill -SIGTERM "$cpid" 2>/dev/null
            local _w=0
            while kill -0 "$cpid" 2>/dev/null && (( _w < 6 )); do
                sleep 0.5; (( _w++ )) || true
            done
            kill -0 "$cpid" 2>/dev/null && kill -SIGKILL "$cpid" 2>/dev/null
            wait "$cpid" 2>/dev/null
        fi
        STREAM_PIDS[$idx]=0
    fi

    # ── 2. Terminate RTT background ping ──────────────────────────────────
    # Try the stored PID first. If it is 0 or already dead, also check
    # PING_LOGFILES[$idx] — the ping process writes to a known log path
    # so we can find and kill it by matching the log file argument.
    local rpid="${PING_PIDS[$idx]:-0}"
    if [[ "$rpid" != "0" && "$rpid" =~ ^[0-9]+$ ]]; then
        if kill -0 "$rpid" 2>/dev/null; then
            kill -SIGTERM "$rpid" 2>/dev/null
            sleep 0.3
            kill -0 "$rpid" 2>/dev/null && kill -SIGKILL "$rpid" 2>/dev/null
            wait "$rpid" 2>/dev/null
        fi
        PING_PIDS[$idx]=0
    fi

    # Fallback: find ping process by log file path — with timeout guard
    local rtt_log="${PING_LOGFILES[$idx]:-${TMPDIR}/rtt_${idx}.log}"
    if [[ -n "$rtt_log" ]]; then
        local stray_pid
        if [[ "$OS_TYPE" == "linux" ]]; then
            stray_pid=$(timeout 2 fuser "$rtt_log" 2>/dev/null \
                | tr ' ' '\n' | grep -E '^[0-9]+$' | head -1)
        else
            stray_pid=$(timeout 2 lsof -t "$rtt_log" 2>/dev/null | head -1)
        fi
        if [[ -n "$stray_pid" && "$stray_pid" =~ ^[0-9]+$ ]]; then
            if kill -0 "$stray_pid" 2>/dev/null; then
                kill -SIGTERM "$stray_pid" 2>/dev/null
                sleep 0.2
                kill -0 "$stray_pid" 2>/dev/null && \
                    kill -SIGKILL "$stray_pid" 2>/dev/null
                wait "$stray_pid" 2>/dev/null
            fi
        fi
        PING_PIDS[$idx]=0
    fi

    # ── 3. Terminate bidir reverse process ────────────────────────────────
    local bpid="${BIDIR_PIDS[$idx]:-0}"
    if [[ "$bpid" != "0" && "$bpid" =~ ^[0-9]+$ ]]; then
        if kill -0 "$bpid" 2>/dev/null; then
            kill -SIGTERM "$bpid" 2>/dev/null
            sleep 0.3
            kill -0 "$bpid" 2>/dev/null && kill -SIGKILL "$bpid" 2>/dev/null
            wait "$bpid" 2>/dev/null
        fi
        BIDIR_PIDS[$idx]=0
    fi

    # Bidir fallback — also with timeout
    local bidir_log="${BIDIR_LOGFILES[$idx]:-}"
    if [[ -n "$bidir_log" && "$bidir_log" != "${S_LOGFILE[$idx]:-}" ]]; then
        local stray_bpid=""
        if [[ "$OS_TYPE" == "linux" ]]; then
            stray_bpid=$(timeout 2 fuser "$bidir_log" 2>/dev/null \
                | tr ' ' '\n' | grep -E '^[0-9]+$' | head -1)
        else
            stray_bpid=$(timeout 2 lsof -t "$bidir_log" 2>/dev/null | head -1)
        fi
        if [[ -n "$stray_bpid" && "$stray_bpid" =~ ^[0-9]+$ ]]; then
            if kill -0 "$stray_bpid" 2>/dev/null; then
                kill -SIGTERM "$stray_bpid" 2>/dev/null
                sleep 0.2
                kill -0 "$stray_bpid" 2>/dev/null && \
                    kill -SIGKILL "$stray_bpid" 2>/dev/null
                wait "$stray_bpid" 2>/dev/null
            fi
        fi
        BIDIR_PIDS[$idx]=0
    fi

    # ── 4. Remove tc netem for this stream ────────────────────────────────
    # Lifts network impairment on the stream's egress interface immediately
    # when the stream finishes. Does nothing if netem was not configured
    # for this stream or if it was already removed.
    if [[ "$OS_TYPE" == "linux" ]]; then
        _remove_netem_for_stream "$idx"
    fi

    # ── 5. Clear sparkline ring buffers ───────────────────────────────────
    _spark_clear "c" "$idx"
    _spark_clear "r" "$idx"


    # ── 5b. Remove ramp tc shaping if active ─────────────────────────────
    if [[ "${S_RAMP_ENABLED[$idx]:-0}" == "1" ]]; then
        _ramp_remove_tc "$idx"
        # Snapshot the rendered curve BEFORE clearing the ring buffer
        # so display_results_table can still render it after cleanup.
        S_RAMP_TIMELINE_SNAPSHOT[$idx]=$(_ramp_timeline_render "$idx" 36)
        _ramp_timeline_clear "$idx"
        S_RAMP_PHASE[$idx]="DONE"
        S_RAMP_TC_ACTIVE[$idx]=0
    fi

    # ── 6. Set terminal state and post notification ────────────────────────
    S_STATUS_CACHE[$idx]="CLEANED"

    local ts; ts="$(date '+%H:%M:%S')"
    local _new_note="[${ts}] ✔  ${label}: processes stopped"
    local _existing; _existing="$(_assoc_get G_NOTIFY_LOG 0 2>/dev/null)"
    local _trimmed
    _trimmed="$(printf '%s\n' "$_existing" "$_new_note" \
        | grep -v '^$' | tail -3)"
    _assoc_set G_NOTIFY_LOG 0 "$_trimmed"
    _assoc_set G_LAST_NOTIFY 0 "$_new_note"
}

# ---------------------------------------------------------------------------
# _cleanup_stream_files  <stream_index>
#
# Phase 2 cleanup: deletes all temporary files for a finished stream.
# Must only be called AFTER parse_final_results() and display_results_table()
# have completed so that log data is available for the results table.
#
# Deletes:
#   ${TMPDIR}/stream_<sn>.log
#   ${TMPDIR}/stream_<sn>.sh
#   ${TMPDIR}/rtt_<idx>.log
#   ${TMPDIR}/bidir_<sn>.log
#   ${TMPDIR}/bidir_<sn>.sh
# ---------------------------------------------------------------------------
_cleanup_stream_files() {
    local idx="$1"
    local sn=$(( idx + 1 ))
    local files_removed=0

    local -a targets=(
        "${TMPDIR}/stream_${sn}.log"
        "${TMPDIR}/stream_${sn}.sh"
        "${TMPDIR}/rtt_${idx}.log"
        "${TMPDIR}/bidir_${sn}.log"
        "${TMPDIR}/bidir_${sn}.sh"
    )

    local f
    for f in "${targets[@]}"; do
        if [[ -f "$f" ]]; then
            rm -f "$f" && (( files_removed++ )) || true
        fi
    done

    local ts; ts="$(date '+%H:%M:%S')"
    printf '%b[CLEANUP]%b  stream %d  %d file(s) removed\n' \
        "$CYAN" "$NC" "$sn" "$files_removed"
}

# ---------------------------------------------------------------------------
# _rtt_stop  <stream_idx>
#
# Gracefully terminates the background ping process for the given stream.
# Called from cleanup and when a stream completes normally.
# ---------------------------------------------------------------------------
_rtt_stop() {
    local idx="$1"
    local pid="${PING_PIDS[$idx]:-0}"
    [[ "$pid" == "0" ]] && return
    kill -TERM "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    PING_PIDS[$idx]=0
}

# ---------------------------------------------------------------------------
# _rtt_display  <stream_idx>
#
# Returns a formatted RTT statistics string that fits exactly within the
# dashboard box inner width.  Called once per stream per dashboard tick.
#
# Fixed layout (fits within 76 printable chars at COLS=80):
#   "  RTT  min:NNNNN  avg:NNNNN  max:NNNNN  jitter:NNNNN  loss:NNN  (NN smpl)"
#
# Colour coding:
#   Green   avg < 10 ms     excellent
#   Cyan    avg 10–50 ms    good
#   Yellow  avg 50–150 ms   acceptable
#   Red     avg > 150 ms    high latency / any packet loss > 0
# ---------------------------------------------------------------------------
_rtt_display() {
    local idx="$1"
    local rtt_min="${S_RTT_MIN[$idx]:-}"
    local rtt_avg="${S_RTT_AVG[$idx]:-}"
    local rtt_max="${S_RTT_MAX[$idx]:-}"
    local rtt_jitter="${S_RTT_JITTER[$idx]:-}"
    local rtt_loss="${S_RTT_LOSS[$idx]:-}"
    local rtt_count="${S_RTT_SAMPLES[$idx]:-0}"

    # No data yet — return fixed-width placeholder
    if [[ -z "$rtt_avg" || "$rtt_avg" == "---" || "$rtt_count" == "0" ]]; then
        printf '%s' "${DIM}  RTT  Waiting for samples...${NC}"
        return
    fi

    # ── Colour for average RTT ────────────────────────────────────────────
    local avg_col="$GREEN"
    local avg_int
    avg_int=$(printf '%.0f' "$rtt_avg" 2>/dev/null || printf '9999')
    if   (( avg_int > 150 )); then avg_col="$RED"
    elif (( avg_int > 50  )); then avg_col="$YELLOW"
    elif (( avg_int > 10  )); then avg_col="$CYAN"
    fi

    # ── Colour for packet loss ────────────────────────────────────────────
    local loss_col="$GREEN"
    local loss_num
    loss_num=$(printf '%s' "$rtt_loss" | tr -d '%')
    local loss_int
    loss_int=$(printf '%.0f' "${loss_num:-0}" 2>/dev/null || printf '0')
    (( loss_int > 0 )) && loss_col="$RED"

    # ── Format each field to a fixed visible width ────────────────────────
    # Pad numeric strings to 7 chars (e.g. "  1.234") so columns align
    # regardless of whether RTT is sub-1ms or 3-digit ms.
    local f_min f_avg f_max f_jitter f_loss f_samp
    f_min=$(printf '%7.3f' "$rtt_min"    2>/dev/null || printf '%7s' "$rtt_min")
    f_avg=$(printf '%7.3f' "$rtt_avg"    2>/dev/null || printf '%7s' "$rtt_avg")
    f_max=$(printf '%7.3f' "$rtt_max"    2>/dev/null || printf '%7s' "$rtt_max")
    f_jitter=$(printf '%6.3f' "$rtt_jitter" 2>/dev/null || printf '%6s' "$rtt_jitter")
    f_loss=$(printf '%4s' "$rtt_loss")
    f_samp=$(printf '%4d' "$rtt_count"   2>/dev/null || printf '%4s' "$rtt_count")

    printf '%s' \
        "  ${DIM}RTT${NC}" \
        "  ${DIM}min${NC} ${GREEN}${f_min}${NC}${DIM}ms${NC}" \
        "  ${DIM}avg${NC} ${avg_col}${f_avg}${NC}${DIM}ms${NC}" \
        "  ${DIM}max${NC} ${YELLOW}${f_max}${NC}${DIM}ms${NC}" \
        "  ${DIM}jitter${NC} ${CYAN}${f_jitter}${NC}${DIM}ms${NC}" \
        "  ${DIM}loss${NC} ${loss_col}${f_loss}${NC}" \
        "  ${DIM}(${f_samp} smpl)${NC}"
}

# =============================================================================
# SECTION 9c — BIDIRECTIONAL ENGINE
# =============================================================================
#
# For each stream marked S_BIDIR[$i]=1 a second iperf3 client process is
# launched with the --reverse flag.  This causes the server to send data
# back to the client, measuring RX (receive) bandwidth simultaneously with
# the TX (transmit) stream.
#
# Both processes share the same server port and target.  iperf3 supports
# parallel forward+reverse connections on the same port natively.
#
# The forward process  → measures TX (client sends to server)
# The reverse process  → measures RX (server sends to client)
#
# Live bandwidth for each direction is parsed independently from separate
# log files and displayed side-by-side in the dashboard.
#
# Public API:
#   _bidir_build_cmd  <stream_idx>   build the reverse iperf3 command string
#   _bidir_launch     <stream_idx>   start the reverse process
#   _bidir_parse_bw   <stream_idx>   read latest RX BW from reverse log
#   _bidir_stop       <stream_idx>   kill the reverse process
# =============================================================================

# ---------------------------------------------------------------------------
# _bidir_build_cmd  <stream_idx>
#
# Builds the reverse iperf3 command for a bidirectional stream.
# Identical to the forward command but with --reverse appended and the
# original --reverse flag removed (to avoid double-reversing).
# Uses the same VRF, bind IP, port, duration, parallel, DSCP settings.
# ---------------------------------------------------------------------------

_bidir_build_cmd() {
    # This function is only called when BIDIR_SUPPORTED=0 (legacy mode).
    # When BIDIR_SUPPORTED=1 the --bidir flag is added to the forward
    # command in build_client_command and no separate process is needed.
    local idx="$1"

    local stream_vrf="${S_VRF[$idx]:-}"
    local stream_bind="${S_BIND[$idx]:-}"
    local target="${S_TARGET[$idx]:-}"
    local port="${S_PORT[$idx]:-}"
    local duration="${S_DURATION[$idx]:-10}"
    local parallel="${S_PARALLEL[$idx]:-1}"
    local protocol="${S_PROTO[$idx]:-TCP}"
    local bw="${S_BW[$idx]:-}"
    local dscp="${S_DSCP_VAL[$idx]:--1}"
    local cca="${S_CCA[$idx]:-}"
    local win="${S_WINDOW[$idx]:-}"
    local mss="${S_MSS[$idx]:-}"
    local nofq="${S_NOFQ[$idx]:-0}"

    # VRF / GRT guard
    if [[ "$OS_TYPE" == "linux" && -n "$stream_vrf" && \
          -n "$stream_bind" && "$stream_bind" != "0.0.0.0" ]]; then
        local _actual_vrf="GRT"
        local _ki
        for (( _ki=0; _ki<${#IFACE_IPS[@]}; _ki++ )); do
            if [[ "${IFACE_IPS[$_ki]}" == "$stream_bind" ]]; then
                _actual_vrf="${IFACE_VRFS[$_ki]:-GRT}"
                break
            fi
        done
        [[ "$_actual_vrf" == "GRT" ]] && stream_vrf=""
    fi

    local cmd=""
    [[ "$OS_TYPE" == "linux" && -n "$stream_vrf" ]] && \
        cmd="ip vrf exec ${stream_vrf} "

    cmd+="${IPERF3_BIN} -c ${target} -p ${port}"
    [[ "$protocol" == "UDP" ]] && cmd+=" -u"
    [[ -n "$bw" ]] && cmd+=" -b ${bw}"

    if (( duration == 0 )); then
        version_ge 3 1 && cmd+=" -t 0" || cmd+=" -t 86400"
    else
        cmd+=" -t ${duration}"
    fi

    cmd+=" -i 1"
    (( parallel > 1 )) && cmd+=" -P ${parallel}"
    cmd+=" --reverse"

    [[ -n "$dscp" ]] && (( dscp >= 0 )) && \
        cmd+=" -S $(( dscp * 4 ))"
    [[ -n "$cca" ]] && cmd+=" -C ${cca}"
    [[ -n "$win" ]] && cmd+=" -w ${win}"
    [[ -n "$mss" ]] && cmd+=" -M ${mss}"
    [[ -n "$stream_bind" ]] && cmd+=" -B ${stream_bind}"

    if [[ "$OS_TYPE" == "linux" ]]; then
        (( nofq )) && (( NOFQ_SUPPORTED )) && \
            cmd+=" --no-fq-socket-pacing"
    fi

    (( FORCEFLUSH_SUPPORTED )) && cmd+=" --forceflush"

    printf '%s' "$cmd"
}

# ---------------------------------------------------------------------------
# _bidir_launch  <stream_idx>
#
# Starts the reverse iperf3 process for a bidirectional stream.
# Called immediately after the forward process is launched.
# ---------------------------------------------------------------------------
_bidir_launch() {
    local idx="$1"

    # Initialise state for this index
    BIDIR_PIDS[$idx]=0
    BIDIR_LOGFILES[$idx]=""
    S_BIDIR_BW[$idx]="---"

    [[ "${S_BIDIR[$idx]:-0}" != "1" ]] && return 0

    # When iperf3 supports --bidir the forward stream already handles both
    # directions in a single process.  No separate reverse process needed.
    # RX bandwidth is parsed from the forward log using _bidir_parse_bw.
    if (( BIDIR_SUPPORTED == 1 )); then
        # Point the bidir log at the forward stream log so _bidir_parse_bw
        # can parse the RX lines from the same log file.
        BIDIR_LOGFILES[$idx]="${S_LOGFILE[$idx]:-}"
        printf '%b[BIDIR  ]%b  stream %d  --bidir  ← RX via forward process\n' \
            "$CYAN" "$NC" "$(( idx + 1 ))"
        return 0
    fi

    # Legacy fallback: iperf3 < 3.7 — launch a separate reverse process.
    # This only works reliably when the server is not in --one-off mode
    # and can accept a second simultaneous connection.
    local sn=$(( idx + 1 ))
    local lf="${TMPDIR}/bidir_${sn}.log"
    local sf="${TMPDIR}/bidir_${sn}.sh"

    BIDIR_LOGFILES[$idx]="$lf"

    local cmd; cmd=$(_bidir_build_cmd "$idx")

    # Add a brief delay so the forward stream connects first
    {
        printf '#!/usr/bin/env bash\n'
        printf 'sleep 2\n'
        printf '%s\n' "$cmd"
    } > "$sf"
    chmod +x "$sf"

    bash "$sf" > "$lf" 2>&1 &
    local pid=$!
    BIDIR_PIDS[$idx]=$pid

    printf '%b[BIDIR  ]%b  stream %d  PID %-6d  ← RX (legacy --reverse)\n' \
        "$CYAN" "$NC" "$sn" "$pid"
}

# ---------------------------------------------------------------------------
# _bidir_parse_bw  <stream_idx>
#
# Reads the latest per-interval bandwidth from the reverse process log.
# Updates S_BIDIR_BW[$idx] and pushes to the "r" sparkline ring buffer.
# ---------------------------------------------------------------------------
_bidir_parse_bw() {
    local idx="$1"
    [[ "${S_BIDIR[$idx]:-0}" != "1" ]] && return

    local lf="${BIDIR_LOGFILES[$idx]:-}"
    [[ -z "$lf" || ! -f "$lf" || ! -s "$lf" ]] && return

    local bw=""

    if (( BIDIR_SUPPORTED == 1 )); then
        # ── iperf3 --bidir: parse [RX-C] tagged lines ─────────────────────
        bw=$(_parse_bidir_bw_from_log "$lf" "rx")
    else
        # ── Legacy --reverse: plain interval lines ────────────────────────
        bw=$(parse_live_bandwidth_from_log "$lf")
    fi

    if [[ -n "$bw" && "$bw" != "---" ]]; then
        S_BIDIR_BW[$idx]="$bw"
        _spark_push "r" "$idx" "$bw"
    fi
}

# ---------------------------------------------------------------------------
# _bidir_stop  <stream_idx>
#
# Terminates the reverse iperf3 process for a bidirectional stream.
# ---------------------------------------------------------------------------
_bidir_stop() {
    local idx="$1"
    local pid="${BIDIR_PIDS[$idx]:-0}"
    [[ "$pid" == "0" ]] && return
    kill -TERM "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    BIDIR_PIDS[$idx]=0
}

# ---------------------------------------------------------------------------
# _bidir_final_bw  <stream_idx>
#
# Returns the final sender BW from the reverse process log (for results table).
# ---------------------------------------------------------------------------

_bidir_final_bw() {
    local idx="$1"
    local lf="${BIDIR_LOGFILES[$idx]:-}"
    [[ -z "$lf" || ! -f "$lf" ]] && { printf '%s' "N/A"; return; }

    local fbw=""

    if (( BIDIR_SUPPORTED == 1 )); then
        # RX summary from [RX-C] tagged summary line
        local rx_line
        rx_line=$(grep -E '\[RX-C\].*receiver' "$lf" 2>/dev/null | tail -1)
        [[ -z "$rx_line" ]] && \
            rx_line=$(grep -E '\[RX-C\].*sender' "$lf" 2>/dev/null | tail -1)
        [[ -z "$rx_line" ]] && \
            rx_line=$(grep -E '\[RX-C\]' "$lf" 2>/dev/null \
                | grep -E 'sender|receiver' | tail -1)

        if [[ -n "$rx_line" ]]; then
            fbw=$(printf '%s\n' "$rx_line" \
                | awk '{for(i=1;i<=NF;i++) if($i~/[KMG]?bits\/sec/) print $(i-1),$i}' \
                | head -1)
            [[ -n "$fbw" ]] && fbw=$(_normalise_text_bw "$fbw")
        fi

        # Fallback to live RX parse
        [[ -z "$fbw" || "$fbw" == "---" ]] && \
            fbw=$(_parse_bidir_bw_from_log "$lf" "rx")
    else
        fbw=$(parse_final_bw_from_log "$lf" "receiver")
        [[ -z "$fbw" || "$fbw" == "---" ]] && \
            fbw=$(parse_final_bw_from_log "$lf" "sender")
        [[ -z "$fbw" || "$fbw" == "---" ]] && \
            fbw=$(parse_live_bandwidth_from_log "$lf")
    fi

    printf '%s' "${fbw:-N/A}"
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

    if [[ "$OS_TYPE" == "linux" && -n "$stream_bind" && \
          "$stream_bind" != "0.0.0.0" ]]; then

        # Determine which VRF (or GRT) actually owns the bind IP
        local _actual_vrf="GRT"
        local _ki
        for (( _ki=0; _ki<${#IFACE_IPS[@]}; _ki++ )); do
            if [[ "${IFACE_IPS[$_ki]}" == "$stream_bind" ]]; then
                _actual_vrf="${IFACE_VRFS[$_ki]:-GRT}"
                break
            fi
        done

        if [[ -n "$stream_vrf" ]]; then
            # A VRF was configured — verify the bind IP actually lives in it
            if [[ "$_actual_vrf" == "GRT" ]]; then
                # Bind IP is in GRT but VRF was set — clear VRF to prevent
                # "bad file descriptor" error at iperf3 socket bind time
                printf '%b\n' \
                    "${YELLOW}  [WARN] Stream $((idx+1)): bind IP ${stream_bind} belongs to GRT" \
                    "but VRF '${stream_vrf}' was configured." \
                    "Clearing VRF to prevent bad file descriptor.${NC}" >&2
                stream_vrf=""
            elif [[ "$_actual_vrf" != "$stream_vrf" ]]; then
                # Bind IP is in a different VRF than configured — correct it
                printf '%b\n' \
                    "${YELLOW}  [WARN] Stream $((idx+1)): bind IP ${stream_bind} belongs to" \
                    "VRF '${_actual_vrf}', not '${stream_vrf}'." \
                    "Correcting VRF to '${_actual_vrf}'.${NC}" >&2
                stream_vrf="$_actual_vrf"
                [[ "$stream_vrf" == "GRT" ]] && stream_vrf=""
            fi
        else
            # No VRF was configured — auto-apply the correct one if the
            # bind IP lives in a VRF (prevents silent GRT-vs-VRF mismatch)
            if [[ "$_actual_vrf" != "GRT" && -n "$_actual_vrf" ]]; then
                printf '%b\n' \
                    "${CYAN}  [AUTO] Stream $((idx+1)): bind IP ${stream_bind} belongs to" \
                    "VRF '${_actual_vrf}'. Auto-applying VRF for correct routing.${NC}" >&2
                stream_vrf="$_actual_vrf"
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

    # Do not add -R when --bidir is enabled. The two flags are mutually
    # exclusive. --bidir already measures both TX and RX simultaneously.
    # Adding -R with --bidir causes iperf3 to exit immediately with:
    # "parameter error - cannot be both reverse and bidirectional"

    if (( S_REVERSE[$idx] == 1 )); then
        if [[ "${S_BIDIR[$idx]:-0}" != "1" || (( BIDIR_SUPPORTED == 0 )) ]]; then
            cmd+=" -R"
        fi
    fi
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

    # ────── Bidirectional via --bidir flag ──────────────────────
    # When bidir is enabled AND iperf3 supports --bidir, add the flag to
    # the forward stream command.  No separate reverse process is launched.
    # When BIDIR_SUPPORTED=0 the reverse process is handled by _bidir_launch.
    if [[ "${S_BIDIR[$idx]:-0}" == "1" ]] && (( BIDIR_SUPPORTED == 1 )); then
        cmd+=" --bidir"
    fi

    printf '%s' "$cmd"
}

write_launch_script() {
    local sf="$1" cmd="$2"
    [[ -d "$TMPDIR" ]] || { printf '%b\n' "${RED}ERROR: TMPDIR missing.${NC}"; return 1; }
    printf '#!/usr/bin/env bash\n%s\n' "$cmd" > "$sf"; chmod +x "$sf"
}

launch_servers() {
    SERVER_PIDS=()
    SRV_PREV_STATE=()
    SRV_BW_CACHE=()

    # ── Pre-launch VRF/bind consistency validation (server) ──────────────
    if [[ "$OS_TYPE" == "linux" ]]; then
        get_interface_list
        local _vi
        for (( _vi=0; _vi<SERVER_COUNT; _vi++ )); do
            local _vbind="${SRV_BIND[$_vi]:-}"
            local _vvrf="${SRV_VRF[$_vi]:-}"

            [[ -z "$_vbind" || "$_vbind" == "0.0.0.0" ]] && continue

            local _vactual="GRT"
            local _vki
            for (( _vki=0; _vki<${#IFACE_IPS[@]}; _vki++ )); do
                if [[ "${IFACE_IPS[$_vki]}" == "$_vbind" ]]; then
                    _vactual="${IFACE_VRFS[$_vki]:-GRT}"
                    break
                fi
            done

            if [[ -n "$_vvrf" && "$_vactual" == "GRT" ]]; then
                printf '%b\n' \
                    "${YELLOW}  [PRE-LAUNCH FIX] Listener $((_vi+1)):" \
                    "bind IP ${_vbind} is in GRT." \
                    "Clearing VRF '${_vvrf}' to prevent bad file descriptor.${NC}"
                SRV_VRF[$_vi]=""
            elif [[ -n "$_vvrf" && "$_vactual" != "GRT" && \
                    "$_vactual" != "$_vvrf" ]]; then
                printf '%b\n' \
                    "${YELLOW}  [PRE-LAUNCH FIX] Listener $((_vi+1)):" \
                    "bind IP ${_vbind} belongs to VRF '${_vactual}'," \
                    "not '${_vvrf}'. Correcting VRF.${NC}"
                SRV_VRF[$_vi]="$_vactual"
            elif [[ -z "$_vvrf" && "$_vactual" != "GRT" && \
                    -n "$_vactual" ]]; then
                printf '%b\n' \
                    "${CYAN}  [PRE-LAUNCH AUTO] Listener $((_vi+1)):" \
                    "bind IP ${_vbind} belongs to VRF '${_vactual}'." \
                    "Auto-applying VRF.${NC}"
                SRV_VRF[$_vi]="$_vactual"
            fi
        done
    fi

    local i
    for (( i=0; i<SERVER_COUNT; i++ )); do
        # ── FIX: compute sn FIRST, before any filename is constructed ──
        local sn=$(( i + 1 ))

        # ── Filenames now always use the correct 1-based index ──────────
        local sf="${TMPDIR}/server_${sn}.sh"
        local lf="${TMPDIR}/server_${sn}.log"

        # Persist log and script paths before attempting launch so that
        # cleanup() can find them even if write_launch_script fails.
        SRV_LOGFILE[$i]="$lf"
        SRV_SCRIPT[$i]="$sf"

        if ! write_launch_script "$sf" "$(build_server_command "$i")"; then
            printf '%b\n' \
                "${RED}  [ERROR] Cannot write script for server ${sn}.${NC}"
            SERVER_PIDS+=(0)
            SRV_PREV_STATE+=("")
            SRV_BW_CACHE+=("---")
            continue
        fi

        bash "$sf" > "$lf" 2>&1 &
        local pid=$!

        SERVER_PIDS+=("$pid")
        SRV_PREV_STATE+=("")
        SRV_BW_CACHE+=("---")

        printf '%b[STARTED]%b  server %d  PID %-6d  port %s\n' \
            "$GREEN" "$NC" "$sn" "$pid" "${SRV_PORT[$i]}"
    done
}

launch_clients() {
    STREAM_PIDS=()
    # RTT ping tracking arrays
    PING_PIDS=()
    PING_LOGFILES=()

    # Initialise bidir tracking arrays
    BIDIR_PIDS=()
    BIDIR_LOGFILES=()

    # ── Pre-launch VRF/bind consistency validation ────────────────────────
    # Refresh the interface list so VRF membership data is current, then
    # verify each stream's bind IP / VRF combination before launching.
    # This catches mismatches that slipped through the configuration wizard
    # and prevents streams from failing immediately with "bad file descriptor".

    if [[ "$OS_TYPE" == "linux" ]]; then
        get_interface_list
        local _vi
        for (( _vi=0; _vi<STREAM_COUNT; _vi++ )); do
            local _vbind="${S_BIND[$_vi]:-}"
            local _vvrf="${S_VRF[$_vi]:-}"

            [[ -z "$_vbind" || "$_vbind" == "0.0.0.0" ]] && continue

            # Find the actual VRF that owns this bind IP
            local _vactual="GRT"
            local _vki
            for (( _vki=0; _vki<${#IFACE_IPS[@]}; _vki++ )); do
                if [[ "${IFACE_IPS[$_vki]}" == "$_vbind" ]]; then
                    _vactual="${IFACE_VRFS[$_vki]:-GRT}"
                    break
                fi
            done

            # Case 1: VRF set but bind IP is in GRT — clear VRF
            if [[ -n "$_vvrf" && "$_vactual" == "GRT" ]]; then
                printf '%b\n' \
                    "${YELLOW}  [PRE-LAUNCH FIX] Stream $((_vi+1)):" \
                    "bind IP ${_vbind} is in GRT." \
                    "Clearing VRF '${_vvrf}' to prevent bad file descriptor.${NC}"
                S_VRF[$_vi]=""

            # Case 2: VRF set to wrong VRF — correct it
            elif [[ -n "$_vvrf" && "$_vactual" != "GRT" && \
                    "$_vactual" != "$_vvrf" ]]; then
                printf '%b\n' \
                    "${YELLOW}  [PRE-LAUNCH FIX] Stream $((_vi+1)):" \
                    "bind IP ${_vbind} belongs to VRF '${_vactual}'," \
                    "not '${_vvrf}'. Correcting VRF.${NC}"
                S_VRF[$_vi]="$_vactual"

            # Case 3: No VRF set but bind IP is in a VRF — auto-apply
            elif [[ -z "$_vvrf" && "$_vactual" != "GRT" && \
                    -n "$_vactual" ]]; then
                printf '%b\n' \
                    "${CYAN}  [PRE-LAUNCH AUTO] Stream $((_vi+1)):" \
                    "bind IP ${_vbind} belongs to VRF '${_vactual}'." \
                    "Auto-applying VRF.${NC}"
                S_VRF[$_vi]="$_vactual"
            fi
        done
    fi

    local i

    for (( i=0; i<STREAM_COUNT; i++ )); do
        local sn=$(( i + 1 ))
        local sf="${TMPDIR}/stream_${sn}.sh"
        local lf="${TMPDIR}/stream_${sn}.log"

        if ! write_launch_script "$sf" "$(build_client_command "$i")"; then
            printf '%b\n' "${RED}  [ERROR] Cannot write script for stream ${sn}.${NC}"
            STREAM_PIDS+=(0)
            S_LOGFILE[$i]="$lf"
            S_STATUS_CACHE[$i]="FAILED"
            S_ERROR_MSG[$i]="Script creation failed"
            # Placeholder entries so all arrays stay index-aligned
            PING_PIDS+=(0)
            PING_LOGFILES+=("")
            # CWND arrays — initialise to sentinel values even on failure
            # so display_results_table and _render_client_frame never read
            # uninitialised variables for this stream index.
            S_CWND_CURRENT[$i]="---"
            S_CWND_MIN[$i]="---"
            S_CWND_MAX[$i]="---"
            S_CWND_FINAL[$i]="---"
            S_CWND_SAMPLES[$i]="0"
            S_CWND_SUM[$i]="0"

            # ── Initialise ramp profile arrays ───────────────────────────────
            # Sentinel values prevent dashboard display before ramp starts.
            S_RAMP_PHASE[$i]="RAMPUP"
            S_RAMP_PHASE_TS[$i]=0
            S_RAMP_BW_CURRENT[$i]="---"
            S_RAMP_TC_ACTIVE[$i]=0
            S_RAMP_TIMELINE_SNAPSHOT[$i]=""
            _ramp_timeline_clear "$i"
            continue
        fi

        S_SCRIPT[$i]="$sf"
        S_LOGFILE[$i]="$lf"
        S_START_TS[$i]=$(date +%s)
        S_STATUS_CACHE[$i]="STARTING"
        S_ERROR_MSG[$i]=""

        # ── Initialise CWND tracking arrays for this stream ───────────────
        # All fields are set to known-good sentinel values before launch so
        # the render functions never encounter uninitialised variables.
        #
        # Sentinel meanings:
        #   S_CWND_CURRENT  "---"  = no sample parsed yet
        #   S_CWND_MIN      "---"  = no sample parsed yet
        #   S_CWND_MAX      "---"  = no sample parsed yet  (not "0" to
        #                            avoid showing "0" in dashboard before
        #                            first sample arrives)
        #   S_CWND_FINAL    "---"  = stream not yet finished
        #   S_CWND_SAMPLES  "0"    = counter starts at zero
        #   S_CWND_SUM      "0"    = running sum starts at zero
        S_CWND_CURRENT[$i]="---"
        S_CWND_MIN[$i]="---"
        S_CWND_MAX[$i]="---"
        S_CWND_FINAL[$i]="---"
        S_CWND_SAMPLES[$i]="0"
        S_CWND_SUM[$i]="0"

        # ── Initialise ramp profile arrays ───────────────────────────────
        # Sentinel values prevent dashboard display before ramp starts.
        S_RAMP_PHASE[$i]="RAMPUP"
        S_RAMP_PHASE_TS[$i]=0
        S_RAMP_BW_CURRENT[$i]="---"
        S_RAMP_TC_ACTIVE[$i]=0
        S_RAMP_TIMELINE_SNAPSHOT[$i]=""
        _ramp_timeline_clear "$i"

        # ── Launch the iperf3 client process ─────────────────────────────
        bash "$sf" > "$lf" 2>&1 &
        local pid=$!
        STREAM_PIDS+=("$pid")

        printf '%b[STARTED]%b  stream %d  PID %-6d  %s -> %s:%s\n' \
            "$GREEN" "$NC" \
            "$sn" "$pid" \
            "${S_PROTO[$i]}" "${S_TARGET[$i]}" "${S_PORT[$i]}"

        # ── Launch RTT background ping ────────────────────────────────────
        # One continuous ping per stream, running in parallel with iperf3.
        # Skipped automatically for loopback targets inside _rtt_launch.
        _rtt_launch "$i"
        if [[ "${PING_PIDS[$i]:-0}" != "0" ]]; then
            printf '%b[PING   ]%b  stream %d  PID %-6d  rtt → %s\n' \
                "$CYAN" "$NC" \
                "$sn" "${PING_PIDS[$i]}" "${S_TARGET[$i]}"
        fi

        # ── Launch bidirectional reverse process ──────────────────────────
        # For streams with S_BIDIR=1:
        #   iperf3 >= 3.7: _bidir_launch points BIDIR_LOGFILES at the
        #                  forward log — no separate process needed.
        #   iperf3 <  3.7: _bidir_launch starts a separate --reverse
        #                  process with a 2-second startup delay.
        _bidir_launch "$i"

        # ── Start ramp profile if configured ─────────────────────────────
        if [[ "${S_RAMP_ENABLED[$i]:-0}" == "1" ]]; then
            _ramp_setup "$i"
            printf '%b[RAMP   ]%b  stream %d  +%ds ↑  hold  %ds ↓  target: %s\n' \
                "$CYAN" "$NC" \
                "$sn" \
                "${S_RAMP_UP[$i]}" \
                "${S_RAMP_DOWN[$i]}" \
                "${S_RAMP_BW_TARGET[$i]:-unlimited}"
        fi
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
        local dly="${S_DELAY[$i]:-}"
        local jit="${S_JITTER[$i]:-}"
        local loss="${S_LOSS[$i]:-}"

        # Initialise per-stream netem tracking to empty
        S_NETEM_IFACE[$i]=""

        [[ -z "$dly" && -z "$jit" && -z "$loss" ]] && continue

        if (( IS_ROOT == 0 )); then
            printf '%b\n' \
                "${YELLOW}  WARNING: tc netem skipped for stream $((i+1)) -- not root.${NC}"
            continue
        fi

        # ── Resolve egress interface via VRF-aware route lookup ────────────
        local oif=""
        local stream_vrf="${S_VRF[$i]:-}"
        local stream_target="${S_TARGET[$i]}"

        if command -v ip >/dev/null 2>&1; then
            if [[ -n "$stream_vrf" ]]; then
                # Primary: ip route get vrf <vrf> <target>  (kernel >= 4.12)
                oif=$(ip route get vrf "${stream_vrf}" "${stream_target}" \
                    2>/dev/null \
                    | grep -oE '\bdev [^ ]+' | awk '{print $2}' | head -1)
                # Fallback: ip vrf exec <vrf> ip route get <target>
                if [[ -z "$oif" ]]; then
                    oif=$(ip vrf exec "${stream_vrf}" \
                        ip route get "${stream_target}" 2>/dev/null \
                        | grep -oE '\bdev [^ ]+' | awk '{print $2}' | head -1)
                fi
            else
                oif=$(ip route get "${stream_target}" 2>/dev/null \
                    | grep -oE '\bdev [^ ]+' | awk '{print $2}' | head -1)
            fi
        fi

        if [[ -z "$oif" ]]; then
            local _vrf_hint=""
            [[ -n "$stream_vrf" ]] && _vrf_hint=" (VRF: ${stream_vrf})"
            printf '%b\n' \
                "${YELLOW}  WARNING: cannot resolve route for ${stream_target}${_vrf_hint}" \
                "-- netem skipped for stream $((i+1)).${NC}"
            continue
        fi

        if [[ "$oif" == lo || "$oif" == lo0 || "$oif" =~ ^lo[0-9] ]]; then
            printf '%b\n' \
                "${YELLOW}  WARNING: stream $((i+1)) routes via loopback (${oif})" \
                "-- netem skipped.${NC}"
            continue
        fi

        # ── Check for duplicate interface ──────────────────────────────────
        local already_applied=0
        local applied_iface
        for applied_iface in "${NETEM_IFACES[@]}"; do
            [[ "$applied_iface" == "$oif" ]] && already_applied=1 && break
        done

        if (( already_applied )); then
            # Still record the interface for this stream so cleanup works
            S_NETEM_IFACE[$i]="$oif"
            printf '%b  [NETEM  ]  dev %-12s  already applied -- shared by stream %d%b\n' \
                "$CYAN" "$oif" "$((i+1))" "$NC"
            continue
        fi

        # ── Read CURRENT netem values on this interface ────────────────────
        local cur_qdisc
        cur_qdisc=$(tc qdisc show dev "$oif" 2>/dev/null | head -1)

        local cur_delay="none" cur_jitter="none" cur_loss="none"
        if printf '%s' "$cur_qdisc" | grep -q 'netem'; then
            cur_delay=$(printf '%s' "$cur_qdisc" \
                | grep -oE 'delay [0-9]+(\.[0-9]+)?(ms|us|s)' \
                | awk '{print $2}' | head -1)
            [[ -z "$cur_delay" ]] && cur_delay="0ms"

            cur_jitter=$(printf '%s' "$cur_qdisc" \
                | grep -oE 'delay [0-9]+(\.[0-9]+)?(ms|us|s) [0-9]+(\.[0-9]+)?(ms|us|s)' \
                | awk '{print $3}' | head -1)
            [[ -z "$cur_jitter" ]] && cur_jitter="0ms"

            cur_loss=$(printf '%s' "$cur_qdisc" \
                | grep -oE 'loss [0-9]+(\.[0-9]+)?%' \
                | awk '{print $2}' | head -1)
            [[ -z "$cur_loss" ]] && cur_loss="0%"
        fi

        # ── Build tc netem command ─────────────────────────────────────────
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
            NETEM_IFACES+=("$oif")
            S_NETEM_IFACE[$i]="$oif"

            # ── Before/after table ─────────────────────────────────────────
            local inner=$(( COLS - 2 ))
            local vrf_label="${stream_vrf:-GRT}"
            local new_delay="${dly:+${dly}ms}"; [[ -z "$dly"  ]] && new_delay="0ms"
            local new_jitter="${jit:+${jit}ms}"; [[ -z "$jit" ]] && new_jitter="0ms"
            local new_loss="${loss:+${loss}%}"; [[ -z "$loss" ]] && new_loss="0%"

            printf '\n'
            printf '+%s+\n' "$(rpt '=' "$inner")"
            bcenter "${BOLD}${CYAN}tc netem Applied — Stream $((i+1))${NC}"
            printf '+%s+\n' "$(rpt '=' "$inner")"
            bleft "  Interface : ${BOLD}${oif}${NC}  ${DIM}(routing via ${vrf_label})${NC}"
            bleft "  Stream    : $((i+1))  ${S_PROTO[$i]} → ${stream_target}:${S_PORT[$i]}"
            printf '+%s+\n' "$(rpt '-' "$inner")"

            # Column widths
            local _CP=14 _CB=14 _CA=14 _CC=10

            bleft "${BOLD}$(printf '%-*s  %-*s  %-*s  %-*s' \
                "$_CP" 'Parameter' \
                "$_CB" 'Before' \
                "$_CA" 'After' \
                "$_CC" 'Change')${NC}"
            printf '+%s+\n' "$(rpt '-' "$inner")"

            # Helper: change label
            _netem_change_label() {
                local before="$1" after="$2" param_set="$3"
                if [[ "$before" == "none" && "$param_set" == "1" ]]; then
                    printf '%b' "${GREEN}added${NC}"
                elif [[ "$before" != "none" && "$before" != "$after" ]]; then
                    printf '%b' "${YELLOW}modified${NC}"
                elif [[ "$before" != "none" && "$before" == "$after" ]]; then
                    printf '%b' "${DIM}unchanged${NC}"
                else
                    printf '%b' "${DIM}---${NC}"
                fi
            }

            # Delay row
            local _d_before="$cur_delay"; [[ "$cur_delay" == "none" ]] && _d_before="${DIM}none${NC}"
            local _d_change; _d_change=$(_netem_change_label \
                "$cur_delay" "$new_delay" "${dly:+1}")
            bleft "$(printf '%-*s  %-*s  %-*s  ' \
                "$_CP" 'Delay' "$_CB" "$cur_delay" "$_CA" "$new_delay")${_d_change}"

            # Jitter row
            local _j_change; _j_change=$(_netem_change_label \
                "$cur_jitter" "$new_jitter" "${jit:+1}")
            bleft "$(printf '%-*s  %-*s  %-*s  ' \
                "$_CP" 'Jitter' "$_CB" "$cur_jitter" "$_CA" "$new_jitter")${_j_change}"

            # Loss row
            local _l_change; _l_change=$(_netem_change_label \
                "$cur_loss" "$new_loss" "${loss:+1}")
            bleft "$(printf '%-*s  %-*s  %-*s  ' \
                "$_CP" 'Packet Loss' "$_CB" "$cur_loss" "$_CA" "$new_loss")${_l_change}"

            printf '+%s+\n' "$(rpt '-' "$inner")"
            bleft "  ${GREEN}✔  netem applied to ${BOLD}${oif}${NC}${GREEN} — will be removed when stream finishes${NC}"
            bleft "  ${DIM}Command: ${nc}${NC}"
            printf '+%s+\n' "$(rpt '=' "$inner")"
            printf '\n'

        else
            printf '%b\n' \
                "${RED}  WARNING: tc netem failed on ${oif} for stream $((i+1)).${NC}"
        fi
    done
}

# ---------------------------------------------------------------------------
# _remove_netem_for_stream  <stream_index>
#
# Removes the tc netem qdisc from the egress interface that was configured
# for this specific stream. Called from _cleanup_stream_procs() so that
# netem impairment is lifted as soon as the stream finishes rather than
# waiting for the global cleanup() signal handler.
#
# Uses S_NETEM_IFACE[$idx] which is set by apply_netem() for each stream
# that had netem applied. Streams that shared an interface will each try
# to remove it — the second attempt is a safe no-op because tc returns
# an error when the qdisc is already gone (suppressed with 2>/dev/null).
#
# After removal the interface is removed from NETEM_IFACES so the global
# cleanup() handler does not attempt to remove it a second time.
# ---------------------------------------------------------------------------
_remove_netem_for_stream() {
    local idx="$1"
    local iface="${S_NETEM_IFACE[$idx]:-}"
    local _log_file="/tmp/iperf3_streams_events.log"

    [[ -z "$iface" ]] && return 0

    if tc qdisc del dev "$iface" root 2>/dev/null; then
        local ts; ts="$(date '+%H:%M:%S')"
        # Log to file — NOT stdout — dashboard owns stdout
        printf '[%s]  NETEM    dev %s  netem removed (stream %d finished)\n' \
            "$ts" "$iface" "$(( idx + 1 ))" >> "$_log_file"
    fi

    S_NETEM_IFACE[$idx]=""

    local new_netem_ifaces=()
    local entry
    for entry in "${NETEM_IFACES[@]}"; do
        [[ "$entry" != "$iface" ]] && new_netem_ifaces+=("$entry")
    done
    NETEM_IFACES=("${new_netem_ifaces[@]}")
    return 0
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

    # ── Detect the correct no-DNS flag for the installed binary ────────────
    #
    # traceroute variants handle DNS suppression differently:
    #
    #   GNU traceroute (Linux, most distros):
    #     Accepts:  --no-dns   (long form, always works)
    #     Does NOT accept: -n  (short form — invalid on GNU traceroute)
    #
    #   BSD traceroute (macOS, FreeBSD):
    #     Accepts:  -n         (short form)
    #
    #   tracepath (Linux iproute2):
    #     Accepts:  -n         (short form, suppresses DNS on modern versions)
    #
    # Detection strategy:
    #   1. Run "<binary> --help" and grep for "--no-dns".
    #      If present → GNU traceroute → use --no-dns.
    #   2. Otherwise assume BSD/tracepath style → use -n.
    #   3. Verify the chosen flag does not produce an error by running a
    #      dry-run against localhost. If it fails, fall back to no flag.
    #
    local no_dns_flag=""
    if [[ "$tr_type" == "traceroute" ]]; then
        local _help_out
        _help_out=$("${tr_bin}" --help 2>&1 || true)
        if printf '%s' "$_help_out" | grep -q '\-\-no-dns\|no.dns'; then
            # GNU traceroute — use long form
            no_dns_flag="--no-dns"
        else
            # BSD traceroute — use short form
            no_dns_flag="-n"
        fi

        # Verify the flag is accepted (dry-run with timeout)
        local _flag_test
        _flag_test=$(timeout 2 "${tr_bin}" ${no_dns_flag} -m 1 -w 1 127.0.0.1 \
            2>&1 | grep -c 'invalid option\|unrecognized option\|Unknown option' \
            || true)
        if (( _flag_test > 0 )); then
            # Flag not accepted — run without DNS suppression flag
            no_dns_flag=""
        fi
    elif [[ "$tr_type" == "tracepath" ]]; then
        # tracepath: test -n support
        local _tp_test
        _tp_test=$(timeout 2 "${tr_bin}" -n 127.0.0.1 2>&1 \
            | grep -c 'invalid option\|unrecognized option\|Unknown option' \
            || true)
        if (( _tp_test == 0 )); then
            no_dns_flag="-n"
        fi
    fi

    # ── Build and execute the traceroute command ───────────────────────────
    if [[ "$OS_TYPE" == "linux" && -n "$vrf_name" ]]; then
        if [[ "$tr_type" == "traceroute" ]]; then
            tr_out=$(sudo ip vrf exec "${vrf_name}" \
                "${tr_bin}" ${no_dns_flag} -m 20 -w 2 -q 1 "${target}" \
                2>/dev/tty | tail -n +2)
        else
            tr_out=$(sudo ip vrf exec "${vrf_name}" \
                "${tr_bin}" ${no_dns_flag} "${target}" \
                2>/dev/tty | tail -n +2)
        fi
    elif [[ "$OS_TYPE" == "linux" ]]; then
        if [[ "$tr_type" == "traceroute" ]]; then
            tr_out=$("${tr_bin}" ${no_dns_flag} -m 20 -w 2 -q 1 "${target}" \
                2>/dev/null | tail -n +2)
        else
            tr_out=$("${tr_bin}" ${no_dns_flag} "${target}" \
                2>/dev/null | tail -n +2)
        fi
    else
        # macOS — BSD traceroute always accepts -n
        if [[ "$tr_type" == "traceroute" ]]; then
            tr_out=$("${tr_bin}" ${no_dns_flag} -m 20 -q 1 "${target}" \
                2>/dev/null | tail -n +2)
        else
            tr_out=$("${tr_bin}" ${no_dns_flag} "${target}" \
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

        printf '  Checking  %s:%s  (%s / %s)...\n' \
            "$tgt" "$prt" "$pro" "$vrf_label"

        local ping_result
        ping_result=$(_preflight_ping_vrf "$tgt" "$vrf")
        local p_status p_rtt p_loss
        p_status=$(printf '%s' "$ping_result" | cut -d'|' -f1)
        p_rtt=$(printf '%s'    "$ping_result" | cut -d'|' -f2)
        p_loss=$(printf '%s'   "$ping_result" | cut -d'|' -f3)

        res_ping_status+=("$p_status")
        res_ping_rtt+=("$p_rtt")
        res_ping_loss+=("$p_loss")

        # ── FIX: use tr instead of ${pro^^} for Bash 3.2 compat ──────
        local pro_upper
        pro_upper=$(printf '%s' "$pro" | tr '[:lower:]' '[:upper:]')

        local t_status
        if [[ "$pro_upper" == "UDP" ]]; then
            t_status="SKIP"
        else
            t_status=$(_preflight_tcp_port_vrf "$tgt" "$prt" "$vrf")
        fi
        res_tcp_status+=("$t_status")

        local overall="PASS"
        if   [[ "$p_status" == "FAIL" || \
                "$t_status" == "FAIL" ]]; then
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

            # In run_preflight_checks, find this block and update the cmd_display line:

            local cmd_display
            if [[ "$OS_TYPE" == "linux" && -n "$vrf" ]]; then
                cmd_display="sudo ip vrf exec ${vrf} traceroute -n ${tgt}"
            else
                cmd_display="traceroute -n ${tgt}"
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
            # ── Bash 3.2 compatible uppercase conversion ──────────────
            local decision_upper
            decision_upper=$(printf '%s' "$decision" \
                | tr '[:lower:]' '[:upper:]')
            case "$decision_upper" in
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
            # ── Bash 3.2 compatible uppercase conversion ──────────────
            local decision_upper
            decision_upper=$(printf '%s' "$decision" \
                | tr '[:lower:]' '[:upper:]')
            case "$decision_upper" in
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
            annotation="${RED}Path MTU: ${disc} B  MSS: ${rec} B  ✖ CRITICAL${NC}"
            ;;
        UNKNOWN)
            annotation="${DIM}Path MTU: UNKNOWN (ICMP probe failed)${NC}"
            ;;
    esac

    # ── Use plain printf to match the results table style ─────────────────
    # The results table uses plain printf (not bleft/box-drawing).
    # _pmtu_annotate_stream_summary must match that style.
    # Indent to align under the Sender BW column.
    if [[ -n "$annotation" ]]; then
        # C_SN=3  C_PROTO=5  C_TGT=15  C_PORT=5  — each separated by 2 spaces
        # indent = 3+2+5+2+15+2+5+2 = 36 chars to align under Sender BW
        printf '  %36s%b\n' '' "$annotation"
    fi
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

# ---------------------------------------------------------------------------
# _dscp_verify_get_iface  <stream_index>
#
# Resolves the correct capture interface for a stream by querying the
# kernel routing table using the stream's TARGET IP address only.
#
# Logic:
#   Loopback  →  always "lo"  (fast path, no route lookup needed)
#
#   Linux VRF →  ip route get vrf <vrf> <target>
#                Queries the VRF routing table directly.
#                Falls back to: ip vrf exec <vrf> ip route get <target>
#                for older kernels that do not support "ip route get vrf".
#
#   Linux GRT →  ip route get <target>
#                Queries the Global Routing Table.
#
#   macOS     →  route -n get <target>
#                No VRF support on macOS.
#
# The "dev <iface>" token in the route output is the authoritative egress
# interface — it is exactly what the kernel uses when iperf3 sends packets
# to the target, so it is the correct interface for tcpdump capture.
#
# Bind IP is intentionally NOT used — the target IP route lookup always
# returns the correct egress interface regardless of source address.
# ---------------------------------------------------------------------------
_dscp_verify_get_iface() {
    local idx="$1"
    local target="${S_TARGET[$idx]:-}"
    local vrf="${S_VRF[$idx]:-}"

    # ── Fast path: loopback ───────────────────────────────────────────────
    if [[ "$target" =~ ^127\. || "$target" == "::1" ]]; then
        printf '%s' "lo"
        return 0
    fi

    # ── Linux ─────────────────────────────────────────────────────────────
    if [[ "$OS_TYPE" == "linux" ]]; then

        local route_out="" oif=""

        # Shared awk program — extracts the interface name from the token
        # immediately following the keyword "dev" in ip-route output.
        # Works for all output formats:
        #   "10.0.0.1 via 10.0.0.254 dev eth0.100 src 10.0.0.2 uid 0"
        #   "10.0.0.1 dev eth0 src 10.0.0.2 uid 0"
        local _awk_dev
        _awk_dev='{ for (i=1; i<=NF; i++) if ($i=="dev" && i+1<=NF) { print $(i+1); exit } }'

        if [[ -n "$vrf" ]]; then
            # ── VRF: query the VRF routing table by target IP ─────────────
            #
            # Primary:  ip route get vrf <vrf> <target>
            #   Supported on kernel >= 4.12 + iproute2 >= 4.12
            #   Directly queries the VRF FIB without entering the VRF ns.
            #
            route_out=$(ip route get vrf "${vrf}" "${target}" 2>/dev/null)
            oif=$(printf '%s' "$route_out" | awk "$_awk_dev")

            if [[ -n "$oif" ]]; then
                printf '%s' "$oif"
                return 0
            fi

            # Fallback: ip vrf exec <vrf> ip route get <target>
            #   Works on older kernels that do not support "ip route get vrf".
            #   Enters the VRF network namespace context and runs the lookup.
            #
            route_out=$(ip vrf exec "${vrf}" ip route get "${target}" 2>/dev/null)
            oif=$(printf '%s' "$route_out" | awk "$_awk_dev")

            if [[ -n "$oif" ]]; then
                printf '%s' "$oif"
                return 0
            fi

            # Both VRF lookups failed
            printf '%s' ""
            return 1

        else
            # ── GRT: query the Global Routing Table by target IP ──────────
            #
            route_out=$(ip route get "${target}" 2>/dev/null)
            oif=$(printf '%s' "$route_out" | awk "$_awk_dev")

            if [[ -n "$oif" ]]; then
                printf '%s' "$oif"
                return 0
            fi

            # GRT lookup failed
            printf '%s' ""
            return 1
        fi
    fi

    # ── macOS ─────────────────────────────────────────────────────────────
    if [[ "$OS_TYPE" == "macos" ]]; then
        local oif=""
        oif=$(route -n get "${target}" 2>/dev/null \
            | awk '/interface:/ { print $2; exit }')
        if [[ -n "$oif" ]]; then
            printf '%s' "$oif"
            return 0
        fi
        printf '%s' ""
        return 1
    fi

    printf '%s' ""
    return 1
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
    if [[ -n "$vrf" ]]; then
        bleft "  ${DIM}Interface resolved via: ip route get vrf ${vrf} ${target}${NC}"
    else
        bleft "  ${DIM}Interface resolved via: ip route get ${target}${NC}"
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

    # Guard: suppress DSCP verification entirely during loopback test mode.
    # tcpdump cannot capture meaningful DSCP markings on the loopback
    # interface because the TOS field is not preserved in the same way
    # as on physical or virtual Ethernet interfaces.
    if _all_streams_loopback; then
        printf '\n'
        printf '+%s+\n' "$(rpt '=' "$inner")"
        bcenter "${BOLD}${CYAN}DSCP Marking Verification${NC}"
        printf '+%s+\n' "$(rpt '=' "$inner")"
        bleft "  ${YELLOW}⚠ Loopback test mode — DSCP verification is not applicable.${NC}"
        bleft "  ${DIM}All streams target 127.0.0.1. tcpdump DSCP capture requires${NC}"
        bleft "  ${DIM}a physical or virtual interface, not the loopback interface.${NC}"
        printf '+%s+\n' "$(rpt '=' "$inner")"
        printf '\n'
        read -r -p "  Press Enter to return to dashboard..." </dev/tty
        printf '\033[?25l'
        return 0
    fi

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

    # Select stream — only from non-loopback streams
    local selected_idx=-1

    # Build a list of selectable (non-loopback) stream indices
    local -a verifiable_indices=()
    local _vi2
    for (( _vi2=0; _vi2<STREAM_COUNT; _vi2++ )); do
        if [[ ! "${S_TARGET[$_vi2]:-}" =~ ^127\. ]] && \
           [[ "${S_TARGET[$_vi2]:-}" != "::1" ]]; then
            verifiable_indices+=("$_vi2")
        fi
    done

    if (( ${#verifiable_indices[@]} == 1 )); then
        # Only one eligible stream — select automatically
        selected_idx="${verifiable_indices[0]}"
    else
        # Multiple eligible streams — show selection menu
        printf '\n'
        printf '+%s+\n' "$(rpt '=' "$inner")"
        bcenter "${BOLD}${CYAN}DSCP Marking Verification — Select Stream${NC}"
        printf '+%s+\n' "$(rpt '=' "$inner")"
        bleft "  ${BOLD}$(printf '%-3s  %-5s  %-16s  %-6s  %-8s  %-10s' \
            '#' 'Proto' 'Target' 'Port' 'DSCP' 'Status')${NC}"
        printf '+%s+\n' "$(rpt '-' "$inner")"

        local _vidx
        for _vidx in "${verifiable_indices[@]}"; do
            local sn=$(( _vidx + 1 ))
            local st="${S_STATUS_CACHE[$_vidx]:-STARTING}"
            local tgt="${S_TARGET[$_vidx]:-?}"
            (( ${#tgt} > 16 )) && tgt="${tgt:0:15}~"
            local dscp_disp="${S_DSCP_NAME[$_vidx]:-CS0}"
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
                "$sn" "${S_PROTO[$_vidx]}" "$tgt" \
                "${S_PORT[$_vidx]}" "$dscp_disp")
            bleft " ${pfx}${st_col}"
        done

        printf '+%s+\n' "$(rpt '=' "$inner")"
        printf '\n'

        local sel_raw sel_lower
        while true; do
            read -r -p "  Stream number to verify (or q to cancel): " sel_raw </dev/tty
            sel_lower=$(printf '%s' "$sel_raw" | tr '[:upper:]' '[:lower:]')
            [[ "$sel_lower" == "q" || -z "$sel_raw" ]] && {
                printf '\033[?25l'
                return 0
            }
            if [[ "$sel_raw" =~ ^[0-9]+$ ]] && \
               (( 10#$sel_raw >= 1 && 10#$sel_raw <= STREAM_COUNT )); then
                local _candidate=$(( 10#$sel_raw - 1 ))
                # Verify selected stream is not loopback
                if [[ "${S_TARGET[$_candidate]:-}" =~ ^127\. ]] || \
                   [[ "${S_TARGET[$_candidate]:-}" == "::1" ]]; then
                    printf '%b\n' \
                        "${YELLOW}  Stream ${sel_raw} targets loopback — not eligible for DSCP verification.${NC}"
                    continue
                fi
                selected_idx=$_candidate
                break
            fi
            printf '%b\n' \
                "${RED}  Enter a stream number 1-${STREAM_COUNT} or q to cancel.${NC}"
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

    # ── Terminal cleanup states — never overwrite ──────────────────────────
    if [[ "$cur" == "CLEANED" || "$cur" == "CLEANUP_PENDING" ]]; then
        return
    fi

    # ── Finality guard — DONE/FAILED are sticky ────────────────────────────
    # Once a stream has been marked DONE and its final BW has been captured
    # (S_FINAL_SENDER_BW is non-empty), do NOT allow the process liveness
    # check to flip the state back to CONNECTED or CONNECTING.
    #
    # This prevents the zombie-process race condition where iperf3 has exited
    # but has not yet been reaped by wait(), causing kill -0 to return 0
    # (process still exists as zombie) and the TCP socket check to fail
    # (connection gone), which together would incorrectly infer CONNECTING.
    #
    # The stream is definitively finished when:
    #   - State is DONE, AND
    #   - S_FINAL_SENDER_BW is set (final BW was captured from the log)
    if [[ "$cur" == "DONE" ]]; then
        _capture_final_bw "$idx"
        return
    fi

    if [[ "$cur" == "FAILED" ]]; then
        return
    fi

    # ── Process liveness ───────────────────────────────────────────────────
    if [[ "$pid" == "0" ]]; then
        S_STATUS_CACHE[$idx]="FAILED"
        [[ -z "${S_ERROR_MSG[$idx]}" ]] && \
            S_ERROR_MSG[$idx]="Failed to launch iperf3 process"
        return
    fi

    local alive=0
    kill -0 "$pid" 2>/dev/null && alive=1

    if (( ! alive )); then
        local err; err=$(extract_error_from_log "$lf" "$idx")
        if [[ -n "$err" ]]; then
            S_STATUS_CACHE[$idx]="FAILED"
            S_ERROR_MSG[$idx]="$err"
            return
        fi
        if [[ -f "$lf" ]] && grep -qE 'sender|receiver' "$lf" 2>/dev/null; then
            S_STATUS_CACHE[$idx]="DONE"
            _capture_final_bw "$idx"
            return
        fi
        if [[ -f "$lf" && -s "$lf" ]]; then
            S_STATUS_CACHE[$idx]="FAILED"
            S_ERROR_MSG[$idx]=$(tail -3 "$lf" 2>/dev/null \
                | tr '\n' ' ' | sed 's/^[[:space:]]*//')
            return
        fi
        S_STATUS_CACHE[$idx]="DONE"
        _capture_final_bw "$idx"
        return
    fi

    # ── Process is alive — check early errors ─────────────────────────────
    if [[ -f "$lf" && -s "$lf" ]]; then
        local early_err; early_err=$(extract_error_from_log "$lf" "$idx")
        [[ -n "$early_err" ]] && {
            S_STATUS_CACHE[$idx]="CONNECTING"
            return
        }
    fi

    # ── Check for active TCP/UDP connection ───────────────────────────────
    local tcp_connected=0
    if [[ "$proto" == "TCP" && -n "$target" && -n "$port" ]]; then
        check_pid_tcp_connected "$pid" "$target" "$port" && tcp_connected=1
    fi
    if [[ "$proto" == "UDP" && -n "$target" && -n "$port" ]]; then
        if [[ "$OS_TYPE" == "macos" ]]; then
            command -v lsof >/dev/null 2>&1 && \
                lsof -p "$pid" -i UDP 2>/dev/null \
                | grep -q "$target" && tcp_connected=1
        else
            ss -un 2>/dev/null \
                | grep -qE "${target}:${port}([[:space:]]|$)" \
                && tcp_connected=1
        fi
    fi

    # ── Check log for interval data or connection message ─────────────────
    local log_connected=0 has_interval=0
    if [[ -f "$lf" && -s "$lf" ]]; then
        if grep -qE \
            '^\[SUM\][[:space:]]+[0-9.]+-[0-9.]+[[:space:]]+sec.*bits|^\[[[:space:]]*[0-9]+\][[:space:]]+[0-9.]+-[0-9.]+[[:space:]]+sec.*bits|^\[[[:space:]]*[0-9]+\]\[.*\][[:space:]]+[0-9.]+-[0-9.]+[[:space:]]+sec.*bits' \
            "$lf" 2>/dev/null; then
            has_interval=1
        fi
        if (( has_interval == 0 )); then
            grep -qE \
                '^\[[[:space:]]*[0-9]+\].*local.*port.*connected to' \
                "$lf" 2>/dev/null && log_connected=1
        fi
    fi

    if (( tcp_connected || has_interval || log_connected )); then
        S_STATUS_CACHE[$idx]="CONNECTED"
        S_ERROR_MSG[$idx]=""
        return
    fi

    if [[ ! -f "$lf" || ! -s "$lf" ]]; then
        S_STATUS_CACHE[$idx]="STARTING"
    else
        S_STATUS_CACHE[$idx]="CONNECTING"
    fi
    S_ERROR_MSG[$idx]=""
}

probe_server_status() {
    # ── Changed calling convention ─────────────────────────────────────────
    # This function NO LONGER prints a return value via printf/echo.
    # It writes the resolved state directly into SRV_PREV_STATE[$idx] so
    # that array assignments are visible to the caller (no subshell).
    #
    # Callers that previously did:
    #   local st; st=$(probe_server_status "$i")
    # Must now do:
    #   probe_server_status "$i"
    #   local st="${SRV_PREV_STATE[$i]}"
    # ──────────────────────────────────────────────────────────────────────
    local idx="$1"
    local pid="${SERVER_PIDS[$idx]:-0}"
    local port="${SRV_PORT[$idx]:-}"

    # Resolve log file path — guard against SRV_LOGFILE[$idx] being empty
    local lf="${SRV_LOGFILE[$idx]:-}"
    [[ -z "$lf" ]] && lf="${TMPDIR}/server_$((idx+1)).log"

    # ── Process liveness check ─────────────────────────────────────────────
    if [[ "$pid" == "0" ]]; then
        SRV_PREV_STATE[$idx]="FAILED"
        return
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
        SRV_PREV_STATE[$idx]="DONE"
        return
    fi

    # ── Resolve current connection state ───────────────────────────────────
    local current_state="STARTING"

    if [[ -n "$port" ]]; then
        if [[ "$OS_TYPE" == "macos" ]]; then
            if lsof -iTCP:"$port" 2>/dev/null | grep -q "ESTABLISHED"; then
                current_state="CONNECTED"
            elif lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
                if [[ -f "$lf" && -s "$lf" ]] && \
                   grep -qiE 'accepted connection|connected|bits/sec' \
                       "$lf" 2>/dev/null; then
                    current_state="RUNNING"
                else
                    current_state="LISTENING"
                fi
            fi
        else
            if ss -tn 2>/dev/null \
                    | grep -qE "ESTAB.*:${port}([[:space:]]|$)"; then
                current_state="CONNECTED"
            elif ss -tn 2>/dev/null \
                    | grep -qE "ESTAB.+:${port}[[:space:]]"; then
                current_state="CONNECTED"
            elif ss -tlnp 2>/dev/null \
                    | grep -qE ":${port}([[:space:]]|$)"; then
                if [[ -f "$lf" && -s "$lf" ]] && \
                   grep -qiE 'accepted connection|connected|bits/sec' \
                       "$lf" 2>/dev/null; then
                    current_state="RUNNING"
                else
                    current_state="LISTENING"
                fi
            fi
        fi
    fi

    # Fallback: infer state from log content when socket check found nothing
    if [[ "$current_state" == "STARTING" && -f "$lf" && -s "$lf" ]]; then
        if grep -qiE 'accepted connection|connected' "$lf" 2>/dev/null; then
            current_state="RUNNING"
        elif grep -qi 'server listening\|listening on' "$lf" 2>/dev/null; then
            current_state="LISTENING"
        fi
    fi

    # ── State-change side effects ───────────────────────────────────────────
    local prev_state="${SRV_PREV_STATE[$idx]:-}"

    # BW cache reset: client disconnected, server back to idle
    case "$prev_state" in
        CONNECTED|RUNNING)
            case "$current_state" in
                LISTENING|STARTING)
                    SRV_BW_CACHE[$idx]="---"
                    ;;
            esac
            ;;
    esac

    # Sparkline reset: new client just connected (transition from idle to active)
    local _prev_active=0 _curr_active=0
    case "$prev_state"   in CONNECTED|RUNNING) _prev_active=1 ;; esac
    case "$current_state" in CONNECTED|RUNNING) _curr_active=1 ;; esac

    if (( _prev_active == 0 && _curr_active == 1 )); then
        _spark_clear "s" "$idx"
    fi

    # ── Write result directly into the array (no subshell, no printf) ──────
    SRV_PREV_STATE[$idx]="$current_state"
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
        # Count both DONE and post-cleanup states so the panel
        # remains visible while cleanup runs and after it completes.
        case "${S_STATUS_CACHE[$i]}" in
            DONE|CLEANED|CLEANUP_PENDING) (( done_count++ )) ;;
        esac
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
        case "${S_STATUS_CACHE[$i]}" in
            DONE|CLEANED|CLEANUP_PENDING) (( done_count++ )) ;;
        esac
    done
    (( done_count == 0 )) && return

    # ── Dynamic target column width ───────────────────────────────────────
    local _tgt_col_w=14
    for (( i=0; i<STREAM_COUNT; i++ )); do
        case "${S_STATUS_CACHE[$i]}" in
            DONE|CLEANED|CLEANUP_PENDING) ;;
            *) continue ;;
        esac
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
        # Render rows for DONE, CLEANED, and CLEANUP_PENDING.
        # By the time this panel renders, successful streams have typically
        # already advanced from DONE to CLEANED via _cleanup_stream_procs().
        # Excluding CLEANED causes the panel to show headers with no data rows.
        case "${S_STATUS_CACHE[$i]}" in
            DONE|CLEANED|CLEANUP_PENDING) ;;
            *) continue ;;
        esac
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
# _count_server_frame_lines
#
# Returns the EXACT number of lines _render_server_frame will print
# given the current SERVER_COUNT and state.
#
# Anatomy of _render_server_frame output:
#   1   bline '='            top border
#   2   bcenter              title
#   3   bline '='            title border
#   4   bleft                "Listeners active: N / N"
#   5   bline '='            status border
#   6   bleft                column header
#   7   bline '-'            header underline
#   per listener (SERVER_COUNT iterations):
#     +1  printf data row
#     +1  bline '-'  per-listener separator  (all except the last)
#   8+N   bline '='          bottom border
#   9+N   bleft              Ctrl+C hint
#  10+N   bline '='          final border
#
# Per-listener separator is printed for every listener EXCEPT the last,
# so separator count = SERVER_COUNT - 1  (minimum 0).
# ---------------------------------------------------------------------------
_count_server_frame_lines() {
    local total=10    # 7 fixed structural lines + bottom border + hint + final border

    # One data row per listener
    (( total += SERVER_COUNT ))

    # Per-listener separators (between rows, not after the last)
    if (( SERVER_COUNT > 1 )); then
        (( total += SERVER_COUNT - 1 ))
    fi

    printf '%d' "$total"
}

# ---------------------------------------------------------------------------
# _count_client_frame_lines_for_state
#
# Returns the EXACT number of lines _render_client_frame will print
# given the current stream states.
#
# Anatomy of _render_client_frame output:
#   1   bline '='            top border
#   2   bcenter              title
#   3   bline '='            title border
#   4   bleft                counters row
#   5   bline '='            counters border
#   6   bleft                column header
#   +1  bleft                progress sub-header (only when has_fixed_dur)
#   7   bline '-'            header underline
#   per stream (STREAM_COUNT iterations):
#     +1  printf data row    (BW + sparkline + status)
#     +1  bleft RTT row      (non-loopback streams only)
#     +1  bleft progress bar (fixed-duration non-FAILED streams only)
#     +1  bline '-'          per-stream separator (all except the last)
#   8+N   bline '='          bottom border
#   9+N   bleft              Ctrl+C + DSCP hint
#  10+N   bline '='          final border
# ---------------------------------------------------------------------------
_count_client_frame_lines_for_state() {
    local total=11

    local i
    for (( i=0; i<STREAM_COUNT; i++ )); do
        local st="${S_STATUS_CACHE[$i]:-STARTING}"

        if [[ "$st" == "CLEANED" || "$st" == "CLEANUP_PENDING" ]]; then
            (( total++ ))
            if (( i < STREAM_COUNT - 1 )); then (( total++ )); fi
            continue
        fi

        (( total++ ))   # TX row (always)

        # Target line — when FQDN or long target needs dedicated display row
        # This check mirrors _needs_target_line() inline for Bash 3.2 safety
        # (avoids function call overhead on every tick in the render loop).
        local _fcst_tgt="${S_TARGET[$i]:-}"
        local _fcst_disp="${S_TARGET_DISPLAY[$i]:-$_fcst_tgt}"
        if [[ -n "${S_TARGET_DISPLAY[$i]:-}" && \
              "${S_TARGET_DISPLAY[$i]}" != "$_fcst_tgt" ]] || \
           (( ${#_fcst_disp} > 15 )); then
            (( total++ ))   # dedicated target line for FQDN
        fi

        if [[ "${S_BIDIR[$i]:-0}" == "1" ]]; then
            (( total++ ))   # RX row
        fi

        local tgt="${S_TARGET[$i]:-}"
        if [[ ! "$tgt" =~ ^127\. && "$tgt" != "::1" ]]; then
            (( total++ ))   # RTT row — non-loopback only
        fi

        if [[ "${S_PROTO[$i]:-TCP}" == "TCP" ]] && \
           [[ ! "$tgt" =~ ^127\. && "$tgt" != "::1" ]] && \
           [[ "${S_CWND_SAMPLES[$i]:-0}" != "0" ]]; then
            (( total++ ))   # CWND inline row
        fi

        if [[ "${S_RAMP_ENABLED[$i]:-0}" == "1" ]]; then
            (( total++ ))   # ramp timeline row
        fi

        if (( S_DURATION[$i] > 0 )) && [[ "$st" != "FAILED" ]]; then
            (( total++ ))   # progress bar row
        fi

        if (( i < STREAM_COUNT - 1 )); then
            (( total++ ))   # per-stream separator
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

# ==============================================================================
# _needs_target_line  <stream_idx>
#
# Returns 0 (true) when a stream's target display string is long enough
# to warrant its own dedicated second line in the dashboard.
#
# A dedicated target line is used when:
#   - The operator entered an FQDN (S_TARGET_DISPLAY differs from S_TARGET)
#   - OR the raw IPv4 is longer than the C_TARGET column width (15 chars)
#
# This keeps the main data row compact while giving long targets full width.
# ==============================================================================
_needs_target_line() {
    local idx="$1"
    local raw_ip="${S_TARGET[$idx]:-}"
    local display="${S_TARGET_DISPLAY[$idx]:-$raw_ip}"

    # FQDN was resolved — always use dedicated line
    [[ -n "${S_TARGET_DISPLAY[$idx]:-}" && \
       "${S_TARGET_DISPLAY[$idx]}" != "$raw_ip" ]] && return 0

    # Raw IPv4 exceeds column width
    (( ${#display} > 15 )) && return 0

    return 1
}

# =============================================================================
# _render_client_frame
#
# FIXES APPLIED:
#   1. TX/RX label widths are fixed at exactly 5 visible chars ("↑ TX " / "↓ RX ")
#      and subtracted from the available row width so bleft() padding stays correct.
#   2. RTT and CWND rows use bleft() with a plain-text prefix that has a known
#      fixed visible width, keeping the right border flush.
#   3. Progress bar indent is computed from the actual column widths rather than
#      a hard-coded constant so it always sits under the Bandwidth column.
#   4. The DONE/CLEANED tombstone row uses printf -v to build the full plain-text
#      string before passing to bleft(), giving vlen() a clean input.
#   5. Column widths are defined once as named constants and referenced everywhere
#      so a single change propagates to header, data rows, and sub-rows.
# =============================================================================

_render_client_frame() {

    # ------------------------------------------------------------------
    # Disable errexit for the entire render function.
    # Arithmetic (( expr )) returns 1 when expr == 0, which kills the
    # script under set -e. The render function is purely presentational
    # and must never exit early.
    # ------------------------------------------------------------------
    local _old_errexit=0
    [[ $- == *e* ]] && _old_errexit=1
    set +e

    local now; now=$(date +%s)
    local i

    # ------------------------------------------------------------------
    # Per-tick probes
    # ------------------------------------------------------------------
    for (( i=0; i<STREAM_COUNT; i++ )); do
        probe_client_status "$i"
        local _pst="${S_STATUS_CACHE[$i]:-STARTING}"
        case "$_pst" in
            DONE|FAILED|CLEANED|CLEANUP_PENDING) ;;
            *)
                _rtt_parse "$i"
                _bidir_parse_bw "$i"
                [[ "${S_PROTO[$i]:-TCP}" == "TCP" ]] && _cwnd_parse "$i"
                [[ "${S_RAMP_ENABLED[$i]:-0}" == "1" ]] && _ramp_tick "$i"
                ;;
        esac
    done

    # ------------------------------------------------------------------
    # Stream counters
    # ------------------------------------------------------------------
    local nc=0 ni=0 ns=0 nd=0 nf=0 n_cleaned=0
    for (( i=0; i<STREAM_COUNT; i++ )); do
        case "${S_STATUS_CACHE[$i]}" in
            CONNECTED)               (( nc++        )) ;;
            CONNECTING)              (( ni++        )) ;;
            STARTING)                (( ns++        )) ;;
            DONE)                    (( nd++        )) ;;
            FAILED)                  (( nf++        )) ;;
            CLEANED|CLEANUP_PENDING) (( n_cleaned++ )) ;;
        esac
    done
    local act=$(( nc + ni + ns ))
    local fts="${S_START_TS[0]:-0}"
    (( fts == 0 )) && fts="$now"
    local efmt; efmt=$(format_seconds $(( now - fts )))

    # ------------------------------------------------------------------
    # Column layout — ALL widths defined here as named constants.
    # Every data row, sub-row, and the column header reference these
    # same constants so alignment is guaranteed to be consistent.
    #
    #   C_SN     =  2   stream number    "1 "
    #   C_PROTO  =  5   protocol         "TCP  "
    #   C_TARGET = 15   target IP/FQDN placeholder
    #   C_PORT   =  5   port             " 5201"
    #   C_BW     = 13   bandwidth        "204.00 Mbps  "
    #   C_SPARK  = 10   sparkline        "▅█▅█▅█▅▅▅▁"
    #   C_TIME   =  6   time remaining   "00:27 "
    #   C_DSCP   =  4   DSCP name        "EF  "
    #   C_STAT   =  9   status           "CONNECTED"
    #
    # Row prefix for bidir label:
    #   _PFX_W   =  5   "↑ TX " or "↓ RX " or "     " (5 visible chars)
    #
    # Box inner width = COLS - 2  (the two border pipes are not counted)
    # ------------------------------------------------------------------
    local C_SN=2
    local C_PROTO=5
    local C_TARGET=15
    local C_PORT=5
    local C_BW=13
    local C_SPARK=10
    local C_TIME=6
    local C_DSCP=4
    local C_STAT=9
    local _PFX_W=5     # visible width of the "↑ TX " / "↓ RX " prefix

    # Pre-compute the total visible width of one data row (no prefix) so
    # we can verify it fits inside the box and compute sub-row indents.
    #
    # Layout per row inside the box (between the two border pipes):
    #   " " + SN + " " + PROTO + " " + TARGET + " " + PORT
    #   + " " + BW + " " + SPARK + " " + TIME + " " + DSCP + " " + STAT + " "
    #   = 1 + C_SN + 1 + C_PROTO + 1 + C_TARGET + 1 + C_PORT
    #     + 1 + C_BW + 1 + C_SPARK + 1 + C_TIME + 1 + C_DSCP + 1 + C_STAT + 1
    #   = 10 gaps + sum(column widths)
    local _INNER=$(( COLS - 2 ))
    local _COL_SUM=$(( C_SN + C_PROTO + C_TARGET + C_PORT + \
                       C_BW + C_SPARK + C_TIME + C_DSCP + C_STAT ))
    # gaps: one space before each column + one trailing space = 10 total
    local _ROW_VISIBLE=$(( _COL_SUM + 10 ))

    # Indent used by sub-rows (RTT, CWND, ramp, progress bar).
    # RTT/CWND/ramp: align their label flush with the left edge of the
    # Bandwidth column so they read as belonging to the stream above.
    #
    #   indent = 1(border-space) + C_SN+1 + C_PROTO+1 + C_TARGET+1 + C_PORT+1
    #          = 1 + (C_SN+1) + (C_PROTO+1) + (C_TARGET+1) + (C_PORT+1)
    local _SUBROW_INDENT=$(( 1 + C_SN+1 + C_PROTO+1 + C_TARGET+1 + C_PORT+1 ))

    # For bidir streams the prefix "↑ TX " or "↓ RX " occupies _PFX_W
    # visible characters at the start of the row. The stream-number
    # column is therefore inset by _PFX_W positions.
    # bleft() pads the total string to fill _INNER. We build the
    # complete row as a single string and let bleft() do one measurement.

    # ------------------------------------------------------------------
    # Check whether any stream has a fixed duration (needed to decide
    # whether to print the progress-bar sub-row and the sub-header line)
    # ------------------------------------------------------------------
    local has_fixed_dur=0
    for (( i=0; i<STREAM_COUNT; i++ )); do
        if (( S_DURATION[$i] > 0 )); then has_fixed_dur=1; break; fi
    done

    # ------------------------------------------------------------------
    # Header
    # ------------------------------------------------------------------
    bline '='
    bcenter "${BOLD}${CYAN}PRISM — Live Dashboard${NC}"
    bline '='

    # Counter row — use printf -v to build plain text first so vlen()
    # sees clean ASCII (no embedded format strings).
    local _ctr_plain
    printf -v _ctr_plain \
        "  Active:%-2d   Connected:%-2d   Done:%-2d   Failed:%-2d   Elapsed:%s" \
        "$act" "$nc" "$nd" "$nf" "$efmt"
    bleft "$_ctr_plain"
    bline '='

    # Column header — built from the same constants as data rows.
    # printf -v builds the plain-text string; bleft() adds ANSI bold
    # and pads to box width.
    local _hdr_plain
    printf -v _hdr_plain \
        " %-*s %-*s %-*s %*s %-*s %-*s %*s %-*s %-*s" \
        "$C_SN"     "#" \
        "$C_PROTO"  "Proto" \
        "$C_TARGET" "Target" \
        "$C_PORT"   "Port" \
        "$C_BW"     "Bandwidth" \
        "$C_SPARK"  "Last 10s" \
        "$C_TIME"   "Time" \
        "$C_DSCP"   "DSCP" \
        "$C_STAT"   "Status"
    bleft "${BOLD}${_hdr_plain}${NC}"
    bline '-'

    # ------------------------------------------------------------------
    # Per-stream rows
    # ------------------------------------------------------------------
    for (( i=0; i<STREAM_COUNT; i++ )); do
        local sn=$(( i + 1 ))
        local st="${S_STATUS_CACHE[$i]:-STARTING}"
        local lf="${S_LOGFILE[$i]:-}"

        # ==============================================================
        # CLEANED / CLEANUP_PENDING tombstone
        # Build the entire row as plain text so bleft() gets a single
        # clean string to measure with vlen().
        # ==============================================================
        if [[ "$st" == "CLEANED" || "$st" == "CLEANUP_PENDING" ]]; then
            local tgt_t="${S_TARGET[$i]:-?}"
            (( ${#tgt_t} > C_TARGET )) && tgt_t="${tgt_t:0:$(( C_TARGET-1 ))}~"

            local _tomb_plain
            printf -v _tomb_plain \
                " %-*s %-*s %-*s %*s %-*s %-*s %*s %-*s" \
                "$C_SN"     "$sn" \
                "$C_PROTO"  "${S_PROTO[$i]}" \
                "$C_TARGET" "$tgt_t" \
                "$C_PORT"   "${S_PORT[$i]}" \
                "$C_BW"     "---" \
                "$C_SPARK"  "··········" \
                "$C_TIME"   "------" \
                "$C_DSCP"   "---"

            if [[ "$st" == "CLEANUP_PENDING" ]]; then
                bleft "${YELLOW}${_tomb_plain} $(printf '%-*s' "$C_STAT" "CLEANING…")${NC}"
            else
                bleft "${DIM}${_tomb_plain} $(printf '%-*s' "$C_STAT" "── DONE ──")${NC}"
            fi

            (( i < STREAM_COUNT - 1 )) && bline '-'
            continue
        fi

        # ==============================================================
        # Live bandwidth (TX direction)
        # ==============================================================
        local bw_tx="---"
        if [[ "$st" == "CONNECTED" ]]; then
            if [[ "${S_BIDIR[$i]:-0}" == "1" ]] && (( BIDIR_SUPPORTED == 1 )); then
                # --bidir: prefer [TX-C] tagged lines
                if [[ -f "$lf" && -s "$lf" ]]; then
                    bw_tx=$(grep -E '\]\[TX-C\]' "$lf" 2>/dev/null \
                        | grep -E '[0-9.]+-[0-9.]+[[:space:]]+sec' \
                        | grep -vE '[[:space:]](sender|receiver)[[:space:]]*$' \
                        | tail -1 \
                        | awk '{
                            for(i=1;i<=NF;i++){
                                if($i~/[KMGkmg]?bits\/sec/ && i>1 && $(i-1)+0>0){
                                    v=$(i-1)+0; u=$i
                                    if(u~/[Gg]/) b=v*1e9
                                    else if(u~/[Mm]/) b=v*1e6
                                    else if(u~/[Kk]/) b=v*1e3
                                    else b=v
                                    if(b>=1e9) printf "%.2f Gbps",b/1e9
                                    else if(b>=1e6) printf "%.2f Mbps",b/1e6
                                    else if(b>=1e3) printf "%.2f Kbps",b/1e3
                                    else printf "%.0f bps",b
                                    exit
                                }
                            }
                        }')
                    [[ -z "$bw_tx" ]] && bw_tx="---"
                fi
                # Fallback to any interval line
                if [[ "$bw_tx" == "---" && -f "$lf" && -s "$lf" ]]; then
                    bw_tx=$(parse_live_bandwidth_from_log "$lf")
                fi
            else
                bw_tx=$(parse_live_bandwidth_from_log "$lf")
            fi
        fi
        [[ "$st" == "DONE" ]] && bw_tx="${S_FINAL_SENDER_BW[$i]:-N/A}"

        # ==============================================================
        # RX bandwidth (bidir only)
        # ==============================================================
        local bw_rx="${S_BIDIR_BW[$i]:-???}"

        # ==============================================================
        # TX sparkline
        # ==============================================================
        local spark_tx; spark_tx=$(_spark_render "c" "$i")
        if [[ "$st" == "CONNECTED" && "$bw_tx" != "---" ]]; then
            _spark_push "c" "$i" "$bw_tx"
            [[ "$JSON_EXPORT_ENABLED" -eq 1 ]] && \
                _json_sample_push "$i" "$bw_tx" "$(date +%s)"
        fi

        # ==============================================================
        # RX sparkline (bidir only)
        # ==============================================================
        local spark_rx=""
        if [[ "${S_BIDIR[$i]:-0}" == "1" ]]; then
            spark_rx=$(_spark_render "r" "$i")
        fi

        # ==============================================================
        # Time remaining / progress
        # ==============================================================
        local td="------"
        local sts="${S_START_TS[$i]:-0}"
        (( sts == 0 )) && sts="$now"
        local dur="${S_DURATION[$i]:-0}"
        local stream_elapsed=$(( now - sts ))
        local show_bar=0

        case "$st" in
            CONNECTED|STARTING|CONNECTING)
                if (( dur == 0 )); then
                    td="  inf "
                    show_bar=0
                else
                    local rem=$(( dur - stream_elapsed ))
                    (( rem < 0 )) && rem=0
                    td=$(format_seconds "$rem")
                    show_bar=1
                fi
                ;;
            DONE)
                td="  done"
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

        # ==============================================================
        # DSCP display
        # ==============================================================
        local dscp_disp="---"
        if [[ -n "${S_DSCP_NAME[$i]}" ]]; then
            dscp_disp="${S_DSCP_NAME[$i]}"
        elif [[ -n "${S_DSCP_VAL[$i]}" ]] && (( S_DSCP_VAL[$i] >= 0 )); then
            dscp_disp="${S_DSCP_VAL[$i]}"
        fi
        (( ${#dscp_disp} > C_DSCP )) && dscp_disp="${dscp_disp:0:$(( C_DSCP-1 ))}~"

        # ==============================================================
        # Status colour
        # ==============================================================
        local sb sc
        case "$st" in
            CONNECTED)  sb="CONNECTED"  sc="$GREEN"  ;;
            CONNECTING) sb="CONNECTING" sc="$YELLOW" ;;
            STARTING)   sb="STARTING"   sc="$YELLOW" ;;
            DONE)       sb="DONE"       sc="$CYAN"   ;;
            FAILED)     sb="FAILED"     sc="$RED"    ;;
            *)          sb="$st"        sc="$NC"     ;;
        esac

        # ==============================================================
        # Truncate variable-width fields to their column caps
        # ==============================================================
        local bw_tx_disp="$bw_tx"
        local bw_rx_disp="${bw_rx:-???}"
        (( ${#bw_tx_disp} > C_BW     )) && bw_tx_disp="${bw_tx_disp:0:$(( C_BW-1 ))}~"
        (( ${#bw_rx_disp} > C_BW     )) && bw_rx_disp="${bw_rx_disp:0:$(( C_BW-1 ))}~"

        # ==============================================================
        # Determine whether this stream needs a dedicated FQDN target
        # line (two-row display)
        # ==============================================================
        local _use_target_line=0
        _needs_target_line "$i" && _use_target_line=1

        local tgt="${S_TARGET[$i]:-?}"
        local tgt_full="${S_TARGET_DISPLAY[$i]:-$tgt}"

        # ==============================================================
        # Build the TX (main data) row
        #
        # For bidir streams the row starts with "↑ TX " (5 visible chars).
        # For non-bidir streams the row starts with 5 spaces so the
        # stream-number column lands at the same horizontal position.
        #
        # We build the fixed-width plain-text portion with printf -v,
        # then concatenate the coloured status and pass the whole thing
        # to bleft(). bleft() uses vlen() to measure the visible length
        # and adds right-padding to reach the box inner width.
        # ==============================================================
        local _tgt_col_val
        if (( _use_target_line == 1 )); then
            # Target column shows a dash-line placeholder when the full
            # FQDN appears on a dedicated second row.
            _tgt_col_val="$(rpt '─' "$C_TARGET")"
        else
            _tgt_col_val="$tgt"
            (( ${#_tgt_col_val} > C_TARGET )) && \
                _tgt_col_val="${_tgt_col_val:0:$(( C_TARGET-1 ))}~"
        fi

        local _row_plain
        printf -v _row_plain \
            " %-*s %-*s %-*s %*s %-*s %-*s %*s %-*s" \
            "$C_SN"     "$sn" \
            "$C_PROTO"  "${S_PROTO[$i]}" \
            "$C_TARGET" "$_tgt_col_val" \
            "$C_PORT"   "${S_PORT[$i]}" \
            "$C_BW"     "$bw_tx_disp" \
            "$C_SPARK"  "$spark_tx" \
            "$C_TIME"   "$td" \
            "$C_DSCP"   "$dscp_disp"

        if [[ "${S_BIDIR[$i]:-0}" == "1" ]]; then
            # Bidir TX row: "↑ TX " prefix (5 visible chars, printed in green)
            bleft "${GREEN}↑ TX${NC} ${_row_plain} ${sc}$(printf '%-*s' "$C_STAT" "$sb")${NC}"
        else
            # Standard row: 5-space indent keeps alignment identical to bidir rows
            bleft "     ${_row_plain} ${sc}$(printf '%-*s' "$C_STAT" "$sb")${NC}"
        fi

        # ==============================================================
        # FQDN target line (two-row display)
        # Printed immediately after the TX row when the target is an
        # FQDN or a long IP that would not fit in C_TARGET columns.
        # ==============================================================
        if (( _use_target_line == 1 )); then
            # Indent the "↳" marker to the same horizontal position as
            # the Target column: 1(border) + _PFX_W + 1 + C_SN + 1 + C_PROTO + 1
            local _tgt_marker_indent=$(( 1 + _PFX_W + 1 + C_SN + 1 + C_PROTO + 1 ))
            local _tgt_avail=$(( _INNER - _tgt_marker_indent - 3 ))
            (( _tgt_avail < 20 )) && _tgt_avail=20

            local tgt_line_str="$tgt_full"
            if (( ${#tgt_line_str} > _tgt_avail )); then
                tgt_line_str="${tgt_line_str:0:$(( _tgt_avail - 1 ))}~"
            fi

            local _tgt_prefix
            _tgt_prefix="$(rpt ' ' $(( _tgt_marker_indent )))${CYAN}↳${NC} "
            bleft "${_tgt_prefix}${DIM}${tgt_line_str}${NC}"
        fi

        # ==============================================================
        # RX row (bidir only)
        # Uses the same column layout as the TX row but with a "↓ RX "
        # prefix and only Bandwidth + Sparkline + Status filled in.
        # All other columns are blank strings padded to their widths.
        # ==============================================================
        if [[ "${S_BIDIR[$i]:-0}" == "1" ]]; then
            local rx_st="STARTING"
            local rx_lf="${BIDIR_LOGFILES[$i]:-}"
            if (( BIDIR_SUPPORTED == 1 )); then
                case "$st" in
                    CONNECTED|CONNECTING|STARTING)
                        if [[ -f "$rx_lf" && -s "$rx_lf" ]]; then
                            if grep -qE \
                                '\]\[RX-C\].*[0-9.]+-[0-9.]+' \
                                "$rx_lf" 2>/dev/null; then
                                rx_st="CONNECTED"
                            else
                                rx_st="CONNECTING"
                            fi
                        fi ;;
                    DONE)   rx_st="DONE"   ;;
                    FAILED) rx_st="FAILED" ;;
                    *)      rx_st="$st"    ;;
                esac
            fi
            local rx_sc
            case "$rx_st" in
                CONNECTED)  rx_sc="$GREEN"  ;;
                CONNECTING) rx_sc="$YELLOW" ;;
                DONE)       rx_sc="$CYAN"   ;;
                FAILED)     rx_sc="$RED"    ;;
                *)          rx_sc="$DIM"    ;;
            esac

            # RX row: blank out SN, Proto, Target, Port, Time, DSCP columns
            local _rx_plain
            printf -v _rx_plain \
                " %-*s %-*s %-*s %*s %-*s %-*s %*s %-*s" \
                "$C_SN"     "" \
                "$C_PROTO"  "" \
                "$C_TARGET" "" \
                "$C_PORT"   "" \
                "$C_BW"     "$bw_rx_disp" \
                "$C_SPARK"  "$spark_rx" \
                "$C_TIME"   "" \
                "$C_DSCP"   ""

            bleft "${CYAN}↓ RX${NC} ${_rx_plain} ${rx_sc}$(printf '%-*s' "$C_STAT" "$rx_st")${NC}"
        fi

        # ==============================================================
        # RTT row
        # Fixed layout with 5-space indent (same as non-bidir rows) so
        # it always aligns under the stream it belongs to.
        # All numeric fields are formatted to fixed widths so the
        # min/avg/max/jitter columns line up across multiple streams.
        # ==============================================================
        local stream_tgt="${S_TARGET[$i]:-}"
        if [[ ! "$stream_tgt" =~ ^127\. && "$stream_tgt" != "::1" ]]; then
            local rtt_min="${S_RTT_MIN[$i]:-}"
            local rtt_avg="${S_RTT_AVG[$i]:-}"
            local rtt_max="${S_RTT_MAX[$i]:-}"
            local rtt_jit="${S_RTT_JITTER[$i]:-}"
            local rtt_loss="${S_RTT_LOSS[$i]:-}"
            local rtt_cnt="${S_RTT_SAMPLES[$i]:-0}"

            if [[ -z "$rtt_avg" || "$rtt_avg" == "---" || "$rtt_cnt" == "0" ]]; then
                # Waiting for first sample
                bleft "     ${DIM}  RTT  Waiting for samples...${NC}"
            else
                # Format each field to a fixed visible width
                local f_min f_avg f_max f_jit f_loss f_cnt
                f_min=$(printf '%8.3f' "$rtt_min"  2>/dev/null || printf '%8s' "$rtt_min")
                f_avg=$(printf '%8.3f' "$rtt_avg"  2>/dev/null || printf '%8s' "$rtt_avg")
                f_max=$(printf '%8.3f' "$rtt_max"  2>/dev/null || printf '%8s' "$rtt_max")
                f_jit=$(printf '%8.3f' "$rtt_jit"  2>/dev/null || printf '%8s' "$rtt_jit")
                f_loss=$(printf '%5s'  "$rtt_loss")
                f_cnt=$(printf '%5d'   "$rtt_cnt"  2>/dev/null || printf '%5s' "$rtt_cnt")

                # Colour average RTT by magnitude
                local avg_col="$GREEN"
                local avg_int
                avg_int=$(printf '%.0f' "$rtt_avg" 2>/dev/null || printf '9999')
                if   (( avg_int > 150 )); then avg_col="$RED"
                elif (( avg_int > 50  )); then avg_col="$YELLOW"
                elif (( avg_int > 10  )); then avg_col="$CYAN"
                fi

                # Colour loss
                local loss_col="$GREEN"
                local loss_num
                loss_num=$(printf '%s' "$rtt_loss" | tr -d '%')
                local loss_int
                loss_int=$(printf '%.0f' "${loss_num:-0}" 2>/dev/null || printf '0')
                (( loss_int > 0 )) && loss_col="$RED"

                # Build the RTT line as a single bleft() call.
                # "     " = 5-space indent matching non-bidir row start.
                # Each "label value unit" group has a fixed total width.
                bleft "     ${DIM}RTT${NC}"\
"  ${DIM}min${NC} ${GREEN}${f_min}${NC}${DIM}ms${NC}"\
"  ${DIM}avg${NC} ${avg_col}${f_avg}${NC}${DIM}ms${NC}"\
"  ${DIM}max${NC} ${YELLOW}${f_max}${NC}${DIM}ms${NC}"\
"  ${DIM}jitter${NC} ${CYAN}${f_jit}${NC}${DIM}ms${NC}"\
"  ${DIM}loss${NC} ${loss_col}${f_loss}${NC}"\
"  ${DIM}(${f_cnt} smpl)${NC}"
            fi
        fi

        # ==============================================================
        # CWND inline row (TCP non-loopback, at least 1 sample)
        # ==============================================================
        if [[ "${S_PROTO[$i]:-TCP}" == "TCP" ]] && \
           [[ ! "$stream_tgt" =~ ^127\. && "$stream_tgt" != "::1" ]] && \
           [[ "${S_CWND_SAMPLES[$i]:-0}" != "0" ]]; then

            local cw_cur="${S_CWND_CURRENT[$i]:----}"
            local cw_min="${S_CWND_MIN[$i]:----}"
            local cw_max="${S_CWND_MAX[$i]:----}"
            local cw_avg; cw_avg=$(_cwnd_avg "$i")

            local f_cur f_min_cw f_max_cw f_avg_cw
            f_cur=$(printf    '%7s' "$cw_cur")
            f_min_cw=$(printf '%7s' "$cw_min")
            f_max_cw=$(printf '%7s' "$cw_max")
            f_avg_cw=$(printf '%7s' "$cw_avg")

            # Colour by magnitude
            local cw_col="$GREEN"
            local cw_int
            cw_int=$(printf '%.0f' "$cw_cur" 2>/dev/null || printf '0')
            if   (( cw_int <  10  )); then cw_col="$RED"
            elif (( cw_int <  50  )); then cw_col="$YELLOW"
            elif (( cw_int < 200  )); then cw_col="$CYAN"
            fi

            bleft "     ${DIM}cwnd${NC}"\
"  ${DIM}cur${NC} ${cw_col}${f_cur}${NC}${DIM}KB${NC}"\
"  ${DIM}min${NC} ${CYAN}${f_min_cw}${NC}${DIM}KB${NC}"\
"  ${DIM}max${NC} ${YELLOW}${f_max_cw}${NC}${DIM}KB${NC}"\
"  ${DIM}avg${NC} ${f_avg_cw}${DIM}KB${NC}"
        fi

        # ==============================================================
        # Ramp timeline row (ramp-enabled streams only)
        # ==============================================================
        if [[ "${S_RAMP_ENABLED[$i]:-0}" == "1" ]]; then
            local ramp_phase="${S_RAMP_PHASE[$i]:-RAMPUP}"
            local ramp_bw_cur="${S_RAMP_BW_CURRENT[$i]:----}"
            local ramp_tgt="${S_RAMP_BW_TARGET[$i]:----}"

            local ramp_phase_col ramp_phase_lbl
            case "$ramp_phase" in
                RAMPUP)   ramp_phase_col="$GREEN";  ramp_phase_lbl="↑ RAMP UP  " ;;
                HOLD)     ramp_phase_col="$CYAN";   ramp_phase_lbl="— HOLD     " ;;
                RAMPDOWN) ramp_phase_col="$YELLOW"; ramp_phase_lbl="↓ RAMP DOWN" ;;
                DONE)     ramp_phase_col="$DIM";    ramp_phase_lbl="✓ DONE     " ;;
                *)        ramp_phase_col="$DIM";    ramp_phase_lbl="  ---      " ;;
            esac

            local ramp_curve
            ramp_curve=$(_ramp_timeline_render "$i" 30)

            local ramp_cur_f ramp_tgt_f
            ramp_cur_f=$(printf '%6s' "$ramp_bw_cur")
            ramp_tgt_f=$(printf '%6s' "$ramp_tgt")

            bleft "     ${DIM}ramp${NC} ${ramp_phase_col}${ramp_curve}${NC}"\
" ${ramp_phase_col}${ramp_phase_lbl}${NC}"\
"  ${DIM}cur${NC} ${ramp_phase_col}${ramp_cur_f}${NC}"\
"  ${DIM}tgt${NC} ${ramp_tgt_f}"
        fi

        # ==============================================================
        # Progress bar row (fixed-duration non-FAILED streams only)
        # Indented to align under the Bandwidth column.
        # ==============================================================
        if (( show_bar == 1 )); then
            local bar_str; bar_str=$(_render_progress_bar "$stream_elapsed" "$dur")
            # Indent = 5(prefix) + 1 + C_SN + 1 + C_PROTO + 1 + C_TARGET + 1 + C_PORT + 1
            local bar_indent=$(( _PFX_W + 1 + C_SN + 1 + C_PROTO + 1 + C_TARGET + 1 + C_PORT + 1 ))
            bleft "$(printf '%*s' "$bar_indent" '')${bar_str}"
        fi

        # ==============================================================
        # Per-stream separator (between streams, not after the last)
        # ==============================================================
        (( i < STREAM_COUNT - 1 )) && bline '-'

    done  # end per-stream loop

    # ------------------------------------------------------------------
    # Footer
    # ------------------------------------------------------------------
    bline '='
    if _all_streams_loopback; then
        bleft "  ${YELLOW}Ctrl+C${NC} to stop all streams"
    else
        bleft "  ${YELLOW}Ctrl+C${NC} to stop all streams  ${DIM}|${NC}  ${CYAN}[v/p]${NC} DSCP verify"
    fi
    bline '='

    # ------------------------------------------------------------------
    # Notification banner — always exactly 1 line
    # ------------------------------------------------------------------
    local _notify_msg
    _notify_msg="$(_assoc_get G_LAST_NOTIFY 0 2>/dev/null)"
    if [[ -n "$_notify_msg" ]]; then
        local _max_len=$(( COLS - 4 ))
        (( ${#_notify_msg} > _max_len )) && \
            _notify_msg="${_notify_msg:0:${_max_len}}…"
        local _padded
        printf -v _padded "%-${COLS}s" "  ${_notify_msg}"
        printf '\033[1;97;42m%s\033[0m\033[K\n' "$_padded"
    else
        printf '\033[K\n'
    fi

    # ------------------------------------------------------------------
    # Restore errexit state
    # ------------------------------------------------------------------
    (( _old_errexit == 1 )) && set -e
}

# =============================================================================
# _render_server_frame  (alignment-fixed)
#
# FIXES:
#   1. All column widths are defined as named constants that sum exactly
#      to COLS-2 minus the separator spaces, so every row fills the box.
#   2. Every row is built with printf -v into a plain-text variable first,
#      then passed to bleft() as a single string. bleft() calls vlen()
#      once on the complete string and pads to exactly INNER chars.
#   3. The column header uses the identical C_* constants as data rows
#      so header and data always align.
#   4. The footer hint is built the same way — plain text measured by
#      bleft() — so the right border is always flush.
#   5. The counter row uses printf -v so the variable-width numbers
#      never cause the right border to drift.
#
# BOX GEOMETRY (COLS = 80):
#   INNER = 78  (chars between the two border pipes)
#
#   Row layout:
#     " " C_SN "  " C_PORT "  " C_BIND "  " C_VRF "  " C_BW "  " C_SPARK "  " C_STAT
#      1 + C_SN + 2 + C_PORT + 2 + C_BIND + 2 + C_VRF + 2 + C_BW + 2 + C_SPARK + 2 + C_STAT
#
#   Chosen widths that sum to 78:
#     C_SN=2  C_PORT=5  C_BIND=16  C_VRF=8  C_BW=13  C_SPARK=10  C_STAT=9
#     gaps = 1+2+2+2+2+2+2 = 13
#     total = 2+5+16+8+13+10+9 + 13 = 76  → +2 for the leading " " and trailing " " = 78 ✓
# =============================================================================

_render_server_frame() {

    # ------------------------------------------------------------------
    # Disable errexit — arithmetic (( )) returns 1 when result is 0,
    # which kills the script under set -e. This function is purely
    # presentational and must never exit early.
    # ------------------------------------------------------------------
    local _old_errexit=0
    [[ $- == *e* ]] && _old_errexit=1
    set +e

    # ------------------------------------------------------------------
    # Box geometry
    # ------------------------------------------------------------------
    local INNER=$(( COLS - 2 ))

    # ------------------------------------------------------------------
    # Column widths — defined once, used everywhere.
    # Adjust C_BIND or C_VRF if you need more room; keep the sum below.
    #
    #   1(lead) + C_SN + 2 + C_PORT + 2 + C_BIND + 2 + C_VRF
    #           + 2 + C_BW + 2 + C_SPARK + 2 + C_STAT + 1(trail)
    #   = 1+2+2+5+2+16+2+8+2+13+2+10+2+9+1 = 77 … need 78
    #   → add 1 to C_STAT → C_STAT=10 gives 78 ✓
    # ------------------------------------------------------------------
    local C_SN=2
    local C_PORT=5
    local C_BIND=16
    local C_VRF=8
    local C_BW=13
    local C_SPARK=10
    local C_STAT=10

    # Verify: 1+C_SN+2+C_PORT+2+C_BIND+2+C_VRF+2+C_BW+2+C_SPARK+2+C_STAT+1
    # = 1+2+2+5+2+16+2+8+2+13+2+10+2+10+1 = 78 = INNER  ✓

    # ------------------------------------------------------------------
    # Count running listeners
    # ------------------------------------------------------------------
    local running=0 i
    for (( i=0; i<SERVER_COUNT; i++ )); do
        local pid="${SERVER_PIDS[$i]:-0}"
        [[ "$pid" != "0" ]] && kill -0 "$pid" 2>/dev/null && (( running++ ))
    done

    # ------------------------------------------------------------------
    # Header block
    # ------------------------------------------------------------------
    bline '='
    bcenter "${BOLD}${CYAN}PRISM — Server Dashboard${NC}"
    bline '='

    # Counter row
    # bleft() pads to INNER so the right border is always flush.
    bleft "  Listeners active: ${running} / ${SERVER_COUNT}"
    bline '='

    # ------------------------------------------------------------------
    # Column header
    # Built with printf -v using the same C_* constants as data rows.
    # BOLD wrapping is added outside the printf so the plain-text
    # length is exactly what vlen() measures.
    # ------------------------------------------------------------------
    local _hdr
    printf -v _hdr \
        " %-*s  %*s  %-*s  %-*s  %-*s  %-*s  %-*s" \
        "$C_SN"     "#" \
        "$C_PORT"   "Port" \
        "$C_BIND"   "Bind IP" \
        "$C_VRF"    "VRF" \
        "$C_BW"     "Bandwidth" \
        "$C_SPARK"  "Last 10s" \
        "$C_STAT"   "Status"
    bleft "${BOLD}${_hdr}${NC}"
    bline '-'

    # ------------------------------------------------------------------
    # Per-listener data rows
    # ------------------------------------------------------------------
    for (( i=0; i<SERVER_COUNT; i++ )); do
        local sn=$(( i + 1 ))

        # Resolve log file
        local lf="${SRV_LOGFILE[$i]:-}"
        [[ -z "$lf" ]] && lf="${TMPDIR}/server_${sn}.log"

        # Probe server status (writes into SRV_PREV_STATE[$i] directly)
        probe_server_status "$i"
        local st="${SRV_PREV_STATE[$i]:-STARTING}"

        # ── Live bandwidth ──────────────────────────────────────────────
        local bw="---"
        case "$st" in
            CONNECTED|RUNNING)
                local live_bw
                live_bw=$(_parse_srv_live_bw "$lf")
                if [[ -n "$live_bw" && "$live_bw" != "---" ]]; then
                    bw="$live_bw"
                    SRV_BW_CACHE[$i]="$live_bw"
                else
                    local _cached="${SRV_BW_CACHE[$i]:-}"
                    [[ -n "$_cached" && "$_cached" != "---" ]] && bw="$_cached"
                fi
                ;;
            LISTENING|STARTING)
                bw="---"
                SRV_BW_CACHE[$i]="---"
                ;;
        esac

        # ── Sparkline ───────────────────────────────────────────────────
        case "$st" in
            CONNECTED|RUNNING)
                [[ -n "$bw" && "$bw" != "---" ]] && \
                    _spark_push "s" "$i" "$bw"
                ;;
        esac
        local spark_str; spark_str=$(_spark_render "s" "$i")

        # ── Status colour ───────────────────────────────────────────────
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

        # ── Field preparation — truncate to column caps ─────────────────
        local vrf_disp="${SRV_VRF[$i]:-GRT}"
        [[ "$OS_TYPE" == "macos" ]] && vrf_disp="N/A"

        local bind_disp="${SRV_BIND[$i]:-0.0.0.0}"
        local bw_disp="$bw"

        # Truncate with ~ indicator if over column width
        if (( ${#bind_disp} > C_BIND )); then
            bind_disp="${bind_disp:0:$(( C_BIND - 1 ))}~"
        fi
        if (( ${#vrf_disp} > C_VRF )); then
            vrf_disp="${vrf_disp:0:$(( C_VRF - 1 ))}~"
        fi
        if (( ${#bw_disp} > C_BW )); then
            bw_disp="${bw_disp:0:$(( C_BW - 1 ))}~"
        fi

        # ── Build plain-text portion with printf -v ─────────────────────
        # This gives bleft() / vlen() a clean ASCII string to measure.
        # The coloured status is appended outside printf so ANSI bytes
        # are never counted in the printf field widths.
        local _row_plain
        printf -v _row_plain \
            " %-*s  %*s  %-*s  %-*s  %-*s  %-*s  " \
            "$C_SN"    "$sn" \
            "$C_PORT"  "${SRV_PORT[$i]}" \
            "$C_BIND"  "$bind_disp" \
            "$C_VRF"   "$vrf_disp" \
            "$C_BW"    "$bw_disp" \
            "$C_SPARK" "$spark_str"

        # Append coloured status, padded to C_STAT visible chars.
        # The trailing space is already included in _row_plain above.
        bleft "${_row_plain}${sc}$(printf '%-*s' "$C_STAT" "$sb")${NC}"

        # Per-listener separator (between rows, not after the last)
        if (( i < SERVER_COUNT - 1 )); then
            bline '-'
        fi
    done

    # ------------------------------------------------------------------
    # Footer
    # bleft() handles padding so the right border is always flush,
    # regardless of how long the hint text is.
    # ------------------------------------------------------------------
    bline '='
    bleft "  ${YELLOW}Ctrl+C${NC} to stop all listeners  ${DIM}|${NC}  ${CYAN}[c]${NC} Packet capture"
    bline '='

    # ------------------------------------------------------------------
    # Restore errexit
    # ------------------------------------------------------------------
    (( _old_errexit == 1 )) && set -e
}

# =============================================================================
# run_dashboard  <mode>
#
# KEY CHANGES vs previous version:
#
#   1. _RENDER_LOCK=1 is set immediately before _render_server_frame /
#      _render_client_frame is called and cleared immediately after.
#      Signal handlers that fire during this window set _DEFERRED_SIGNAL
#      instead of acting, so no signal text can be injected mid-frame.
#
#   2. After clearing _RENDER_LOCK, the deferred signal is dispatched
#      at the safe point between cursor-restore and the keyboard poll.
#      This guarantees the frame is always complete before any signal
#      handler output appears on screen.
#
#   3. _LAST_FRAME_LINE_COUNT is updated immediately after the render
#      lock is released so _trap_cursor_exit always has the correct
#      frame height even when the signal fires on the very first tick.
#
#   4. The final cursor-repositioning block uses the same
#      \033[u + \033[NB + \033[J sequence as _trap_cursor_exit so
#      normal exit and signal exit produce identical clean output.
# =============================================================================
run_dashboard() {
    local mode="${1:-client}"
    local count
    [[ "$mode" == "server" ]] && count=$SERVER_COUNT || count=$STREAM_COUNT

    # Initialise per-stream cleanup tracking
    if [[ "$mode" != "server" ]]; then
        local _ci
        for (( _ci=0; _ci<STREAM_COUNT; _ci++ )); do
            S_CLEANUP_QUEUED[$_ci]="${S_CLEANUP_QUEUED[$_ci]:-0}"
        done
    fi

    # Initial status probe before pre-reservation
    if [[ "$mode" != "server" ]]; then
        local j
        for (( j=0; j<STREAM_COUNT; j++ )); do
            probe_client_status "$j"
        done
    fi

    # Calculate pre-reserve line count
    local pre_lines
    if [[ "$mode" == "server" ]]; then
        pre_lines=$(_count_server_frame_lines)
    else
        pre_lines=$(_count_client_frame_lines_for_state)
    fi

    FRAME_LINES=$pre_lines
    _PREV_DYNAMIC_LINES=0
    local _last_total=$pre_lines

    # Update the global so _trap_cursor_exit has a valid value from tick 0
    _LAST_FRAME_LINE_COUNT=$pre_lines

    # Reserve vertical space and establish the frame anchor
    local k
    for (( k=0; k<pre_lines; k++ )); do printf '\n'; done
    printf '\033[%dA' "$pre_lines"
    printf '\033[s'
    printf '\033[?25l'

    # Reset deferred signal state
    _DEFERRED_SIGNAL=""
    _RENDER_LOCK=0

    local _dashboard_running=1

    # =========================================================================
    # Main render loop
    # =========================================================================
    while (( _dashboard_running == 1 )); do

        # ── Per-tick state probe ───────────────────────────────────────────
        if [[ "$mode" != "server" ]]; then
            local j
            for (( j=0; j<STREAM_COUNT; j++ )); do
                probe_client_status "$j"
            done
        fi

        # ── Phase A: queue finished streams for cleanup ────────────────────
        if [[ "$mode" != "server" ]]; then
            local _si
            for (( _si=0; _si<STREAM_COUNT; _si++ )); do
                local _cur_st="${S_STATUS_CACHE[$_si]:-}"
                if [[ "$_cur_st" == "DONE" || "$_cur_st" == "FAILED" ]]; then
                    if [[ "${S_CLEANUP_QUEUED[$_si]:-0}" != "1" && \
                          "${S_CLEANUP_QUEUED[$_si]:-0}" != "2" ]]; then
                        S_CLEANUP_QUEUED[$_si]="1"
                        S_STATUS_CACHE[$_si]="CLEANUP_PENDING"
                    fi
                fi
            done
        fi

        # ── Restore cursor to top of frame ────────────────────────────────
        printf '\033[u'

        # ── RENDER — protected by _RENDER_LOCK ────────────────────────────
        # Any signal that arrives between the lock set and lock clear is
        # deferred into _DEFERRED_SIGNAL and dispatched below.
        _RENDER_LOCK=1

        if [[ "$mode" == "server" ]]; then
            _render_server_frame
        else
            _render_client_frame
        fi

        _RENDER_LOCK=0
        # ── End of protected render ────────────────────────────────────────

        # ── Update exact line count AFTER render ───────────────────────────
        # Must happen with _RENDER_LOCK=0 so the count is available to
        # _trap_cursor_exit if a deferred signal is dispatched next.
        local fixed_lines
        if [[ "$mode" == "server" ]]; then
            fixed_lines=$(_count_server_frame_lines)
        else
            # Inline _fc calculation (main shell context — not a subshell)
            local _fc=11
            local _fci _fcst _fctgt _fctgt_disp _fctgt_raw

            for (( _fci=0; _fci<STREAM_COUNT; _fci++ )); do
                _fcst="${S_STATUS_CACHE[$_fci]:-STARTING}"
                _fctgt="${S_TARGET[$_fci]:-}"

                if [[ "$_fcst" == "CLEANED" || \
                      "$_fcst" == "CLEANUP_PENDING" ]]; then
                    _fc=$(( _fc + 1 ))
                    if (( _fci < STREAM_COUNT - 1 )); then
                        _fc=$(( _fc + 1 ))
                    fi
                    continue
                fi

                _fc=$(( _fc + 1 ))   # TX row

                _fctgt_raw="${S_TARGET[$_fci]:-}"
                _fctgt_disp="${S_TARGET_DISPLAY[$_fci]:-$_fctgt_raw}"
                if [[ -n "${S_TARGET_DISPLAY[$_fci]:-}" && \
                      "${S_TARGET_DISPLAY[$_fci]}" != "$_fctgt_raw" ]] || \
                   (( ${#_fctgt_disp} > 15 )); then
                    _fc=$(( _fc + 1 ))   # FQDN target line
                fi

                [[ "${S_BIDIR[$_fci]:-0}" == "1" ]] && \
                    _fc=$(( _fc + 1 ))   # RX row

                if [[ ! "$_fctgt" =~ ^127\. && "$_fctgt" != "::1" ]]; then
                    _fc=$(( _fc + 1 ))   # RTT row
                fi

                if [[ "${S_PROTO[$_fci]:-TCP}" == "TCP" ]] && \
                   [[ ! "$_fctgt" =~ ^127\. && "$_fctgt" != "::1" ]] && \
                   [[ "${S_CWND_SAMPLES[$_fci]:-0}" != "0" ]]; then
                    _fc=$(( _fc + 1 ))   # CWND row
                fi

                [[ "${S_RAMP_ENABLED[$_fci]:-0}" == "1" ]] && \
                    _fc=$(( _fc + 1 ))   # Ramp row

                if (( S_DURATION[$_fci] > 0 )) && \
                   [[ "$_fcst" != "FAILED" ]]; then
                    _fc=$(( _fc + 1 ))   # Progress bar
                fi

                if (( _fci < STREAM_COUNT - 1 )); then
                    _fc=$(( _fc + 1 ))   # Per-stream separator
                fi
            done

            fixed_lines=$_fc
        fi

        # Erase stale content below the current frame
        printf '\033[J'

        # ── Dynamic panels (client mode only) ─────────────────────────────
        local completed_lines=0 failed_lines=0
        if [[ "$mode" != "server" ]]; then
            completed_lines=$(_count_completed_panel_lines)
            failed_lines=$(_count_failed_panel_lines)
            (( completed_lines > 0 )) && _render_completed_panel
            (( failed_lines    > 0 )) && _render_failed_panel
        fi

        # ── DSCP verify hint block (client non-loopback) ──────────────────
        local _hint_lines=0
        if [[ "$mode" != "server" ]] && ! _all_streams_loopback; then
            local _any_verifiable=0
            local _ji
            for (( _ji=0; _ji<STREAM_COUNT; _ji++ )); do
                if [[ "${S_STATUS_CACHE[$_ji]}" == "CONNECTED" ]] && \
                   [[ ! "${S_TARGET[$_ji]:-}" =~ ^127\. ]] && \
                   [[ "${S_TARGET[$_ji]:-}" != "::1" ]]; then
                    _any_verifiable=1
                    break
                fi
            done
            printf '\033[K\n'
            if (( _any_verifiable == 1 )); then
                printf '  %b[v/p]%b  Verify DSCP marking for a stream\033[K\n' \
                    "$DIM" "$NC"
            else
                printf '\033[K\n'
            fi
            printf '\033[K\n'
            _hint_lines=3
        fi

        # ── Record total lines printed and re-anchor cursor ────────────────
        local dynamic_lines=$(( completed_lines + failed_lines ))
        _last_total=$(( fixed_lines + dynamic_lines + _hint_lines ))
        _PREV_DYNAMIC_LINES=$(( completed_lines + failed_lines ))

        # Update global BEFORE re-saving anchor so _trap_cursor_exit
        # always has the correct value when a deferred signal fires.
        _LAST_FRAME_LINE_COUNT=$_last_total

        if (( _last_total > 0 )); then
            printf '\033[%dA' "$_last_total"
        fi
        printf '\033[s'   # re-save anchor at top of rendered frame

        # ── Dispatch deferred signal ───────────────────────────────────────
        # The render is complete, the cursor is anchored, and
        # _LAST_FRAME_LINE_COUNT is current. Safe to handle the signal now.
        if [[ -n "$_DEFERRED_SIGNAL" ]]; then
            local _sig="$_DEFERRED_SIGNAL"
            _DEFERRED_SIGNAL=""
            _RENDER_LOCK=0
            case "$_sig" in
                INT)
                    _trap_cursor_exit
                    tty_echo "${BOLD}${YELLOW}  PRISM [SIGINT]  Ctrl+C — stopping...${NC}"
                    cleanup "SIGINT (Ctrl+C)"
                    exit 130
                    ;;
                TERM)
                    _trap_cursor_exit
                    tty_echo "${BOLD}${YELLOW}  PRISM [SIGTERM] Stopping...${NC}"
                    cleanup "SIGTERM"
                    exit 143
                    ;;
                QUIT)
                    _trap_cursor_exit
                    tty_echo "${BOLD}${YELLOW}  PRISM [SIGQUIT] Ctrl+\\ — stopping...${NC}"
                    cleanup "SIGQUIT"
                    exit 131
                    ;;
                HUP)
                    _trap_cursor_exit
                    tty_echo "${BOLD}${YELLOW}  PRISM [SIGHUP]  Terminal closed — stopping...${NC}"
                    cleanup "SIGHUP"
                    exit 129
                    ;;
            esac
        fi

        # ── Phase B: run cleanup for queued streams ────────────────────────
        if [[ "$mode" != "server" ]]; then
            local _si
            for (( _si=0; _si<STREAM_COUNT; _si++ )); do
                if [[ "${S_STATUS_CACHE[$_si]:-}"   == "CLEANUP_PENDING" && \
                      "${S_CLEANUP_QUEUED[$_si]:-0}" == "1" ]]; then
                    S_CLEANUP_QUEUED[$_si]="2"
                    _cleanup_stream_procs "$_si"
                fi
            done
        fi

        # ── Exit condition (client mode) ───────────────────────────────────
        if [[ "$mode" != "server" ]]; then
            local _all_finished=1
            local j
            for (( j=0; j<STREAM_COUNT; j++ )); do
                local _jst="${S_STATUS_CACHE[$j]:-STARTING}"
                case "$_jst" in
                    CLEANED|FAILED) ;;
                    CLEANUP_PENDING)
                        [[ "${S_CLEANUP_QUEUED[$j]:-0}" != "2" ]] && \
                            _all_finished=0
                        ;;
                    DONE)
                        if [[ "${S_CLEANUP_QUEUED[$j]:-0}" == "2" ]]; then
                            S_STATUS_CACHE[$j]="CLEANED"
                        else
                            [[ "${S_CLEANUP_QUEUED[$j]:-0}" == "0" ]] && {
                                S_CLEANUP_QUEUED[$j]="1"
                                S_STATUS_CACHE[$j]="CLEANUP_PENDING"
                            }
                            _all_finished=0
                        fi
                        ;;
                    *) _all_finished=0; break ;;
                esac
            done
            (( _all_finished == 1 )) && _dashboard_running=0
        fi

        # ── Non-blocking keyboard poll (~1 s per tick) ────────────────────
        local key_pressed="" key_lower=""
        local tick_slice
        for (( tick_slice=0; tick_slice<10; tick_slice++ )); do
            (( _dashboard_running == 0 )) && break

            if IFS= read -r -s -n 1 -t 0.1 \
                   key_pressed </dev/tty 2>/dev/null; then
                key_lower=$(printf '%s' "$key_pressed" \
                    | tr '[:upper:]' '[:lower:]')
                break
            fi
            key_pressed=""
            key_lower=""

            # Check for deferred signal between slices
            if [[ -n "$_DEFERRED_SIGNAL" ]]; then
                break
            fi

            (( CLEANUP_DONE == 1 )) && {
                _dashboard_running=0
                break
            }
        done

        # Dispatch any signal that arrived during the keyboard poll
        if [[ -n "$_DEFERRED_SIGNAL" ]]; then
            local _sig="$_DEFERRED_SIGNAL"
            _DEFERRED_SIGNAL=""
            _RENDER_LOCK=0
            case "$_sig" in
                INT)
                    _trap_cursor_exit
                    tty_echo "${BOLD}${YELLOW}  PRISM [SIGINT]  Ctrl+C — stopping...${NC}"
                    cleanup "SIGINT (Ctrl+C)"
                    exit 130
                    ;;
                TERM)
                    _trap_cursor_exit
                    tty_echo "${BOLD}${YELLOW}  PRISM [SIGTERM] Stopping...${NC}"
                    cleanup "SIGTERM"
                    exit 143
                    ;;
                QUIT)
                    _trap_cursor_exit
                    tty_echo "${BOLD}${YELLOW}  PRISM [SIGQUIT] Ctrl+\\ — stopping...${NC}"
                    cleanup "SIGQUIT"
                    exit 131
                    ;;
                HUP)
                    _trap_cursor_exit
                    tty_echo "${BOLD}${YELLOW}  PRISM [SIGHUP]  Terminal closed — stopping...${NC}"
                    cleanup "SIGHUP"
                    exit 129
                    ;;
            esac
        fi

        (( CLEANUP_DONE == 1 )) && { _dashboard_running=0; continue; }

        # ── DSCP verify keypress handler ───────────────────────────────────
        if [[ "$mode" != "server" ]]   && \
           ! _all_streams_loopback     && \
           [[ "$key_lower" == "v" || "$key_lower" == "p" ]]; then

            printf '\033[?25h'
            printf '\033[%dB' "$_last_total"
            _dscp_verify_interactive

            local j
            for (( j=0; j<STREAM_COUNT; j++ )); do
                probe_client_status "$j"
            done

            local new_pre
            new_pre=$(_count_client_frame_lines_for_state)
            FRAME_LINES=$new_pre
            _LAST_FRAME_LINE_COUNT=$new_pre

            for (( k=0; k<new_pre; k++ )); do printf '\n'; done
            printf '\033[%dA' "$new_pre"
            printf '\033[s'
            printf '\033[?25l'
            _last_total=$new_pre
        fi

        # ── Packet capture keypress handler (server mode) ─────────────────
        if [[ "$mode" == "server" ]] && [[ "$key_lower" == "c" ]]; then

            printf '\033[?25h'
            printf '\033[%dB' "$_last_total"
            _dscp_verify_server_interactive

            local new_pre
            new_pre=$(_count_server_frame_lines)
            FRAME_LINES=$new_pre
            _LAST_FRAME_LINE_COUNT=$new_pre

            for (( k=0; k<new_pre; k++ )); do printf '\n'; done
            printf '\033[%dA' "$new_pre"
            printf '\033[s'
            printf '\033[?25l'
            _last_total=$new_pre
        fi

    done
    # =========================================================================
    # End of render loop
    # =========================================================================

    # ── Restore terminal state ─────────────────────────────────────────────
    printf '\033[?25h'

    # ── Move cursor cleanly below the rendered output ──────────────────────
    # Restore to the saved anchor then advance past the full frame.
    # \033[J erases any ghost lines left by a previously taller frame.
    if (( _last_total > 0 )); then
        printf '\033[u\033[%dB\033[J' "$_last_total"
    else
        printf '\033[u\033[J'
    fi
    printf '\n'

    # ── Flush buffered stream cleanup event log ────────────────────────────
    local _log_file="/tmp/iperf3_streams_events.log"
    if [[ -f "$_log_file" ]]; then
        printf '\n'
        while IFS= read -r _log_line; do
            printf '  %s\n' "$_log_line"
        done < "$_log_file"
        rm -f "$_log_file"
        printf '\n'
    fi
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
        # CLEANED and CLEANUP_PENDING are post-completion states that still
        # have valid log data available (files not deleted until Phase 2).
        # Treat them identically to DONE for results parsing.

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
    echo ""
    print_header "PRISM — Final Results"
    _print_session_header "Final Results"
    _print_session_name_header
    echo ""

    # ── Fixed column widths for results table ─────────────────────────────
    #   C_SN     =  3
    #   C_PROTO  =  5
    #   C_TGT    = 15
    #   C_PORT   =  5
    #   C_SBW    = 12   sender BW
    #   C_RBW    = 12   receiver BW
    #   C_EXTRA  = 20   TCP retx / UDP jitter+loss
    #   C_RTT    = 21   RTT min/avg/max summary
    # Separators: 7 × 2 = 14  →  total = 3+5+15+5+12+12+20+21+14 = 107
    # At 80 cols we print to stdout (not inside the box) so full width is fine.
    local C_SN=3 C_PROTO=5 C_TGT=15 C_PORT=5
    local C_SBW=12 C_RBW=12 C_EXTRA=20 C_RTT=21

    local sep_len=$(( C_SN+2+C_PROTO+2+C_TGT+2+C_PORT+2+C_SBW+2+C_RBW+2+C_EXTRA+2+C_RTT ))

    # ── Header row ────────────────────────────────────────────────────────
    printf '  %s\n' "$(rpt '─' "$sep_len")"
    printf '  %-*s  %-*s  %-*s  %*s  %-*s  %-*s  %-*s  %-*s\n' \
        "$C_SN"    '#' \
        "$C_PROTO" 'Proto' \
        "$C_TGT"   'Target' \
        "$C_PORT"  'Port' \
        "$C_SBW"   'Sender BW' \
        "$C_RBW"   'Receiver BW' \
        "$C_EXTRA" 'Retx / Jitter+Loss' \
        "$C_RTT"   'RTT min/avg/max ms'
    printf '  %s\n' "$(rpt '─' "$sep_len")"

    local i
    for (( i=0; i<STREAM_COUNT; i++ )); do
        local sn=$(( i + 1 ))
        local proto="${S_PROTO[$i]}"
        local tgt="${S_TARGET[$i]:-?}"
        (( ${#tgt} > C_TGT )) && tgt="${tgt:0:$(( C_TGT - 1 ))}~"

        # ── Failed stream row ─────────────────────────────────────────────
        if [[ "${S_STATUS_CACHE[$i]}" == "FAILED" ]]; then
            local err="${S_ERROR_MSG[$i]:-Connection failed}"
            local err_max=$(( sep_len - C_SN - 2 - C_PROTO - 2 - C_TGT - 2 - C_PORT - 2 - 8 ))
            (( ${#err} > err_max )) && err="${err:0:$(( err_max - 3 ))}..."
            printf '  %b%-*s%b  %-*s  %-*s  %*s  %bFAILED: %s%b\n' \
                "$RED"  "$C_SN"    "$sn"    "$NC" \
                "$C_PROTO" "$proto" \
                "$C_TGT"   "$tgt" \
                "$C_PORT"  "${S_PORT[$i]}" \
                "$RED" "$err" "$NC"
        # ── Normal stream row ─────────────────────────────────────────────
        else
            local extra
            [[ "$proto" == "TCP" ]] \
                && extra="Retx: ${RESULT_RTX[$i]:-0}" \
                || extra="J:${RESULT_JITTER[$i]:-N/A} L:${RESULT_LOSS_PCT[$i]:-N/A}"

            # RTT summary
            local rtt_col="$GREEN" rtt_sum="---"
            local rmin="${S_RTT_MIN[$i]:-}" ravg="${S_RTT_AVG[$i]:-}"
            local rmax="${S_RTT_MAX[$i]:-}" rsamples="${S_RTT_SAMPLES[$i]:-0}"
            if [[ -n "$ravg" && "$ravg" != "---" && "$rsamples" != "0" ]]; then
                rtt_sum=$(printf '%s/%s/%s' "$rmin" "$ravg" "$rmax")
                local avg_int
                avg_int=$(printf '%.0f' "$ravg" 2>/dev/null || printf '9999')
                if   (( avg_int > 150 )); then rtt_col="$RED"
                elif (( avg_int > 50  )); then rtt_col="$YELLOW"
                elif (( avg_int > 10  )); then rtt_col="$CYAN"
                fi
            fi

            # ──— TX row ───────────────────────────────
            local tx_pfx=""
            [[ "${S_BIDIR[$i]:-0}" == "1" ]] && tx_pfx="${GREEN}→ TX${NC}  "

            printf '  %b%-*s%b  %-*s  %-*s  %*s  %b%-*s%b  %b%-*s%b  %-*s  %b%-*s%b\n' \
                "$GREEN"   "$C_SN"    "$sn"    "$NC" \
                "$C_PROTO" "$proto" \
                "$C_TGT"   "$tgt" \
                "$C_PORT"  "${S_PORT[$i]}" \
                "$GREEN"   "$C_SBW"   "${RESULT_SENDER_BW[$i]:-N/A}"   "$NC" \
                "$CYAN"    "$C_RBW"   "${RESULT_RECEIVER_BW[$i]:-N/A}" "$NC" \
                "$C_EXTRA" "$extra" \
                "$rtt_col" "$C_RTT"   "$rtt_sum"  "$NC"

            # ──— RX row (bidirectional only) ──────────
            if [[ "${S_BIDIR[$i]:-0}" == "1" ]]; then
                local rx_final; rx_final=$(_bidir_final_bw "$i")
                printf '  %b%-*s%b  %-*s  %-*s  %*s  %b%-*s%b  %-*s  %-*s  %-*s\n' \
                    "$CYAN"  "$C_SN"    "←RX"   "$NC" \
                    "$C_PROTO" "" \
                    "$C_TGT"   "" \
                    "$C_PORT"  "" \
                    "$CYAN"  "$C_SBW"  "$rx_final" "$NC" \
                    "$C_RBW"  "(reverse)" \
                    "$C_EXTRA" "" \
                    "$C_RTT"  ""
            fi
        fi

        # ── MTU annotation ────────────────────────────────────────────────
        _pmtu_annotate_stream_summary "$i"

        # ── CWND results sub-row (TCP non-loopback only) ──────────────────
        if [[ "${S_PROTO[$i]:-TCP}" == "TCP" && \
              ! "${S_TARGET[$i]:-}" =~ ^127\. && \
              "${S_TARGET[$i]:-}" != "::1" && \
              "${S_CWND_SAMPLES[$i]:-0}" != "0" ]]; then

            local rc_min="${S_CWND_MIN[$i]:----}"
            local rc_max="${S_CWND_MAX[$i]:----}"
            local rc_fin="${S_CWND_FINAL[$i]:----}"
            local rc_avg; rc_avg=$(_cwnd_avg "$i")
            local rc_smp="${S_CWND_SAMPLES[$i]:-0}"

            # Fixed-width fields — 7 chars (e.g. "  94.6")
            local rf_min rf_max rf_fin rf_avg
            rf_min=$(printf '%7s' "$rc_min")
            rf_max=$(printf '%7s' "$rc_max")
            rf_fin=$(printf '%7s' "$rc_fin")
            rf_avg=$(printf '%7s' "$rc_avg")

            # Colour final value by magnitude
            local rf_col="$GREEN"
            local rf_int
            rf_int=$(printf '%.0f' "$rc_fin" 2>/dev/null || printf '0')
            if   (( rf_int < 10  )); then rf_col="$RED"
            elif (( rf_int < 50  )); then rf_col="$YELLOW"
            elif (( rf_int < 200 )); then rf_col="$CYAN"
            fi

            # Indent 36 chars to align under Sender BW column
            printf '  %-36s' ''
            printf '%b' "${BOLD}${CYAN}cwnd${NC}  "
            printf '%b' "${DIM}min${NC} ${CYAN}${rf_min}${NC}${DIM}KB${NC}  "
            printf '%b' "${DIM}max${NC} ${YELLOW}${rf_max}${NC}${DIM}KB${NC}  "
            printf '%b' "${DIM}avg${NC} ${rf_avg}${DIM}KB${NC}  "
            printf '%b' "${DIM}final${NC} ${rf_col}${rf_fin}${NC}${DIM}KB${NC}"
            printf '  %b(%d smpl)%b\n' "$DIM" "$rc_smp" "$NC"
        fi

        # ── Ramp profile summary (ramp-enabled streams only) ──────────────
        if [[ "${S_RAMP_ENABLED[$i]:-0}" == "1" ]]; then
            local rs_up="${S_RAMP_UP[$i]:-0}"
            local rs_dn="${S_RAMP_DOWN[$i]:-0}"
            local rs_tgt="${S_RAMP_BW_TARGET[$i]:----}"
            local rs_dur="${S_DURATION[$i]:-0}"

            # Compute hold duration
            local rs_hold=$(( rs_dur - rs_up - rs_dn ))
            (( rs_hold < 0 )) && rs_hold=0

            # Use frozen snapshot captured at cleanup time.
            # The live ring buffer is already cleared by this point.
            # Fall back to a live render only if snapshot is empty
            # (e.g. stream failed before any ramp samples were recorded).
            local rs_curve="${S_RAMP_TIMELINE_SNAPSHOT[$i]:-}"
            if [[ -z "$rs_curve" ]]; then
                rs_curve=$(_ramp_timeline_render "$i" 36)
            fi

            # Indent 36 chars to align under Sender BW column
            printf '  %-36s' ''
            printf '%b' "${BOLD}${CYAN}ramp${NC}  "
            printf '%b' "${DIM}↑${NC}${GREEN}${rs_up}s${NC}  "
            printf '%b' "${DIM}hold${NC} ${CYAN}${rs_hold}s${NC}  "
            printf '%b' "${DIM}↓${NC}${YELLOW}${rs_dn}s${NC}  "
            printf '%b' "${DIM}target${NC} ${rs_tgt}  "
            printf '%b\n' "${GREEN}${rs_curve}${NC}"
        fi

        # ── RTT detail sub-row ────────────────────────────────────────────
        local stream_tgt="${S_TARGET[$i]:-}"
        if [[ ! "$stream_tgt" =~ ^127\. && "$stream_tgt" != "::1" ]]; then
            local rmin="${S_RTT_MIN[$i]:-???}"
            local ravg="${S_RTT_AVG[$i]:-???}"
            local rmax="${S_RTT_MAX[$i]:-???}"
            local rjit="${S_RTT_JITTER[$i]:-???}"
            local rloss="${S_RTT_LOSS[$i]:-???}"
            local rsamp="${S_RTT_SAMPLES[$i]:-0}"

            if [[ "$ravg" != "---" && "$ravg" != "???" && "$rsamp" != "0" ]]; then
                # Indent = 36 chars to align under Sender BW column
                printf '  %-36s' ''
                printf '%b' "$DIM"
                printf 'min %7.3f ms  avg %7.3f ms  max %7.3f ms  ' \
                    "$rmin" "$ravg" "$rmax" 2>/dev/null || \
                printf 'min %-7s ms  avg %-7s ms  max %-7s ms  ' \
                    "$rmin" "$ravg" "$rmax"
                printf 'jitter %6.3f ms  loss %-5s  (%d smpl)' \
                    "$rjit" "$rloss" "$rsamp" 2>/dev/null || \
                printf 'jitter %-6s ms  loss %-5s  (%s smpl)' \
                    "$rjit" "$rloss" "$rsamp"
                printf '%b\n' "$NC"
            fi
        fi
        # ── Row separator ─────────────────────────────────────────────────
        if (( i < STREAM_COUNT - 1 )); then
            printf '  %s\n' "$(rpt '·' "$sep_len")"
        fi
    done

    printf '  %s\n' "$(rpt '─' "$sep_len")"
    echo ""

    # ── Completion summary ────────────────────────────────────────────────
    local tf=0 td=0
    for (( i=0; i<STREAM_COUNT; i++ )); do
        case "${S_STATUS_CACHE[$i]}" in
            FAILED)
                (( tf++ ))
                ;;
            DONE|CLEANED|CLEANUP_PENDING)
                # CLEANED and CLEANUP_PENDING are post-completion states —
                # they count as successfully completed streams
                (( td++ ))
                ;;
        esac
    done
    if (( tf > 0 )); then
        printf '%b  %d stream(s) FAILED.  %d completed OK.%b\n' \
            "$RED" "$tf" "$td" "$NC"
    else
        printf '%b  All %d stream(s) completed successfully.%b\n' \
            "$GREEN" "$STREAM_COUNT" "$NC"
    fi

    # ── MTU advisory footer (unchanged) ───────────────────────────────────
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
    echo ""
    print_header "PRISM — Server Mode"
    _print_session_header "Server Mode"
    echo ""
    local n
    while true; do
        read -r -p "  How many listeners? [1]: " n </dev/tty; n="${n:-1}"
        [[ "$n" =~ ^[0-9]+$ ]] && (( 10#$n >= 1 && 10#$n <= 64 )) && break
        printf '%b\n' "${RED}  Enter a positive integer (1-64).${NC}"
    done
    configure_server_streams "$n"
    show_stream_summary "server"
    confirm_proceed "Launch ${n} listener(s)?" || return
    echo ""; launch_servers
    echo ""; printf '%b\n' "${GREEN}  Servers running. Opening dashboard...${NC}"; sleep 1
    run_dashboard "server"
    echo ""; printf '%b\n' "${CYAN}  Server mode ended.${NC}"; echo ""
}


# =============================================================================
# MIXED TRAFFIC PATTERN GENERATOR
# =============================================================================
#
# Allows the operator to define a traffic mix by percentage. The script
# calculates stream counts, per-stream bandwidth, and DSCP markings
# automatically, then launches the resulting streams via run_client_mode
# logic.
#
# Supported traffic classes:
#   TCP Bulk          — large file transfer, no DSCP or AF11/AF21/AF31
#   TCP Interactive   — latency-sensitive TCP, AF41/CS3
#   UDP Real-time     — VoIP/video, EF/AF41/VA
#   UDP Bulk          — background UDP, CS1/CS2
#   UDP Low-priority  — scavenger traffic, CS1/default
#
# Design:
#   1. Operator defines a mix profile (up to 5 classes).
#   2. Each class has a percentage, target IP, port, protocol,
#      DSCP, and optional bandwidth cap.
#   3. The script distributes a total stream count across classes
#      proportionally and allocates bandwidth per stream.
#   4. The resulting configuration is handed to the stream launch
#      machinery exactly as if the operator had configured it manually.
# =============================================================================

# ==============================================================================
# _mtp_show_presets  (Fixed v2)
#
# Renders the Built-in Traffic Mix Presets table inside a box that adapts
# to the current terminal width (COLS).
#
# DESIGN:
#   - All column widths are derived dynamically from COLS so the table
#     renders cleanly at any terminal width from 60 to 220+ columns.
#   - Long Mix Description strings are word-wrapped across continuation
#     lines. Each continuation line prints blank # and Preset Name fields
#     so only the description text wraps — the borders always close cleanly.
#   - The _wrap_text helper splits on spaces (word-aware) and stores each
#     physical line in the _WRAP_LINES[] array (Bash 3.2 compatible).
#   - A visual separator is printed before option 6 (Custom Mix) and
#     option 7 (Back to Main Menu) to group them distinctly.
#   - The session header is rendered at the top using _print_session_header
#     which already handles its own truncation/wrapping.
#
# BOX GEOMETRY (example at COLS=80):
#   "| " + C_NUM(3) + " | " + C_NAME(20) + " | " + C_DESC + " |"
#    2   +    3     +  3   +      20     +  3   +   C_DESC  +  2
#   C_DESC = COLS - 2 - 3 - 3 - 20 - 3 - 2 = COLS - 33
#   At COLS=80: C_DESC = 47  (fits all preset descriptions without wrapping)
#   At COLS=120: C_DESC = 87 (all descriptions on one line, spacious)
#   At COLS=60: C_DESC = 27  (wrapping activates for longer descriptions)
#
# MINIMUM WIDTH: 60 columns enforced — below this the table degrades
#   gracefully by truncating the Preset Name column before C_DESC.
# ==============================================================================
_mtp_show_presets() {

    # ------------------------------------------------------------------
    # SECTION 1: Terminal width and box geometry
    # ------------------------------------------------------------------
    local W="${COLS:-80}"
    [[ $W -lt 60 ]] && W=60
    local INNER=$(( W - 2 ))

    # Fixed column widths
    local C_NUM=3    # "#" column — always 3 chars
    local C_NAME=20  # Preset name — fixed at 20, truncated if needed

    # Description column gets all remaining space:
    # Border chars: "| " + C_NUM + " | " + C_NAME + " | " + C_DESC + " |"
    #               2   +  C_NUM +  3   +   C_NAME  +  3  +  C_DESC  + 2
    local C_DESC=$(( W - 2 - C_NUM - 3 - C_NAME - 3 - 2 ))
    [[ $C_DESC -lt 15 ]] && C_DESC=15  # enforce absolute minimum

    # ------------------------------------------------------------------
    # SECTION 2: Preset data
    # Plain text only — no ANSI codes embedded in data strings.
    # Numbers, names, and descriptions are stored separately so the
    # word-wrap and padding arithmetic works on clean character counts.
    # ------------------------------------------------------------------
    local -a P_NUMS=(  1   2   3   4   5   6   7 )

    local -a P_NAMES=(
        "Enterprise WAN"
        "Data Centre"
        "Unified Comms"
        "Bulk Transfer"
        "Multimedia CDN"
        "Custom Mix"
        "Back to Main Menu"
    )

    local -a P_DESCS=(
        "70% TCP Bulk (AF11) + 20% UDP RTP (EF) + 10% UDP Low (CS1)"
        "60% TCP Bulk (AF21) + 30% TCP iSCSI (AF31) + 10% ICMP/Mgmt (CS2)"
        "50% UDP Voice (EF) + 30% UDP Video (AF41) + 20% TCP Signalling (CS3)"
        "80% TCP Bulk (AF11) + 20% TCP Background (CS1)"
        "65% TCP HTTPS (AF31) + 25% UDP Stream (AF41) + 10% UDP Low (CS1)"
        "Define your own percentages and classes interactively"
        "Return without launching any streams"
    )

    # ------------------------------------------------------------------
    # SECTION 3: Helper — horizontal rule
    # Usage: _mtp_rule <left_char> <fill_char> <right_char>
    # ------------------------------------------------------------------
    _mtp_rule() {
        printf "%s%s%s\n" "$1" "$(rpt "$2" $INNER)" "$3"
    }

    # ------------------------------------------------------------------
    # SECTION 4: Helper — word-wrap
    # Splits <text> into lines of at most <width> visible characters,
    # breaking only at spaces. Result stored in _WRAP_LINES[].
    # Bash 3.2 compatible (no mapfile, no associative arrays).
    # ------------------------------------------------------------------
    _wrap_text() {
        local text="$1"
        local maxw="$2"
        _WRAP_LINES=()
        local line="" word

        # Split on whitespace using read -ra (Bash 3.2 safe)
        local IFS_SAVE="$IFS"
        IFS=' '
        local -a words
        read -ra words <<< "$text"
        IFS="$IFS_SAVE"

        for word in "${words[@]}"; do
            if [[ -z "$line" ]]; then
                line="$word"
            elif (( ${#line} + 1 + ${#word} <= maxw )); then
                line="$line $word"
            else
                _WRAP_LINES+=("$line")
                line="$word"
            fi
        done
        [[ -n "$line" ]] && _WRAP_LINES+=("$line")

        # Guarantee at least one element even for empty input
        [[ ${#_WRAP_LINES[@]} -eq 0 ]] && _WRAP_LINES+=("")
    }

    # ------------------------------------------------------------------
    # SECTION 5: Helper — single table data row
    # Prints one physical line of the presets table.
    #
    # Parameters:
    #   $1  num_str   — value for # column  (empty on continuation lines)
    #   $2  name_str  — value for Name col  (empty on continuation lines)
    #   $3  desc_line — one wrapped line of the description
    #   $4  is_first  — "1" = first line of an entry (colors applied)
    #                   "0" = continuation line (dim/no color)
    # ------------------------------------------------------------------
    _mtp_data_row() {
        local num_str="$1"
        local name_str="$2"
        local desc_line="$3"
        local is_first="$4"

        # Safety: truncate inputs to their column widths as a last resort
        num_str="${num_str:0:$C_NUM}"
        name_str="${name_str:0:$C_NAME}"
        desc_line="${desc_line:0:$C_DESC}"

        # Calculate right-padding for each column
        local num_pad=$(( C_NUM  - ${#num_str}  ))
        local name_pad=$(( C_NAME - ${#name_str} ))
        local desc_pad=$(( C_DESC - ${#desc_line} ))
        [[ $num_pad  -lt 0 ]] && num_pad=0
        [[ $name_pad -lt 0 ]] && name_pad=0
        [[ $desc_pad -lt 0 ]] && desc_pad=0

        if [[ "$is_first" == "1" ]]; then
            # First line: apply colors to each field
            printf "| %b%s%b%s | %b%s%b%s | %s%s |\n"            \
                "${CYAN}"  "$num_str"  "${NC}" "$(rpt ' ' $num_pad)"   \
                "${BOLD}"  "$name_str" "${NC}" "$(rpt ' ' $name_pad)"  \
                "$desc_line" "$(rpt ' ' $desc_pad)"
        else
            # Continuation line: blank num/name, dim description
            printf "| %s%s | %s%s | %b%s%b%s |\n"                 \
                "$num_str"  "$(rpt ' ' $num_pad)"                  \
                "$name_str" "$(rpt ' ' $name_pad)"                 \
                "${DIM}" "$desc_line" "${NC}" "$(rpt ' ' $desc_pad)"
        fi
    }

    # ------------------------------------------------------------------
    # SECTION 6: Helper — column separator row
    # Prints the horizontal rule between header and data, and between
    # grouped sections (before option 6 and option 7).
    # ------------------------------------------------------------------
    _mtp_col_sep() {
        printf "|%s|%s|%s|\n"                      \
            "$(rpt '-' $(( C_NUM  + 2 )))"         \
            "$(rpt '-' $(( C_NAME + 2 )))"         \
            "$(rpt '-' $(( C_DESC + 2 )))"
    }

    # ------------------------------------------------------------------
    # SECTION 7: Helper — centered title line inside the box
    # ------------------------------------------------------------------
    _mtp_title() {
        local txt="$1"
        local vlen=${#txt}
        local lpad=$(( (INNER - vlen) / 2 ))
        local rpad=$(( INNER - vlen - lpad ))
        [[ $lpad -lt 0 ]] && lpad=0
        [[ $rpad -lt 0 ]] && rpad=0
        printf "|%s%b%s%b%s|\n"                    \
            "$(rpt ' ' $lpad)"                      \
            "${BOLD_W}" "$txt" "${NC}"              \
            "$(rpt ' ' $rpad)"
    }

    # ------------------------------------------------------------------
    # SECTION 8: Helper — left-aligned full-width info line
    # ------------------------------------------------------------------
    _mtp_info() {
        local txt="$1"
        local tlen=${#txt}
        local rpad=$(( INNER - tlen - 3 ))
        [[ $rpad -lt 0 ]] && rpad=0
        printf "|  %b%s%b%s|\n" "${DIM}" "$txt" "${NC}" "$(rpt ' ' $rpad)"
    }

    # ------------------------------------------------------------------
    # SECTION 9: Render the session header and intro block
    # ------------------------------------------------------------------

    echo ""

    # ------------------------------------------------------------------
    # SECTION 10: Render the presets table
    # ------------------------------------------------------------------
    _mtp_rule "+" "=" "+"
    _mtp_title "Built-in Traffic Mix Presets"
    _mtp_rule "+" "=" "+"

    # Column header row
    printf "| %b%-${C_NUM}s%b | %b%-${C_NAME}s%b | %b%-${C_DESC}s%b |\n" \
        "${BOLD}" "#"             "${NC}"  \
        "${BOLD}" "Preset Name"   "${NC}"  \
        "${BOLD}" "Mix Description" "${NC}"

    _mtp_col_sep

    # Data rows — iterate over all presets
    local i
    for i in "${!P_NUMS[@]}"; do
        local num="${P_NUMS[$i]}"
        local name="${P_NAMES[$i]}"
        local desc="${P_DESCS[$i]}"

        # Visual separator before Custom Mix (6) and Back to Menu (7)
        # so they are clearly grouped away from the 5 main presets.
        if [[ "$num" -eq 6 || "$num" -eq 7 ]]; then
            _mtp_col_sep
        fi

        # Word-wrap the description to fit C_DESC
        _wrap_text "$desc" "$C_DESC"

        # Print the first physical line (num + name + first desc line)
        _mtp_data_row "$num" "$name" "${_WRAP_LINES[0]}" "1"

        # Print any continuation lines (blank num + name, wrapped desc)
        local j
        for (( j=1; j<${#_WRAP_LINES[@]}; j++ )); do
            _mtp_data_row "" "" "${_WRAP_LINES[$j]}" "0"
        done
    done

    _mtp_rule "+" "=" "+"
    echo ""
}

# ---------------------------------------------------------------------------
# _mtp_select_preset  <out_array_name>
#
# Loads a preset mix into the named array variable.
# Array format: each element = "PROTO:PCT:DSCP_NAME:BW_PER_STREAM:LABEL"
#   PROTO        = TCP or UDP
#   PCT          = integer percentage (must sum to 100)
#   DSCP_NAME    = e.g. EF, AF11, CS1, or "" for best-effort
#   BW_PER_STREAM= per-stream bandwidth string e.g. 100M, 0 for unlimited
#   LABEL        = human-readable class label
# ---------------------------------------------------------------------------
_mtp_load_preset() {
    local preset_num="$1"
    # Output arrays populated by caller after this function returns
    # using the MTP_CLASS_* globals set below.

    MTP_CLASSES=()

    case "$preset_num" in
        1)  # Enterprise WAN
            MTP_CLASSES=(
                "TCP:70:AF11:0:TCP Bulk (AF11)"
                "UDP:20:EF:2M:UDP RTP Voice/Video (EF)"
                "UDP:10:CS1:512K:UDP Low-Priority (CS1)"
            )
            ;;
        2)  # Data Centre
            MTP_CLASSES=(
                "TCP:60:AF21:0:TCP Bulk Storage (AF21)"
                "TCP:30:AF31:0:TCP iSCSI/NFS (AF31)"
                "UDP:10:CS2:1M:UDP Management (CS2)"
            )
            ;;
        3)  # Unified Comms
            MTP_CLASSES=(
                "UDP:50:EF:1M:UDP Voice (EF)"
                "UDP:30:AF41:4M:UDP Video Conferencing (AF41)"
                "TCP:20:CS3:0:TCP Signalling (CS3)"
            )
            ;;
        4)  # Bulk Transfer
            MTP_CLASSES=(
                "TCP:80:AF11:0:TCP Bulk (AF11)"
                "TCP:20:CS1:0:TCP Background (CS1)"
            )
            ;;
        5)  # Multimedia CDN
            MTP_CLASSES=(
                "TCP:65:AF31:0:TCP HTTPS Content (AF31)"
                "UDP:25:AF41:8M:UDP Stream (AF41)"
                "UDP:10:CS1:256K:UDP Low-Priority (CS1)"
            )
            ;;
        6)  # Custom — caller builds MTP_CLASSES interactively
            MTP_CLASSES=()
            ;;
    esac
}

# ---------------------------------------------------------------------------
# _mtp_define_custom_mix
#
# Interactive wizard to define a custom traffic mix.
# Populates MTP_CLASSES global array.
# ---------------------------------------------------------------------------
_mtp_define_custom_mix() {
    local inner=$(( COLS - 2 ))
    MTP_CLASSES=()

    printf '+%s+\n' "$(rpt '=' $inner)"
    bcenter "${BOLD}${CYAN}Define Custom Traffic Mix${NC}"
    printf '+%s+\n' "$(rpt '=' $inner)"
    bleft "  Define up to 5 traffic classes. Percentages must sum to 100."
    bleft "  ${DIM}Each class becomes one or more streams proportional to its share.${NC}"
    printf '+%s+\n' "$(rpt '-' $inner)"
    echo ""

    local total_pct=0
    local class_num=0
    local max_classes=5

    while (( class_num < max_classes )); do
        local remaining=$(( 100 - total_pct ))
        if (( remaining <= 0 )); then
            break
        fi

        (( class_num++ ))
        printf '%b  ── Class %d ──%b\n' "$CYAN" "$class_num" "$NC"
        echo ""

        # Protocol
        local proto
        while true; do
            read -r -p "  Protocol [TCP/UDP] (default TCP): " proto </dev/tty
            proto="${proto:-TCP}"
            proto=$(printf '%s' "$proto" | tr '[:lower:]' '[:upper:]')
            [[ "$proto" == "TCP" || "$proto" == "UDP" ]] && break
            printf '%b  Enter TCP or UDP.%b\n' "$RED" "$NC"
        done

        # Percentage
        local pct
        while true; do
            printf "  Percentage of total traffic [remaining: %d%%]: " "$remaining"
            read -r pct </dev/tty
            pct="${pct:-$remaining}"
            if [[ "$pct" =~ ^[0-9]+$ ]] && \
               (( pct >= 1 && pct <= remaining )); then
                break
            fi
            printf '%b  Enter 1-%d.%b\n' "$RED" "$remaining" "$NC"
        done
        total_pct=$(( total_pct + pct ))

        # ── DSCP marking ──────────────────────────────────────────────────
        # Show the full DSCP reference table immediately so the operator
        # can see all available values before making a selection.
        # The table is re-printed whenever the operator types 'list'.
        # The loop continues until a valid DSCP name/value is entered
        # or Enter is pressed to select none (best-effort).

        echo ""
        printf '%b  -- DSCP Marking --%b\n' "$CYAN" "$NC"
        echo ""

        # Print the DSCP table inline (same data as show_dscp_table
        # but without the full box header so it fits the wizard flow)
        printf '  %-12s  %-4s  %-4s  %-44s\n' \
            "Name" "DSCP" "TOS" "Typical Use Case"
        printf '  %s  %s  %s  %s\n' \
            "$(rpt '-' 12)" "$(rpt '-' 4)" "$(rpt '-' 4)" "$(rpt '-' 44)"

        local -a _dscp_rows=(
            "Default/CS0:0:0:Best Effort — no QoS marking"
            "CS1:8:32:Scavenger / Low-priority bulk"
            "AF11:10:40:Low data (assured, low drop)"
            "AF12:12:48:Low data (assured, med drop)"
            "AF13:14:56:Low data (assured, high drop)"
            "CS2:16:64:OAM / Network management"
            "AF21:18:72:High-throughput data (low drop)"
            "AF22:20:80:High-throughput data (med drop)"
            "AF23:22:88:High-throughput data (high drop)"
            "CS3:24:96:Broadcast video / Signalling"
            "AF31:26:104:Multimedia streaming (low drop)"
            "AF32:28:112:Multimedia streaming (med drop)"
            "AF33:30:120:Multimedia streaming (high drop)"
            "CS4:32:128:Real-time interactive"
            "AF41:34:136:Multimedia conf (low drop)"
            "AF42:36:144:Multimedia conf (med drop)"
            "AF43:38:152:Multimedia conf (high drop)"
            "CS5:40:160:Signalling / Call control"
            "VA:44:176:Voice Admit (CAC admitted)"
            "EF:46:184:Expedited Forwarding — VoIP"
            "CS6:48:192:Network Control (BGP/OSPF)"
            "CS7:56:224:Reserved / Network Critical"
        )

        local _dr
        for _dr in "${_dscp_rows[@]}"; do
            local _dn _dv _dt _du
            IFS=':' read -r _dn _dv _dt _du <<< "$_dr"
            printf '  %-12s  %-4s  %-4s  %-44s\n' \
                "$_dn" "$_dv" "$_dt" "$_du"
        done

        printf '  %s  %s  %s  %s\n' \
            "$(rpt '-' 12)" "$(rpt '-' 4)" "$(rpt '-' 4)" "$(rpt '-' 44)"
        echo ""
        printf '  %b TOS = DSCP × 4  |  Enter name (e.g. EF, AF41), 0-63,' \
            "$DIM"
        printf ' "list" to reprint, or Enter for none%b\n\n' "$NC"

        local dscp_name=""
        while true; do
            read -r -p \
                "  DSCP marking for Class ${class_num} (name/0-63/list/Enter=none): " \
                dscp_raw </dev/tty
            dscp_raw="${dscp_raw:-}"

            # Empty input → best-effort, no DSCP
            if [[ -z "$dscp_raw" ]]; then
                dscp_name=""
                printf '%b  No DSCP marking applied (best-effort).%b\n' \
                    "$DIM" "$NC"
                break
            fi

            # 'list' → reprint the table and re-prompt
            local _dscp_lower
            _dscp_lower=$(printf '%s' "$dscp_raw" | tr '[:upper:]' '[:lower:]')
            if [[ "$_dscp_lower" == "list" ]]; then
                echo ""
                printf '  %-12s  %-4s  %-4s  %-44s\n' \
                    "Name" "DSCP" "TOS" "Typical Use Case"
                printf '  %s  %s  %s  %s\n' \
                    "$(rpt '-' 12)" "$(rpt '-' 4)" "$(rpt '-' 4)" \
                    "$(rpt '-' 44)"
                for _dr in "${_dscp_rows[@]}"; do
                    local _dn _dv _dt _du
                    IFS=':' read -r _dn _dv _dt _du <<< "$_dr"
                    printf '  %-12s  %-4s  %-4s  %-44s\n' \
                        "$_dn" "$_dv" "$_dt" "$_du"
                done
                printf '  %s  %s  %s  %s\n' \
                    "$(rpt '-' 12)" "$(rpt '-' 4)" "$(rpt '-' 4)" \
                    "$(rpt '-' 44)"
                echo ""
                continue
            fi

            # Validate via dscp_name_to_value
            local _dscp_val
            _dscp_val=$(dscp_name_to_value "$dscp_raw")
            if [[ "$_dscp_val" == "-1" ]]; then
                printf '%b  Invalid DSCP "%s". Enter a name from the table,' \
                    "$RED" "$dscp_raw"
                printf ' a value 0-63, "list", or press Enter for none.%b\n' \
                    "$NC"
                continue
            fi

            dscp_name=$(printf '%s' "$dscp_raw" | tr '[:lower:]' '[:upper:]')
            printf '%b  DSCP set to: %b%s%b (value: %s  TOS: %s)%b\n' \
                "$GREEN" "$BOLD" "$dscp_name" "$NC" \
                "$_dscp_val" "$(( _dscp_val * 4 ))" "$NC"
            break
        done

        # Per-stream bandwidth (UDP requires it, TCP optional)
        local bw_per_stream=""
        if [[ "$proto" == "UDP" ]]; then
            while true; do
                read -r -p "  Bandwidth per stream (required for UDP, e.g. 1M, 500K): " \
                    bw_per_stream </dev/tty
                bw_per_stream="${bw_per_stream:-1M}"
                validate_bandwidth "$bw_per_stream" && break
                printf '%b  Invalid bandwidth.%b\n' "$RED" "$NC"
            done
        else
            read -r -p "  Bandwidth limit per stream (Enter for unlimited): " \
                bw_per_stream </dev/tty
            bw_per_stream="${bw_per_stream:-0}"
            if ! validate_bandwidth "$bw_per_stream" 2>/dev/null; then
                bw_per_stream="0"
            fi
        fi
        [[ "$bw_per_stream" == "" ]] && bw_per_stream="0"

        # Label
        local default_label="${proto} ${pct}%${dscp_name:+ (${dscp_name})}"
        read -r -p "  Class label [${default_label}]: " class_label </dev/tty
        class_label="${class_label:-$default_label}"

        MTP_CLASSES+=("${proto}:${pct}:${dscp_name}:${bw_per_stream}:${class_label}")

        echo ""
        if (( total_pct >= 100 )); then
            break
        fi

        if (( class_num < max_classes )); then
            local add_more
            read -r -p "  Add another class? [Y/n]: " add_more </dev/tty
            [[ "$add_more" =~ ^[Nn] ]] && break
        fi
    done

    # If percentages don't sum to 100, normalise the last class
    if (( total_pct < 100 && ${#MTP_CLASSES[@]} > 0 )); then
        local deficit=$(( 100 - total_pct ))
        printf '%b  Note: percentages sum to %d%%. Adjusting last class by +%d%%.%b\n' \
            "$YELLOW" "$total_pct" "$deficit" "$NC"
        # Adjust the last class's percentage
        local last_idx=$(( ${#MTP_CLASSES[@]} - 1 ))
        local last="${MTP_CLASSES[$last_idx]}"
        local lp ln ld lb ll
        IFS=':' read -r lp ln ld lb ll <<< "$last"
        ln=$(( ln + deficit ))
        MTP_CLASSES[$last_idx]="${lp}:${ln}:${ld}:${lb}:${ll}"
    fi

    echo ""
}

# ---------------------------------------------------------------------------
# _mtp_configure_targets
#
# Collects target IPs, duration, bind interface, and port configuration
# for each traffic class.
#
# Port configuration offers three modes:
#
#   1. Auto sequential   — operator sets a single base port; each class
#                          starts immediately after the previous class's
#                          last port. No manual port entry required.
#
#   2. Custom per-class  — operator enters a specific base port for each
#                          class. Within a class, streams increment from
#                          that base. Operator can reuse the previous
#                          class's base or change it.
#
#   3. Single port all   — all streams across all classes use the same
#                          port. Useful when the server uses a single
#                          listener that handles all traffic types.
#
# The selected mode and base port are stored in MTP_BASE_PORT and
# MTP_PORT_MODE for use in _mtp_calculate_streams.
# ---------------------------------------------------------------------------
_mtp_configure_targets() {
    local inner=$(( COLS - 2 ))
    MTP_TARGETS=()
    MTP_PORTS=()
    MTP_DURATIONS=()
    MTP_BINDS=()
    MTP_VRFS=()
    MTP_BASE_PORT=5201
    MTP_PORT_MODE="auto"   # auto | custom | single

    printf '+%s+\n' "$(rpt '=' $inner)"
    bcenter "${BOLD}${CYAN}Configure Targets for Each Traffic Class${NC}"
    printf '+%s+\n' "$(rpt '=' $inner)"
    echo ""

    # ── Global duration ────────────────────────────────────────────────────
    local duration
    while true; do
        read -r -p "  Test duration in seconds (0=unlimited) [60]: " \
            duration </dev/tty
        duration="${duration:-60}"
        validate_duration "$duration" && break
        printf '%b  Enter a non-negative integer.%b\n' "$RED" "$NC"
    done
    local dur_val=0
    [[ "$duration" != "0" ]] && dur_val=$(( 10#$duration ))

    # ── Port configuration mode ────────────────────────────────────────────
    echo ""
    printf '+%s+\n' "$(rpt '-' $inner)"
    bcenter "${BOLD}Port Configuration${NC}"
    printf '+%s+\n' "$(rpt '-' $inner)"
    bleft "  Choose how ports are assigned across traffic classes."
    printf '+%s+\n' "$(rpt '-' $inner)"

    # Display the three options as a small table
    local PC_NUM=3 PC_NAME=22 PC_DESC=$(( inner - 3 - 3 - 22 - 2 - 2 ))
    (( PC_DESC < 20 )) && PC_DESC=20

    bleft "${BOLD}$(printf '%-*s  %-*s  %-*s' \
        $PC_NUM '#' $PC_NAME 'Mode' $PC_DESC 'Description')${NC}"
    printf '+%s+\n' "$(rpt '-' $inner)"

    _port_mode_row() {
        local num="$1" name="$2" desc="$3"
        local row
        printf -v row '%-*s  %-*s  %-*s' \
            $PC_NUM "$num" $PC_NAME "$name" $PC_DESC "$desc"
        local rlen=${#row}
        local rp=$(( inner - 2 - rlen - 1 ))
        (( rp < 0 )) && rp=0
        printf '|  %s%s|\n' "$row" "$(rpt ' ' $rp)"
    }

    _port_mode_row "1" "Auto Sequential" \
        "Set one base port — classes increment automatically (no overlap)"
    _port_mode_row "2" "Custom Per-Class" \
        "Specify a different base port for each traffic class manually"
    _port_mode_row "3" "Single Port All" \
        "All streams use the same port (single server listener)"
    printf '+%s+\n' "$(rpt '=' $inner)"
    echo ""

    local port_mode_choice
    while true; do
        read -r -p "  Select port mode [1]: " port_mode_choice </dev/tty
        port_mode_choice="${port_mode_choice:-1}"
        [[ "$port_mode_choice" =~ ^[1-3]$ ]] && break
        printf '%b  Enter 1, 2, or 3.%b\n' "$RED" "$NC"
    done

    case "$port_mode_choice" in
        1) MTP_PORT_MODE="auto"   ;;
        2) MTP_PORT_MODE="custom" ;;
        3) MTP_PORT_MODE="single" ;;
    esac

    # ── Base / single port prompt (modes 1 and 3) ──────────────────────────
    if [[ "$MTP_PORT_MODE" == "auto" || \
          "$MTP_PORT_MODE" == "single" ]]; then
        local mode_label
        [[ "$MTP_PORT_MODE" == "auto"   ]] && \
            mode_label="Starting base port (classes auto-increment from here)"
        [[ "$MTP_PORT_MODE" == "single" ]] && \
            mode_label="Single port used by all streams"

        echo ""
        while true; do
            printf "  %s [5201]: " "$mode_label"
            local bp
            read -r bp </dev/tty
            bp="${bp:-5201}"
            validate_port "$bp" && {
                MTP_BASE_PORT=$(( 10#$bp ))
                break
            }
            printf '%b  Invalid port. Enter 1-65535.%b\n' "$RED" "$NC"
        done
    fi

    echo ""

    # ── Global bind IP — full interface-selection wizard ───────────────────
    printf '+%s+\n' "$(rpt '-' $inner)"
    bcenter "${BOLD}Source Bind Interface / IP${NC}"
    printf '+%s+\n' "$(rpt '-' $inner)"
    bleft "  Select a source interface for all streams, enter an IP directly,"
    bleft "  type ${BOLD}list${NC} to refresh the table, or ${BOLD}0${NC} / Enter for auto."
    printf '+%s+\n' "$(rpt '-' $inner)"
    echo ""

    get_interface_list
    show_interface_table
    echo ""

    local global_bind=""
    local global_vrf=""
    local bind_from_grt=0

    while true; do
        local _bind_raw
        read -r -p \
            "  Bind source (0=auto, #=interface, IP, 'list', Enter=auto): " \
            _bind_raw </dev/tty
        _bind_raw="${_bind_raw:-}"

        # Enter / 0 → auto
        if [[ -z "$_bind_raw" || "$_bind_raw" == "0" ]]; then
            global_bind=""
            global_vrf=""
            bind_from_grt=0
            printf '%b  Auto source address — no bind IP applied.%b\n' \
                "$CYAN" "$NC"
            break
        fi

        # 'list' → refresh
        local _bind_lower
        _bind_lower=$(printf '%s' "$_bind_raw" | tr '[:upper:]' '[:lower:]')
        if [[ "$_bind_lower" == "list" ]]; then
            echo ""
            get_interface_list
            show_interface_table
            echo ""
            continue
        fi

        # Numeric → select by table row
        if [[ "$_bind_raw" =~ ^[0-9]+$ ]]; then
            local _sel_num=$(( 10#$_bind_raw ))
            local _total_ifaces=${#IFACE_NAMES[@]}

            if (( _sel_num < 1 || _sel_num > _total_ifaces )); then
                printf '%b  Invalid number. Enter 0 or 1-%d.%b\n' \
                    "$RED" "$_total_ifaces" "$NC"
                continue
            fi

            local _sel_idx=$(( _sel_num - 1 ))
            local _sel_ip="${IFACE_IPS[$_sel_idx]}"
            local _sel_iface="${IFACE_NAMES[$_sel_idx]}"
            local _sel_state="${IFACE_STATES[$_sel_idx]}"
            local _sel_vrf="${IFACE_VRFS[$_sel_idx]}"

            if [[ "$_sel_ip" == "N/A" || -z "$_sel_ip" ]]; then
                printf '%b  %s has no IPv4 address. Choose another.%b\n' \
                    "$RED" "$_sel_iface" "$NC"
                continue
            fi

            [[ "$_sel_state" != "up" ]] && \
                printf '%b  WARNING: %s state="%s". Proceeding.%b\n' \
                    "$YELLOW" "$_sel_iface" "$_sel_state" "$NC"

            printf '%b  Bound to: %s → %s%b\n' \
                "$GREEN" "$_sel_iface" "$_sel_ip" "$NC"
            global_bind="$_sel_ip"

            if [[ "$OS_TYPE" == "linux" ]]; then
                if [[ "$_sel_vrf" == "GRT" || -z "$_sel_vrf" ]]; then
                    global_vrf=""
                    bind_from_grt=1
                    printf '%b  Interface is in GRT — no VRF exec applied.%b\n' \
                        "$CYAN" "$NC"
                else
                    global_vrf="$_sel_vrf"
                    bind_from_grt=0
                    printf '%b  Auto-detected VRF: %s%b\n' \
                        "$GREEN" "$global_vrf" "$NC"
                    local vrf_override
                    read -r -p \
                        "  VRF [${global_vrf}] (Enter to confirm): " \
                        vrf_override </dev/tty
                    vrf_override="${vrf_override:-$global_vrf}"
                    if [[ -z "$vrf_override" ]]; then
                        printf '%b  VRF cleared — using GRT.%b\n' \
                            "$YELLOW" "$NC"
                        global_vrf=""
                        bind_from_grt=1
                    else
                        global_vrf="$vrf_override"
                        printf '%b  Streams will use VRF: %s%b\n' \
                            "$CYAN" "$global_vrf" "$NC"
                    fi
                fi
            fi
            break
        fi

        # Direct IP entry
        if validate_ip "$_bind_raw"; then
            global_bind="$_bind_raw"
            printf '%b  Bind IP set to: %s%b\n' "$GREEN" "$global_bind" "$NC"

            if [[ "$OS_TYPE" == "linux" ]]; then
                local _auto_vrf=""
                local _ki
                for (( _ki=0; _ki<${#IFACE_IPS[@]}; _ki++ )); do
                    if [[ "${IFACE_IPS[$_ki]}" == "$global_bind" ]]; then
                        _auto_vrf="${IFACE_VRFS[$_ki]:-GRT}"
                        break
                    fi
                done

                if [[ "$_auto_vrf" == "GRT" || -z "$_auto_vrf" ]]; then
                    global_vrf=""
                    bind_from_grt=1
                    printf '%b  IP belongs to GRT — no VRF exec applied.%b\n' \
                        "$CYAN" "$NC"
                elif [[ -n "$_auto_vrf" ]]; then
                    global_vrf="$_auto_vrf"
                    bind_from_grt=0
                    printf '%b  Auto-detected VRF: %s%b\n' \
                        "$GREEN" "$global_vrf" "$NC"
                    local vrf_raw
                    read -r -p \
                        "  VRF [${global_vrf}] (Enter to confirm): " \
                        vrf_raw </dev/tty
                    vrf_raw="${vrf_raw:-$global_vrf}"
                    [[ -z "$vrf_raw" ]] && global_vrf="" || \
                        global_vrf="$vrf_raw"
                else
                    read -r -p \
                        "  VRF (Enter for GRT/none): " \
                        global_vrf </dev/tty
                    global_vrf="${global_vrf:-}"
                fi
            fi
            break
        fi

        printf '%b  Unrecognised input "%s".%b\n' "$RED" "$_bind_raw" "$NC"
        printf '%b  Enter: number | IP | list | 0 or Enter for auto%b\n' \
            "$RED" "$NC"
    done

    echo ""

    # ── Per-class target IP and optional custom port ───────────────────────
    local last_target=""
    # For custom mode: track the suggested next port so the operator sees
    # a sensible default even when overriding per-class.
    local suggested_port=$MTP_BASE_PORT

    local ci
    for (( ci=0; ci<${#MTP_CLASSES[@]}; ci++ )); do
        local class="${MTP_CLASSES[$ci]}"
        local cproto cpct cdscp cbw clabel
        IFS=':' read -r cproto cpct cdscp cbw clabel <<< "$class"

        printf '+%s+\n' "$(rpt '-' $inner)"
        printf '%b  Class %d — %s  (%s / %d%%)%b\n' \
            "$CYAN" "$(( ci + 1 ))" "$clabel" "$cproto" "$cpct" "$NC"
        printf '+%s+\n' "$(rpt '-' $inner)"

        # Target IP or FQDN
        local tgt_prompt="  Target IP or FQDN"
        [[ -n "$last_target" ]] && \
            tgt_prompt="  Target IP or FQDN [${last_target}]"
        local tgt tgt_display
        while true; do
            read -r -p "${tgt_prompt}: " tgt </dev/tty
            tgt="${tgt:-$last_target}"
            [[ -z "$tgt" ]] && {
                printf '%b  Target is required.%b\n' "$RED" "$NC"
                continue
            }

            local _resolved_ip _resolved_display
            local _resolve_rc
            _validate_and_resolve_target "$tgt" "_resolved_ip" "_resolved_display"
            _resolve_rc=$?

            case $_resolve_rc in
                0)
                    tgt="$_resolved_ip"
                    tgt_display="$_resolved_display"
                    printf '  %b✓ Target set: %b%s%b\n' \
                        "$GREEN" "$BOLD" "$tgt_display" "$NC"
                    break
                    ;;
                1)
                    printf '%b  Invalid address or unresolvable FQDN: "%s"%b\n' \
                        "$RED" "$tgt" "$NC"
                    continue
                    ;;
                2)
                    printf '%b  Enter a valid unicast target.%b\n' \
                        "$RED" "$NC"
                    continue
                    ;;
            esac
        done
        last_target="$tgt"

        # Port assignment based on selected mode
        local class_port=0

        case "$MTP_PORT_MODE" in

            auto)
                # Port is computed in _mtp_calculate_streams — store 0
                # as a placeholder. Show the operator what port will be used.
                printf '%b  Port: auto-assigned from %d (sequential)%b\n' \
                    "$DIM" "$suggested_port" "$NC"
                class_port=0
                # We don't know sc yet, but update suggestion by 1 so the
                # display is approximately correct (exact value set in
                # _mtp_calculate_streams).
                suggested_port=$(( suggested_port + 1 ))
                ;;

            custom)
                # ── Compute an accurate default by pre-calculating how many
                # streams the previous class allocated and advancing past them.
                # This ensures the suggested default never collides with ports
                # already used by earlier classes.
                #
                # We replicate the largest-remainder calculation here using
                # the total stream count the operator already entered.
                # If that value is not yet known we fall back to +1.

                local _suggested=$suggested_port

                local cp
                while true; do
                    printf "  Base port for this class [%d]: " "$_suggested"
                    read -r cp </dev/tty
                    cp="${cp:-$_suggested}"
                    validate_port "$cp" && {
                        class_port=$(( 10#$cp ))
                        break
                    }
                    printf '%b  Invalid port. Enter 1-65535.%b\n' \
                        "$RED" "$NC"
                done

                # Advance suggested_port for the NEXT class.
                # Use a pre-estimate of this class's stream count so the
                # next default skips past all ports this class will use.
                # Pre-estimate: round(total * pct / 100), minimum 1.
                local _pre_sc=1
                if [[ -n "${_mtp_total_streams:-}" ]] && \
                   (( _mtp_total_streams > 0 )); then
                    _pre_sc=$(( _mtp_total_streams * cpct / 100 ))
                    (( _pre_sc < 1 )) && _pre_sc=1
                fi
                suggested_port=$(( class_port + _pre_sc ))
                ;;

            single)
                # All classes use the same single port.
                class_port=$MTP_BASE_PORT
                printf '%b  Port: %d (shared across all classes)%b\n' \
                    "$DIM" "$class_port" "$NC"
                ;;

        esac

        MTP_TARGETS+=("$tgt")
        MTP_PORTS+=("$class_port")
        MTP_DURATIONS+=("$dur_val")
        MTP_BINDS+=("$global_bind")
        MTP_VRFS+=("$global_vrf")
        echo ""
    done
}

# ---------------------------------------------------------------------------
# _mtp_calculate_streams  <total_streams>
#
# Given MTP_CLASSES and a total stream count, calculates per-class stream
# counts using the largest-remainder method so they sum exactly to the
# requested total without rounding errors.
#
# Populates all S_* stream configuration arrays that the launch machinery
# (launch_clients, run_dashboard, parse_final_results) expects.
#
# VRF/bind consistency is validated per-class using the same logic as
# build_client_command so traffic is routed correctly whether the interface
# belongs to GRT or a named VRF.
# ---------------------------------------------------------------------------
_mtp_calculate_streams() {
    local total_streams="$1"
    local inner=$(( COLS - 2 ))

    local n_classes=${#MTP_CLASSES[@]}

    # ── Step 1: Calculate raw (fractional) stream counts ──────────────────
    # Scale by 1000 to preserve three decimal places of precision while
    # staying in integer arithmetic throughout.
    local -a raw_counts=()
    local -a floor_counts=()
    local -a remainders=()

    local ci
    for (( ci=0; ci<n_classes; ci++ )); do
        local class="${MTP_CLASSES[$ci]}"
        local cpct
        IFS=':' read -r _ cpct _ _ _ <<< "$class"

        local raw=$(( total_streams * cpct * 1000 / 100 ))
        local floor=$(( raw / 1000 ))
        local remainder=$(( raw % 1000 ))

        # Every class must contribute at least 1 stream
        if (( floor < 1 )); then
            floor=1
        fi

        raw_counts+=("$raw")
        floor_counts+=("$floor")
        remainders+=("$remainder")
    done

    # ── Step 2: Largest-remainder method ──────────────────────────────────
    # Compute how many extra streams remain after flooring, then assign
    # them one-by-one to the classes with the largest fractional remainders.
    local floor_sum=0
    local f
    for f in "${floor_counts[@]}"; do
        floor_sum=$(( floor_sum + f ))
    done
    local deficit=$(( total_streams - floor_sum ))

    # Build a sorted index array (descending by remainder).
    # Bubble sort is sufficient — n_classes is always ≤ 5.
    local -a sorted_indices=()
    for (( ci=0; ci<n_classes; ci++ )); do
        sorted_indices+=("$ci")
    done

    local swapped=1
    while (( swapped )); do
        swapped=0
        local si
        for (( si=0; si<${#sorted_indices[@]}-1; si++ )); do
            local a="${sorted_indices[$si]}"
            local b="${sorted_indices[$(( si+1 ))]}"
            if (( remainders[a] < remainders[b] )); then
                sorted_indices[$si]=$b
                sorted_indices[$(( si+1 ))]=$a
                swapped=1
            fi
        done
    done

    local -a final_counts=()
    for (( ci=0; ci<n_classes; ci++ )); do
        final_counts+=("${floor_counts[$ci]}")
    done
    for (( si=0; si<deficit && si<n_classes; si++ )); do
        local idx="${sorted_indices[$si]}"
        final_counts[$idx]=$(( final_counts[$idx] + 1 ))
    done

    # ── Step 3: Display the calculated allocation table ───────────────────
    printf '+%s+\n' "$(rpt '=' $inner)"
    bcenter "${BOLD}${CYAN}Traffic Mix — Stream Allocation${NC}"
    printf '+%s+\n' "$(rpt '=' $inner)"

    local C_CL=3 C_LB=28 C_PR=5 C_PC=5 C_SC=7 C_BW=12
    bleft "${BOLD}$(printf '%-*s  %-*s  %-*s  %-*s  %-*s  %-*s' \
        $C_CL '#' \
        $C_LB 'Class' \
        $C_PR 'Proto' \
        $C_PC 'Pct' \
        $C_SC 'Streams' \
        $C_BW 'BW/Stream')${NC}"
    printf '+%s+\n' "$(rpt '-' $inner)"

    local total_check=0
    for (( ci=0; ci<n_classes; ci++ )); do
        local class="${MTP_CLASSES[$ci]}"
        local cproto cpct cdscp cbw clabel
        IFS=':' read -r cproto cpct cdscp cbw clabel <<< "$class"

        local sc="${final_counts[$ci]}"
        total_check=$(( total_check + sc ))

        local bw_disp="${cbw:-unlimited}"
        [[ "$bw_disp" == "0" || -z "$bw_disp" ]] && bw_disp="unlimited"

        local row
        printf -v row '%-*s  %-*s  %-*s  %-*s  %-*s  %-*s' \
            $C_CL "$(( ci+1 ))" \
            $C_LB "$clabel" \
            $C_PR "$cproto" \
            $C_PC "${cpct}%" \
            $C_SC "$sc" \
            $C_BW "$bw_disp"
        local rlen=${#row}
        local rp=$(( inner - 2 - rlen - 1 ))
        (( rp < 0 )) && rp=0
        printf '|  %s%s|\n' "$row" "$(rpt ' ' $rp)"
    done

    printf '+%s+\n' "$(rpt '-' $inner)"
    bleft "  ${BOLD}Total streams: ${total_check}${NC}   distributed across ${n_classes} traffic class(es)"
    printf '+%s+\n' "$(rpt '=' $inner)"
    echo ""

    # ── Step 4: Reset all stream configuration arrays ─────────────────────
    S_PROTO=();    S_TARGET=();    S_PORT=();      S_BW=()
    S_DURATION=(); S_DSCP_NAME=(); S_DSCP_VAL=();  S_PARALLEL=()
    S_REVERSE=();  S_CCA=();       S_WINDOW=();     S_MSS=()
    S_BIND=();     S_VRF=();       S_DELAY=();      S_JITTER=()
    S_LOSS=();     S_NOFQ=();      S_LOGFILE=();    S_SCRIPT=()
    S_START_TS=(); S_STATUS_CACHE=(); S_ERROR_MSG=()
    S_FINAL_SENDER_BW=(); S_FINAL_RECEIVER_BW=()
    S_BIDIR=()

 # ── Step 5: Populate stream arrays ────────────────────────────────────
    local stream_idx=0
    local next_port="${MTP_BASE_PORT:-5201}"   # running counter for auto mode

    # Collision guard: track every port allocated so far across ALL classes.
    # In custom mode the operator may enter a base port that overlaps with
    # a port already used by a previous class. We detect and auto-advance.
    local -a _allocated_ports=()

    _port_is_allocated() {
        local p="$1"
        local ap
        for ap in "${_allocated_ports[@]}"; do
            [[ "$ap" == "$p" ]] && return 0
        done
        return 1
    }

    _next_free_port() {
        # Return the smallest port >= $1 that is not in _allocated_ports
        local p="$1"
        while _port_is_allocated "$p"; do
            p=$(( p + 1 ))
        done
        printf '%d' "$p"
    }

    for (( ci=0; ci<n_classes; ci++ )); do
        local class="${MTP_CLASSES[$ci]}"
        local cproto cpct cdscp cbw clabel
        IFS=':' read -r cproto cpct cdscp cbw clabel <<< "$class"

        local sc="${final_counts[$ci]}"
        local tgt="${MTP_TARGETS[$ci]:-}"
        local dur="${MTP_DURATIONS[$ci]:-60}"
        local bind="${MTP_BINDS[$ci]:-}"
        local class_vrf="${MTP_VRFS[$ci]:-}"
        local stored_port="${MTP_PORTS[$ci]:-0}"

        # ── Determine base port for this class ─────────────────────────────
        local class_base_port

        case "${MTP_PORT_MODE:-auto}" in

            auto)
                # Auto: use the global sequential counter — guaranteed clean
                class_base_port=$next_port
                ;;

            custom)
                # Custom: operator specified a base port.
                # Check it does not collide with already-allocated ports.
                if (( stored_port > 0 )); then
                    local _clean_port
                    _clean_port=$(_next_free_port "$stored_port")
                    if (( _clean_port != stored_port )); then
                        printf '%b  [MTP] Class %d (%s): port %d already ' \
                            "$YELLOW" "$(( ci+1 ))" "$clabel" "$stored_port"
                        printf 'allocated — advancing to %d.%b\n' \
                            "$_clean_port" "$NC"
                    fi
                    class_base_port=$_clean_port
                else
                    # Stored port was 0 (placeholder) — fall back to auto
                    local _clean_port
                    _clean_port=$(_next_free_port "$next_port")
                    class_base_port=$_clean_port
                fi
                ;;

            single)
                # Single: all streams share one port — no increment
                class_base_port=$MTP_BASE_PORT
                ;;

        esac

        # ── Resolve DSCP value ─────────────────────────────────────────────
        local dscp_val=-1
        local dscp_name="$cdscp"
        if [[ -n "$cdscp" ]]; then
            dscp_val=$(dscp_name_to_value "$cdscp")
            if [[ "$dscp_val" == "-1" ]]; then
                dscp_name=""
                dscp_val=-1
            fi
        fi

        # ── Per-stream bandwidth ───────────────────────────────────────────
        local bw_str=""
        if [[ "$cbw" != "0" && -n "$cbw" ]]; then
            bw_str="$cbw"
        elif [[ "$cproto" == "UDP" ]]; then
            bw_str="1M"
        fi

        # ── VRF / bind consistency ─────────────────────────────────────────
        local stream_vrf="$class_vrf"

        if [[ "$OS_TYPE" == "linux" && -n "$bind" && \
              "$bind" != "0.0.0.0" ]]; then

            local _actual_vrf="GRT"
            local _vki
            for (( _vki=0; _vki<${#IFACE_IPS[@]}; _vki++ )); do
                if [[ "${IFACE_IPS[$_vki]}" == "$bind" ]]; then
                    _actual_vrf="${IFACE_VRFS[$_vki]:-GRT}"
                    break
                fi
            done

            if [[ -n "$stream_vrf" ]]; then
                if [[ "$_actual_vrf" == "GRT" ]]; then
                    printf '%b  [MTP] Class %d: bind %s in GRT — ' \
                        "$YELLOW" "$(( ci+1 ))" "$bind"
                    printf 'clearing VRF "%s".%b\n' "$stream_vrf" "$NC"
                    stream_vrf=""
                elif [[ "$_actual_vrf" != "$stream_vrf" ]]; then
                    printf '%b  [MTP] Class %d: bind %s in VRF "%s" — ' \
                        "$YELLOW" "$(( ci+1 ))" "$bind" "$_actual_vrf"
                    printf 'correcting from "%s".%b\n' "$stream_vrf" "$NC"
                    stream_vrf="$_actual_vrf"
                    [[ "$stream_vrf" == "GRT" ]] && stream_vrf=""
                fi
            else
                if [[ "$_actual_vrf" != "GRT" && -n "$_actual_vrf" ]]; then
                    printf '%b  [MTP] Class %d: bind %s — ' \
                        "$CYAN" "$(( ci+1 ))" "$bind"
                    printf 'auto-applying VRF "%s".%b\n' "$_actual_vrf" "$NC"
                    stream_vrf="$_actual_vrf"
                fi
            fi

            if [[ -n "$stream_vrf" ]] && (( IS_ROOT == 0 )); then
                printf '%b  [MTP] Class %d: VRF "%s" requires root.%b\n' \
                    "$YELLOW" "$(( ci+1 ))" "$stream_vrf" "$NC"
            fi
        fi

        # ── Generate stream entries ────────────────────────────────────────
        local si
        for (( si=0; si<sc; si++ )); do

            local stream_port
            case "${MTP_PORT_MODE:-auto}" in
                single)
                    stream_port=$MTP_BASE_PORT
                    ;;
                *)
                    # For both auto and custom: within a class, streams
                    # increment from class_base_port. Each port is checked
                    # for collision and advanced if necessary.
                    local _candidate=$(( class_base_port + si ))
                    if [[ "${MTP_PORT_MODE:-auto}" == "custom" ]]; then
                        _candidate=$(_next_free_port "$_candidate")
                    fi
                    stream_port=$_candidate
                    ;;
            esac

            # Register this port as allocated
            if [[ "${MTP_PORT_MODE:-auto}" != "single" ]]; then
                _allocated_ports+=("$stream_port")
            fi

            S_PROTO+=("$cproto")
            S_TARGET+=("$tgt")
            S_PORT+=("$stream_port")
            S_BW+=("$bw_str")
            S_DURATION+=("$dur")
            S_DSCP_NAME+=("$dscp_name")
            S_DSCP_VAL+=("$dscp_val")
            S_PARALLEL+=(1)
            S_REVERSE+=(0)
            S_CCA+=("")
            S_WINDOW+=("")
            S_MSS+=("")
            S_BIND+=("$bind")
            S_VRF+=("$stream_vrf")
            S_DELAY+=("")
            S_JITTER+=("")
            S_LOSS+=("")
            S_NOFQ+=(0)
            S_LOGFILE+=("")
            S_SCRIPT+=("")
            S_START_TS+=(0)
            S_STATUS_CACHE+=("STARTING")
            S_ERROR_MSG+=("")
            S_FINAL_SENDER_BW+=("")
            S_FINAL_RECEIVER_BW+=("")
            S_BIDIR+=(0)

            (( stream_idx++ ))
        done

        # Advance the global next_port counter past all ports used by
        # this class so auto mode and fallback paths stay clean.
        case "${MTP_PORT_MODE:-auto}" in
            single) ;;   # no change — all classes share one port
            *)
                local _last_used=$(( class_base_port + sc - 1 ))
                if (( _last_used >= next_port )); then
                    next_port=$(( _last_used + 1 ))
                fi
                ;;
        esac
    done

    STREAM_COUNT=$stream_idx
}

# ---------------------------------------------------------------------------
# _mtp_show_summary
#
# Displays a professional summary of the generated stream configuration
# grouped by traffic class before launch confirmation.
# ---------------------------------------------------------------------------
_mtp_show_summary() {
    local inner=$(( COLS - 2 ))
    printf '+%s+\n' "$(rpt '=' $inner)"
    bcenter "${BOLD}${CYAN}Mixed Traffic Configuration Summary${NC}"
    printf '+%s+\n' "$(rpt '=' $inner)"

    local C_SN=3 C_CL=24 C_PR=5 C_TG=15 C_PO=5 C_BW=13 C_DS=6 C_DU=6
    bleft "${BOLD}$(printf '%-*s  %-*s  %-*s  %-*s  %*s  %-*s  %-*s  %*s' \
        $C_SN '#' $C_CL 'Class' $C_PR 'Proto' $C_TG 'Target' \
        $C_PO 'Port' $C_BW 'Bandwidth' $C_DS 'DSCP' $C_DU 'Dur')${NC}"
    printf '+%s+\n' "$(rpt '-' $inner)"

    local i
    for (( i=0; i<STREAM_COUNT; i++ )); do
        local sn=$(( i + 1 ))
        local tgt="${S_TARGET[$i]:-?}"
        (( ${#tgt} > C_TG )) && tgt="${tgt:0:$(( C_TG-1 ))}~"
        local bw="${S_BW[$i]:-unlimited}"
        [[ -z "$bw" ]] && bw="unlimited"
        local dscp="${S_DSCP_NAME[$i]:----}"
        [[ -z "$dscp" ]] && dscp="---"
        local dur="${S_DURATION[$i]:-0}"
        [[ "$dur" == "0" ]] && dur="inf" || dur="${dur}s"

        # Find which class this stream belongs to (derive from DSCP+proto)
        local class_label=""
        local ci2
        for (( ci2=0; ci2<${#MTP_CLASSES[@]}; ci2++ )); do
            local cl="${MTP_CLASSES[$ci2]}"
            local cp cd cb clb
            IFS=':' read -r cp _ cd cb clb <<< "$cl"
            if [[ "$cp" == "${S_PROTO[$i]}" && "$cd" == "${S_DSCP_NAME[$i]}" ]]; then
                class_label="$clb"
                break
            fi
        done
        (( ${#class_label} > C_CL )) && class_label="${class_label:0:$(( C_CL-1 ))}~"

        local row
        printf -v row '%-*s  %-*s  %-*s  %-*s  %*s  %-*s  %-*s  %*s' \
            $C_SN "$sn" \
            $C_CL "$class_label" \
            $C_PR "${S_PROTO[$i]}" \
            $C_TG "$tgt" \
            $C_PO "${S_PORT[$i]}" \
            $C_BW "$bw" \
            $C_DS "$dscp" \
            $C_DU "$dur"
        local rlen=${#row}
        local rp=$(( inner - 2 - rlen - 1 ))
        (( rp < 0 )) && rp=0
        printf '|  %s%s|\n' "$row" "$(rpt ' ' $rp)"
    done

    printf '+%s+\n' "$(rpt '=' $inner)"
    bleft "  ${GREEN}${BOLD}${STREAM_COUNT} streams${NC} configured across ${#MTP_CLASSES[@]} traffic class(es)"
    printf '+%s+\n' "$(rpt '=' $inner)"
    echo ""
}

# ---------------------------------------------------------------------------
# run_mixed_traffic_mode
#
# Main entry point for the Mixed Traffic Pattern Generator.
# Orchestrates preset selection or custom definition, target configuration,
# stream calculation, and launch.
# ---------------------------------------------------------------------------
run_mixed_traffic_mode() {
    echo ""
    local inner=$(( COLS - 2 ))

    # ------------------------------------------------------------------
    # SESSION HEADER + INTRO BLOCK
    # Rendered exactly once here. _mtp_show_presets must NOT render
    # its own copy of this content.
    # ------------------------------------------------------------------
    _print_session_header

    echo ""
    printf '+%s+\n' "$(rpt '=' $inner)"
    bcenter "${BOLD}${CYAN}PRISM — Mixed Traffic Pattern Generator${NC}"
    printf '+%s+\n' "$(rpt '=' $inner)"
    bleft "  Define a traffic mix by percentage. Streams are calculated"
    bleft "  and configured automatically based on your mix definition."
    printf '+%s+\n' "$(rpt '=' $inner)"
    echo ""

    # ------------------------------------------------------------------
    # PRESETS TABLE
    # _mtp_show_presets renders ONLY the Built-in Traffic Mix Presets
    # table. It does not repeat the session header or intro block.
    # ------------------------------------------------------------------
    _mtp_show_presets

    local preset_choice
    while true; do
        read -r -p "  Select [1-7]: " preset_choice </dev/tty
        preset_choice="${preset_choice:-}"
        case "$preset_choice" in
            [1-6]) break ;;
            7|q|Q)
                printf '%b  Returning to main menu.%b\n\n' "$CYAN" "$NC"
                return 0
                ;;
            *)
                printf '%b  Enter 1-6 to select a preset, or 7 to return.%b\n' \
                    "$RED" "$NC"
                ;;
        esac
    done

    _mtp_load_preset "$preset_choice"

    if [[ "$preset_choice" == "6" ]]; then
        _mtp_define_custom_mix
        if (( ${#MTP_CLASSES[@]} == 0 )); then
            printf '%b  No classes defined. Returning to menu.%b\n' \
                "$RED" "$NC"
            return 0
        fi
    fi

    # ── Step 2: Total stream count ─────────────────────────────────────────
    local total_streams
    while true; do
        read -r -p "  Total number of streams to generate [10]: " \
            total_streams </dev/tty
        total_streams="${total_streams:-10}"
        if [[ "$total_streams" =~ ^[0-9]+$ ]] && \
           (( total_streams >= ${#MTP_CLASSES[@]} && total_streams <= 64 )); then
            break
        fi
        printf '%b  Enter %d-%d (minimum 1 per class).%b\n' \
            "$RED" "${#MTP_CLASSES[@]}" 64 "$NC"
    done

    echo ""

    # ── Step 3: Configure targets ──────────────────────────────────────────
    _mtp_total_streams=$total_streams   # used by _mtp_configure_targets
                                        # to compute accurate port defaults
    _mtp_configure_targets

    echo ""

    # ── Step 4: Calculate stream allocation ───────────────────────────────
    _mtp_calculate_streams "$total_streams"

    # ── Step 5: Display summary and confirm ───────────────────────────────
    _mtp_show_summary

    confirm_proceed "Launch ${STREAM_COUNT} mixed traffic stream(s)?" || return 0
    _prompt_session_name
    [[ -n "$SESSION_ID" ]] && JSON_EXPORT_ENABLED=1

    # ── Step 6: Pre-flight, MTU discovery, and launch ─────────────────────
    apply_netem

    echo ""
    if ! run_preflight_checks; then
        if (( ${#NETEM_IFACES[@]} > 0 )); then
            local iface
            for iface in "${NETEM_IFACES[@]}"; do
                tc qdisc del dev "$iface" root 2>/dev/null
            done
            NETEM_IFACES=()
        fi
        return 1
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
        printf '%b  CRITICAL path MTU on one or more paths.%b\n' "$RED" "$NC"
        if ! confirm_proceed "Proceed despite MTU warnings?"; then
            return 1
        fi
    fi

    echo ""
    launch_clients
    echo ""
    printf '%b  Mixed traffic streams running. Opening dashboard...%b\n' \
        "$GREEN" "$NC"
    sleep 1
    run_dashboard "client"
    echo ""

    parse_final_results
    display_results_table
    _session_append_history "mtp"
    _json_export_write "mtp"
    offer_log_view

    local _ci
    for (( _ci=0; _ci<STREAM_COUNT; _ci++ )); do
        _cleanup_stream_files "$_ci"
        _json_sample_clear "$_ci"
    done
    JSON_EXPORT_ENABLED=0
}




run_client_mode() {
    echo ""
    print_header "PRISM — Client Mode"
    _print_session_header "Client Mode"
    echo ""
    local n
    while true; do
        read -r -p "  How many streams? [1]: " n </dev/tty; n="${n:-1}"
        [[ "$n" =~ ^[0-9]+$ ]] && (( 10#$n >= 1 && 10#$n <= 64 )) && break
        printf '%b\n' "${RED}  Enter a positive integer (1-64).${NC}"
    done

    configure_client_streams "$n" "" ""
    show_stream_summary "client"
    confirm_proceed "Launch ${n} stream(s)?" || return
    _prompt_session_name
    [[ -n "$SESSION_ID" ]] && JSON_EXPORT_ENABLED=1
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

    # Phase 1 process cleanup has already run inside run_dashboard().
    # Log files are still present at this point for results parsing.
    parse_final_results
    display_results_table
    _session_append_history "client"
    _json_export_write "client"
    offer_log_view

    # Phase 2: delete log files now that results have been read and displayed
    local _ci
    for (( _ci=0; _ci<STREAM_COUNT; _ci++ )); do
        _cleanup_stream_files "$_ci"
        _json_sample_clear "$_ci"
    done
    JSON_EXPORT_ENABLED=0
}

run_loopback_mode() {
    echo ""
    print_header "PRISM — Loopback Test Mode"
    _print_session_header "Loopback Test"
    echo ""
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
    _prompt_session_name
    [[ -n "$SESSION_ID" ]] && JSON_EXPORT_ENABLED=1
    echo ""; launch_servers; echo ""; wait_for_servers
    echo ""; launch_clients
    echo ""; printf '%b\n' "${GREEN}  Running. Opening dashboard...${NC}"; sleep 1
    run_dashboard "client"
    echo ""
    parse_final_results
    display_results_table
    _session_append_history "loopback"
    _json_export_write "loopback"
    offer_log_view

    # Phase 2: delete log files after results are displayed
    local _ci
    for (( _ci=0; _ci<STREAM_COUNT; _ci++ )); do
        _cleanup_stream_files "$_ci"
        _json_sample_clear "$_ci"
    done
    JSON_EXPORT_ENABLED=0
}

# ---------------------------------------------------------------------------
# _dscp_verify_server_get_iface  <listener_index>
#
# Resolves the correct capture interface for a server listener.
#
# A server listener binds to a specific local IP address (bind IP).
# The correct capture interface is the interface that OWNS that IP address —
# i.e. the interface on which incoming packets arrive.
#
# Resolution strategy (in priority order):
#
#   1. PRIMARY — ip addr show lookup (Linux):
#      Find which interface has the bind IP assigned.
#      This is always correct for server-side capture:
#        - For VRF listeners: returns the member interface (e.g. ens224)
#          NOT the VRF master device (e.g. vrf10)
#        - For GRT listeners: returns the physical/virtual interface (e.g. ens192)
#      Command: ip -4 addr show
#      Avoids ip route get entirely for local addresses because route lookup
#      of a local address returns the VRF master or loopback, not the
#      actual member interface where packets are received.
#
#   2. FALLBACK — ifconfig lookup (macOS):
#      Same approach using ifconfig output.
#
#   3. MANUAL — returns empty string when bind is 0.0.0.0 (all interfaces)
#      The caller (_dscp_verify_server_interactive) handles this case by
#      presenting the operator with a manual interface selection menu.
# ---------------------------------------------------------------------------

_dscp_verify_server_get_iface() {
    local idx="$1"
    local bind_ip="${SRV_BIND[$idx]:-}"
    local vrf="${SRV_VRF[$idx]:-}"

    # bind is 0.0.0.0 or unset — cannot resolve a single interface
    [[ -z "$bind_ip" || "$bind_ip" == "0.0.0.0" ]] && {
        printf '%s' ""
        return 1
    }

    if [[ "$OS_TYPE" == "linux" ]]; then

        # ── Primary: find which interface owns the bind IP ─────────────────
        local oif=""
        oif=$(ip -4 addr show 2>/dev/null \
            | awk -v ip="$bind_ip" '
                /^[0-9]+:/ {
                    iface = $2
                    gsub(/:$/, "", iface)
                    current_iface = iface
                }
                /inet / {
                    split($2, a, "/")
                    if (a[1] == ip) {
                        print current_iface
                        exit
                    }
                }
            ')

        if [[ -n "$oif" ]]; then
            # ── Loopback sub-interface guard ───────────────────────────────
            # If the IP is assigned to a loopback sub-interface (lo, lo0,
            # lo101, lo.*, etc.) the actual traffic arrives on a different
            # physical or virtual interface. Loopback sub-interfaces are
            # used for VRF route-leaking, router-ID assignment, and
            # management — they do not carry real data-plane traffic.
            #
            # In this case: find the actual traffic-bearing interface by
            # doing a route lookup for the bind IP inside the VRF.
            local _is_loopback=0
            if [[ "$oif" =~ ^lo ]] || [[ "$oif" == "lo" ]]; then
                _is_loopback=1
            fi

            if (( _is_loopback == 0 )); then
                # Check if it is a VRF master device — reject if so
                local is_vrf_master=0
                if ip -d link show dev "$oif" 2>/dev/null | grep -q ' vrf '; then
                    is_vrf_master=1
                fi

                if (( is_vrf_master == 0 )); then
                    printf '%s' "$oif"
                    return 0
                fi
            fi

            # The resolved interface is either loopback or a VRF master.
            # Fall through to route-based lookup to find the real
            # traffic-bearing interface.
        fi

        # ── Fallback: route-based lookup for traffic-bearing interface ─────
        # Use the routing table to find the egress interface for the
        # bind IP. This correctly identifies physical/virtual interfaces
        # that carry real iperf3 data traffic, even when the bind IP is
        # also assigned to a loopback sub-interface for routing purposes.
        local _awk_dev
        _awk_dev='{ for (i=1; i<=NF; i++) if ($i=="dev" && i+1<=NF) { print $(i+1); exit } }'

        local route_oif=""

        if [[ -n "$vrf" ]]; then
            # Route lookup inside the VRF
            local route_out
            route_out=$(ip route get vrf "${vrf}" "${bind_ip}" 2>/dev/null)
            route_oif=$(printf '%s' "$route_out" | awk "$_awk_dev")

            if [[ -z "$route_oif" ]]; then
                # Fallback for older kernels
                route_out=$(ip vrf exec "${vrf}" \
                    ip route get "${bind_ip}" 2>/dev/null)
                route_oif=$(printf '%s' "$route_out" | awk "$_awk_dev")
            fi
        else
            # GRT route lookup
            local route_out
            route_out=$(ip route get "${bind_ip}" 2>/dev/null)
            route_oif=$(printf '%s' "$route_out" | awk "$_awk_dev")
        fi

        # If the route lookup also returns a loopback interface, try
        # finding physical VRF member interfaces directly.
        if [[ -n "$route_oif" && ! "$route_oif" =~ ^lo ]]; then
            # Verify it is not a VRF master
            local _rm=0
            ip -d link show dev "$route_oif" 2>/dev/null | grep -q ' vrf ' \
                && _rm=1
            if (( _rm == 0 )); then
                printf '%s' "$route_oif"
                return 0
            fi
        fi

        # ── Last resort: enumerate physical VRF member interfaces ──────────
        # When both the addr-show and route methods return loopback or VRF
        # master interfaces, enumerate the physical member interfaces of
        # the VRF and pick the first one that is operationally up.
        if [[ -n "$vrf" ]]; then
            local member_iface=""
            local candidate
            while IFS= read -r candidate; do
                [[ -z "$candidate" ]] && continue
                # Skip loopback members
                [[ "$candidate" =~ ^lo ]] && continue
                # Check operational state
                local op_state
                op_state=$(ip link show dev "$candidate" 2>/dev/null \
                    | grep -oE '<[^>]+>' | head -1)
                if [[ "$op_state" == *"LOWER_UP"* || \
                      "$op_state" == *"UP"* ]]; then
                    member_iface="$candidate"
                    break
                fi
            done < <(ip link show master "${vrf}" 2>/dev/null \
                | awk '/^[0-9]+:/ {
                    iface = $2
                    gsub(/:$/, "", iface)
                    print iface
                }')

            if [[ -n "$member_iface" ]]; then
                printf '%s' "$member_iface"
                return 0
            fi
        fi

        # All resolution methods failed
        printf '%s' ""
        return 1
    fi

    # ── macOS ──────────────────────────────────────────────────────────────
    if [[ "$OS_TYPE" == "macos" ]]; then
        local oif=""
        oif=$(ifconfig 2>/dev/null \
            | awk -v ip="$bind_ip" '
                /^[a-z]/ {
                    iface = $1
                    gsub(/:$/, "", iface)
                }
                /inet / {
                    if ($2 == ip) { print iface; exit }
                }
            ')
        if [[ -n "$oif" ]]; then
            printf '%s' "$oif"
            return 0
        fi
        printf '%s' ""
        return 1
    fi

    printf '%s' ""
    return 1
}

# ---------------------------------------------------------------------------
# _dscp_verify_server_run  <listener_index>  <capture_interface>
#
# Runs tcpdump on the resolved interface for the given server listener.
# Captures incoming iperf3 traffic and reports:
#   - Source IP:Port  (iperf3 client)
#   - Destination IP:Port  (this server listener)
#   - TOS hex byte
#   - DSCP decimal value
#   - PASS/FAIL verdict against the expected DSCP (if configured)
#
# Unlike the client-side verification which filters on dst host+port,
# the server-side filter captures INCOMING traffic TO the listener port,
# so the filter is:  tcp/udp dst port <port>
# When a specific bind IP is set the filter is additionally narrowed to:
#   dst host <bind_ip> and dst port <port>
# ---------------------------------------------------------------------------
_dscp_verify_server_run() {
    local idx="$1"
    local iface="$2"
    local inner=$(( COLS - 2 ))

    local port="${SRV_PORT[$idx]:-}"
    local bind_ip="${SRV_BIND[$idx]:-}"
    local vrf="${SRV_VRF[$idx]:-}"
    local listener_num=$(( idx + 1 ))

    # ── Display header ────────────────────────────────────────────────────
    printf '\n'
    printf '+%s+\n' "$(rpt '=' "$inner")"
    bcenter "${BOLD}${CYAN}DSCP Verification — Server Listener ${listener_num}${NC}"
    printf '+%s+\n' "$(rpt '=' "$inner")"

    local vrf_label
    [[ -n "$vrf" ]] && vrf_label="VRF: ${vrf}" || vrf_label="GRT"

    bleft "  Listener : ${BOLD}port ${port}${NC}  (${vrf_label})"
    if [[ -n "$bind_ip" && "$bind_ip" != "0.0.0.0" ]]; then
        bleft "  Bind IP  : ${BOLD}${bind_ip}${NC}"
        bleft "  ${DIM}Interface resolved via: ip -4 addr show (interface owning ${bind_ip})${NC}"
    else
        bleft "  Bind IP  : ${BOLD}0.0.0.0 (all interfaces)${NC}"
        bleft "  ${DIM}Interface selected manually (bind is 0.0.0.0)${NC}"
    fi

    bleft "  Interface: ${BOLD}${iface}${NC}"

    # Show resolution method — helps operator understand why a particular
    # interface was selected, especially when loopback fallback occurred
    if [[ -n "$bind_ip" && "$bind_ip" != "0.0.0.0" ]]; then
        if [[ "$iface" =~ ^lo ]]; then
            bleft "  ${DIM}Interface resolved via: ip -4 addr show (loopback — traffic may arrive on VRF member)${NC}"
        elif [[ -n "$vrf" ]]; then
            bleft "  ${DIM}Interface resolved via: ip route get vrf ${vrf} ${bind_ip} (VRF member interface)${NC}"
        else
            bleft "  ${DIM}Interface resolved via: ip -4 addr show (interface owning ${bind_ip})${NC}"
        fi
    else
        bleft "  ${DIM}Interface selected manually (bind is 0.0.0.0)${NC}"
    fi

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

    # ── Check listener status ─────────────────────────────────────────────
    local srv_state="${SRV_PREV_STATE[$idx]:-STARTING}"
    if [[ "$srv_state" != "CONNECTED" && "$srv_state" != "RUNNING" ]]; then
        bleft "  ${YELLOW}⚠ Listener ${listener_num} has no active client (state: ${srv_state}).${NC}"
        bleft "  ${DIM}Traffic may not be flowing — capture may return no results.${NC}"
        printf '+%s+\n' "$(rpt '-' "$inner")"
    fi

    bleft "  ${DIM}Capturing up to 50 packets (3 second window)...${NC}"
    printf '+%s+\n' "$(rpt '-' "$inner")"

    # ── Build tcpdump filter ───────────────────────────────────────────────
    # Server side: capture INCOMING traffic arriving at the listener port.
    # Filter by destination port (always).  Also filter by destination host
    # when a specific bind IP is set to avoid capturing unrelated traffic
    # on shared interfaces.
    local proto_filter="tcp or udp"
    local tcpdump_filter

    if [[ -n "$bind_ip" && "$bind_ip" != "0.0.0.0" ]]; then
        tcpdump_filter="dst host ${bind_ip} and dst port ${port}"
    else
        tcpdump_filter="dst port ${port}"
    fi

    # ── Run tcpdump ───────────────────────────────────────────────────────
    local capture_file="${TMPDIR}/dscp_srv_cap_${idx}_$$.txt"
    local capture_cmd

    if (( IS_ROOT == 1 )); then
        capture_cmd="${tcpdump_bin} -i ${iface} -v -n -l -c 50 ${tcpdump_filter}"
    else
        capture_cmd="sudo ${tcpdump_bin} -i ${iface} -v -n -l -c 50 ${tcpdump_filter}"
    fi

    timeout 3 bash -c "${capture_cmd}" > "$capture_file" 2>&1

    if [[ ! -f "$capture_file" || ! -s "$capture_file" ]]; then
        bleft "  ${YELLOW}⚠ No output from tcpdump.${NC}"
        bleft "  ${DIM}Ensure a client is actively sending to this listener and retry.${NC}"
        printf '+%s+\n' "$(rpt '=' "$inner")"
        rm -f "$capture_file"
        return 1
    fi

    if grep -qiE 'permission denied|Operation not permitted|No such device' \
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

    # ── Merge continuation lines ──────────────────────────────────────────
    local merged_file="${TMPDIR}/dscp_srv_merged_${idx}_$$.txt"
    awk '
        /^[[:space:]]/ && NR > 1 { printf " %s", $0; next }
        NR > 1 { print "" }
        { printf "%s", $0 }
        END { print "" }
    ' "$capture_file" > "$merged_file"

    # ── Parse and display packets ─────────────────────────────────────────
    bleft "  ${BOLD}$(printf '%-4s  %-21s  %-21s  %-6s  %-4s  %-6s' \
        'Pkt' 'Source IP:Port' 'Destination IP:Port' 'TOS' 'DSCP' 'DSCP Name')${NC}"
    printf '+%s+\n' "$(rpt '-' "$inner")"

    local pkt_num=0
    local dscp_counts=""   # colon-separated "dscp:count" pairs for summary

    while IFS= read -r merged_line; do
        echo "$merged_line" | grep -qiE 'tos 0x' || continue
        echo "$merged_line" | grep -qE '>'        || continue

        # Extract TOS hex
        local tos_hex
        tos_hex=$(printf '%s' "$merged_line" \
            | grep -oE 'tos 0x[0-9a-fA-F]+' \
            | awk '{print $2}' | head -1)
        [[ -z "$tos_hex" ]] && continue

        # Extract src > dst address pair
        local addr_match
        addr_match=$(printf '%s' "$merged_line" | grep -oE \
            '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}[.:][0-9]+ +> +[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}[.:][0-9]+' \
            | head -1)
        [[ -z "$addr_match" ]] && continue

        local src_raw dst_raw
        src_raw=$(printf '%s' "$addr_match" | awk '{print $1}')
        dst_raw=$(printf '%s' "$addr_match" | awk '{print $3}')

        # Convert dot-notation port to colon notation for display
        local src_disp dst_disp
        src_disp=$(printf '%s' "$src_raw" | awk -F'.' '{
            if (NF==5) printf "%s.%s.%s.%s:%s",$1,$2,$3,$4,$5
            else       print $0 }')
        dst_disp=$(printf '%s' "$dst_raw" | awk -F'.' '{
            if (NF==5) printf "%s.%s.%s.%s:%s",$1,$2,$3,$4,$5
            else       print $0 }')

        # Calculate DSCP from TOS byte
        local tos_dec captured_dscp
        tos_dec=$(( 16#${tos_hex#0x} ))
        captured_dscp=$(( tos_dec >> 2 ))

        # Resolve DSCP name for display
        local dscp_name
        dscp_name=$(awk -v d="$captured_dscp" 'BEGIN {
            m[0]="CS0/BE"; m[8]="CS1";  m[10]="AF11"; m[12]="AF12"
            m[14]="AF13";  m[16]="CS2"; m[18]="AF21"; m[20]="AF22"
            m[22]="AF23";  m[24]="CS3"; m[26]="AF31"; m[28]="AF32"
            m[30]="AF33";  m[32]="CS4"; m[34]="AF41"; m[36]="AF42"
            m[38]="AF43";  m[40]="CS5"; m[44]="VA";   m[46]="EF"
            m[48]="CS6";   m[56]="CS7"
            if (d in m) print m[d]
            else         printf "DSCP-%d", d
        }')

        # Colour the DSCP name
        local dscp_col="$GREEN"
        case "$dscp_name" in
            CS0/BE)             dscp_col="$DIM"    ;;
            EF)                 dscp_col="$CYAN"   ;;
            AF4*|CS5|CS6|CS7)   dscp_col="$YELLOW" ;;
        esac

        (( pkt_num++ ))

        # Track DSCP value counts for summary
        local _found_dscp=0
        local _new_counts=""
        local _entry
        while IFS= read -r _entry; do
            [[ -z "$_entry" ]] && continue
            local _d _c
            IFS=':' read -r _d _c <<< "$_entry"
            if [[ "$_d" == "$captured_dscp" ]]; then
                _c=$(( _c + 1 ))
                _found_dscp=1
            fi
            _new_counts+="${_d}:${_c}"$'\n'
        done <<< "$dscp_counts"
        if (( _found_dscp == 0 )); then
            _new_counts+="${captured_dscp}:1"$'\n'
        fi
        dscp_counts="$_new_counts"

        # Display up to 20 rows
        if (( pkt_num <= 20 )); then
            (( ${#src_disp} > 21 )) && src_disp="${src_disp:0:20}~"
            (( ${#dst_disp} > 21 )) && dst_disp="${dst_disp:0:20}~"

            local row_pfx
            row_pfx=$(printf '%-4d  %-21s  %-21s  %-6s  %-4d  ' \
                "$pkt_num" "$src_disp" "$dst_disp" "$tos_hex" "$captured_dscp")
            bleft " ${row_pfx}${dscp_col}${dscp_name}${NC}"
        fi

    done < "$merged_file"

    rm -f "$capture_file" "$merged_file"

    # ── Summary ───────────────────────────────────────────────────────────
    printf '+%s+\n' "$(rpt '-' "$inner")"

    if (( pkt_num == 0 )); then
        bleft "  ${YELLOW}⚠ No packets with TOS field found in capture.${NC}"
        bleft "  ${DIM}Ensure a client is actively sending to port ${port} and retry.${NC}"
    else
        (( pkt_num > 20 )) && \
            bleft "  ${DIM}(Showing first 20 of ${pkt_num} packets captured)${NC}"

        bleft "  ${BOLD}Packets captured: ${pkt_num}${NC}"
        bleft "  ${BOLD}DSCP values observed:${NC}"

        local _entry
        while IFS= read -r _entry; do
            [[ -z "$_entry" ]] && continue
            local _d _c
            IFS=':' read -r _d _c <<< "$_entry"
            local _name
            _name=$(awk -v d="$_d" 'BEGIN {
                m[0]="CS0/BE"; m[8]="CS1";  m[10]="AF11"; m[12]="AF12"
                m[14]="AF13";  m[16]="CS2"; m[18]="AF21"; m[20]="AF22"
                m[22]="AF23";  m[24]="CS3"; m[26]="AF31"; m[28]="AF32"
                m[30]="AF33";  m[32]="CS4"; m[34]="AF41"; m[36]="AF42"
                m[38]="AF43";  m[40]="CS5"; m[44]="VA";   m[46]="EF"
                m[48]="CS6";   m[56]="CS7"
                if (d in m) print m[d]
                else         printf "DSCP-%d", d
            }')
            bleft "    ${CYAN}DSCP ${_d}${NC}  ${DIM}(${_name})${NC}  — ${_c} packet(s)"
        done <<< "$dscp_counts"
    fi

    printf '+%s+\n' "$(rpt '=' "$inner")"
    return 0
}

# ---------------------------------------------------------------------------
# _dscp_verify_server_interactive
#
# Called from the server dashboard when the operator presses c/C.
# Presents a listener selection menu, resolves the capture interface using
# ip route get (VRF or GRT), and runs _dscp_verify_server_run.
# ---------------------------------------------------------------------------

_dscp_verify_server_interactive() {
    local inner=$(( COLS - 2 ))

    printf '\033[?25h'
    printf '\n'

    if (( SERVER_COUNT == 0 )); then
        printf '+%s+\n' "$(rpt '=' "$inner")"
        bcenter "${BOLD}${CYAN}Packet Capture — Server${NC}"
        printf '+%s+\n' "$(rpt '=' "$inner")"
        bleft "  ${YELLOW}⚠ No server listeners configured.${NC}"
        printf '+%s+\n' "$(rpt '=' "$inner")"
        printf '\n'
        read -r -p "  Press Enter to return to dashboard..." </dev/tty
        printf '\033[?25l'
        return 0
    fi

    # ── Refresh listener state before showing selection menu ─────────────
    # probe_server_status updates SRV_PREV_STATE[] with the current live
    # state so the selection table shows CONNECTED/RUNNING/LISTENING etc.
    # instead of STARTING (which is the initial value before the first
    # dashboard tick runs probe_server_status).
    local i
    for (( i=0; i<SERVER_COUNT; i++ )); do
        probe_server_status "$i" > /dev/null
    done

    # ── Column widths for the selection table ─────────────────────────────
    # Inner usable width after bleft 1-space indent = COLS - 3 = 77
    # Fields: #(3) Port(6) BindIP(16) VRF(10) Status(10) = 45 + 4 gaps(4) = 49
    local SC_SN=3 SC_PORT=6 SC_BIND=16 SC_VRF=10 SC_STAT=10

    # ── Listener selection ────────────────────────────────────────────────
    local selected_idx=-1

    if (( SERVER_COUNT == 1 )); then
        selected_idx=0
    else
        printf '+%s+\n' "$(rpt '=' "$inner")"
        bcenter "${BOLD}${CYAN}Packet Capture — Select Listener${NC}"
        printf '+%s+\n' "$(rpt '=' "$inner")"

        # Header row — fixed column widths
        bleft "${BOLD}$(printf \
            ' %-*s  %*s  %-*s  %-*s  %-*s' \
            "$SC_SN"   '#' \
            "$SC_PORT" 'Port' \
            "$SC_BIND" 'Bind IP' \
            "$SC_VRF"  'VRF' \
            "$SC_STAT" 'Status')${NC}"
        printf '+%s+\n' "$(rpt '-' "$inner")"

        for (( i=0; i<SERVER_COUNT; i++ )); do
            local sn=$(( i + 1 ))
            # Use refreshed state from SRV_PREV_STATE
            local st="${SRV_PREV_STATE[$i]:-UNKNOWN}"
            local bind_disp="${SRV_BIND[$i]:-0.0.0.0}"
            local vrf_disp="${SRV_VRF[$i]:-GRT}"

            # Truncate long fields
            (( ${#bind_disp} > SC_BIND )) && \
                bind_disp="${bind_disp:0:$(( SC_BIND - 1 ))}~"
            (( ${#vrf_disp}  > SC_VRF  )) && \
                vrf_disp="${vrf_disp:0:$(( SC_VRF - 1 ))}~"

            # Status colour
            local st_col
            case "$st" in
                CONNECTED) st_col="${GREEN}"  ;;
                RUNNING)   st_col="${CYAN}"   ;;
                LISTENING) st_col="${BLUE}"   ;;
                DONE)      st_col="${DIM}"    ;;
                FAILED)    st_col="${RED}"    ;;
                *)         st_col="${YELLOW}" ;;
            esac

            # Build plain portion then append coloured status
            local plain_part
            plain_part=$(printf ' %-*s  %*s  %-*s  %-*s  ' \
                "$SC_SN"   "$sn" \
                "$SC_PORT" "${SRV_PORT[$i]}" \
                "$SC_BIND" "$bind_disp" \
                "$SC_VRF"  "$vrf_disp")
            bleft "${plain_part}${st_col}$(printf '%-*s' "$SC_STAT" "$st")${NC}"

            # Separator between listeners (not after last)
            if (( i < SERVER_COUNT - 1 )); then
                printf '+%s+\n' "$(rpt '-' "$inner")"
            fi
        done

        printf '+%s+\n' "$(rpt '=' "$inner")"
        printf '\n'

        local sel_raw sel_lower
        while true; do
            read -r -p "  Listener number to capture (or q to cancel): " \
                sel_raw </dev/tty
            sel_lower=$(printf '%s' "$sel_raw" | tr '[:upper:]' '[:lower:]')
            [[ "$sel_lower" == "q" || -z "$sel_raw" ]] && {
                printf '\033[?25l'; return 0
            }
            if [[ "$sel_raw" =~ ^[0-9]+$ ]] && \
               (( 10#$sel_raw >= 1 && 10#$sel_raw <= SERVER_COUNT )); then
                selected_idx=$(( 10#$sel_raw - 1 ))
                break
            fi
            printf '%b\n' \
                "${RED}  Enter a listener number 1-${SERVER_COUNT} or q to cancel.${NC}"
        done
    fi

    # ── Resolve capture interface ─────────────────────────────────────────
    local iface
    iface=$(_dscp_verify_server_get_iface "$selected_idx")

    # When bind is 0.0.0.0 or resolution fails, offer manual selection
    if [[ -z "$iface" ]]; then
        printf '\n'
        printf '+%s+\n' "$(rpt '=' "$inner")"
        bcenter "${BOLD}${CYAN}Packet Capture — Select Interface${NC}"
        printf '+%s+\n' "$(rpt '=' "$inner")"
        bleft "  ${YELLOW}Cannot auto-resolve interface (bind is 0.0.0.0 or lookup failed).${NC}"
        bleft "  ${DIM}Select the interface to capture on:${NC}"
        printf '+%s+\n' "$(rpt '-' "$inner")"

        # Interface table column widths
        local IC_SN=3 IC_IF=16 IC_IP=15 IC_VRF=10
        bleft "${BOLD}$(printf ' %-*s  %-*s  %-*s  %-*s' \
            "$IC_SN" '#' "$IC_IF" 'Interface' "$IC_IP" 'IP Address' \
            "$IC_VRF" 'VRF')${NC}"
        printf '+%s+\n' "$(rpt '-' "$inner")"

        get_interface_list

        local vrf_filter="${SRV_VRF[$selected_idx]:-}"
        local j disp_idx=0
        local -a selectable_ifaces=()

        for (( j=0; j<${#IFACE_NAMES[@]}; j++ )); do
            local iface_vrf="${IFACE_VRFS[$j]:-GRT}"
            if [[ ( -z "$vrf_filter" && "$iface_vrf" == "GRT" ) || \
                  ( -n "$vrf_filter" && "$iface_vrf" == "$vrf_filter" ) ]]; then
                (( disp_idx++ ))
                selectable_ifaces+=("${IFACE_NAMES[$j]}")
                local if_disp="${IFACE_NAMES[$j]}"
                local ip_disp="${IFACE_IPS[$j]}"
                (( ${#if_disp} > IC_IF )) && if_disp="${if_disp:0:$(( IC_IF-1 ))}~"
                (( ${#ip_disp} > IC_IP )) && ip_disp="${ip_disp:0:$(( IC_IP-1 ))}~"
                bleft "$(printf ' %-*s  %-*s  %-*s  %-*s' \
                    "$IC_SN"  "$disp_idx" \
                    "$IC_IF"  "$if_disp" \
                    "$IC_IP"  "$ip_disp" \
                    "$IC_VRF" "$iface_vrf")"
            fi
        done

        printf '+%s+\n' "$(rpt '=' "$inner")"
        printf '\n'

        if (( ${#selectable_ifaces[@]} == 0 )); then
            printf '%b\n' "${RED}  No interfaces found for this listener.${NC}"
            read -r -p "  Press Enter to return to dashboard..." </dev/tty
            printf '\033[?25l'
            return 1
        fi

        local iface_sel
        while true; do
            read -r -p "  Interface number (or q to cancel): " iface_sel </dev/tty
            local iface_lower
            iface_lower=$(printf '%s' "$iface_sel" | tr '[:upper:]' '[:lower:]')
            [[ "$iface_lower" == "q" || -z "$iface_sel" ]] && {
                printf '\033[?25l'; return 0
            }
            if [[ "$iface_sel" =~ ^[0-9]+$ ]] && \
               (( 10#$iface_sel >= 1 && \
                  10#$iface_sel <= ${#selectable_ifaces[@]} )); then
                iface="${selectable_ifaces[$(( 10#$iface_sel - 1 ))]}"
                break
            fi
            printf '%b\n' \
                "${RED}  Enter 1-${#selectable_ifaces[@]} or q to cancel.${NC}"
        done
    fi

    # ── Run capture ───────────────────────────────────────────────────────
    _dscp_verify_server_run "$selected_idx" "$iface"

    printf '\n'
    read -r -p "  Press Enter to return to dashboard..." </dev/tty
    printf '\033[?25l'
    return 0
}


# ==============================================================================
# show_main_menu
#
# ALIGNMENT GUARANTEES:
#   1. All box lines use COLS as the single source of truth for width.
#   2. The title is centered using _visible_len() (ANSI-safe) so color
#      codes never corrupt the centering arithmetic.
#   3. Section labels use exact right-padding derived from INNER width
#      and the plain-text label length — no ANSI bytes in the math.
#   4. Menu item rows use a two-pass approach: build the plain-text
#      portion first, measure it, then pad to INNER width.
#   5. All fields are truncated before printing so nothing can overflow
#      the right border regardless of terminal width.
#   6. COLS is re-read at the start of every call so the menu adapts
#      immediately when the operator resizes the terminal.
# ==============================================================================

show_main_menu() {
    clear

    # ------------------------------------------------------------------
    # Re-detect terminal width on every call.
    # This ensures the menu adapts when the terminal is resized between
    # menu invocations without requiring a full script restart.
    # ------------------------------------------------------------------
    local TW
    if command -v tput >/dev/null 2>&1 && TW=$(tput cols 2>/dev/null); then
        :
    elif [[ -n "${COLUMNS:-}" ]]; then
        TW=$COLUMNS
    else
        TW=80
    fi
    [[ $TW -lt 60 ]] && TW=60
    COLS=$TW

    local INNER=$(( COLS - 2 ))   # usable chars between left and right border

    # ------------------------------------------------------------------
    # _mh_rule <left> <fill> <right>
    # Full-width horizontal rule using the current COLS value.
    # ------------------------------------------------------------------
    _mh_rule() {
        printf "%s%s%s\n" "$1" "$(rpt "$2" $INNER)" "$3"
    }

    # ------------------------------------------------------------------
    # _mh_center <text>
    # Centers text inside the box using _visible_len() so ANSI escape
    # codes do not corrupt the padding arithmetic.
    # ------------------------------------------------------------------
    _mh_center() {
        local txt="$1"
        local vlen
        vlen=$(_visible_len "$txt")
        local lpad=$(( (INNER - vlen) / 2 ))
        local rpad=$(( INNER - vlen - lpad ))
        [[ $lpad -lt 0 ]] && lpad=0
        [[ $rpad -lt 0 ]] && rpad=0
        printf "|%s%b%s|\n" \
            "$(rpt ' ' $lpad)" "$txt" "$(rpt ' ' $rpad)"
    }

    # ------------------------------------------------------------------
    # _mh_left <text>
    # Left-aligned full-width line. Uses _visible_len() for right-pad
    # so embedded ANSI codes do not affect border alignment.
    # ------------------------------------------------------------------
    _mh_left() {
        local txt="$1"
        local vlen
        vlen=$(_visible_len "$txt")
        local rpad=$(( INNER - vlen ))
        [[ $rpad -lt 0 ]] && rpad=0
        printf "|%b%s|\n" "$txt" "$(rpt ' ' $rpad)"
    }

    # ------------------------------------------------------------------
    # _mh_section <label>
    # Renders a section label row.
    # The label is plain text (no ANSI) so ${#label} is exact.
    # Layout: "|  " + label + spaces + "|"
    #          2   + len   + rpad   + 1  = COLS
    #          rpad = INNER - 2 - len
    # ------------------------------------------------------------------
    _mh_section() {
        local label="$1"
        local llen=${#label}
        local rpad=$(( INNER - 2 - llen ))
        [[ $rpad -lt 0 ]] && rpad=0
        printf "|  %b%s%b%s|\n" \
            "${BOLD}" "$label" "${NC}" "$(rpt ' ' $rpad)"
    }

    # ------------------------------------------------------------------
    # _mh_item <num> <name> <desc>
    # Renders one menu item row with exact border alignment.
    #
    # Layout:
    #   "|  " + num(1) + "  " + name(name_col) + " " + desc + pad + "|"
    #
    # Column widths:
    #   num_col  = 1   (single digit 1-8)
    #   name_col = 20  (fixed, truncated with ~ if too long)
    #   desc_col = INNER - 2 - num_col - 2 - name_col - 1 - 1
    #            = INNER - 26
    #
    # All arithmetic is on plain text lengths only.
    # The description is truncated to desc_col before printing so it
    # can never push past the right border.
    # ------------------------------------------------------------------
    _mh_item() {
        local num="$1"
        local name="$2"
        local desc="$3"

        local num_col=1
        local name_col=20

        # Available space for description
        # "|  " + num + "  " + name + " " + desc + pad + "|"
        #  2   +  1  +  2  +  20  + 1  + desc  +  0  + 1  = COLS
        # desc_max = COLS - 2 - num_col - 2 - name_col - 1 - 1
        #          = COLS - 27
        local desc_max=$(( COLS - 27 ))
        [[ $desc_max -lt 10 ]] && desc_max=10

        # Truncate name and desc to their column widths
        if (( ${#name} > name_col )); then
            name="${name:0:$(( name_col - 1 ))}~"
        fi
        if (( ${#desc} > desc_max )); then
            desc="${desc:0:$(( desc_max - 1 ))}~"
        fi

        # Right-pad name to exactly name_col chars
        local name_pad=$(( name_col - ${#name} ))
        [[ $name_pad -lt 0 ]] && name_pad=0

        # Right-pad desc to exactly desc_max chars
        local desc_pad=$(( desc_max - ${#desc} ))
        [[ $desc_pad -lt 0 ]] && desc_pad=0

        # Build and print the row
        # Visible structure: "|  N  NAME_PADDED DESC_PADDED|"
        printf "|  %b%s%b  %b%s%b%s %s%s|\n"      \
            "${CYAN}"  "$num"  "${NC}"              \
            "${BOLD}"  "$name" "${NC}"              \
            "$(rpt ' ' $name_pad)"                  \
            "$desc"                                 \
            "$(rpt ' ' $desc_pad)"
    }

    # ------------------------------------------------------------------
    # RENDER: Header block
    # ------------------------------------------------------------------
    _mh_rule "+" "=" "+"

    # Title — uses _mh_center with _visible_len so BOLD/NC bytes are
    # excluded from the centering calculation.
    local _title
    _title="${BOLD}PRISM${NC}  ${DIM}Performance Real-time iPerf3 Stream Manager${NC}  ${BOLD}v8.3.9${NC}"
    _mh_center "$_title"

    _mh_rule "+" "=" "+"

    # System info lines — plain text built first, then printed with
    # _mh_left which uses _visible_len for correct right-padding.
    local _iperf_line="${DIM}iperf3 ${IPERF3_MAJOR}.${IPERF3_MINOR}.${IPERF3_PATCH}${NC}"
    _iperf_line+="  at ${IPERF3_BIN}"
    [[ "$OS_TYPE" == "macos" ]] && \
        _iperf_line+="  ${DIM}[macOS / bash ${BASH_MAJOR}.x]${NC}"

    local _root_text
    (( IS_ROOT )) && _root_text="${GREEN}root${NC}" || _root_text="${YELLOW}non-root${NC}"

    local _status_line
    _status_line=" ${DIM}User${NC}  ${_root_text}"
    _status_line+="  ${DIM}·${NC}  Theme  ${DIM}${THEME_CURRENT:-dark}${NC}"
    _status_line+="  ${DIM}·${NC}  OS  ${DIM}${OS_TYPE}${NC}"

    _mh_left "${_status_line}"
    _mh_rule "+" "=" "+"

    # ------------------------------------------------------------------
    # RENDER: NETWORK section
    # ------------------------------------------------------------------
    _mh_section "NETWORK"
    _mh_rule "+" "-" "+"
    _mh_item "1" "Interface Table"  "List interfaces, IPs, VRFs and link state"
    _mh_item "2" "Server Mode"      "Launch one or more iperf3 listeners"
    _mh_item "3" "Client Mode"      "Generate traffic streams with full QoS control"
    _mh_item "4" "Loopback Test"    "Self-contained server + client validation"
    _mh_item "5" "Mixed Traffic"    "Generate streams from a traffic mix definition"
    _mh_rule "+" "-" "+"

    # ------------------------------------------------------------------
    # RENDER: REFERENCE section
    # ------------------------------------------------------------------
    _mh_section "REFERENCE"
    _mh_rule "+" "-" "+"
    _mh_item "6" "DSCP Reference"   "DSCP / TOS / EF / AF / CS class mappings"
    _mh_item "7" "Colour Theme"     "Dark · Light · Mono  (active: ${THEME_CURRENT:-dark})"
    _mh_rule "+" "-" "+"

    # ------------------------------------------------------------------
    # RENDER: SESSION section
    # ------------------------------------------------------------------
    _mh_section "SESSION"
    _mh_rule "+" "-" "+"
    _mh_item "8" "Exit"             ""
    _mh_rule "+" "=" "+"

    echo ""
}

main_menu() {
    while true; do
        show_main_menu
        local choice
        read -r -p "  Select [1-8]: " choice </dev/tty
        case "$choice" in
            1)
                echo ""; build_vrf_maps; get_interface_list
                show_interface_table; echo ""
                read -r -p "  Press Enter to return to menu..." </dev/tty ;;
            2)
                build_vrf_maps; get_interface_list; run_server_mode; echo ""
                read -r -p "  Press Enter to return to menu..." </dev/tty
                # Reset configuration only — PIDs already cleaned by
                # run_dashboard exit / cleanup trap during the session
                SERVER_COUNT=0
                SRV_PORT=(); SRV_BIND=(); SRV_VRF=()
                SRV_ONEOFF=(); SRV_LOGFILE=(); SRV_SCRIPT=()
                SRV_PREV_STATE=(); SRV_BW_CACHE=()
                SERVER_PIDS=()
                ;;
            3)
                build_vrf_maps; get_interface_list; run_client_mode; echo ""
                read -r -p "  Press Enter to return to menu..." </dev/tty
                # Reset configuration only
                STREAM_COUNT=0
                S_NETEM_IFACE=()
                NETEM_IFACES=()
                S_PROTO=();  S_TARGET=(); S_PORT=();   S_BW=()
                S_DURATION=(); S_DSCP_NAME=(); S_DSCP_VAL=()
                S_PARALLEL=(); S_REVERSE=(); S_CCA=()
                S_WINDOW=();   S_MSS=();    S_BIND=()
                S_VRF=();      S_DELAY=();  S_JITTER=(); S_LOSS=()
                S_NOFQ=();     S_LOGFILE=(); S_SCRIPT=()
                S_START_TS=(); S_STATUS_CACHE=(); S_ERROR_MSG=()
                S_FINAL_SENDER_BW=(); S_FINAL_RECEIVER_BW=()
                STREAM_PIDS=()
                PING_PIDS=();  PING_LOGFILES=()
                S_RTT_MIN=();  S_RTT_AVG=();  S_RTT_MAX=()
                S_RTT_JITTER=(); S_RTT_LOSS=(); S_RTT_SAMPLES=()
                S_CWND_CURRENT=(); S_CWND_MIN=();   S_CWND_MAX=()
                S_CWND_FINAL=();   S_CWND_SAMPLES=(); S_CWND_SUM=()
                S_RAMP_ENABLED=(); S_RAMP_UP=();      S_RAMP_DOWN=()
                S_RAMP_STEPS=();   S_RAMP_PHASE=();   S_RAMP_PHASE_TS=()
                S_RAMP_BW_CURRENT=(); S_RAMP_BW_TARGET=()
                S_RAMP_IFACE=();   S_RAMP_TC_ACTIVE=()
                S_RAMP_TIMELINE_SNAPSHOT=()
                S_TARGET_DISPLAY=()
                if (( BASH_MAJOR >= 4 )); then
                    PMTU_RESULTS=(); PMTU_STATUS=(); PMTU_RECOMMEND=()
                fi
                JSON_EXPORT_ENABLED=0
                JSON_EXPORT_FILES=()
                # Also clear any leftover sample buffers
                local _jci
                for (( _jci=0; _jci<STREAM_COUNT; _jci++ )); do
                    _json_sample_clear "$_jci"
                done
                ;;
            4)
                build_vrf_maps; get_interface_list; run_loopback_mode; echo ""
                read -r -p "  Press Enter to return to menu..." </dev/tty
                # Reset configuration only
                STREAM_COUNT=0; SERVER_COUNT=0
                NETEM_IFACES=()
                S_NETEM_IFACE=()
                SRV_PORT=(); SRV_BIND=(); SRV_VRF=()
                SRV_ONEOFF=(); SRV_LOGFILE=(); SRV_SCRIPT=()
                SRV_PREV_STATE=(); SRV_BW_CACHE=()
                S_PROTO=();  S_TARGET=(); S_PORT=();   S_BW=()
                S_DURATION=(); S_DSCP_NAME=(); S_DSCP_VAL=()
                S_PARALLEL=(); S_REVERSE=(); S_CCA=()
                S_WINDOW=();   S_MSS=();    S_BIND=()
                S_VRF=();      S_DELAY=();  S_JITTER=(); S_LOSS=()
                S_NOFQ=();     S_LOGFILE=(); S_SCRIPT=()
                S_START_TS=(); S_STATUS_CACHE=(); S_ERROR_MSG=()
                S_FINAL_SENDER_BW=(); S_FINAL_RECEIVER_BW=()
                STREAM_PIDS=(); SERVER_PIDS=()
                PING_PIDS=();   PING_LOGFILES=()
                S_RTT_MIN=();   S_RTT_AVG=();  S_RTT_MAX=()
                S_RTT_JITTER=(); S_RTT_LOSS=(); S_RTT_SAMPLES=()
                S_CWND_CURRENT=(); S_CWND_MIN=();   S_CWND_MAX=()
                S_CWND_FINAL=();   S_CWND_SAMPLES=(); S_CWND_SUM=()
                S_RAMP_ENABLED=(); S_RAMP_UP=();      S_RAMP_DOWN=()
                S_RAMP_STEPS=();   S_RAMP_PHASE=();   S_RAMP_PHASE_TS=()
                S_RAMP_BW_CURRENT=(); S_RAMP_BW_TARGET=()
                S_RAMP_IFACE=();   S_RAMP_TC_ACTIVE=()
                S_RAMP_TIMELINE_SNAPSHOT=()
                S_TARGET_DISPLAY=()
                JSON_EXPORT_ENABLED=0
                JSON_EXPORT_FILES=()
                # Also clear any leftover sample buffers
                local _jci
                for (( _jci=0; _jci<STREAM_COUNT; _jci++ )); do
                    _json_sample_clear "$_jci"
                done
                ;;

            5)
                build_vrf_maps; get_interface_list; run_mixed_traffic_mode; echo ""
                read -r -p "  Press Enter to return to menu..." </dev/tty
                STREAM_COUNT=0
                MTP_CLASSES=(); MTP_TARGETS=(); MTP_PORTS=()
                MTP_DURATIONS=(); MTP_BINDS=(); MTP_VRFS=()
                S_PROTO=();  S_TARGET=(); S_PORT=();   S_BW=()
                S_DURATION=(); S_DSCP_NAME=(); S_DSCP_VAL=()
                S_PARALLEL=(); S_REVERSE=(); S_CCA=()
                S_WINDOW=();   S_MSS=();    S_BIND=()
                S_VRF=();      S_DELAY=();  S_JITTER=(); S_LOSS=()
                S_NOFQ=();     S_LOGFILE=(); S_SCRIPT=()
                S_START_TS=(); S_STATUS_CACHE=(); S_ERROR_MSG=()
                S_FINAL_SENDER_BW=(); S_FINAL_RECEIVER_BW=()
                STREAM_PIDS=(); PING_PIDS=(); PING_LOGFILES=()
                S_RTT_MIN=();  S_RTT_AVG=();  S_RTT_MAX=()
                S_RTT_JITTER=(); S_RTT_LOSS=(); S_RTT_SAMPLES=()
                S_CWND_CURRENT=(); S_CWND_MIN=();   S_CWND_MAX=()
                S_CWND_FINAL=();   S_CWND_SAMPLES=(); S_CWND_SUM=()
                S_RAMP_ENABLED=(); S_RAMP_UP=();      S_RAMP_DOWN=()
                S_RAMP_STEPS=();   S_RAMP_PHASE=();   S_RAMP_PHASE_TS=()
                S_RAMP_BW_CURRENT=(); S_RAMP_BW_TARGET=()
                S_RAMP_IFACE=();   S_RAMP_TC_ACTIVE=()
                S_BIDIR=()
                S_RAMP_TIMELINE_SNAPSHOT=()
                S_TARGET_DISPLAY=()
                MTP_BASE_PORT=5201
                MTP_PORT_MODE="auto"
                if (( BASH_MAJOR >= 4 )); then
                    PMTU_RESULTS=(); PMTU_STATUS=(); PMTU_RECOMMEND=()
                fi
                JSON_EXPORT_ENABLED=0
                JSON_EXPORT_FILES=()
                # Also clear any leftover sample buffers
                local _jci
                for (( _jci=0; _jci<STREAM_COUNT; _jci++ )); do
                    _json_sample_clear "$_jci"
                done

                ;;
            6)
                echo ""; show_dscp_table
                read -r -p "  Press Enter to return to menu..." </dev/tty ;;
            7)
                show_theme_menu ;;
            8|q|Q)
                echo ""; printf '%b\n' "${GREEN}  PRISM — Goodbye! Cleaning up...${NC}"; echo "";
                cleanup "user exit (option 7)"
                exit 0 ;;
            "") ;;
            *)
                printf '%b\n' "${RED}  Invalid choice '${choice}'. Enter 1 to 7.${NC}"
                sleep 1 ;;
        esac
    done
}

# ==============================================================================
# MAIN EXECUTION FLOW
# ==============================================================================
main() {
    _init_colors
    _init_ansi_lengths
    _build_session_header
    _theme_load
    _theme_sync
    register_traps
    init_tmpdir
    find_iperf3
    get_iperf3_version
    detect_forceflush
    check_root
    build_vrf_maps
    get_interface_list
    _print_capability_matrix

    # Step 5: Feature guard checks using populated CAP_* globals.
    if [[ "$S_RAMP_ENABLED" == "1" ]] && [[ "$CAP_RAMP_RAW" == *"OFF"* ]]; then
        printf "%bERROR:%b TCP Ramp-Up requested but capability is [OFF].\n" \
            "$R" "$NC"
        printf "       Run as root with iproute2 (tc) installed.\n"
        exit 1
    fi

    if [[ "$S_BIDIR" == "1" ]] && [[ "$CAP_BIDIR_RAW" == *"OFF"* ]]; then
        printf "%bERROR:%b Bidir requested but iperf3 version is too old.\n" \
            "$R" "$NC"
        printf "       Upgrade iperf3 to v3.7 or later.\n"
        exit 1
    fi

    # Step 6: Countdown before TUI takes over.
    printf "Launching PRISM dashboard in 5 seconds "
    for _i in 5 4 3 2 1; do
        printf "!"
        sleep 1
    done
    printf "\n\n\n"

    main_menu
}

# Entry point
main "$@"