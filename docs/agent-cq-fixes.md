# Agent CQ 问题修复记录

## 背景

rpingmesh Agent 在运行过程中出现两类 Grafana 可见异常：

1. **RTT 曲线出现 `+Inf` 桶**：Prometheus histogram 中 RTT 值达到 56 年级别（Unix epoch）
2. **RTT 曲线周期性消失（采集断连）**：某段时间内某条链路的数据完全缺失
3. **探测超时**：Prober 报告 `ack1Received=true, ack2Received=false`，Responder 报告 `Failed to send first/second ACK packet`

---

## 已修复的问题

### Fix 1：`sendCompChan` 竞争条件（T1→T2 阶段）

**根因**

原始实现中所有并发的 `SendProbePacket` goroutine 共用一个 `sendCompChan`。NIC 返回 CQE 后，CQ Poller 把 WC 投递到这个共享 channel，但任意一个等待的 goroutine 都可能消费到不属于自己的 WC，导致：

- 错误 goroutine 拿到了别人的 T2 时间戳（RTT 计算错误）
- 正确的 goroutine 永远等不到自己的 WC（context timeout，探测失败）

**修复**

引入 `pendingSendChans sync.Map`，每次 `post_send` 前为该 WR-ID 注册一个独占的 `chan *GoWorkCompletion`（buffer=1），CQ Poller 用 `LoadAndDelete` 把 WC 精确投递给对应的等待方。

**关键代码位置**：`internal/rdma/cq.go` `handleSendCompletion`、`internal/rdma/packet.go` `SendProbePacket`

---

### Fix 2：`pendingSendChans` 注册时序竞争

**根因**

原实现先 `post_send`，再 `pendingSendChans.Store(wrid, ch)`。在快速 NIC 上，CQE 可能在 `post_send` 返回后、`Store` 执行前就已到达，CQ Poller 找不到注册的 channel，fallback 到 `sendCompChan`，原调用方永远等不到响应。

**修复**

将 `pendingSendChans.Store` 移到 `post_send` **之前**。若 `post_send` 失败，立即 `Delete` 已注册的 entry 以防内存泄漏。

适用函数：`SendProbePacket`、`SendFirstAckPacket`、`SendSecondAckPacket`

---

### Fix 3：零 HW 时间戳导致 `+Inf` RTT

**根因**

当 NIC 不支持 `IBV_WC_EX_WITH_COMPLETION_TIMESTAMP_WALLCLOCK` 或时间戳未就绪时，`CompletionWallclockNS == 0`。原代码直接 `time.Unix(0, 0)` 得到 Unix epoch（1970年），与当前时间的差值约 56 年，写入 Prometheus histogram 后全部落入 `+Inf` 桶。

**修复**

在 `internal/rdma/cq.go` 引入辅助函数：

```go
func hwTimestampOrNow(wallclockNS uint64) time.Time {
    if wallclockNS == 0 {
        return time.Now()
    }
    return time.Unix(0, int64(wallclockNS))
}
```

所有 HW 时间戳转换统一使用此函数（`T2`、`T3`、`T4`、`ReceivedAt`）。

---

### Fix 4：`EINTR` 导致 CQ Poller 退出（采集断连）

**根因**

Go runtime 会向 goroutine 所在的 OS thread 发送 `SIGURG` 信号（用于 goroutine 抢占）。`ibv_get_cq_event` 内部调用 `read(2)` 阻塞等待 eventfd，收到信号后 `read` 返回 `EINTR`（errno=4）。原代码把这个错误当作 fatal 错误处理，导致 CQ Poller goroutine 退出，该链路的所有收发操作永久挂起，Grafana 上表现为 RTT 曲线消失。

**修复**

在 `ibv_get_cq_event` 失败分支中检测 `errno == EINTR`，遇到时 `continue` 重试而不退出：

```go
errNo := syscall.Errno(C.get_errno())
if errNo == syscall.EINTR {
    log.Debug().Msg("CQ poller: ibv_get_cq_event interrupted by signal (EINTR), retrying")
    continue
}
```

