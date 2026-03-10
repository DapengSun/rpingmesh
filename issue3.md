# Issue #3: Probe Link Disconnection and +Inf RTT Metrics

## Symptom

After the system has been running for a period of time, some probe links experience "collection disconnection":

- Probe RTT metrics stop updating for specific source–destination RNIC pairs.
- The `rpingmesh.nwrtt` histogram in Prometheus shows observations accumulating exclusively in the `+Inf` bucket.
- In Grafana, the probe duration panel renders as `+Inf` for affected links.
- The `rpingmesh.timeout` counter climbs steadily for the same links, while the `rpingmesh.nwrtt` gauge freezes at its last recorded value.

The system appears alive (the agent process is running, other links continue to report), but specific RNIC pairs silently stop producing valid RTT measurements.

---

## Root Cause Analysis

Two independent bugs interact to produce the observed symptoms. Either one alone can trigger the issue; together they make it near-certain over long runtimes.

---

### Bug 1: Zero Hardware Timestamp Produces Epoch-Based RTT

#### Background: the 6-timestamp probe model

Each probe measures network latency using six hardware timestamps:

| Timestamp | Meaning | Source |
|-----------|---------|--------|
| T1 | Prober posts the send WR (software clock) | `time.Now()` in `packet.go` |
| T2 | Prober's NIC completes the send (HW clock) | `ibv_wc_read_completion_wallclock_ns` on send CQE |
| T3 | Responder's NIC receives the probe (HW clock) | `ibv_wc_read_completion_wallclock_ns` on recv CQE |
| T4 | Responder's NIC completes sending first ACK (HW clock) | `ibv_wc_read_completion_wallclock_ns` on send CQE |
| T5 | Prober's NIC receives the ACK (HW clock) | `ibv_wc_read_completion_wallclock_ns` on recv CQE |
| T6 | Prober finishes processing (software clock) | `time.Now()` in `prober.go` |

The network RTT is computed as:

```
NetworkRtt = (T5 - T2) - (T4 - T3)
           = one-way flight time (×2) minus responder processing delay
```

Hardware timestamps are read via `ibv_wc_read_completion_wallclock_ns()` from the extended CQ (CQE), which returns wall-clock nanoseconds stamped by the RDMA NIC. This requires the NIC to support hardware timestamping and the CQ to be created with the appropriate extended attributes.

#### The bug

At every site where a hardware CQE timestamp was converted to a `time.Time`, the code used:

```go
// Before fix — four occurrences across cq.go and packet.go
time.Unix(0, int64(wc.CompletionWallclockNS))
```

When `CompletionWallclockNS == 0` — which occurs when:
- The NIC does not support hardware timestamping,
- The extended CQ timestamp feature is not available on the specific device,
- The NIC clock has not yet synchronized after a reset or driver reload, or
- The first few completions after queue creation return 0 before the hardware clock is ready,

— `time.Unix(0, 0)` evaluates to **Unix epoch: 1970-01-01 00:00:00 UTC**.

The RTT calculation then subtracts epoch from a timestamp in 2025/2026:

```
T5 - T2  =  ~2026-01-01  -  1970-01-01
         ≈  56 years × 365.25 days × 86400 s × 10⁹ ns/s
         ≈  1.77 × 10¹⁸ nanoseconds
```

This value is larger than every configured Prometheus histogram bucket boundary. Consequently, **every observation lands exclusively in the `+Inf` bucket**, which is exactly what was observed in Grafana.

