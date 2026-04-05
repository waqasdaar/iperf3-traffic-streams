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
## Quick Start
60-Second Bandwidth Test Between Two Hosts

```
sudo ./iperf3-traffic-streams.sh
```

```
Select [1-6]: 2              # Server Mode
Selection [0]: 0             # Bind all interfaces
How many listeners? [1]: 1
Listen port [5201]: 5201
Bind IP: Enter               # 0.0.0.0
VRF: Enter                   # none
One-off mode? [no]: n
Launch 1 listener(s)? [Y/n]: Y
```

**On the client host**

```
sudo ./iperf3-traffic-streams.sh
```

```
Select [1-6]: 3              # Client Mode
Selection [0]: 0             # auto source
How many streams? [1]: 1
Protocol [TCP/UDP]: TCP
Target IP: 192.168.1.10
Port [5201]: 5201
Bandwidth: Enter             # unlimited
Duration [10]: 60
DSCP: Enter                  # none
Parallel threads [1]: 1
Launch 1 stream(s)? [Y/n]: Y
```

## Application Menu

```
+==============================================================================+
|             iperf3 Multi-Stream Traffic Manager  v7.7                        |
+==============================================================================+
|                                                                              |
|   1   Interface Table        View interfaces, IPs, speeds, VRF mapping       |
|   2   Server Mode            Start one or more iperf3 server listeners       |
|   3   Client Mode            Launch one or more client traffic streams       |
|   4   Loopback Test          Local server + client for quick validation      |
|   5   DSCP Reference Table   Show DSCP names, values, TOS, and use cases     |
|   6   Exit                                                                   |
|                                                                              |
+==============================================================================+
```

**Interface Table Example**

```
+----+---------------+--------------------+----------+----------+--------------+
|  # | Interface     | IP Address         | State    | Speed    | VRF          |
+----+---------------+--------------------+----------+----------+--------------+
| [ GRT -- Global Routing Table ]  (1 interface(s))                            |
+----+---------------+--------------------+----------+----------+--------------+
|  1 | eth0          | 192.168.1.100      | up       | 1000Mb/s | GRT          |
+----+---------------+--------------------+----------+----------+--------------+
| [ VRF: vrf10 ]  (2 interface(s))                                             |
+----+---------------+--------------------+----------+----------+--------------+
|  2 | eth1          | 10.10.114.3        | up       | 1000Mb/s | vrf10        |
|  3 | eth2          | 10.10.115.3        | up       | 1000Mb/s | vrf10        |
+----+---------------+--------------------+----------+----------+--------------+
| [ VRF: vrf20 ]  (1 interface(s))                                             |
+----+---------------+--------------------+----------+----------+--------------+
|  4 | eth3          | 172.16.20.1        | up       | 10Gb/s   | vrf20        |
+----+---------------+--------------------+----------+----------+--------------+
```
## Use Cases

### Use Case 1 — Basic TCP Throughput Test
**Goal**: Measure end-to-end __TCP__ throughput between two hosts.
Typical scenarios:
- Baseline measurement before and after a change
- Cabling or switch troubleshooting
- Validating link capacity

__Configuration__

| **Parameters** | **Value**    |
|----------------|--------------|
| Protocol       | TCP          |
| Target         | 192.168.1.10 |
| Port           | 5201         |
| Bandwidth      | unlimited    |
| Duration       | 30 seconds   |
| DSCP           | none         |

**Running the Test**

__Server host__ — **192.168.1.10**

```
Select [1-6]: 2
Selection [0]: 0
How many listeners? [1]: 1
Listen port [5201]: 5201
Bind IP: Enter
VRF: Enter
One-off mode? [no]: n
Launch 1 listener(s)? [Y/n]: Y

[STARTED]  server 1  PID 22100  port 5201

  Servers running. Opening dashboard...

```

**Client Host**

```
Select [1-6]: 3
Selection [0]: 0
How many streams? [1]: 1
Protocol [TCP/UDP]: TCP
Target server IP/hostname: 192.168.1.10
Server port [5201]: 5201
Bandwidth limit (empty=unlimited):
Duration seconds [10]: 30
DSCP: Enter
Parallel threads [1]: 1
Reverse mode? [no]: n
Launch 1 stream(s)? [Y/n]: Y

[STARTED]  stream 1  PID 376758  TCP -> 192.168.1.10:5201

  Streams running. Opening dashboard...

```

**Live Dashboard**

