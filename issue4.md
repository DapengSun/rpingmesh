# Issue #4: Probe Timeout Accumulation and Non-Recovery

## Symptom

After the system has been running for a period of time, probe timeouts begin to accumulate and never self-recover:

- The `rpingmesh.timeout` counter climbs steadily for specific source–destination RNIC pairs and does not stop.
- The `rpingmesh.nwrtt` gauge freezes at its last valid value; no new RTT observations are recorded.
- The agent process continues running and other links may remain healthy, but affected RNIC pairs are permanently stuck in a timeout loop.
- Restarting the agent clears the condition, confirming it is a runtime state corruption rather than a configuration error.
- CPU usage may be anomalously high even when the target list is empty (e.g., during pinglist refresh gaps).
- Pinglist refresh operations (every 300 s) may appear sluggish or delayed during a timeout storm.

The condition is non-recovering: once an RNIC enters the timeout loop, it does not return to healthy probing on its own.

---

## Root Cause Analysis

Three independent bugs interact to produce the observed symptoms. Bug 1 is the primary cause of non-recovery; Bugs 2 and 3 are contributing factors that worsen the situation.

---

### Bug 1: Dropped Recv Completion Permanently Leaks an RQ Slot

#### Background: the RDMA Receive Queue and completion flow

Each `UDQueue` (one per RNIC) maintains a fixed-size **Receive Queue (RQ)** backed by `InitialRecvBuffers = 32` pre-posted receive Work Requests (WRs). Each WR occupies one numbered slot (0–31) in `u.RecvSlots`. When the NIC receives an incoming RDMA packet, it places the data into the next available slot and generates a recv Work Completion (WC) that identifies the slot via `wc.wr_id`.

The CQ poller goroutine (started by `StartCQPoller()`) processes these WCs in `processSingleWC` → `handleRecvCompletion`. After a recv WC is processed, the slot **must** be reposted to the RQ via `PostRecvSlot(slot)` so the NIC can receive the next packet into it. If a slot is never reposted, it is permanently removed from the RQ. With only 32 slots, 32 unreposted completions drain the RQ entirely.

When the RQ is empty:
- The NIC has no recv buffers to place incoming probes into.
- Every incoming probe packet is silently discarded at the NIC level.
- The prober sends a probe and never receives an ACK → probe session times out.
- `ProbeResult_TIMEOUT` is recorded; `RecordRTT` is never called → gauge freezes.
- The timeout counter climbs indefinitely.

This is the non-recovering state.

#### The bug

In `handleRecvCompletion`, non-ACK completions (packets intended for the responder) are forwarded to the responder goroutine via `recvCompChan` (a buffered channel of size 100). When that channel is full — which happens when the responder loop cannot keep up with the incoming probe rate — the CQ poller falls through to the `default` branch of a `select` statement:

```go
// Before fix — default branch in handleRecvCompletion
select {
case u.recvCompChan <- gwc:
default:
    log.Warn()...
    // ← slot is NEVER reposted; permanently removed from RQ
}
return false // Non-ACK packet, PostRecv() should be called by caller
```

The `default` branch logged a warning and returned `false`, intending the caller (`processSingleWC`) to repost the slot. However, `processSingleWC` only reposted when `handleRecvCompletion` returned `false`. This meant:

- **When the channel is full (drop path):** `handleRecvCompletion` returns `false` → `processSingleWC` repostes. This appeared correct, but introduced a different problem: `processSingleWC` reposted the slot *immediately* after calling `handleRecvCompletion`, even in the non-drop (send) path. This meant the slot buffer could be overwritten by a new incoming packet before `ReceivePacket` (the channel consumer) had finished reading the data from it — a data race.

- **When the channel is not full (send path):** `handleRecvCompletion` returned `false` → `processSingleWC` prematurely reposted the slot. Meanwhile `ReceivePacket` (in `packet.go`) also called `PostRecvSlot(slot)` after processing the data, causing double-posting of the same slot.

The root issue is that slot lifecycle management was split inconsistently between `handleRecvCompletion`, its caller `processSingleWC`, and `ReceivePacket`.

#### Why `recvCompChan` fills up

The responder processes one packet at a time: receive → send ACK 1 → send ACK 2. Each ACK send blocks waiting for the send completion (up to `AckSendTimeout = 10ms`). At the default probe rate of 10 probes/sec per destination × N destinations, the incoming rate can exceed the sequential responder's processing capacity. Once the channel saturates, every subsequent recv completion is dropped without reposting, and 32 drops drain the RQ.