**关键代码位置**：`internal/rdma/cq.go` `StartCQPoller`

---

### Fix 5：ACK Send Timeout 误触发（`ack1Received=true, ack2Received=false`）

#### 5a：WRID 复用导致 stale completion 污染

**根因**

原代码用 `sendWRID = slot + numRecvSlots` 作为 WR-ID。`NumSendSlots = 32`，当某次 ACK send 超时后，`pendingSendChans[wrid]` 中的 stale entry 留存。若后续 32 次 send 将所有 slot 轮完重新用到 slot 0，新的 `Store` 会覆盖旧 entry，stale CQE 被投递到新 channel，新 send 收到错误 WC。

**修复**

在 `UDQueue` 中添加 `nextSendWRID uint64`（原子计数器），所有 send 操作改用 `atomic.AddUint64(&u.nextSendWRID, 1)` 生成全局唯一 WRID。slot 仍用于 buffer 管理，WRID 与 slot 解耦。

**关键代码位置**：`internal/rdma/queue.go` `UDQueue` 结构体，`internal/rdma/packet.go` 三个 Send 函数

#### 5b：`AckSendTimeout` 过小导致误超时

**根因**

`AckSendTimeout = 10ms`。NIC 完成 ACK send 的时间 < 1μs，但 CQE 经由 **event-driven CQ Poller goroutine** 传递（`ibv_get_cq_event` 阻塞 → 内核唤醒 → Go scheduler 调度），偶发抖动 > 10ms 时超时触发。超时后 Responder 返回 error，跳过 `SendSecondAckPacket`，导致 Prober 只收到 ACK1，等待 ACK2 直到 probe timeout。

**修复（临时方案）**

将 `AckSendTimeout` 从 `10ms` 调整到 `500ms`，确保正常调度抖动范围内都能拿到真实 HW timestamp：

```go
// internal/rdma/packet.go
AckSendTimeout = 500 * time.Millisecond
```

> ⚠️ **这是临时缓解措施，不是根本修复**，详见下方「当前无法优化的困境」。

---

## 当前无法再优化的困境

### 问题描述

Fix 5b 仅通过放宽超时值来缓解问题，**根本原因未消除**：

```
post_send ACK1 → NIC 完成发包（< 1μs）→ 写入 CompChannel eventfd
    ↓
内核把 CQ Poller 线程从 epoll_wait / read() 唤醒
    ↓  ← 抖动来源（内核调度 + Go goroutine 调度，偶发 > 10ms）
Go runtime 把 CQ Poller goroutine 分配到 OS thread
    ↓
ibv_start_poll → 找到 CQE → 通过 pendingSendChans 投递给 Responder goroutine
```

整个 Send 侧 T4 时间戳的获取路径需要经过**两层调度器**（OS 内核 + Go runtime），而这两者的抖动在系统负载下无法保证。放大超时只是让超时更难被触发，但：

1. 调度延迟仍然存在，T4 时间戳的记录点（`hwTimestampOrNow` 返回时刻）仍然可能偏移
2. 极端负载下超时依然可能发生
3. 更本质的问题：**event-driven polling 本身就是为吞吐量设计的，不适合微秒级延迟测量场景**

### 技术约束

在当前架构下（单一 CQ，event-driven CQ Poller goroutine）无法进一步优化，因为：

- `ibv_get_cq_event` 是阻塞 syscall，唤醒延迟由 OS 决定，Go 层无法控制
- CQ Poller goroutine 与 Responder goroutine 是独立的，它们之间的通信本身引入了额外的调度点
- `ibv_start_poll`/`ibv_next_poll`/`ibv_end_poll` 不是线程安全的，不能从 Responder goroutine 直接并发访问同一个 CQ

---

## 根本修复计划：拆分 Send/Recv CQ，Send 侧改为 Inline Busy-Poll

### 设计思路

将 Send CQ 与 Recv CQ 彻底分离，ACK send 完成后在**调用方 goroutine 内直接 spin-poll** Send CQ，完全绕过内核通知路径和 Go 调度器：