```
+==============================================================================+
|                   iperf3 Traffic Manager -- Live Dashboard                   |
+==============================================================================+
|  Active:1   Connected:1   Done:0   Failed:0   Elapsed:00:08                  |
+------------------------------------------------------------------------------+
|  #    Proto  Target         Port   Bandwidth    Time    DSCP   Status        |
+------------------------------------------------------------------------------+
|  1    TCP    192.168.1.10   5201   941.22 Mbps  00:22   ---    CONNECTED     |
+------------------------------------------------------------------------------+
|  Ctrl+C to stop all streams                                                  |
+------------------------------------------------------------------------------+
```

**Final Results**

```
+==============================================================================+
|                                Final Results                                 |
+==============================================================================+

  #    Proto  Target            Port   Sender BW     Receiver BW   Retx
  --------------------------------------------------------------------------------
  1    TCP    192.168.1.10      5201   941.22 Mbps   938.55 Mbps   Retx:2
  --------------------------------------------------------------------------------

  All 1 stream(s) completed successfully.
```

## Use Case 2 — UDP Performance and Loss Test

**Goal**: Measure _UDP_ throughput, jitter, and packet loss for
          real-time application path validation.
Typical scenarios:
- VoIP path quality assessment
- Video streaming path validation
- QoS policy verification
- Pre/post impairment comparison

**Important**: iperf3 requires an explicit bandwidth value for UDP. Without it the default is 1 Mbps, which may not reflect real traffic.

**Configuration**
| **Parameters** | **Value**  |
|----------------|------------|
| Protocol       | UDP        |
| Target         | 10.10.10.5 |
| Port           | 5201       |
| Bandwidth      | 200M       |
| Duration       | 30 seconds |
| DSCP           | EF         |

**Running the Test**
```
Protocol [TCP/UDP]: UDP
Target server IP/hostname: 10.10.10.5
Server port [5201]: 5201
Bandwidth (required for UDP): 200M
Duration seconds [10]: 30
DSCP: EF
Launch 1 stream(s)? [Y/n]: Y

[STARTED]  stream 1  PID 379620  UDP -> 10.10.10.5:5201

  Streams running. Opening dashboard...

```

**Live Dashboard**

```
+==============================================================================+
|                   iperf3 Traffic Manager -- Live Dashboard                   |
+==============================================================================+
|  Active:1   Connected:1   Done:0   Failed:0   Elapsed:00:12                  |
+------------------------------------------------------------------------------+
|  #    Proto  Target         Port   Bandwidth    Time    DSCP   Status        |
+------------------------------------------------------------------------------+
|  1    UDP    10.10.10.5     5201   200.01 Mbps  00:18   EF     CONNECTED     |
+------------------------------------------------------------------------------+
|  Ctrl+C to stop all streams                                                  |
+------------------------------------------------------------------------------+
```

**Final Results**

```
+==============================================================================+
|                                Final Results                                 |
+==============================================================================+

  #    Proto  Target         Port   Sender BW     Receiver BW   Retx / Jitter+Loss
  ----------------------------------------------------------------------------------
  1    UDP    10.10.10.5     5201   200.01 Mbps   199.87 Mbps   J:0.012ms L:0.001%
  ----------------------------------------------------------------------------------

  All 1 stream(s) completed successfully.
```

## Use Case 3 — Multi-Stream Parallel Testing

**Goal**: Simulate realistic production traffic using multiple concurrent streams, each with independent protocol, target, bandwidth, and DSCP
configuration.
Typical scenarios:
- Server or path saturation testing
- Mixed protocol environments
- Validating per-class QoS behavior simultaneously

**Configuration — 3 Streams**
| **Stream** | **Protocol** | **Target**    | **Port** | **Bandwidth** | **DSCP** |
|------------|--------------|---------------|----------|---------------|----------|
| 1          | TCP          | 192.168.10.10 | 5201     | unlimited     | AF31     |
| 2          | UDP          | 192.168.10.11 | 5202     | 50M           | EF       |
| 3          | TCP          | 192.168.10.12 | 5203     | unlimited     | CS3      |

**Running the Test**

```
How many streams? [1]: 3

── Stream 1 of 3 ──
Protocol: TCP
Target:   192.168.10.10
Port:     5201
Bandwidth: Enter
Duration: 60
DSCP:     AF31

── Stream 2 of 3 ──
Protocol: UDP
Target:   192.168.10.11
Port:     5202
Bandwidth: 50M
Duration: 60
DSCP:     EF

── Stream 3 of 3 ──
Protocol: TCP
Target:   192.168.10.12
Port:     5203
Bandwidth: Enter
Duration: 60
DSCP:     CS3

Launch 3 stream(s)? [Y/n]: Y

[STARTED]  stream 1  PID 44100  TCP -> 192.168.10.10:5201
[STARTED]  stream 2  PID 44101  UDP -> 192.168.10.11:5202
[STARTED]  stream 3  PID 44102  TCP -> 192.168.10.12:5203

  Streams running. Opening dashboard...

```

