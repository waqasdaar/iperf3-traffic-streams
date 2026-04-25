# PRISM — Performance Real-time iPerf3 Stream Manager

> Enterprise-grade multi-stream traffic orchestration with a live QoS dashboard.

[![Version](https://img.shields.io/badge/version-8.3.8-blue.svg)](https://github.com/waqasdaar/prism)
[![Shell](https://img.shields.io/badge/shell-Bash%203.2%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey.svg)](https://github.com/waqasdaar/prism)
[![License](https://img.shields.io/badge/license-MIT-orange.svg)](LICENSE)

---

## Table of Contents

1. [Introduction](#introduction)
2. [How It Works](#how-it-works)
3. [Requirements](#requirements)
4. [Installation](#installation)
5. [Quick Start](#quick-start)
6. [Application Menu](#application-menu)
7. [Implemented Use Cases](#implemented-use-cases)
8. [Dashboard Reference](#dashboard-reference)
9. [DSCP Reference Table](#dscp-reference-table)
10. [Output and Log Files](#output-and-log-files)
11. [Cleanup and Signal Handling](#cleanup-and-signal-handling)
12. [Troubleshooting](#troubleshooting)
13. [Known Limitations](#known-limitations)
14. [Contributing](#contributing)
15. [Author](#author)
16. [License](#license)

---

## Introduction

**PRISM** (Performance Real-time iPerf3 Stream Manager) is a
production-grade Bash wrapper for
[iperf3](https://github.com/esnet/iperf) that transforms
single-stream benchmarking into a comprehensive network testing
platform.

Rather than running one iperf3 process manually, PRISM orchestrates
multiple simultaneous streams across different protocols, QoS classes,
VRFs, and network paths — all while rendering a live terminal dashboard
that shows bandwidth, RTT, TCP congestion window, traffic ramp curves,
and stream health in real time.

### What makes PRISM different

| Capability | Vanilla iperf3 | PRISM |
|---|---|---|
| Simultaneous multi-stream | Manual scripting | Built-in, up to 64 streams |
| Live dashboard | None | Real-time TUI with sparklines |
| DSCP / QoS marking | Single stream | Per-stream with live verification |
| Mixed traffic profiles | None | Percentage-based traffic mix generator |
| TCP CWND tracking | Verbose log only | Live dashboard row + results table |
| Traffic ramp-up | None | Kernel-level `tc tbf` shaping |
| RTT measurement | None | Parallel `ping` per stream |
| VRF-aware routing | None | Full `ip vrf exec` integration |
| Path MTU discovery | None | Binary-search ICMP probe |
| Pre-flight checks | None | Ping + TCP port + traceroute |
| JSON results export | None | Structured per-second time-series |
| Session history | None | JSON Lines audit log |
| FQDN targets | None | 6-method DNS resolution chain |
| Bidirectional test | Manual two processes | Native `--bidir` (iperf3 ≥ 3.7) |
| Network impairment | None | `tc netem` delay / jitter / loss |
| DSCP verification | None | Live tcpdump packet capture overlay |
| Theme support | None | Dark / Light / Mono terminal themes |

---

## How It Works



```
┌──────────────────────────────────────────────────────────────────┐
│                       PRISM Architecture                         │
│                                                                  │
│  ┌──────────────┐    ┌──────────────────────────────────────┐    │
│  │  Operator    │───▶│  Configuration Wizard                │    │
│  │  (terminal)  │    │  Protocol · Target · DSCP · VRF ...  │    │
│  └──────────────┘    └──────────────────────────────────────┘    │
│                                      │                           │
│                          ┌───────────▼──────────┐                │
│                          │   Pre-flight Engine  │                │
│                          │  Ping · TCP · MTU    │                │
│                          │  Traceroute          │                │
│                          └───────────┬──────────┘                │
│                                      │                           │
│          ┌───────────────────────────▼────────────────────┐      │
│          │                Launch Engine                   │      │
│          │  iperf3 clients · ping · bidir · ramp (tc)     │      │
│          └──────┬─────────┬──────────┬────────────────────┘      │
│                 │         │          │                           │
│          ┌──────▼──┐  ┌───▼────┐  ┌──▼──────────┐                │
│          │ iperf3  │  │  ping  │  │  tc tbf     │                │
│          │ streams │  │ (RTT)  │  │  (ramp)     │                │
│          └──────┬──┘  └───┬────┘  └─────────────┘                │
│                 │         │                                      │
│          ┌──────▼─────────▼──────────────────────────────┐       │
│          │              Live TUI Dashboard               │       │
│          │  BW · RTT · CWND · Ramp · Progress · DSCP     │       │
│          └──────────────────────┬────────────────────────┘       │
│                                 │                                │
│          ┌──────────────────────▼────────────────────────┐       │
│          │              Results & Export                 │       │
│          │  Table · JSON · Session History · Logs        │       │
│          └───────────────────────────────────────────────┘       │
└──────────────────────────────────────────────────────────────────┘
```
PRISM operates as a single Bash process that coordinates all child
processes through a signal-safe cleanup system. On each one-second
dashboard tick it:

1. Probes every iperf3 process via `/proc/<pid>/net/tcp` (Linux) or
   `lsof` (macOS) to determine connection state
2. Parses live bandwidth from iperf3 per-interval log output
3. Reads the latest RTT sample from parallel background ping logs
4. Extracts the TCP congestion window from iperf3 verbose output
5. Advances the traffic ramp-up state machine and applies `tc tbf`
6. Redraws the terminal frame using ANSI cursor anchoring (no flicker,
   no scrolling)
7. Appends per-second bandwidth samples to the in-memory JSON ring
   buffer for later export

When all streams finish, PRISM exports a structured JSON results file,
appends a summary record to the per-host session history log, and
prompts whether to retain or delete the export files.

---

## Requirements

### Mandatory

| Dependency | Minimum Version | Purpose |
|---|---|---|
| `bash` | 3.2+ | Runtime (macOS ships Bash 3.2) |
| `iperf3` | 3.1+ | Traffic generation engine |
| `awk` | any | Bandwidth parsing and arithmetic |
| `sed` | any | Log processing and sanitization |

### Optional — enables specific features

| Dependency | Feature Unlocked |
|---|---|
| `iperf3` ≥ 3.7 | `--bidir` simultaneous TX+RX measurement |
| `tc` (iproute2) + **root** | TCP traffic ramp-up via `tc tbf` shaping |
| `ip` (iproute2) | VRF routing, interface discovery, path MTU |
| `ping` | RTT / jitter / loss measurement per stream |
| `tcpdump` + **root** | DSCP marking live packet verification |
| `traceroute` or `tracepath` | Path hop discovery in pre-flight checks |
| `getent` | Primary DNS resolver (Linux glibc) |
| `dig` | Secondary DNS resolver |
| `host` | Tertiary DNS resolver |
| `nslookup` | Quaternary DNS resolver |
| `python3` or `python2` | Fallback DNS resolver via `socket` module |
| `ss` | TCP connection state probing (Linux) |
| `lsof` | TCP/UDP connection state probing (macOS) |
| `tput` | Terminal width auto-detection |
| `ethtool` | NIC speed detection on Linux |
| `jq` | Post-test JSON results analysis (user tool) |

### Platform notes

- **Linux**: Full feature set available. Root or `sudo` required for VRF
  operations, `tc` traffic shaping, and `tcpdump` packet capture.
- **macOS**: Core throughput measurement and dashboard work correctly.
  VRF (`ip vrf exec`), `tc` shaping, and `tc netem` are Linux-only
  features and are gracefully skipped on macOS.

---

## Installation

PRISM is a self-contained Bash script. No compilation, no package
manager, no virtual environment is required.

### Step 1 — Clone the repository

```bash
git clone https://github.com/waqasdaar/prism.git
cd prism
```
### Step 2 — Make the script executable

```bash
chmod +x prism.sh
```
### Step 3 — Verify iperf3 is installed

#### Debian / Ubuntu
```bash
sudo apt install iperf3
```

#### RHEL / CentOS / Rocky Linux / Fedora
```bash
sudo dnf install iperf3
```
#### macOS (Homebrew)
```bash
brew install iperf3
```

### Step 4 — Install the full toolchain (recommended)

Installing the complete set of optional dependencies enables all PRISM features including VRF routing, traffic shaping, DSCP verification, and path discovery.

```bash
# Debian / Ubuntu
sudo apt install \
    iperf3 iproute2 tcpdump traceroute \
    dnsutils python3 ethtool jq

# RHEL / CentOS / Rocky Linux
sudo dnf install \
    iperf3 iproute tcpdump traceroute \
    bind-utils python3 ethtool jq

# macOS (Homebrew)
brew install iperf3 jq
```

### Step 5 — Run PRISM
```bash
# Recommended: run as root for full feature access
sudo ./prism.sh

# Non-root: core features work; VRF, tc, and tcpdump features
# will display [ WARN ] or [ OFF ] in the Capability Matrix
./prism.sh
```

## Quick Start

### Loopback self-test (no remote server needed)

The fastest way to confirm PRISM works on your system. No remote infrastructure required.
```bash
sudo ./prism.sh
```

1. Select **`4`** — Loopback Test
2. Streams: `1`
3. Protocol: `TCP`
4. Duration: `10`
5. Accept all other defaults by pressing Enter

PRISM will start a local iperf3 server on `127.0.0.1:5201`, connect a client, display the live dashboard for 10 seconds, and print the final results table. Expected output:

```
All 1 stream(s) completed successfully.
```

### Basic client test (remote iperf3 server required)

```bash
# On the remote server host:
iperf3 -s -p 5201

# On the PRISM host:
sudo ./prism.sh
```
* Select **`3`** — Client Mode
* Streams: `1`
* Protocol: `TCP`
* Target: `192.168.1.100` _(or an FQDN such as `iperf3.moji.fr`)_
* Port: `5201`
* Bandwidth: _(press Enter for unlimited)_
* Duration: `30`
* Accept all other defaults

## Pre-flight capability check

Every time **PRISM** launches it displays the Capability Matrix showing which features are available on your system:

```
+==============================================================================+
|             PRISM  PRE-FLIGHT CAPABILITY MATRIX                              |
+------------------------------------------------------------------------------+
| Feature                | Status   | Requirement / Note                      |
|------------------------|----------|-----------------------------------------|
| TCP Ramp-Up (TBF)      | [  OK  ] | root + tc (iproute2) confirmed          |
| Bidir Streams          | [  OK  ] | iperf3 v3.16.0 supports --bidir         |
| VRF Orchestration      | [  OK  ] | root + kernel VRF support confirmed     |
| DSCP Verification      | [  OK  ] | root + tcpdump confirmed                |
| TCP CWND Tracking      | [  OK  ] | Standard iperf3 verbose log parsing     |
| Mixed Traffic (MTP)    | [  OK  ] | iperf3 + awk confirmed                  |
| FQDN Resolution        | [  OK  ] | FQDN resolution via getent              |
+==============================================================================+
```

## Application Menu

```
+==============================================================================+
|          PRISM  Performance Real-time iPerf3 Stream Manager  v8.3.8          |
+==============================================================================+
|  User  root  ·  Theme  dark  ·  OS  linux                                   |
+==============================================================================+
|  NETWORK                                                                     |
+------------------------------------------------------------------------------+
|  1  Interface Table      List interfaces, IPs, VRFs and link state           |
|  2  Server Mode          Launch one or more iperf3 listeners                 |
|  3  Client Mode          Generate traffic streams with full QoS control      |
|  4  Loopback Test        Self-contained server + client validation           |
|  5  Mixed Traffic        Generate streams from a traffic mix definition      |
+------------------------------------------------------------------------------+
|  REFERENCE                                                                   |
+------------------------------------------------------------------------------+
|  6  DSCP Reference       DSCP / TOS / EF / AF / CS class mappings           |
|  7  Colour Theme         Dark · Light · Mono  (active: dark)                 |
+------------------------------------------------------------------------------+
|  SESSION                                                                     |
+------------------------------------------------------------------------------+
|  8  Exit                                                                     |
+==============================================================================+
```
Menu options explained

|        Option       |                                                                                                                      Description                                                                                                                      |
|:-------------------:|:-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------:|
| 1 — Interface Table | Displays all network interfaces with their IP address, operational  state, link speed, and VRF membership. Use this to identify the correct  bind interface before running a test.                                                                    |
| 2 — Server Mode     | Configures and launches one or more iperf3 listeners. Each listener  can be bound to a specific IP and VRF. A live server dashboard shows  per-listener bandwidth, connection state, and sparkline. Press c in the dashboard for live packet capture. |
| 3 — Client Mode     | The primary test mode. Configures up to 64 streams, each with  independent protocol, target, bandwidth cap, DSCP marking, DSCP  verification, VRF, bind interface, netem impairment, bidir, CWND  tracking, and ramp profile.                         |
| 4 — Loopback Test   | Automatically launches local iperf3 servers and clients on 127.0.0.1. No remote infrastructure required. Ideal for baseline validation, regression testing, and smoke tests after a system change.                                                    |
| 5 — Mixed Traffic   | Generates a multi-class traffic mix defined by percentage. Choose  from five built-in enterprise presets or define a fully custom mix  interactively. Streams are automatically allocated and launched.                                               |
| 6 — DSCP Reference  | Displays the complete DSCP / TOS mapping table with PHB classes and use cases, without running a test.                                                                                                                                                |
| 7 — Colour Theme    | Switches between Dark, Light, and Mono terminal themes. The selection is persisted to ~/.config/prism/theme and reloaded on next launch. A live colour swatch confirms the change.                                                                    |
| 8 — Exit            | Terminates all active iperf3 and ping processes, removes tc qdiscs,  deletes temporary files, and prompts about JSON export file retention  before exiting.                                                                                           |

## Implemented Use Cases

### Use Case 1 — Basic TCP Throughput Benchmark

**Scenario:** Measure maximum TCP throughput between two hosts on a LAN or WAN link.

```
Menu:       3 — Client Mode
Streams:    1
Protocol:   TCP
Target:     192.168.1.100
Port:       5201
Bandwidth:  (unlimited — press Enter)
Duration:   30
DSCP:       (none — press Enter)
Parallel:   1
Bidir:      No
```

**What you get:**

* Live per-second bandwidth with 10-second sparkline
* RTT (min / avg / max / jitter / loss) from a parallel ping process
* TCP CWND curve showing congestion window growth over time
* Final sender and receiver bandwidth summary
* JSON export file with per-second bandwidth samples

### Use Case 2 — VoIP / RTP Quality Simulation (UDP EF)

**Scenario:** Simulate a G.711 VoIP RTP stream and verify that the DSCP EF marking is preserved end-to-end through the network.

```
Menu:       3 — Client Mode
Streams:    1
Protocol:   UDP
Target:     10.0.0.1
Port:       5004
Bandwidth:  1M
Duration:   60
DSCP:       EF
```
After the stream starts, press **`v`** in the dashboard to open the DSCP verification overlay. PRISM captures 50 packets via tcpdump and confirms that the IP TOS byte is `0xb8` (DSCP 46 × 4 = 184 = 0xb8):

```
+==============================================================================+
|              DSCP Marking Verification — Stream 1                            |
+------------------------------------------------------------------------------+
| Pkt  Source IP:Port          Destination IP:Port     TOS     Got  Exp  Result|
|------|----------------------|----------------------|--------|-----|----|----- |
|  1   10.0.0.2:54321         10.0.0.1:5004          0xb8     46   46  PASS   |
|  2   10.0.0.2:54321         10.0.0.1:5004          0xb8     46   46  PASS   |
+------------------------------------------------------------------------------+
|  Summary:  50 packets  |  50 PASS  |  0 FAIL                                 |
|  Verdict:  PASS — DSCP marking verified correct on stream 1                  |
+==============================================================================+
```
### Use Case 3 — Multi-Stream QoS Differentiation

**Scenario:** Simultaneously send traffic across four QoS classes to verify that a QoS policy correctly prioritises real-time traffic over bulk data under congestion.
```
Menu:     3 — Client Mode
Streams:  4

Stream 1:  UDP · EF   · 1M    · "VoIP voice"
Stream 2:  UDP · AF41 · 4M    · "Video conferencing"
Stream 3:  TCP · AF21 · 0     · "Business data (unlimited)"
Stream 4:  TCP · CS1  · 0     · "Background backup (unlimited)"
```
The live dashboard displays all four streams simultaneously with individual bandwidth readings, sparklines, RTT rows, CWND rows (for TCP streams), and DSCP labels. The final results table shows sender and receiver bandwidth for each class side by side.