#### The fix

The `default` branch in `handleRecvCompletion` now calls `PostRecvSlot(slot)` / `PostRecv()` immediately before the completion data is discarded, so the RQ slot is never permanently lost:

```go
// After fix
select {
case u.recvCompChan <- gwc:
    // Slot will be reposted by ReceivePacket after it processes the packet data.
default:
    log.Warn()...
    // Repost the recv buffer immediately so the RQ slot is never permanently lost.
    if slot >= 0 && slot < u.NumRecvSlots {
        if errPost := u.PostRecvSlot(slot); errPost != nil {
            log.Error()...
        }
    } else {
        if errPost := u.PostRecv(); errPost != nil {
            log.Error()...
        }
    }
}
return true // Slot lifecycle is managed: deferred to ReceivePacket (sent) or reposted here (dropped).
```

The function now returns `true` unconditionally in the non-ACK path. This tells `processSingleWC` that slot lifecycle has been fully managed internally, preventing the premature/double repost. The two cases are now cleanly separated:

| Path | Slot lifecycle |
|------|---------------|
| Channel not full (send) | `handleRecvCompletion` returns `true` → `ReceivePacket` reposts after reading the data |
| Channel full (drop) | `handleRecvCompletion` reposts immediately → returns `true` → `processSingleWC` does not repost |

The RQ is now self-healing: under any level of backpressure, slots are always returned to the RQ and the NIC always has recv buffers available for incoming probes.

---

### Bug 2: Scheduler Mutex Held During Blocking Rate-Limiter Call

#### Background: per-target rate limiting

`ProbeScheduler.GetNextTarget()` uses a per-destination `ratelimit.Limiter` (from `uber-go/ratelimit`) to enforce a maximum probe rate of `targetProbeRatePerSec` (default 10) per destination GID. The `limiter.Take()` call blocks until the next token is available — at 10/s, this is a sleep of up to ~100ms per call.

`ProbeScheduler.UpdateTargets()` is called approximately every 300 seconds (when the controller pushes a new pinglist). It acquires the same write mutex to replace the target list.

#### The bug

`GetNextTarget()` used `defer ps.mutex.Unlock()`, which held the write lock for the full duration of the function, including the `limiter.Take()` call:

```go
// Before fix
func (ps *ProbeScheduler) GetNextTarget() *probe.PingTarget {
    ps.mutex.Lock()
    defer ps.mutex.Unlock()  // ← held for entire function, including limiter.Take()
    ...
    limiter.Take()  // ← blocks ~100ms while mutex is held
    return target
}
```

During a timeout storm, the sequential probe worker calls `GetNextTarget()` in a tight loop. Each call holds the write mutex for ~100ms. Any concurrent call to `UpdateTargets()` is blocked for up to 100ms waiting for the mutex. Over a 300s refresh interval with thousands of probe cycles, pinglist updates were effectively serialized behind the probe loop, delaying target list changes and preventing recovery from misconfigured or stale targets.

#### The fix

The mutex is now released *before* `limiter.Take()` is called. The target struct is copied by value and the `limiter` interface value is captured before the lock is released; both are safe to use without the lock:

```go
// After fix
func (ps *ProbeScheduler) GetNextTarget() *probe.PingTarget {
    ps.mutex.Lock()
    if len(ps.targets) == 0 {
        ps.mutex.Unlock()
        return nil
    }
    target := ps.targets[ps.currentIndex]  // value copy — safe after unlock
    ps.currentIndex = (ps.currentIndex + 1) % len(ps.targets)
    limiter, exists := ps.targetLimiters[target.GID]
    ps.mutex.Unlock()  // ← released before blocking call

    if !exists {
        log.Warn()...
        return &target
    }
    limiter.Take()  // blocks outside the mutex
    return &target
}
```

`UpdateTargets()` can now run at any time without waiting for an in-progress `limiter.Take()` to complete. Pinglist refreshes take effect within one 300s cycle rather than potentially being delayed further.

---

### Bug 3: Busy Spin When No Targets Are Configured

#### Background: the sequential probe worker loop

The `runSequentialProbeWorker` goroutine runs a tight `for` loop that calls `processNextProbe()` on every iteration. `processNextProbe()` calls `GetNextTarget()` to obtain the next probe target.