**Live Dashboard**

```
+==============================================================================+
|                   iperf3 Traffic Manager -- Live Dashboard                   |
+==============================================================================+
|  Active:3   Connected:3   Done:0   Failed:0   Elapsed:00:14                  |
+------------------------------------------------------------------------------+
|  #    Proto  Target          Port   Bandwidth    Time    DSCP   Status       |
+------------------------------------------------------------------------------+
|  1    TCP    192.168.10.10   5201   931.00 Mbps  00:46   AF31   CONNECTED    |
|  2    UDP    192.168.10.11   5202    50.00 Mbps  00:46   EF     CONNECTED    |
|  3    TCP    192.168.10.12   5203   420.14 Mbps  00:46   CS3    CONNECTED    |
+------------------------------------------------------------------------------+
|  Ctrl+C to stop all streams                                                  |
+------------------------------------------------------------------------------+
```

**Final Results**

```
+==============================================================================+
|                                Final Results                                 |
+==============================================================================+

  #    Proto  Target          Port   Sender BW     Receiver BW   Retx / Jitter+Loss
  -----------------------------------------------------------------------------------
  1    TCP    192.168.10.10   5201   931.00 Mbps   929.22 Mbps   Retx:1
  2    UDP    192.168.10.11   5202    50.00 Mbps    49.91 Mbps   J:0.030ms L:0.0%
  3    TCP    192.168.10.12   5203   420.14 Mbps   418.90 Mbps   Retx:0
  -----------------------------------------------------------------------------------

  All 3 stream(s) completed successfully.
```

## Use Case 4 — Server Mode with Multiple Listeners
**Goal**: Start multiple iperf3 listeners on different ports, bind addresses, and VRFs in a single operation.
Typical scenarios:
- Receiving traffic from multiple clients simultaneously
- Testing multiple VRF paths from a single host
- Pre-positioning listeners before a test window

**Configuration — 2 Listeners**
| Listener | Port | Bind IP         |
|----------|------|-----------------|
| 1        | 5201 | 192.168.114.200 |
| 2        | 5202 | 10.10.114.3     |

**Running the Test**
```
Select [1-6]: 2
Selection [0]: 0
How many listeners? [1]: 2

── Listener 1 of 2 ──
Listen port [5201]: 5201
Bind IP: 192.168.114.200
VRF: Enter
One-off mode? [no]: n

── Listener 2 of 2 ──
Listen port [5202]: 5202
Bind IP: 10.10.114.3
VRF: vrf10
One-off mode? [no]: n

Launch 2 listener(s)? [Y/n]: Y

[STARTED]  server 1  PID 967934  port 5201
[STARTED]  server 2  PID 967935  port 5202

  Waiting for servers to start listening...
  [READY  ]  server 1  port 5201
  [READY  ]  server 2  port 5202

  Servers running. Opening dashboard...

```
**Server Dashboard (Clients Connected)**

```
+==============================================================================+
|                  iperf3 Traffic Manager -- Server Dashboard                  |
+==============================================================================+
|  Listeners active: 2 / 2                                                     |
+------------------------------------------------------------------------------+
|  #    Port    Bind IP            VRF         Bandwidth      Status           |
+------------------------------------------------------------------------------+
|  1    5201    192.168.114.200    GRT          938.21 Mbps   CONNECTED        |
|  2    5202    10.10.114.3        vrf10         88.10 Mbps   CONNECTED        |
+------------------------------------------------------------------------------+
|  Ctrl+C to stop all listeners                                                |
+------------------------------------------------------------------------------+
```
## Use Case 5 — VRF-Aware Testing

**Goal**: Run iperf3 client and server processes within a specific Linux VRF instance to validate VRF-specific routing and connectivity.
Typical scenarios:
- MPLS / L3VPN tenant path validation
- Network segmentation verification
- VRF routing policy testing
- Multi-tenant connectivity validation

  
__The script automatically__:
- Discovers all configured VRFs via ip vrf show
- Maps each interface to its VRF via ip link show master
- Displays VRF membership in the interface table
- Injects ip vrf exec <vrf> before the iperf3 command

