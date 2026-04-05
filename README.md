# iperf3 Multi-Stream Traffic Tool

<div align="center">

![Version](https://img.shields.io/badge/version-7.7-blue?style=flat-square)
![Shell](https://img.shields.io/badge/shell-bash%204.0%2B-green?style=flat-square)
![Platform](https://img.shields.io/badge/platform-Linux-orange?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-yellow?style=flat-square)
![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square)

*An enterprise-grade interactive Bash wrapper for `iperf3` featuring
multi-stream orchestration, real-time live dashboards, VRF awareness,
DSCP/QoS marking, TCP tuning, and network impairment injection.*

</div>

---

## Table of Contents

- [Introduction](#introduction)
- [How It Works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Application Menu](#application-menu)
- [Use Cases](#use-cases)
  - [Use Case 1 — Basic TCP Throughput Test](#use-case-1--basic-tcp-throughput-test)
  - [Use Case 2 — UDP Performance and Loss Test](#use-case-2--udp-performance-and-loss-test)
  - [Use Case 3 — Multi-Stream Parallel Testing](#use-case-3--multi-stream-parallel-testing)
  - [Use Case 4 — Server Mode with Multiple Listeners](#use-case-4--server-mode-with-multiple-listeners)
  - [Use Case 5 — VRF-Aware Testing](#use-case-5--vrf-aware-testing)
  - [Use Case 6 — DSCP and QoS Marking](#use-case-6--dscp-and-qos-marking)
  - [Use Case 7 — TCP Tuning and CCA Comparison](#use-case-7--tcp-tuning-and-cca-comparison)
  - [Use Case 8 — Network Impairment Injection](#use-case-8--network-impairment-injection)
  - [Use Case 9 — Reverse Mode Asymmetric Testing](#use-case-9--reverse-mode-asymmetric-testing)
  - [Use Case 10 — Loopback Local Validation](#use-case-10--loopback-local-validation)
- [Dashboard Reference](#dashboard-reference)
- [DSCP Reference Table](#dscp-reference-table)
- [Output and Log Files](#output-and-log-files)
- [Cleanup and Signal Handling](#cleanup-and-signal-handling)
- [Troubleshooting](#troubleshooting)
- [Known Limitations](#known-limitations)
- [License](#license)

---

## Introduction

`iperf3_manager.sh` is a production-grade terminal application that wraps
`iperf3` in a fully interactive menu-driven interface. It was built to
solve the real operational challenges that network engineers face when using
raw `iperf3` commands in enterprise and carrier environments.

### The Problem with Raw `iperf3`

Using `iperf3` directly works well for a single stream, but breaks down
quickly in production scenarios:

| Challenge | Why It Hurts |
|---|---|
| Multiple simultaneous streams | Requires multiple terminals, manual PID tracking |
| VRF-specific testing | Must remember exact `ip vrf exec` syntax and VRF names |
| DSCP marking | Must manually convert names like `EF` or `AF41` to TOS values |
| Live monitoring | Output scrolls away and is hard to follow across streams |
| TCP tuning | Must remember flags for CCA, window size, MSS across streams |
| Cleanup after Ctrl+C | Orphaned processes and `tc` rules left behind |
| UDP bandwidth target | Easy to forget and run at default 1 Mbps |
| Post-test analysis | No consolidated summary across multiple streams |

### What This Tool Provides

`iperf3_manager.sh` replaces all of that complexity with a single guided
workflow that any operator can use without memorising `iperf3` flags.

### Who Should Use This Tool

- Network engineers validating WAN or LAN throughput
- Operations teams running before/after change benchmarks
- Lab engineers testing QoS, DSCP, and traffic classification
- Anyone testing within Linux VRF environments
- Teams needing reproducible multi-stream test results

---

## How It Works

The script builds a complete orchestration layer around `iperf3`:

```
┌─────────────────────────────────────────────────────────────────────┐
│ iperf3-traffic-manager.sh                                           │
│                                                                     │
│ 1. Detect system capabilities and iperf3 version                    │
│ 2. Discover interfaces, IPs, speeds, and VRF memberships            │
│ 3. Guide operator through stream/listener configuration             │
│ 4. Build per-stream launch scripts with correct flags               │
│ 5. Launch iperf3 processes in background                            │
│ 6. Track PIDs and log file paths per stream                         │
│ 7. Parse plain-text iperf3 output every second                      │
│ 8. Render overwrite dashboard without terminal scrolling            │
│ 9. Show consolidated final results on completion                    │
│ 10. Clean up all processes and tc rules on exit                     │
└─────────────────────────────────────────────────────────────────────┘
```
### Why Plain Text Output Instead of JSON

`iperf3 -J` (JSON mode) buffers all output until the process exits.
This makes it useless for real-time display. The script uses plain-text
output and parses interval lines using `grep` and `awk` anchored on the
`bits/sec` token, which works identically for both TCP and UDP output.

### How the Dashboard Avoids Scrolling

- **Step 1** Print N blank lines Forces terminal to scroll
       Reserves N lines of viewport space
- **Step 2** Move cursor up N rows printf '\033[%dA' N
- **Step 3** Overwrite frame in place Renders over the blank lines
- **Step 4** Sleep 1 second
- **Step 5** Repeat from Step 2

This technique works reliably across SSH sessions, `tmux`, `screen`, and
all standard terminal emulators.

### How Connection Status Is Detected

Status detection uses three layers in priority order:

- **Layer 1** /proc/<pid>/net/tcp TCP ESTABLISHED via hex IP:port match
              /proc/<pid>/net/udp UDP socket presence
- **Layer 2** ss -tn / ss -un Socket state via iproute2
- **Layer 3** Log interval-line grep Pattern: [ N] X.X-Y.Y sec.*bits

Presence confirms active transfer

---

## Requirements

### Mandatory

| Component | Minimum | Notes |
|---|---|---|
| Operating System | Linux | Required for VRF and `/proc` features |
| `bash` | 4.0 | Associative arrays and modern expansions required |
| `iperf3` | 3.0 | Core measurement engine |
| `iproute2` | any | Provides `ip`, `ss`, and `tc` |
| `awk` | any | Bandwidth parsing and unit conversion |
| `grep` | any | Log scanning |
| `coreutils` | any | `mktemp`, `date`, `rm`, `cat`, `wc` |

### Optional

| Component | Purpose | Missing Impact |
|---|---|---|
| `tc` from `iproute2` | Network impairment via `tc netem` | Netem prompts shown but skipped |
| `ethtool` | Interface speed detection fallback | Speed reported as `N/A` |
| Root / `sudo` | VRF exec, netem, ports below 1024 | Warning shown, features may fail |

### iperf3 Feature Detection

The script auto-detects the installed `iperf3` version and enables
features accordingly:

| Feature | Flag | Detected How |
|---|---|---|
| Live output flushing | `--forceflush` | `iperf3 --help` output scan |
| Unlimited duration | `-t 0` | Version comparison |
| FQ pacing control | `--no-fq-socket-pacing` | Version comparison |

### Supported Linux Distributions

| Distribution | Status |
|---|---|
| Ubuntu 18.04 to 24.04 | Fully supported |
| Debian 10, 11, 12 | Fully supported |
| RHEL / CentOS 7, 8, 9 | Fully supported |
| Rocky Linux / AlmaLinux | Fully supported |
| Fedora 36 and later | Fully supported |
| openSUSE Leap 15 | Supported |
| Alpine Linux | Partial — requires bash and full awk |
| macOS | Partial — no VRF or netem, bash must be upgraded |
| Windows WSL2 | Partial — netem unavailable |

---

## Installation

### Step 1 — Install Required Packages

**Ubuntu / Debian**
```bash
sudo apt update
sudo apt install -y iperf3 iproute2 gawk grep coreutils ethtool
```
**RHEL / CentOS 7**
```
sudo yum install -y iperf3 iproute gawk grep coreutils ethtool
```
**RHEL 8+ / Rocky / AlmaLinux / Fedora**
```
sudo dnf install -y iperf3 iproute gawk grep coreutils ethtool
```
**Build iperf3 from source (for latest version)**
```
git clone https://github.com/esnet/iperf.git
cd iperf
./configure
make
sudo make install
iperf3 --version
```
## Step 2 — Get the Script
```
git clone https://github.com/waqasdaar/iperf3-traffic-streams.git
cd iperf3-traffic-streams
```
## Step 3 — Set Execute Permission
```
chmod +x iperf3-traffic-streams.sh
```
## Step 4 — Optional System-Wide Installation
```
sudo cp iperf3_manager.sh /usr/local/bin/iperf3-traffic-streams.sh
sudo chmod +x /usr/local/bin/iperf3-traffic-streams.sh
```
## Step 5 — Verify Everything Is Ready
```
# Check bash version (must be 4.0 or later)
bash --version

# Check iperf3
iperf3 --version

# Check iproute2
ip -V
ss --version

# Run the script
sudo ./iperf3-traffic-streams.sh
```
**Expected Launch Screen**

```
+==============================================================================+
|                                                                              |
|             iperf3 Multi-Stream Traffic Manager  v7.7                        |
|                                                                              |
+==============================================================================+
|  iperf3 3.9   at /usr/bin/iperf3                                             |
|  Running as: root  (full feature access)                                     |
|                                                                              |
+------------------------------------------------------------------------------+
|                                                                              |
|   1   Interface Table                                                        |
|   2   Server Mode   --  start iperf3 listener(s)                             |
|   3   Client Mode   --  generate traffic stream(s)                           |
|   4   Loopback Test --  local server + client validation                     |
|   5   DSCP Reference Table                                                   |
|   6   Exit                                                                   |
|                                                                              |
+==============================================================================+

  Select [1-6]:
```