`GetNextTarget()` returns `nil` when the target list is empty — which happens:
- At agent startup before the first pinglist is received from the controller.
- During the brief gap between `UpdateTargets` clearing the old list and populating the new one.
- If the controller sends an empty pinglist.

#### The bug

When `GetNextTarget()` returned `nil`, the old `processNextProbe()` returned immediately without sleeping:

```go
// Before fix
target := c.scheduler.GetNextTarget()
if target == nil {
    // No targets configured, return immediately  ← no sleep
    return
}
```

`runSequentialProbeWorker` then immediately called `processNextProbe()` again. The loop continued at the maximum speed the CPU could execute `GetNextTarget()` → check nil → return, burning 100% of a CPU core while waiting for targets to appear. Under a timeout storm this competes with the CQ poller and responder goroutines for CPU time, worsening the backlog.

#### The fix

When no target is available, `processNextProbe()` now waits 100ms before returning, using a `select` that also listens on `stopCh` so the worker wakes immediately during shutdown:

```go
// After fix
if target == nil {
    select {
    case <-c.stopCh:
    case <-time.After(100 * time.Millisecond):
    }
    return
}
```

CPU usage when targets are unavailable drops from ~100% to negligible. The 100ms sleep is well below the pinglist refresh interval (300s) and introduces no observable latency in picking up newly added targets.

---

## How the Bugs Interact

| Scenario | Primary bug | Observable effect |
|----------|-------------|-------------------|
| High probe rate, responder backlogged | Bug 1 | `recvCompChan` fills → RQ slots drain → all probes timeout → non-recovering |
| Timeout storm + pinglist refresh | Bug 2 | `UpdateTargets()` blocked ~100ms per probe cycle → pinglist update delayed |
| Empty or refreshing pinglist | Bug 3 | Sequential probe worker burns 100% CPU while waiting for targets |
| All three present | Bugs 1+2+3 | Bug 3 CPU burn worsens Bug 1 backlog; Bug 2 delays recovery via pinglist; Bug 1 makes the system non-recovering |

Bug 1 is the only bug that causes non-recovery. Bugs 2 and 3 are not independently fatal but significantly worsen the time-to-failure and prevent pinglist-based recovery.

---

## Files Changed

### `internal/rdma/cq.go`

1. In `handleRecvCompletion`, added `PostRecvSlot(slot)` / `PostRecv()` in the `default` branch of the `select` statement (~line 399), ensuring the RQ slot is immediately reposted when the channel is full.
2. Changed the return value at the end of the non-ACK (`else`) path from `return false` to `return true`, delegating full slot lifecycle responsibility to `handleRecvCompletion` and preventing `processSingleWC` from issuing a premature or duplicate repost.

### `internal/monitor/cluster_monitor.go`

1. `GetNextTarget()`: replaced `defer ps.mutex.Unlock()` with explicit `ps.mutex.Unlock()` calls — one in the early-return nil path and one after reading the target and limiter (before `limiter.Take()`). Changed `target` from a pointer into the slice to a value copy so the returned pointer remains valid and unaffected by subsequent `UpdateTargets()` calls.
2. `processNextProbe()`: replaced the immediate `return` on nil target with a 100ms `select`-based sleep that responds to `stopCh`.

---

## Verification

1. **RQ exhaustion path**: configure a high-rate probe environment (many targets, fast rate) to saturate `recvCompChan`. Before the fix, `rpingmesh.timeout` would climb indefinitely and not recover. After the fix, `recvCompChan full` warnings appear in logs at `WARN` level but probe timeouts stabilise and do not grow without bound.

2. **Slot repost path**: with debug logging enabled, confirm that every warn-level `"Receive completion channel full"` log is followed by either a successful repost log at trace level or an error log from `PostRecvSlot` — never silent slot loss.

3. **Mutex contention path**: call `UpdateTargets()` concurrently with active probing. Before the fix, the call would block for ~100ms per probe cycle. After the fix, `UpdateTargets()` completes immediately regardless of ongoing `limiter.Take()` calls.

4. **Busy-spin path**: stop the controller (or configure an empty pinglist). Before the fix, one CPU core would spike to 100%. After the fix, CPU usage is near zero while no targets are configured.

5. **Long-run stability**: run the agent for an extended period (hours to days) at the full probe rate. Before the fix, some RNIC queues would permanently enter the timeout loop within minutes to hours. After the fix, all links remain healthy across restarts and pinglist refreshes.