**Interface Table Showing VRF Layout**
```
+----+---------------+--------------------+----------+----------+--------------+
|  # | Interface     | IP Address         | State    | Speed    | VRF          |
+----+---------------+--------------------+----------+----------+--------------+
| [ GRT -- Global Routing Table ]  (1 interface(s))                            |
+----+---------------+--------------------+----------+----------+--------------+
|  1 | eth0          | 192.168.1.100      | up       | 1000Mb/s | GRT          |
+----+---------------+--------------------+----------+----------+--------------+
| [ VRF: vrf10 ]  (2 interface(s))                                             |
+----+---------------+--------------------+----------+----------+--------------+
|  2 | eth1          | 10.10.114.3        | up       | 1000Mb/s | vrf10        |
|  3 | eth2          | 10.10.115.3        | up       | 1000Mb/s | vrf10        |
+----+---------------+--------------------+----------+----------+--------------+
```
**VRF Server Configuration**
```
Listen port [5201]: 5201
Bind IP: 10.10.114.3
VRF (press Enter for GRT/none): vrf10
```
**Generated command:**
```
ip vrf exec vrf10 iperf3 -s -p 5201 -B 10.10.114.3 -i 1
```
**VRF Client Configuration**
```
Target server IP/hostname: 10.10.114.1
VRF (press Enter for GRT/none): vrf10
```
**Generated command:**
```
ip vrf exec vrf10 iperf3 -c 10.10.114.1 -p 5201 -t 30 -i 1
```

**VRF Server Dashboard**
```
+==============================================================================+
|                  iperf3 Traffic Manager -- Server Dashboard                  |
+==============================================================================+
|  Listeners active: 2 / 2                                                     |
+------------------------------------------------------------------------------+
|  #    Port    Bind IP           VRF         Bandwidth      Status            |
+------------------------------------------------------------------------------+
|  1    5201    10.10.114.3       vrf10        941.20 Mbps   CONNECTED         |
|  2    5202    10.10.115.3       vrf10        880.44 Mbps   CONNECTED         |
+------------------------------------------------------------------------------+
|  Ctrl+C to stop all listeners                                                |
+------------------------------------------------------------------------------+
```

## Use Case 6 — DSCP and QoS Marking

**Goal**: Generate traffic with specific DSCP markings to validate end-to-end QoS classification, policing, and queuing behavior.
Typical scenarios:
- Verifying DiffServ policy application
- Testing traffic classification on routers and switches
- Validating per-class queue behavior
- Confirming DSCP preservation across network boundaries

**DSCP Reference Table**
Access from the main menu with _option 5_:
```
Name          DSCP  TOS   Typical Use Case
  ────────────  ────  ────  ─────────────────────────────────────────────
  Default/CS0   0     0     Best Effort
  CS1           8     32    Scavenger / Low-priority bulk
  AF11          10    40    Low data (assured, low drop)
  AF12          12    48    Low data (assured, med drop)
  AF13          14    56    Low data (assured, high drop)
  CS2           16    64    OAM / Network management
  AF21          18    72    High-throughput data (low drop)
  AF22          20    80    High-throughput data (med drop)
  AF23          22    88    High-throughput data (high drop)
  CS3           24    96    Broadcast video / Signaling
  AF31          26    104   Multimedia streaming (low drop)
  AF32          28    112   Multimedia streaming (med drop)
  AF33          30    120   Multimedia streaming (high drop)
  CS4           32    128   Real-time interactive
  AF41          34    136   Multimedia conf (low drop)
  AF42          36    144   Multimedia conf (med drop)
  AF43          38    152   Multimedia conf (high drop)
  CS5           40    160   Signaling -- call control
  VA            44    176   Voice Admit (CAC admitted)
  EF            46    184   Expedited Forwarding -- VoIP
  CS6           48    192   Network Control (BGP/OSPF)
  CS7           56    224   Reserved / Network Critical
  ────────────  ────  ────  ─────────────────────────────────────────────

  TOS = DSCP * 4  |  Enter name, 0-63, 'list', or press Enter for none.
```
**DSCP Configuration During Stream Setup**
```
Stream 1 - DSCP (name/0-63/'list'/Enter=none) [none]: EF
```
**Sets iperf3 flag: -S 184 (EF=46, TOS=46×4=184)**
```
Stream 2 - DSCP (name/0-63/'list'/Enter=none) [none]: AF41
```
**Sets iperf3 flag: -S 136 (AF41=34, TOS=34×4=136)**
```
Stream 3 - DSCP (name/0-63/'list'/Enter=none) [none]: 46
```
Numeric entry also accepted, equivalent to EF


**Multi-Class QoS Validation Dashboard**
```
+==============================================================================+
|                   iperf3 Traffic Manager -- Live Dashboard                   |
+==============================================================================+
|  Active:3   Connected:3   Done:0   Failed:0   Elapsed:00:10                  |
+------------------------------------------------------------------------------+
|  #    Proto  Target         Port   Bandwidth    Time    DSCP   Status        |
+------------------------------------------------------------------------------+
|  1    UDP    10.0.0.1       5201   100.00 Mbps  00:50   EF     CONNECTED     |
|  2    TCP    10.0.0.1       5202   500.11 Mbps  00:50   AF41   CONNECTED     |
|  3    TCP    10.0.0.1       5203   300.45 Mbps  00:50   CS3    CONNECTED     |
+------------------------------------------------------------------------------+
|  Ctrl+C to stop all streams                                                  |
+------------------------------------------------------------------------------+
```
## Use Case 7 — TCP Tuning and CCA Comparison

