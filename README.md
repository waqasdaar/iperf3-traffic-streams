# PRISM — Performance Real-time iPerf3 Stream Manager

> Enterprise-grade multi-stream traffic orchestration with a live QoS dashboard.

[![Version](https://img.shields.io/badge/version-8.3.9-blue.svg)](https://github.com/waqasdaar/prism)
[![Shell](https://img.shields.io/badge/shell-Bash%203.2%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey.svg)](https://github.com/waqasdaar/prism)
[![License](https://img.shields.io/badge/license-MIT-orange.svg)](LICENSE)

---

# Table of contents

- [Introduction](#introduction)
  - [What makes PRISM different](#what-makes-prism-different)
- [How It Works](#how-it-works)
- [Requirements](#requirements)
  - [Mandatory](#mandatory)
  - [Optional — enables specific features](#optional--enables-specific-features)
  - [Platform notes](#platform-notes)
- [Installation](#installation)
  - [Step 1 — Clone the repository](#step-1--clone-the-repository)
  - [Step 2 — Make the script executable](#step-2--make-the-script-executable)
  - [Step 3 — Verify iperf3 is installed](#step-3--verify-iperf3-is-installed)
    - [Debian / Ubuntu](#debian--ubuntu)
    - [RHEL / CentOS / Rocky Linux / Fedora](#rhel--centos--rocky-linux--fedora)
    - [macOS (Homebrew)](#macos-homebrew)
  - [Step 4 — Install the full toolchain (recommended)](#step-4--install-the-full-toolchain-recommended)
  - [Step 5 — Run PRISM](#step-5--run-prism)
- [Quick Start](#quick-start)
  - [Loopback self-test (no remote server needed)](#loopback-self-test-no-remote-server-needed)
  - [Basic client test (remote iperf3 server required)](#basic-client-test-remote-iperf3-server-required)
- [Pre-flight capability check](#pre-flight-capability-check)
- [Application Menu](#application-menu)
- [Implemented Use Cases](#implemented-use-cases)
  - [Use Case 1 — Basic TCP Throughput Benchmark](#use-case-1--basic-tcp-throughput-benchmark)
  - [Use Case 2 — VoIP / RTP Quality Simulation (UDP EF)](#use-case-2--voip--rtp-quality-simulation-udp-ef)
  - [Use Case 3 — Multi-Stream QoS Differentiation](#use-case-3--multi-stream-qos-differentiation)
  - [Use Case 4 — Enterprise WAN Mix with Mixed Traffic Generator](#use-case-4--enterprise-wan-mix-with-mixed-traffic-generator)
  - [Use Case 5 — TCP Traffic Ramp-Up Profile](#use-case-5--tcp-traffic-ramp-up-profile)
  - [Use Case 6 — Bidirectional Simultaneous Test](#use-case-6--bidirectional-simultaneous-test)
  - [Use Case 7 — Path MTU Discovery Before a Test](#use-case-7--path-mtu-discovery-before-a-test)
  - [Use Case 8 — FQDN Target with Automatic DNS Resolution](#use-case-8--fqdn-target-with-automatic-dns-resolution)
  - [Use Case 9 — Network Impairment Simulation (tc netem)](#use-case-9--network-impairment-simulation-tc-netem)
  - [Use Case 10 — VRF-Aware Multi-Tenant Testing](#use-case-10--vrf-aware-multi-tenant-testing)
  - [Use Case 11 — Server Mode with Live Dashboard](#use-case-11--server-mode-with-live-dashboard)
  - [Use Case 12 — Session Naming and Audit Trail](#use-case-12--session-naming-and-audit-trail)
- [Dashboard Reference](#dashboard-reference)
  - [Full annotated layout](#full-annotated-layout)
    - [Column reference](#column-reference)
    - [Stream lifecycle states](#stream-lifecycle-states)
    - [Sub-rows (per stream, conditionally displayed)](#sub-rows-per-stream-conditionally-displayed)
    - [Sparkline character map](#sparkline-character-map)
  - [Keyboard shortcuts during the dashboard](#keyboard-shortcuts-during-the-dashboard)
  - [Completed and failed stream panels](#completed-and-failed-stream-panels)
- [DSCP Reference Table](#dscp-reference-table)
- [Output and Log Files](#output-and-log-files)
  - [Temporary stream logs](#temporary-stream-logs)
  - [JSON results export](#json-results-export)
    - [Analysing results with jq](#analysing-results-with-jq)
  - [Session history log](#session-history-log)
  - [Colour theme preference](#colour-theme-preference)
  - [Event log (runtime only)](#event-log-runtime-only)
- [Cleanup and Signal Handling](#cleanup-and-signal-handling)
  - [Signal map](#signal-map)
  - [Why Ctrl+Z is blocked](#why-ctrlz-is-blocked)
  - [Two-phase stream cleanup](#two-phase-stream-cleanup)
  - [Cleanup output example](#cleanup-output-example)
  - [JSON export cleanup prompt](#json-export-cleanup-prompt)
- [Troubleshooting](#troubleshooting)
  - [iperf3 not found](#iperf3-not-found)
  - [Stream fails immediately — Connection refused](#stream-fails-immediately--connection-refused)
  - [Stream fails — Bad file descriptor (VRF mismatch)](#stream-fails--bad-file-descriptor-vrf-mismatch)
  - [tc shaping not applied — ramp-up silently skipped](#tc-shaping-not-applied--ramp-up-silently-skipped)
  - [DSCP verification returns "No packets captured"](#dscp-verification-returns-no-packets-captured)
  - [DNS resolution fails for FQDN targets](#dns-resolution-fails-for-fqdn-targets)
  - [Bidir test fails with "parameter error"](#bidir-test-fails-with-parameter-error)
  - [Dashboard drifts or content overlaps after terminal resize](#dashboard-drifts-or-content-overlaps-after-terminal-resize)
  - [Path MTU shows UNKNOWN for all targets](#path-mtu-shows-unknown-for-all-targets)
  - [JSON export file not created](#json-export-file-not-created)
  - [Session history not written](#session-history-not-written)
- [Known Limitations](#known-limitations)
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

<br><br>
<img width="1672" height="941" alt="PRISM-UseCases" src="https://github.com/user-attachments/assets/a83f9057-cf3f-4902-b71b-c51ad1d686d1" />

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

### Use Case 4 — Enterprise WAN Mix with Mixed Traffic Generator

**Scenario:** Simulate a realistic enterprise WAN traffic profile to capacity-plan a new MPLS circuit before cutover.

```
Menu:    5 — Mixed Traffic
Preset:  1 — Enterprise WAN
         → 70% TCP Bulk (AF11)
         → 20% UDP Voice/RTP (EF)
         → 10% UDP Low-priority (CS1)

Total streams: 10
Target:        10.1.1.1
Duration:      120
Port mode:     Auto sequential (from 5201)
```

**PRISM** automatically allocates 7 TCP bulk streams, 2 UDP voice streams, and 1 UDP low-priority stream using the largest-remainder method, assigns ports sequentially from 5201, and launches all 10 streams simultaneously. The mixed traffic dashboard shows every stream with its class label, protocol, DSCP, and live bandwidth.

**Built-in presets**

| # |     Preset     |                            Mix Definition                            |
|:-:|:--------------:|:--------------------------------------------------------------------:|
| 1 | Enterprise WAN | 70% TCP Bulk (AF11) · 20% UDP RTP (EF) · 10% UDP Low (CS1)           |
| 2 | Data Centre    | 60% TCP Bulk (AF21) · 30% TCP iSCSI (AF31) · 10% UDP Mgmt (CS2)      |
| 3 | Unified Comms  | 50% UDP Voice (EF) · 30% UDP Video (AF41) · 20% TCP Signalling (CS3) |
| 4 | Bulk Transfer  | 80% TCP Bulk (AF11) · 20% TCP Background (CS1)                       |
| 5 | Multimedia CDN | 65% TCP HTTPS (AF31) · 25% UDP Stream (AF41) · 10% UDP Low (CS1)     |
| 6 | Custom Mix     | Define your own percentages and classes interactively                |

**Port allocation modes**

|       Mode       |                              Description                             |
|:----------------:|:--------------------------------------------------------------------:|
| Auto Sequential  | One base port; each class increments automatically. No manual entry. |
| Custom Per-Class | Specify a different base port for each traffic class.                |
| Single Port All  | All streams across all classes share one port.                       |

### Use Case 5 — TCP Traffic Ramp-Up Profile

**Scenario:** Simulate a CDN origin gradually increasing throughput to avoid TCP incast on a shared uplink, and observe the congestion window growth curve.

```
Menu:          3 — Client Mode
Streams:       1
Protocol:      TCP
Target:        203.0.113.50
Bandwidth:     500M
Duration:      120
Ramp-up:       Yes
  Ramp-up:     20s
  Ramp-down:   10s
```
PRISM installs a `tc tbf` token bucket filter on the resolved egress interface, linearly increases the shaped rate from a floor of 8 Kbps to 500 Mbps over 20 seconds, holds at full rate for the test body, then ramps down over 10 seconds. The live dashboard shows the real-time ramp curve using Unicode block characters and the active phase:

```
ramp ▁▁▂▃▄▅▆▇████████████████████████▇▅▃  ↑ HOLD    cur 498M  tgt 500M
```
The results table displays a frozen snapshot of the complete ramp timeline alongside the final bandwidth summary.

### Use Case 6 — Bidirectional Simultaneous Test

**Scenario:** Measure full-duplex performance on a 10 Gbps link to confirm there is no TX/RX asymmetry or hardware contention.

```
Menu:       3 — Client Mode
Streams:    1
Protocol:   TCP
Target:     10.10.0.1
Port:       5201
Duration:   60
Bidir:      Yes
```

Requires **iperf3 ≥ 3.7** on both client and server. PRISM adds `--bidir` to the iperf3 command and displays dedicated TX and RX rows in the dashboard:

```
1  TCP  ──────────────   5201   9.41 Gbps   ▃▅▇██████   00:42  EF  CONNECTED
         ↳ 10.10.0.1
→ TX ─────────────────────────────────────────────────────────────────────────
← RX     9.38 Gbps   ▃▅▇██████                                    CONNECTED
    RTT  min  0.210ms  avg  0.234ms  max  0.312ms  jitter  0.021ms  loss  0%
    cwnd  cur  8192.0KB  min  4096.0KB  max  8192.0KB  avg  7654.3KB
```

### Use Case 7 — Path MTU Discovery Before a Test

**Scenario:** Identify fragmentation or MTU black holes before running a high-throughput test across a GRE or MPLS tunnel.

**PRISM** automatically runs path MTU discovery as part of the pre-flight sequence using an ICMP binary-search probe with the DF bit set:

```
+==============================================================================+
|                      Path MTU Discovery Results                              |
+------------------------------------------------------------------------------+
| Target           | VRF      | Iface MTU  | Path MTU   | Rec MSS  | Status   |
|------------------|----------|------------|------------|----------|----------|
| 10.1.1.1         | GRT      | 1500 B     | 1450 B     | 1410 B   | FRAG WARN|
+==============================================================================+
  ⚠  FRAGMENTATION RISK: Path MTU is 1450 bytes
     Common causes: MPLS label (+4-20 B), GRE tunnel (+24 B), IPsec ESP
     Recommended MSS: 1410 bytes  (configure with iperf3 -M 1410)
```

If critical fragmentation is detected, PRISM prompts before proceeding and recommends the MSS value to pass to iperf3 with `-M`.

### Use Case 8 — FQDN Target with Automatic DNS Resolution

**Scenario:** Test against a public iperf3 server using its hostname.

```
Menu:    3 — Client Mode
Target:  iperf3.moji.fr
```

**PRISM** resolves the FQDN through a 6-method fallback chain and confirms the resolved IP before connecting:

```
Resolving iperf3.moji.fr... ✓ 163.172.189.215
  → Target set: iperf3.moji.fr (163.172.189.215)
```

The dashboard renders a dedicated second line for the full FQDN to prevent truncation in the fixed-width target column:

```
1  TCP  ──────────────   5200   94.40 Mbps   ▅▆▇████   00:28  EF  CONNECTED
         ↳ iperf3.moji.fr (163.172.189.215)
```
**DNS resolution chain**

PRISM tries each resolver in order, stopping at the first success:

| Priority |              Tool              |                       Notes                      |
|:--------:|:------------------------------:|:------------------------------------------------:|
| 1        | getent hosts                   | glibc resolver; respects /etc/hosts and nsswitch |
| 2        | dig +short A                   | Precise; returns only A records                  |
| 3        | host -t A                      | Available on Linux and macOS                     |
| 4        | nslookup                       | Legacy; available almost everywhere              |
| 5        | python3 socket.gethostbyname() | Uses system resolver stack                       |
| 6        | python2 socket.gethostbyname() | Older system fallback                            |

### Use Case 9 — Network Impairment Simulation (tc netem)

**Scenario:** Reproduce WAN conditions (100 ms RTT, 10 ms jitter, 0.5% packet loss) on a lab host to test application resilience before production deployment.

```
Menu:      3 — Client Mode
Protocol:  TCP
Target:    10.0.0.1
Duration:  60
Delay:     100  ms
Jitter:    10   ms
Loss:      0.5  %
```

PRISM applies `tc netem` to the correct egress interface via a VRF-aware route lookup and displays a before/after comparison table:

```
+==============================================================================+
|              tc netem Applied — Stream 1                                     |
+------------------------------------------------------------------------------+
|  Interface : eth0  (routing via GRT)                                         |
|  Stream    : 1  TCP → 10.0.0.1:5201                                          |
+------------------------------------------------------------------------------+
|  Parameter     | Before     | After      | Change    |
|----------------|------------|------------|-----------|
|  Delay         | 0ms        | 100ms      | added     |
|  Jitter        | 0ms        | 10ms       | added     |
|  Packet Loss   | 0%         | 0.5%       | added     |
+==============================================================================+
```
Netem is automatically removed when the stream finishes via the per-stream cleanup handler.

### Use Case 10 — VRF-Aware Multi-Tenant Testing

**Scenario:** Run simultaneous iperf3 streams across two separate VRFs on an SD-WAN or multi-tenant router, verifying traffic isolation.

```
Menu:     3 — Client Mode
Streams:  2

Stream 1:
  Target:   10.1.1.1
  VRF:      tenant-a
  Bind IP:  10.1.0.1  (interface in tenant-a)
  DSCP:     AF21

Stream 2:
  Target:   10.2.1.1
  VRF:      tenant-b
  Bind IP:  10.2.0.1  (interface in tenant-b)
  DSCP:     CS1
```
**PRISM** validates that each bind IP belongs to the specified VRF before launch, auto-corrects mismatches, and executes each iperf3 process inside the correct VRF namespace via `ip vrf exec`. Both streams appear simultaneously in the live dashboard with independent bandwidth readings.

### Use Case 11 — Server Mode with Live Dashboard

**Scenario:** Run PRISM as a persistent multi-listener server, accepting connections from multiple remote clients simultaneously.

```
Menu:        2 — Server Mode
Listeners:   2

Listener 1:  port 5201, bind 0.0.0.0, VRF: GRT
Listener 2:  port 5202, bind 10.5.0.1, VRF: prod-vrf
```

The live server dashboard shows each listener's lifecycle state and live bandwidth:

```
+==============================================================================+
|                      PRISM — Server Dashboard                                |
+==============================================================================+
|  Listeners active: 1 / 2                                                    |
+==============================================================================+
|  #   Port   Bind IP            VRF       Bandwidth      Last 10s    Status  |
+------------------------------------------------------------------------------+
|  1   5201   0.0.0.0            GRT       940.12 Mbps    ▅▆▇████████ CONNECTED|
+------------------------------------------------------------------------------+
|  2   5202   10.5.0.1           prod-vrf  ---            ··········  LISTENING|
+==============================================================================+
|  Ctrl+C to stop all listeners  |  [c] Packet capture                        |
+==============================================================================+
```

Press **`c`** in the server dashboard to open the DSCP capture overlay for any active listener.

### Use Case 12 — Session Naming and Audit Trail

**Scenario:** Run a series of before/after change tests and maintain a traceable audit log for change management records.

Before each test run, PRISM presents the session naming panel:

```
+==============================================================================+
|        Test Session Naming  (optional — press Enter to skip each field)      |
+==============================================================================+
|  Session ID:  20260425-143022-a3f1                                           |
+------------------------------------------------------------------------------+

  Session Name
  Examples: baseline-Q1  post-firewall-change  WAN-link-test-2026

  Name [20260425-143022-a3f1]: wan-baseline-Q2
  ✓ Name set to: wan-baseline-Q2

  Tags [none]: pre-change production wan
  ✓ Tags set: [pre-change] [production] [wan]

  Note [none]: Before firewall policy update ticket CHG-4821
  ✓ Note set.
```

The session record is appended to `~/.config/prism/session_history.json` in JSON Lines format and embedded in the per-test JSON export file. Use `jq` to query test history:

```
# Find all tests tagged "production"
grep '"production"' ~/.config/prism/session_history.json | jq '.name,.results'

# Compare sender bandwidth across baseline and post-change runs
jq 'select(.name | startswith("wan-baseline")) | .results[].sender_bw' \
    ~/.config/prism/session_history.json
```

## Dashboard Reference

The live client dashboard is redrawn once per second using ANSI cursor anchoring (`\033[s` save / `\033[u` restore). It never scrolls — it overwrites in place to eliminate flicker.

### Full annotated layout

```
+==============================================================================+
|                        PRISM — Live Dashboard                                |
+==============================================================================+
|  Active: 2   Connected: 2   Done: 0   Failed: 0   Elapsed: 00:14            |
+==============================================================================+
| #  Proto  Target           Port   Bandwidth     Last 10s    Time  DSCP Status|
+------------------------------------------------------------------------------+
 1  TCP    ──────────────   5201   940.12 Mbps   ▅▆▇████▇▆   00:46   EF  CONNECTED
           ↳ iperf3.moji.fr (163.172.189.215)
   RTT  min   1.100ms  avg   1.234ms  max   2.100ms  jitter  0.123ms  loss  0%  (46 smpl)
   cwnd  cur  128.0KB  min   90.5KB  max  132.0KB  avg  115.3KB
   ramp ▁▂▃▄▅▆▇████████████████████▇▅▃  ↑ HOLD       cur  940M  tgt  1G
   [████████████████░░░░░░░░░░░░░░░░] 62%
+------------------------------------------------------------------------------+
 2  UDP    10.0.0.2          5004   999.87 Kbps   ▆▇████▇▆▅   00:46  AF41 CONNECTED
← RX       998.21 Kbps   ▆▇████▇▆▅                                  CONNECTED
   RTT  min   0.800ms  avg   0.923ms  max   1.100ms  jitter  0.045ms  loss  0%  (46 smpl)
+==============================================================================+
|  Ctrl+C to stop all streams  |  [v/p] DSCP verify                           |
+==============================================================================+
```

#### Column reference

| **Column** |                       **Description**                       |
|:----------:|:-----------------------------------------------------------:|
| #          | Stream number (1-based)                                     |
| Proto      | TCP or UDP                                                  |
| Target     | Destination IP. FQDN targets appear on a dedicated ↳ line   |
| Port       | Destination port number                                     |
| Bandwidth  | Current per-interval bandwidth (updated every second)       |
| Last 10s   | 10-second bandwidth sparkline (Unicode blocks ▁▂▃▄▅▆▇█)     |
| Time       | Countdown to stream end; inf for unlimited duration streams |
| DSCP       | Configured DSCP class name (e.g. EF, AF41, CS1)             |

#### Stream lifecycle states

|  **State** | **Colour** |                 **Meaning**                 |
|:----------:|:----------:|:-------------------------------------------:|
| STARTING   | Yellow     | iperf3 process launched, no log output yet  |
| CONNECTING | Yellow     | Process alive, TCP handshake in progress    |
| CONNECTED  | Green      | Active data transfer confirmed              |
| DONE       | Cyan       | Stream completed normally                   |
| FAILED     | Red        | Connection refused, timeout, or DNS failure |
| CLEANING…  | Yellow     | Post-completion process teardown running    |
| ── DONE ── | Dim        | Cleanup complete, permanent tombstone row   |

#### Sub-rows (per stream, conditionally displayed)

|  **Sub-row** |     **Display Condition**     |                   **Content**                  |
|:------------:|:-----------------------------:|:----------------------------------------------:|
| ↳ FQDN (IP)  | FQDN target or IP > 15 chars  | Full resolved hostname and IP                  |
| → TX label   | Bidir enabled                 | Labels the TX direction row                    |
| ← RX row     | Bidir enabled                 | Reverse direction bandwidth and sparkline      |
| RTT row      | Non-loopback stream           | min / avg / max / jitter / loss / sample count |
| cwnd row     | TCP, non-loopback, ≥ 1 sample | cur / min / max / avg in KBytes                |
| ramp row     | Ramp profile enabled          | Timeline curve, phase name, cur/tgt rate       |
| Progress bar | Fixed duration, not failed    | Unicode fill bar with percentage               |

#### Sparkline character map

The 10-second sparkline encodes relative bandwidth using Unicode block characters that fill each cell from the bottom up:

| **Character** | **Unicode** | **Level** |             **Meaning**            |
|:-------------:|:-----------:|:---------:|:----------------------------------:|
| ·             | U+00B7      | 0         | No data / buffer empty             |
| ▁             | U+2581      | 1         | Very low (≤ 12.5% of window range) |
| ▂             | U+2582      | 2         | Low                                |
| ▃             | U+2583      | 3         | Below mid                          |
| ▄             | U+2584      | 4         | Mid (stable traffic flat-line)     |
| ▅             | U+2585      | 5         | Above mid                          |
| ▆             | U+2586      | 6         | High                               |
| ▇             | U+2587      | 7         | Very high                          |
| █             | U+2588      | 8         | Maximum for this window            |

The sparkline uses dynamic range normalisation: the full height always reflects the min-to-max range of the 10-second window, making even small fluctuations visible.

### Keyboard shortcuts during the dashboard

| **Key** |        **Mode**       |                **Action**               |
|:-------:|:---------------------:|:---------------------------------------:|
| v or p  | Client (non-loopback) | Open DSCP marking verification overlay  |
| c       | Server                | Open server-side packet capture overlay |
| Ctrl+C  | Both                  | Stop all streams and exit cleanly       |
| Ctrl+Z  | Both                  | Blocked — would orphan iperf3 processes |

### Completed and failed stream panels

When streams finish, PRISM renders additional panels below the main dashboard frame:

**Completed Streams panel** — appears as streams reach `DONE` state, showing final sender and receiver bandwidth for each stream.

**Failed Streams panel** — appears if any stream reaches `FAILED` state, showing the error message (e.g. "Connection refused", "No route to host").

## DSCP Reference Table

**PRISM** uses DSCP (Differentiated Services Code Point) values to mark traffic for QoS treatment. At the DSCP prompt, enter the name (e.g. `EF`), a decimal value (0–63), or press Enter for no marking.

```
TOS byte = DSCP value × 4
```

| **DSCP Name** | **Value** | **TOS (dec)** | **TOS (hex)** |  **PHB Class**  |        **Typical Use Case**       |
|:-------------:|:---------:|:-------------:|:-------------:|:---------------:|:---------------------------------:|
| Default / CS0 | 0         | 0             | 0x00          | Best Effort     | Default internet traffic          |
| CS1           | 8         | 32            | 0x20          | Scavenger       | Low-priority bulk, backup         |
| AF11          | 10        | 40            | 0x28          | AF Class 1      | Low data, low drop probability    |
| AF12          | 12        | 48            | 0x30          | AF Class 1      | Low data, medium drop             |
| AF13          | 14        | 56            | 0x38          | AF Class 1      | Low data, high drop               |
| CS2           | 16        | 64            | 0x40          | OAM             | Network management, SNMP          |
| AF21          | 18        | 72            | 0x48          | AF Class 2      | High-throughput data, low drop    |
| AF22          | 20        | 80            | 0x50          | AF Class 2      | High-throughput data, medium drop |
| AF23          | 22        | 88            | 0x58          | AF Class 2      | High-throughput data, high drop   |
| CS3           | 24        | 96            | 0x60          | Broadcast Video | Signalling, broadcast video       |
| AF31          | 26        | 104           | 0x68          | AF Class 3      | Multimedia streaming, low drop    |
| AF32          | 28        | 112           | 0x70          | AF Class 3      | Multimedia streaming, medium drop |
| AF33          | 30        | 120           | 0x78          | AF Class 3      | Multimedia streaming, high drop   |
| CS4           | 32        | 128           | 0x80          | Real-time       | Real-time interactive             |
| AF41          | 34        | 136           | 0x88          | AF Class 4      | Video conferencing, low drop      |
| AF42          | 36        | 144           | 0x90          | AF Class 4      | Video conferencing, medium drop   |
| AF43          | 38        | 152           | 0x98          | AF Class 4      | Video conferencing, high drop     |
| CS5           | 40        | 160           | 0xa0          | Signalling      | SIP call control                  |
| VA            | 44        | 176           | 0xb0          | Voice Admit     | CAC-admitted voice                |
| EF            | 46        | 184           | 0xb8          | Expedited       | VoIP, low-latency voice           |
| CS6           | 48        | 192           | 0xc0          | Network Control | BGP, OSPF, IS-IS                  |
| CS7           | 56        | 224           | 0xe0          | Reserved        | Network critical, reserved        |

## Output and Log Files

### Temporary stream logs

During a test, PRISM writes all iperf3 and ping output to a temporary directory created at startup:

```
/tmp/iperf3_streams.XXXXXX/
├── stream_1.log       # iperf3 client stdout/stderr for stream 1
├── stream_1.sh        # Generated iperf3 launch script for stream 1
├── stream_2.log       # iperf3 client stdout/stderr for stream 2
├── stream_2.sh        # Generated iperf3 launch script for stream 2
├── rtt_0.log          # Continuous ping output for stream 1 (0-based index)
├── rtt_1.log          # Continuous ping output for stream 2
├── bidir_1.log        # Reverse process log (legacy bidir, iperf3 < 3.7 only)
├── server_1.log       # iperf3 server output (Server Mode / Loopback Mode)
└── dscp_cap_0_*.txt   # Temporary tcpdump capture (deleted immediately)
```

All files in the temporary directory are deleted by Phase 2 cleanup after the results table is displayed. The directory itself is then removed.

### JSON results export

After each named-session test, PRISM writes a structured JSON file to the same directory as `prism.sh` (or the current working directory as fallback):

```
./prism_20260425-143022-a3f1.json
```
**Complete schema**

```
{
  "schema_version": "1.0",
  "session": {
    "id":           "20260425-143022-a3f1",
    "name":         "wan-baseline-Q2",
    "tags":         ["pre-change", "wan", "production"],
    "note":         "Before firewall policy update",
    "started":      1745000000,
    "finished":     1745000120,
    "duration_sec": 120,
    "host":         "emea-edge-madrid",
    "user":         "root",
    "os":           "Linux 5.15.0-101-generic",
    "iperf3":       "3.16.0",
    "iperf3_bin":   "/usr/bin/iperf3",
    "mode":         "client"
  },
  "streams": [
    {
      "stream":        1,
      "proto":         "TCP",
      "target":        "10.0.0.1",
      "port":          5201,
      "bandwidth":     "unlimited",
      "duration_sec":  60,
      "dscp_name":     "EF",
      "dscp_val":      46,
      "parallel":      1,
      "bidir":         false,
      "reverse":       false,
      "bind_ip":       "10.0.0.2",
      "vrf":           "",
      "ramp_enabled":  false,
      "status":        "DONE",
      "summary": {
        "sender_bw":      "940.12 Mbps",
        "receiver_bw":    "938.50 Mbps",
        "retransmits":    "0",
        "jitter_ms":      "",
        "loss_pct":       "",
        "rtt_min_ms":     "1.100",
        "rtt_avg_ms":     "1.234",
        "rtt_max_ms":     "1.890",
        "rtt_jitter_ms":  "0.123",
        "rtt_loss_pct":   "0%",
        "rtt_samples":    60,
        "cwnd_min_kb":    "90.1",
        "cwnd_max_kb":    "128.0",
        "cwnd_avg_kb":    "110.5",
        "cwnd_final_kb":  "125.0"
      },
      "samples": [
        {"t": 1745000001, "bps": 985400320},
        {"t": 1745000002, "bps": 987234560},
        {"t": 1745000003, "bps": 990123456}
      ]
    }
  ]
}
```

#### Analysing results with jq

```
# Show session metadata and all stream summaries
jq '.session, .streams[].summary' prism_20260425-143022-a3f1.json

# Extract per-second bandwidth time-series for stream 1
jq '.streams[0].samples' prism_20260425-143022-a3f1.json

# List sender bandwidth for every stream
jq '.streams[] | {stream, sender_bw: .summary.sender_bw}' \
    prism_20260425-143022-a3f1.json

# Calculate average bps from samples using jq arithmetic
jq '[.streams[0].samples[].bps] | add / length' \
    prism_20260425-143022-a3f1.json

# Find sessions tagged "production" in the history log
grep '"production"' ~/.config/prism/session_history.json | jq .

# Get all sessions where any stream failed
jq 'select(.results[].status == "FAILED")' \
    ~/.config/prism/session_history.json

# Compare sender BW across two named sessions
jq 'select(.name | test("wan-baseline")) | {name, results: [.results[].sender_bw]}' \
    ~/.config/prism/session_history.json
```

### Session history log

Every completed test with a named session is appended as a single-line JSON record to:

```
~/.config/prism/session_history.json
```

This file uses **JSON Lines format** — one complete JSON object per line. It is directly consumable by `jq`, Python `json.loads()`, and any log aggregation or SIEM tool without requiring a JSON array wrapper.

### Colour theme preference
```
~/.config/prism/theme
```
Contains one word: `dark`, `light`, or `mono`. Written when a theme is selected in the Theme menu. Auto-detected from `COLORFGBG` on first run if no saved preference exists.

### Event log (runtime only)

```
/tmp/iperf3_streams_events.log
```
During a running test, per-stream process cleanup events are written here (since stdout belongs to the dashboard). The file is read and printed to the terminal after the dashboard exits, then deleted.

## Cleanup and Signal Handling

PRISM registers handlers for all common termination signals so that iperf3 processes, ping processes, and tc qdiscs are always cleaned up — even when the operator interrupts the test.

### Signal map
|  **Signal** |   **Trigger**   |              **PRISM Response**             |
|:-----------:|:---------------:|:-------------------------------------------:|
| SIGINT      | Ctrl+C          | Graceful stop: SIGTERM → 3 s wait → SIGKILL |
| SIGTERM     | kill <pid>      | Same as SIGINT                              |
| SIGQUIT     | Ctrl+\          | Same as SIGINT                              |
| SIGHUP      | Terminal closed | Same as SIGINT                              |
| SIGTSTP     | Ctrl+Z          | Blocked — message printed, no background    |
| EXIT (trap) | Normal exit     | Runs full cleanup if not already done       |

### Why Ctrl+Z is blocked

Sending **PRISM** to the background would leave iperf3 child processes, ping processes, and `tc tbf` qdiscs running unmanaged. The `SIGTSTP` trap intercepts `Ctrl+Z` and prints a warning instead of suspending. Use `Ctrl+C` to stop cleanly.

### Two-phase stream cleanup

**PRISM** uses a non-blocking two-phase cleanup design so the dashboard remains responsive while streams are being torn down:

| **Phase** |            **When**           |                                                                         **Actions**                                                                        |
|:---------:|:-----------------------------:|:----------------------------------------------------------------------------------------------------------------------------------------------------------:|
| Phase A   | Stream reaches DONE or FAILED | Set state to CLEANUP_PENDING, show "CLEANING…" in dashboard                                                                                                |
| Phase B   | Next dashboard tick           | Kill iperf3 PID → kill ping PID → kill bidir PID → remove netem →  remove tc tbf → clear sparkline buffers → capture ramp snapshot → set  state to CLEANED |

**Phase 2** (file deletion) runs after `display_results_table()` completes, ensuring log files are available for final bandwidth parsing.

### Cleanup output example

```
+======================================================================+
  PRISM — Cleanup  [signal: SIGINT (Ctrl+C)]
+======================================================================+

  Client Streams:
    [STOP  ]  PID 12345  stream 1 [TCP->10.0.0.1:5201]
    [DONE  ]  PID 12346  stream 2 [UDP->10.0.0.1:5004]  (already exited)

  RTT Ping Processes:
    [STOP  ]  PID 12347  rtt-ping stream 1

  Temporary Files:
    [DEL]  /tmp/iperf3_streams.Ab3xY9/stream_1.log  (48291 bytes)
    [REMOVED]  /tmp/iperf3_streams.Ab3xY9

  Processes stopped : 1
  Already exited    : 1
  Cleanup complete. All resources released.
+======================================================================+
```

### JSON export cleanup prompt

On exit, if JSON export files were created during the session, PRISM prompts:
```
+======================================================================+
  JSON Export Files — Cleanup
+======================================================================+

  The following JSON results file(s) were created this session:

    /opt/prism/prism_20260425-143022-a3f1.json  (18432 bytes)

  Delete these JSON file(s)?
    Y  Delete all listed files
    N  Keep all files  (default — press Enter)

  Choice [N]:
```
The default is always **keep** (`N`) to prevent accidental data loss.

## Troubleshooting
### iperf3 not found
```
PRISM ERROR: iperf3 not found.
Install: apt install iperf3 | yum install iperf3
```
**Fix:** Install iperf3 for your distribution. For the latest version download a static binary from the [iperf3 releases page](https://github.com/esnet/iperf/releases).

### Stream fails immediately — Connection refused
```
FAILED: Connection refused — is iperf3 server on 10.0.0.1:5201?
```
**Fix:** Ensure iperf3 is running on the remote host and the port matches:
```
# On the remote server:
iperf3 -s -p 5201

# Verify it is listening:
ss -tlnp | grep 5201
```
Check that any firewall on the server host allows inbound TCP/UDP on the configured port.

### Stream fails — Bad file descriptor (VRF mismatch)

```
FAILED: Bad file descriptor — VRF/bind IP mismatch or iperf3 server not reachable
```

**Cause:** The bind IP belongs to a GRT interface but a VRF was configured, or the bind IP belongs to a different VRF than specified.

**Fix:** PRISM auto-corrects this during the pre-launch validation pass and will print a `[PRE-LAUNCH FIX]` message. To diagnose manually:

```
# Identify which VRF owns a bind IP
ip -4 addr show | grep <bind-ip>

# Verify routing from within a VRF
ip route get vrf <vrf-name> <target-ip>
```
### tc shaping not applied — ramp-up silently skipped

**Cause:** `tc tbf` requires root privileges and a non-loopback interface.

**Fix:** Run PRISM as root:
```
sudo ./prism.sh
```
Verify `tc` is installed and the capability matrix shows `[ OK ]` for TCP Ramp-Up

```
which tc || sudo apt install iproute2
```

Loopback targets (`127.x.x.x`) cannot be shaped — use a real network interface for ramp-up tests.

### DSCP verification returns "No packets captured"

**Possible causes and fixes:**

1. **Stream not yet sending data:** Wait until the stream shows `CONNECTED` before pressing `v`.

2. **Insufficient privileges:** tcpdump requires root or `CAP_NET_RAW`:
```
sudo ./prism.sh
```
3. **Hardware offload rewriting TOS:** The NIC may be stripping DSCP before the kernel sees it. Disable tx offload:
```
sudo ethtool -K <interface> tx-checksumming off
```
4. **Firewall or policy remarking:** A QoS policy between the capture point and the wire may be rewriting the DSCP value. This is a finding — PRISM's FAIL verdict in this case is correct.

### DNS resolution fails for FQDN targets
```
Resolving iperf3.moji.fr... FAILED
  Could not resolve "iperf3.moji.fr"
```

**Fix:** Verify at least one resolver tool is available:

```
which getent dig host nslookup python3
```
Check DNS is configured and working on the host:
```
cat /etc/resolv.conf
getent hosts iperf3.moji.fr
dig +short A iperf3.moji.fr
```

If the target is in a private DNS zone, ensure the test host uses the correct nameserver and search domain.

### Bidir test fails with "parameter error"
```
iperf3: parameter error - cannot be both reverse and bidirectional
```
**Cause:** An older iperf3 binary that reports a version ≥ 3.7 but does not properly support `--bidir`.

**Fix:** Check the actual iperf3 version on both client and server:

```
iperf3 --version
```
Upgrade to **iperf3 3.9** or later for stable `--bidir` support.

### Dashboard drifts or content overlaps after terminal resize

**Cause:** PRISM pre-calculates the frame height before the first tick. A resize mid-test causes a one-tick misalignment.

**Fix:** Resize the terminal between tests, not during. The dashboard self-corrects on the next one-second tick via `printf '\033[J'` (erase to end of screen).

### Path MTU shows UNKNOWN for all targets

**Cause:** ICMP echo requests are blocked by a host-based firewall, a transit ACL, or the target itself does not respond to ping.

**Fix:** This is informational. PRISM will still proceed using the interface MTU as the default. To investigate:

```
# Test ICMP with DF bit set manually
ping -M do -s 1400 -c 3 <target>

# Check local firewall
iptables -L -n | grep icmp
```

### JSON export file not created

**Cause:** `JSON_EXPORT_ENABLED` is only set to 1 after the session naming prompt. If the operator presses `Ctrl+C` before the prompt completes, no export is written.

**Fix:** Allow the session naming prompt to complete (pressing Enter through all fields is sufficient to accept the auto-generated ID).
### Session history not written

**Cause:** The directory `~/.config/prism/` cannot be created, or the filesystem is read-only.

**Fix:**
```
mkdir -p ~/.config/prism
ls -la ~/.config/prism/
```
Ensure the user running PRISM has write access to their home directory.

## Known Limitations
|          **Limitation**          |                                                                  **Detail**                                                                 |                               Workaround / Roadmap                              |
|:--------------------------------:|:-------------------------------------------------------------------------------------------------------------------------------------------:|:-------------------------------------------------------------------------------:|
| IPv6 not supported               | IPv6 targets, AAAA DNS records, and /proc/net/tcp6 connection probing are not implemented                                                   | Planned for a future release                                                    |
| macOS VRF                        | ip vrf exec is a Linux kernel feature. All macOS streams use the Global Routing Table                                                       | No workaround on macOS                                                          |
| macOS tc / netem                 | Traffic shaping (tc tbf) and network impairment (tc netem) require Linux iproute2                                                           | Use a Linux VM or container                                                     |
| Bidir requires iperf3 ≥ 3.7      | --bidir was introduced in iperf3 3.7. Older clients fall back to two separate processes, which is less accurate                             | Upgrade iperf3 on both endpoints                                                |
| DSCP verify on loopback          | TOS is not reliably preserved on 127.0.0.1. DSCP verification is suppressed for loopback targets                                            | Use a physical or virtual Ethernet interface                                    |
| Terminal width minimum           | Some TUI elements require at least 60 columns to render without truncation                                                                  | Widen the terminal before running                                               |
| Ctrl+Z blocked                   | Backgrounding PRISM is prevented to avoid orphaned iperf3 and tc processes                                                                  | Use Ctrl+C to stop then relaunch                                                |
| TCP ramp requires root           | tc tbf kernel shaping requires CAP_NET_ADMIN. UDP ramp via iperf3 -b stepping works without root                                            | Run as root for TCP ramp                                                        |
| RTT sparkline                    | The 10-second sparkline shows bandwidth only. RTT over time is a numeric summary but not a graph                                            | Planned for a future release                                                    |
| Single NIC concurrency           | All streams share one NIC egress queue. Physical link speed limits total aggregate bandwidth regardless of stream count                     | Use multiple interfaces or a higher-capacity link                               |
| Remote server management         | PRISM starts local iperf3 servers (Server Mode / Loopback Mode) but does not manage remote servers                                          | Start the remote iperf3 server manually or via SSH before running a client test |
| Bash 3.2 assoc-array shims       | macOS ships with Bash 3.2 which lacks declare -A. PRISM provides shims for PMTU and VRF maps. Very large VRF tables may be slow on Bash 3.2 | Upgrade to Bash 5 via brew install bash on macOS                                |
| Single dashboard tick = 1 second | The dashboard refresh rate is fixed at approximately 1 second. Sub-second bandwidth fluctuations are not individually visible               | Use iperf3 raw log files for sub-second analysis                                |
| JSON sample limit                | The per-stream bandwidth ring buffer retains a maximum of 3600 samples (1 hour at 1 sample/second). Older samples are discarded             | For tests longer than 1 hour, analyse the raw iperf3 log file                   |