```
当前架构（一个 CQ，event-driven）：
  Recv CQ = Send CQ = u.CQ
       ↓ 统一走 CQ Poller goroutine
  ibv_get_cq_event → 内核唤醒 → Go 调度 → 抖动

目标架构（两个 CQ）：
  Recv CQ（带 CompChannel）→ CQ Poller goroutine（event-driven，OK）
  Send CQ（无 CompChannel）→ 调用方 goroutine inline spin-poll（无调度，< 1μs）
```

### 改动计划

#### 1. `internal/rdma/queue.go`

- `UDQueue` 新增字段 `SendCQ *C.struct_ibv_cq_ex`
- `createQueuePair` 中创建两个 CQ：
  - `recvCQ`：带 `CompChannel`，用于接收完成通知（event-driven）
  - `sendCQ`：不带 `CompChannel`，纯轮询使用
- QP 初始化改为 `send_cq = sendCQ, recv_cq = recvCQ`（当前两者指向同一个 CQ）
- `Destroy` 增加对 `SendCQ` 的销毁
- 移除 `sendCompChan`、`pendingSendChans` 字段（Send 侧不再需要 channel 通信）

#### 2. `internal/rdma/cq.go`

- CQ Poller 只监听 `u.CQ`（即 Recv CQ），移除 `handleSendCompletion`
- 删除 `handleSendCompletion` 中对 `pendingSendChans` 的处理逻辑
- `waitForSendCompletion` / `waitForSendCompletionCtx` 可全部移除

#### 3. `internal/rdma/packet.go`

- 新增 `pollSendCQ` 辅助函数，在调用方 goroutine 里直接对 `u.SendCQ` 做 spin-poll：

  ```go
  // 伪代码
  func (u *UDQueue) pollSendCQ(wrid uint64, ctx context.Context) (*GoWorkCompletion, error) {
      var attr C.struct_ibv_poll_cq_attr
      for {
          if ret := C.ibv_start_poll(u.SendCQ, &attr); ret == 0 {
              gwc := extractWC(u.SendCQ)
              C.ibv_end_poll(u.SendCQ)
              if gwc.WRID == wrid {
                  return gwc, nil
              }
          }
          select {
          case <-ctx.Done():
              return nil, ctx.Err()
          default:
              runtime.Gosched() // 避免 100% CPU，但绝大多数情况下下一次 poll 即可找到 CQE
          }
      }
  }
  ```

- `SendFirstAckPacket`、`SendSecondAckPacket`、`SendProbePacket`：`post_send` 后改调 `pollSendCQ`，不再使用 channel 等待
- 移除 `AckSendTimeout` 常量，改为由 context deadline 控制超时
- 移除 `pendingSendChans.Store` 相关代码

### 预期效果

| 指标 | 当前（event-driven） | 改造后（inline poll） |
|---|---|---|
| CQE 传递延迟 | 受内核+Go调度，0.1ms ~ 10ms+ | NIC 完成即可读取，< 1μs |
| T4 时间戳准确性 | 偶发抖动导致偏移 | 准确，仅受 NIC HW 时钟精度影响 |
| `AckSendTimeout` 误触发 | 偶发（约 0.006%） | 消除 |
| CPU 开销 | 低（阻塞等待） | 轻微增加（poll 循环，< 1μs 即退出） |
| 代码复杂度 | `pendingSendChans` + channel | 直接 poll，逻辑更简单 |

### 并发安全注意事项

- `ibv_start_poll`/`ibv_end_poll` 不是线程安全的，同一 CQ 不能被多个 goroutine 并发调用
- Responder 队列：单 goroutine 顺序处理，无并发，安全
- Sender 队列（Prober）：多个 probe goroutine 并发调用 `SendProbePacket`，需在 `pollSendCQ` 内加 mutex 序列化对 `u.SendCQ` 的访问（或为 Sender 也改用 event-driven，仅 Responder 改为 inline poll）