**Goal**: Benchmark the impact of different TCP congestion control algorithms, receive window sizes, and MSS values on throughput and retransmissions.
Typical scenarios:
- Comparing BBR vs CUBIC over a WAN path
- Tuning buffer sizes for high-latency links
- MSS optimization for VPN or tunnelled paths
- Pre-deployment CCA selection

**Configuration — BBR vs CUBIC**
```
Protocol: TCP
Target:   10.0.0.1
Port:     5201
Duration: 60

-- TCP Options --
Available CCAs: bbr cubic reno
CCA [kernel default]: bbr
Window size: 256K
MSS: 1460
```

**Stream 2 — CUBIC:**
```
Protocol: TCP
Target:   10.0.0.1
Port:     5202
Duration: 60

-- TCP Options --
CCA [kernel default]: cubic
Window size: 256K
MSS: 1460
```
**Generated Commands**
```
# Stream 1 — BBR
iperf3 -c 10.0.0.1 -p 5201 -t 60 -i 1 -C bbr -w 256K -M 1460

# Stream 2 — CUBIC
iperf3 -c 10.0.0.1 -p 5202 -t 60 -i 1 -C cubic -w 256K -M 1460
```

**Live Dashboard**

```
+==============================================================================+
|                   iperf3 Traffic Manager -- Live Dashboard                   |
+==============================================================================+
|  Active:2   Connected:2   Done:0   Failed:0   Elapsed:00:20                  |
+------------------------------------------------------------------------------+
|  #    Proto  Target         Port   Bandwidth    Time    DSCP   Status        |
+------------------------------------------------------------------------------+
|  1    TCP    10.0.0.1       5201   948.12 Mbps  00:40   ---    CONNECTED     |
|  2    TCP    10.0.0.1       5202   931.44 Mbps  00:40   ---    CONNECTED     |
+------------------------------------------------------------------------------+
|  Ctrl+C to stop all streams                                                  |
+------------------------------------------------------------------------------+
```
**Final Results**
```
+==============================================================================+
|                                Final Results                                 |
+==============================================================================+

  #    Proto  Target      Port   Sender BW     Receiver BW   Retx
  ------------------------------------------------------------------
  1    TCP    10.0.0.1    5201   948.12 Mbps   945.33 Mbps   Retx:1
  2    TCP    10.0.0.1    5202   931.44 Mbps   929.11 Mbps   Retx:8
  ------------------------------------------------------------------

  All 2 stream(s) completed successfully.
```
BBR achieved higher throughput with fewer retransmissions, suggesting better behavior under buffer congestion on this path.

## Use Case 8 — Network Impairment Injection
**Goal**: Simulate degraded or distant network paths by injecting artificial delay, jitter, and packet loss using tc netem.

Typical scenarios:
- WAN simulation in a lab
- Satellite link emulation
- Application resilience testing under degraded conditions
- Validating QoS behavior with packet loss present

**Note:** Requires root privileges and **tc** from i**proute2**.

**Impairment Parameters**

| Parameter   | Description                    | Example Values |
|-------------|--------------------------------|----------------|
| Delay (ms)  | Fixed added one-way latency    | 50, 100, 250   |
| Jitter (ms) | Random variation around delay  | 5, 10, 25      |
| Loss (%)    | Random packet drop probability | 0.1, 1.0, 5.0  |

**Example — Simulating a Degraded WAN Link**

```
-- Network Impairment via tc netem (Enter to skip each) --
Delay ms   [skip]: 100
Jitter ms  [skip]: 10
Loss %     [skip]: 0.5
```
**Applied command:**

```
tc qdisc add dev eth0 root netem delay 100ms 10ms loss 0.5%
```
**Output**
```
[NETEM  ]  dev eth0       delay=100ms jitter=10ms loss=0.5%
```
**Live Dashboard**
```
+==============================================================================+
|                   iperf3 Traffic Manager -- Live Dashboard                   |
+==============================================================================+
|  Active:1   Connected:1   Done:0   Failed:0   Elapsed:00:08                  |
+------------------------------------------------------------------------------+
|  #    Proto  Target         Port   Bandwidth    Time    DSCP   Status        |
+------------------------------------------------------------------------------+
|  1    UDP    10.0.0.1       5201    96.40 Mbps  00:22   EF     CONNECTED     |
+------------------------------------------------------------------------------+
|  Ctrl+C to stop all streams                                                  |
+------------------------------------------------------------------------------+
```