The responder delay `(T4 - T3)` may also be epoch-based (if the responder's NIC timestamps are also 0), in which case `responderDelay ≈ 0` and the full `1.77 × 10¹⁸ ns` value is recorded as the network RTT.

#### Affected sites

Four locations in the `internal/rdma` package performed this unchecked conversion:

| File | Function | Field | Role |
|------|----------|-------|------|
| `cq.go` | `handleRecvCompletion` | `IncomingAckInfo.ReceivedAt` | T5: prober ACK receive time |
| `packet.go` | `SendProbePacket` | return value `t2` | T2: prober send completion time |
| `packet.go` | `ReceivePacket` | `receiveTime` | T3: responder probe receive time |
| `packet.go` | `SendFirstAckPacket` | `sendCompletionTime` | T4: responder first ACK send time |

All four timestamps feed directly into the RTT formula. A zero at any one of them produces an astronomically wrong result.

#### The fix

A single helper function was added to `cq.go` (shared across the `rdma` package):

```go
// hwTimestampOrNow returns a time.Time from a hardware wallclock nanosecond value.
// Falls back to time.Now() when wallclockNS is 0 (hardware timestamps unavailable),
// preventing epoch-based timestamps from producing astronomical RTT values.
func hwTimestampOrNow(wallclockNS uint64) time.Time {
    if wallclockNS == 0 {
        return time.Now()
    }
    return time.Unix(0, int64(wallclockNS))
}
```

All four conversion sites were updated to call `hwTimestampOrNow(...)` instead of `time.Unix(0, int64(...))`.

When hardware timestamps are unavailable, the system now falls back to software wall-clock time (`time.Now()`). Software timestamps are slightly less precise than hardware timestamps (they include kernel scheduling jitter), but they produce correct RTT values in the microsecond–millisecond range rather than `+Inf`. This is the right trade-off: precision is degraded gracefully rather than the metric becoming completely unusable.

When hardware timestamps are available and non-zero, behaviour is identical to before — `time.Unix(0, int64(wallclockNS))` is returned unchanged.

---

### Bug 2: CQ Poller Goroutine Dies Permanently on EINTR

#### Background: the CQ poller

Each `UDQueue` (one per RNIC, one for sending probes and one for receiving them) runs a single CQ poller goroutine started by `StartCQPoller()` in `cq.go`. This goroutine is the **only mechanism** for processing RDMA work completions (WCs) for that queue. It:

1. Blocks on `ibv_get_cq_event()` waiting for the completion channel to signal that new WCs are available.
2. Acknowledges the event and calls `ibv_start_poll()` to retrieve WCs in batch.
3. For each WC, either dispatches ACK packets to probe sessions (via `ackHandler`) or forwards receive completions to the `recvCompChan` channel for the responder loop.

If this goroutine stops, all RDMA completions for the queue are lost. In-flight probes never receive their ACKs and time out. The RTT gauge for every probe through that queue freezes at the last recorded value and the timeout counter climbs indefinitely.

#### The bug

The `ibv_get_cq_event()` call is a blocking Linux system call (it performs a `read()` on a file descriptor backed by the completion event channel). Like all blocking system calls, it can be interrupted by a signal delivery. When this happens, the kernel returns `-1` and sets `errno = EINTR` (error code 4).

The pre-fix code treated every non-zero return from `ibv_get_cq_event()` identically — as a fatal error requiring the goroutine to exit:

```go
// Before fix
retGetEvent := C.ibv_get_cq_event(u.CompChannel, &cqEv, &cqCtx)
if retGetEvent != 0 {
    select {
    case <-u.cqPollerDone:
        return // clean shutdown
    default:
        log.Error()...
        select {
        case u.errChan <- fmt.Errorf("ibv_get_cq_event failed: %w", syscall.Errno(C.get_errno())):
        default:
        }
        return // ← goroutine exits permanently
    }
}
```

`EINTR` is not a fatal error. It indicates that a Unix signal (e.g., `SIGTERM`, `SIGCHLD`, `SIGUSR1`, garbage-collector or profiler signals from the Go runtime) arrived while the thread was blocked in the system call. The correct response is to retry the call. The incorrect response — permanently stopping the goroutine — is what caused probe link disconnection.

After this point, no ACKs are ever dispatched for that queue. The probe sessions for all links through that RNIC wait for their ACKs, hit their timeouts, and send `ProbeResult_TIMEOUT` results. Since `RecordRTT` is only called on `ProbeResult_OK`, the RTT gauge freezes at the last valid RTT and is never updated again.

Signals that could trigger this in production:
- **Go runtime signals**: The Go runtime sends `SIGURG` to goroutines for asynchronous preemption (introduced in Go 1.14). Any CGo thread blocked in a system call can receive `SIGURG`.
- **`SIGCHLD`**: Delivered when a child process exits; relevant if the agent spawns subprocesses (e.g., traceroute).
- **`SIGUSR1`/`SIGUSR2`**: May be sent by monitoring tools, health-check frameworks, or operators for diagnostics.
- **`SIGTERM`**: If the agent handles `SIGTERM` gracefully (e.g., starting a shutdown sequence), any other threads still blocked in system calls receive `EINTR`.

Because the Go runtime regularly sends `SIGURG` for goroutine preemption, this bug could trigger even in the absence of any external signals — it just requires a specific timing where `SIGURG` is delivered to the CGo thread running `ibv_get_cq_event`.

#### The fix

The errno is now captured once and checked before deciding how to handle the failure:

```go
// After fix
retGetEvent := C.ibv_get_cq_event(u.CompChannel, &cqEv, &cqCtx)
if retGetEvent != 0 {
    select {
    case <-u.cqPollerDone:
        return // clean shutdown
    default:
        errNo := syscall.Errno(C.get_errno())
        if errNo == syscall.EINTR {
            // Signal interrupted the blocking call; this is transient, retry.
            log.Debug()...
            continue
        }
        log.Error()...
        select {
        case u.errChan <- fmt.Errorf("ibv_get_cq_event failed: %w", errNo):
        default:
        }
        return // truly fatal error, poller stops
    }
}
```

On `EINTR`, the poller logs a debug-level message and loops back to the top, re-entering `ibv_get_cq_event`. No ACKs are lost (the event is still pending in the completion channel) and no probes are disrupted.

On any other error (e.g., `EBADF` if the completion channel file descriptor is closed), the original fatal-exit behaviour is preserved, because those errors genuinely indicate that the queue is unusable.

---

## How the Bugs Interact

The two bugs produce overlapping symptoms but through different failure paths:

| Scenario | Mechanism | Observable effect |
|----------|-----------|-------------------|
| HW timestamps = 0 at queue init | T2, T3, T4, or T5 = epoch; RTT ≈ 56 years | `+Inf` in Prometheus histogram from first probe |
| HW timestamps become 0 mid-run (NIC reset, driver flap) | Same as above, but starts after a period of valid data | `+Inf` appears suddenly after good data |
| `EINTR` kills CQ poller | No ACKs processed; all probes time out | RTT gauge frozen, timeout counter climbs, RTT histogram gets no new observations |
| Both bugs present | CQ poller may recover if restarted, but HW timestamps of 0 still produce `+Inf` | Compound: some links show +Inf, others show frozen gauge |

Because the bugs are independent, **both fixes are required**. Bug 1 alone would still cause incorrect RTT values when hardware timestamps are unavailable. Bug 2 alone would still kill all probing through an RNIC when a signal interrupts the CQ poller.

---

## Files Changed

### `internal/rdma/cq.go`

1. Added `hwTimestampOrNow()` helper function (lines 67–75).
2. Changed `IncomingAckInfo.ReceivedAt` assignment in `handleRecvCompletion` to use `hwTimestampOrNow()` (line 369).
3. Added `EINTR` check and `continue` in the `ibv_get_cq_event` failure branch of `StartCQPoller` (lines 515–520).
4. Captured `errNo` once from `C.get_errno()` to avoid calling `get_errno()` multiple times in the error path (which could return stale values on a second call).

### `internal/rdma/packet.go`

1. `SendProbePacket`, line 263: `t2` (T2 timestamp) changed to `hwTimestampOrNow()`.
2. `ReceivePacket`, line 438: `receiveTime` (T3 timestamp) changed to `hwTimestampOrNow()`.
3. `SendFirstAckPacket`, line 588: `sendCompletionTime` (T4 timestamp) changed to `hwTimestampOrNow()`.

---

## Verification

To verify the fix is effective:

1. **Zero HW timestamp path**: Disable hardware timestamps on a test RNIC (or use a virtual RDMA device that does not support them). Before the fix, `rpingmesh.nwrtt` would immediately show only the `+Inf` bucket. After the fix, RTT values appear in normal microsecond-range buckets.

2. **EINTR path**: Send `SIGUSR1` (or `SIGURG`) to the agent process while probing is active. Before the fix, affected RNIC queues would permanently stop processing completions and all probes through them would time out. After the fix, a debug log line `"CQ poller: ibv_get_cq_event interrupted by signal (EINTR), retrying"` appears and probing continues uninterrupted.

3. **Long-run stability**: Run the agent for an extended period (hours to days). Before the fix, links would gradually disconnect as Go runtime `SIGURG` signals (sent for goroutine preemption) eventually interrupted a CQ poller at the wrong moment. After the fix, all links remain stable.
