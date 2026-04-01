# iperf3 Multi-Stream Traffic Manager 

## What Is This?

The iperf3 Multi-Stream Traffic Manager is an interactive Bash script that wraps the standard iperf3 network testing tool with enterprise-grade capabilities. It transforms iperf3 from a simple point-to-point bandwidth tester into a comprehensive network validation platform.

If you've ever needed to:

- Test bandwidth across multiple paths simultaneously
- Validate QoS policies by generating traffic with specific DSCP markings
- Run iperf3 inside Linux VRFs without hand-crafting ip vrf exec commands
- Compare how different TCP congestion algorithms perform on your links
- Simulate real-world network impairments (delay, jitter, loss) during testing
- Actually see what your test packets look like at L2, L3, and L4

…then this script was built for you.

## Who Is This For?

| **Audience**                     | **Why They'd Use It**                                               |
|------------------------------|-----------------------------------------------------------------|
| Network Engineers            | QoS validation, path testing, VRF-aware traffic generation      |
| Systems Engineers            | Bandwidth baselining, congestion control tuning                 |
| Lab Engineers                | Multi-stream test scenarios without manual command construction |
| Pre-Sales / Proof of Concept | Demonstrable QoS differentiation and traffic visualization      |
| Students / Learners          | Understanding DSCP, TCP/UDP headers, congestion algorithms      |

## Prerequisites

| **Requirement**                                | **Purpose**                                          |
|------------------------------------------------|------------------------------------------------------|
| Linux (Ubuntu 20.04+ / Debian 11+ recommended) | Primary OS                                           |
| iperf3 (3.x)                                   | Core traffic generator                               |
| iproute2                                       | VRF detection, interface enumeration                 |
| tc / netem (optional)                          | Congestion simulation                                |
| Root / sudo                                    | VRF sysctl tuning, netem rules, binding to low ports |

### Use Case 1: Basic Bandwidth Testing (Single Stream)

#### Scenario

You have a new 10 Gbps link between two data center switches. Before putting it into production, you want to validate that the link actually delivers expected throughput end-to-end.


##### How to Run

###### On the server side:
```
$ sudo ./iperf3-traffic-flows.sh
```
**Select Option 1**: Start iperf3 Server, choose the interface and port (e.g., ens192 on port 5201).

**On the client side**:
```
$ sudo ./iperf3-traffic-flows.sh
```