**Final Results**

```
+==============================================================================+
|                                Final Results                                 |
+==============================================================================+

  #    Proto  Target      Port   Sender BW     Receiver BW   Jitter / Loss
  --------------------------------------------------------------------------
  1    UDP    10.0.0.1    5201   100.00 Mbps    96.40 Mbps   9.88ms / 0.49%
  --------------------------------------------------------------------------

  All 1 stream(s) completed successfully.
```
**Automatic Cleanup**
When the script exits, all _tc rules_ are removed:
```
tc netem:
    [REMOVED]  netem on eth0
```

## Use Case 9 — Reverse Mode Asymmetric Testing

**Goal**: Measure throughput in the server-to-client direction without
changing which host runs the server. This reveals upstream vs downstream
asymmetry in the path.


Typical scenarios:
- ADSL / cable asymmetric link validation
- Asymmetric MPLS path discovery
- Upload vs download comparison

**Configuration**
```
Reverse mode -R? [no]: y
```
**Generated command**:
```
iperf3 -c 10.0.0.1 -p 5201 -t 30 -i 1 -R
```
**Example — Proving Path Asymmetry**

**Stream 1** — Forward (client → server):
```
Reverse mode -R? [no]: n
```
**Stream 2** — Reverse (server → client):
```
Reverse mode -R? [no]: y
```
**Final Results** — Asymmetry Visible
```
+==============================================================================+
|                                Final Results                                 |
+==============================================================================+

  #    Proto  Target      Port   Sender BW     Receiver BW   Retx
  ------------------------------------------------------------------
  1    TCP    10.0.0.1    5201   950.00 Mbps   948.10 Mbps   Retx:0
  2    TCP    10.0.0.1    5202   480.22 Mbps   478.90 Mbps   Retx:3
  ------------------------------------------------------------------

  All 2 stream(s) completed successfully.
```

**Stream 1 (forward) shows full 950 Mbps.**

**Stream 2 (reverse) shows only 480 Mbps. confirming upstream asymmetry.**

## Use Case 10 — Loopback Local Validation

**Goal**: Verify that iperf3 is working correctly and measure local kernel TCP/UDP stack performance without requiring a second host.


Typical scenarios:
- Post-install smoke test
- Lab host validation
- Confirming tool functionality before remote testing

**Configuration**
```
Select [1-6]: 4
How many loopback streams? [1]: 1

Stream 1:
Protocol: TCP
Bandwidth: Enter
Duration: 10
DSCP: Enter

Launch loopback test? [Y/n]: Y

[STARTED]  server 1  PID 33200  port 5201
[READY  ]  server 1  port 5201
[STARTED]  stream 1  PID 33210  TCP -> 127.0.0.1:5201

  Running. Opening dashboard...

```

**Live Dashboard**
```
+==============================================================================+
|                   iperf3 Traffic Manager -- Live Dashboard                   |
+==============================================================================+
|  Active:1   Connected:1   Done:0   Failed:0   Elapsed:00:05                  |
+------------------------------------------------------------------------------+
|  #    Proto  Target         Port   Bandwidth    Time    DSCP   Status        |
+------------------------------------------------------------------------------+
|  1    TCP    127.0.0.1      5201   24.81 Gbps   00:05   ---    CONNECTED     |
+------------------------------------------------------------------------------+
|  Ctrl+C to stop all streams                                                  |
+------------------------------------------------------------------------------+
```

**Final Results**
```
+==============================================================================+
|                                Final Results                                 |
+==============================================================================+

  #    Proto  Target       Port   Sender BW     Receiver BW   Retx
  ------------------------------------------------------------------
  1    TCP    127.0.0.1    5201   24.81 Gbps    24.79 Gbps    Retx:0
  ------------------------------------------------------------------

  All 1 stream(s) completed successfully.
```

Loopback throughput of 20–40 Gbps is normal on modern Linux hardware. 
Values significantly below this may indicate kernel or CPU bottlenecks.

## Dashboard Reference

**Client Dashboard Column Definitions**


| Column    | Width | Description                                |
|-----------|-------|--------------------------------------------|
| #         | 3     | Stream index number                        |
| Proto     | 5     | TCP or UDP                                 |
| Target    | 13    | Destination IP, truncated with ~ if longer |
| Port      | 5     | Destination port number                    |
| Bandwidth | 11    | Current 1-second interval throughput       |
| Time      | 6     | Remaining duration or inf for unlimited    |
| DSCP      | 5     | DSCP name or numeric value, --- if not set |
| Status    | 9     | Current stream state                       |


**Server Dashboard Column Definitions**

| Column    | Width | Description                                   |
|-----------|-------|-----------------------------------------------|
| #         | 3     | Listener index number                         |
| Port      | 6     | Listening port number                         |
| Bind IP   | 16    | Bound address, 0.0.0.0 means all interfaces   |
| VRF       | 10    | VRF name or GRT for global routing table      |
| Bandwidth | 12    | Live receive throughput from connected client |
| Status    | 9     | Current listener state                        |

**Status Reference**

| Status     | Side            | Meaning                                   |
|------------|-----------------|-------------------------------------------|
| STARTING   | Client / Server | Process launched, no log output yet       |
| CONNECTING | Client          | Log file exists, no interval data yet     |
| CONNECTED  | Client / Server | Active data transfer confirmed            |
| LISTENING  | Server          | Port open and accepting connections       |
| RUNNING    | Server          | Client connected and transfer in progress |
| DONE       | Client / Server | Stream or listener exited normally        |
| FAILED     | Client          | Error detected — check error panel        |

## DSCP Reference Table

| Name          | DSCP | TOS | Typical Use Case                    |
|---------------|------|-----|-------------------------------------|
| Default / CS0 | 0    | 0   | Best Effort                         |
| CS1           | 8    | 32  | Scavenger / Low-priority bulk       |
| AF11          | 10   | 40  | Low data — assured, low drop        |
| AF12          | 12   | 48  | Low data — assured, med drop        |
| AF13          | 14   | 56  | Low data — assured, high drop       |
| CS2           | 16   | 64  | OAM / Network management            |
| AF21          | 18   | 72  | High-throughput data — low drop     |
| AF22          | 20   | 80  | High-throughput data — med drop     |
| AF23          | 22   | 88  | High-throughput data — high drop    |
| CS3           | 24   | 96  | Broadcast video / Signaling         |
| AF31          | 26   | 104 | Multimedia streaming — low drop     |
| AF32          | 28   | 112 | Multimedia streaming — med drop     |
| AF33          | 30   | 120 | Multimedia streaming — high drop    |
| CS4           | 32   | 128 | Real-time interactive               |
| AF41          | 34   | 136 | Multimedia conferencing — low drop  |
| AF42          | 36   | 144 | Multimedia conferencing — med drop  |
| AF43          | 38   | 152 | Multimedia conferencing — high drop |
| CS5           | 40   | 160 | Signaling — call control            |
| VA            | 44   | 176 | Voice Admit — CAC admitted          |
| EF            | 46   | 184 | Expedited Forwarding — VoIP         |
| CS6           | 48   | 192 | Network Control — BGP / OSPF        |
| CS7           | 56   | 224 | Reserved / Network Critical         |

**Formula**: TOS = DSCP × 4

## Output and Log Files

_Temporary Directory Structure_

```
/tmp/iperf3_mgr.XXXXXX/
├── stream_1.sh          Generated iperf3 client launch script
├── stream_1.log         Plain-text iperf3 output for stream 1
├── stream_2.sh
├── stream_2.log
├── server_1.sh          Generated iperf3 server launch script
├── server_1.log         Plain-text iperf3 server output
└── server_2.log
```

**Sample Raw Client Log**

```
Connecting to host 192.168.1.10, port 5201
[  5] local 192.168.1.20 port 54321 connected to 192.168.1.10 port 5201
[ ID] Interval           Transfer     Bitrate         Retr  Cwnd
[  5]   0.00-1.00   sec   112 MBytes   939 Mbits/sec    0   1.50 MBytes
[  5]   1.00-2.00   sec   113 MBytes   947 Mbits/sec    0   1.50 MBytes
[  5]   2.00-3.00   sec   112 MBytes   940 Mbits/sec    1   1.49 MBytes
[  5]   3.00-4.00   sec   113 MBytes   948 Mbits/sec    0   1.51 MBytes
...
[  5]   0.00-30.00  sec  3.29 GBytes   942 Mbits/sec    2   sender
[  5]   0.00-30.00  sec  3.28 GBytes   939 Mbits/sec        receiver
```

**Interactive Log Viewer**
After a test completes, the script prompts:
```
View raw log for stream # (or press Enter/q to quit): 1
```

## Cleanup and Signal Handling

**Signals Handled**

| Signal  | Trigger         | Exit Code                        |
|---------|-----------------|----------------------------------|
| SIGINT  | Ctrl+C          | 130                              |
| SIGTERM | kill <pid>      | 143                              |
| SIGQUIT | Ctrl+\          | 131                              |
| SIGHUP  | Terminal closed | 129                              |
| SIGTSTP | Ctrl+Z          | blocked — warning shown          |
| EXIT    | Any exit path   | runs cleanup if not already done |

**Cleanup Actions Performed**

```
1. Terminate all running client stream processes
2. Terminate all running server listener processes
3. Remove all tc netem qdiscs that were applied
4. Delete all generated launch scripts
5. Delete all temporary log files
6. Remove the temporary working directory
```

**Example Cleanup Output**
```
[SIGINT]  Ctrl+C -- stopping...

+===========================================================================+
  iperf3 Manager -- Cleanup  [signal: SIGINT (Ctrl+C)]
+===========================================================================+

  Client Streams:
    [STOP  ]  PID 12345  stream 1 [TCP->192.168.1.10:5201]
    [DONE  ]  PID 12346  stream 2 [UDP->10.10.10.5:5201]  (already exited)

  Server Listeners:
    [STOP  ]  PID 22100  listener 1 [port 5201 bind 0.0.0.0]

  tc netem:
    [REMOVED]  netem on eth0

  Temporary Files:
    [DEL]  /tmp/iperf3_mgr.abcd12/stream_1.log  (14823 bytes)
    [DEL]  /tmp/iperf3_mgr.abcd12/stream_1.sh   (128 bytes)
    [REMOVED]  /tmp/iperf3_mgr.abcd12

  Processes stopped : 2
  Already exited    : 1
  Cleanup complete. All resources released.

```

## Troubleshooting

### 1. **Stream Stuck at STARTING**

**Symptoms**: Status does not advance after several seconds.


**Possible causes**:
- Target host is unreachable
- Server is not running on the target port
- Firewall is blocking the port
- VRF mismatch between client and server

**Checks**
```
ping <target_ip>
ip route get <target_ip>
ss -tlnp | grep 5201
tail -20 /tmp/iperf3_mgr.*/stream_1.log
```

### 2. **Bandwidth Shows ---**

**Symptoms**: Bandwidth column remains at --- after connection.


**Possible causes**:
- First 1-second interval has not yet been written
- Client is still in the connection handshake
- Log file is empty or not being written

**Checks**
```
tail -f /tmp/iperf3_mgr.*/stream_1.log
cat /tmp/iperf3_mgr.*/stream_1.sh
```

### 3. **VRF Test Fails**

**Symptoms**: ip vrf exec fails or produces a permission error.


**Cause**: ip vrf exec requires root privileges.

**Fix:**
```
sudo ./iperf3-traffic-streams.sh
```

### 4. **tc netem Not Applied**

**Symptoms**: [NETEM] line does not appear after configuration.


**Possible causes**:

- Script not running as root
- tc binary not installed
- No route found for target IP
  
**Checks**:
```
which tc
sudo tc qdisc show
ip route get <target_ip>
sudo ./iperf3-traffic-streams.sh
```

### 5. **Dashboard Scrolls or Reprints**

**Symptoms**: Dashboard prints new headers instead of updating in place.


**Possible causes**:
- Terminal window width is less than 80 columns
- Terminal emulator does not honour ANSI escape sequences

**Fix**:
```
# Resize terminal to at least 80 columns
# Or explicitly set columns
export COLUMNS=80
./iperf3-traffic-streams.sh
```

### 6. **iperf3 Not Found**

**Symptoms**: Script exits with ERROR: iperf3 not found.


**Fix**:
```
# Ubuntu / Debian
sudo apt install -y iperf3

# RHEL / Rocky / AlmaLinux
sudo dnf install -y iperf3

which iperf3
iperf3 --version
```

### 7. **Bash Version Too Old**

**Symptoms**: declare: -A: invalid option or unexpected syntax errors.


**Cause**: Bash version is below 4.0. Common on macOS which ships 3.2.


**Fix**:
```
bash --version

# macOS upgrade via Homebrew
brew install bash
echo /usr/local/bin/bash | sudo tee -a /etc/shells
chsh -s /usr/local/bin/bash
```

## Known Limitations
| Area             | Detail                                                     |
|------------------|------------------------------------------------------------|
| IPv6             | /proc/net/tcp parsing targets IPv4; IPv6 uses ss fallback  |
| macOS            | No VRF support; no tc netem; bash must be upgraded to 4.0+ |
| Windows WSL2     | tc netem not available                                     |
| Bash below 4.0   | Associative arrays not supported; script will not run      |
| Stream count     | Very high stream counts may exhaust file descriptors       |
| JSON output      | Deliberately not used; JSON is buffered until process exit |
| Log preservation | Logs are deleted on cleanup; copy them before exiting      |
| --forceflush     | Only available in newer iperf3 versions; auto-detected     |
