# Agent探测流程详解：T1-T6概念与双向探测

## 📌 T1-T6 时间戳概念详解

T1-T6 是 R-Pingmesh 中用于精确测量网络往返时间(RTT)和端到端延迟的6个关键时间戳点。每个时间戳代表探测过程中的一个特定时刻：

### 时间戳定义

| 时间戳 | 位置 | 含义 | 测量方式 | 精度 |
|--------|------|------|---------|------|
| **T1** | Prober应用层 | Probe包发送请求时间 | `time.Now()` (软件时钟) | 微秒级 |
| **T2** | Prober硬件层 | Probe包实际发送完成时间 | RNIC硬件CQE (Completion Queue Event) | **纳秒级** |
| **T3** | Responder硬件层 | Probe包接收时间 | 远端RNIC硬件CQE接收事件 | **纳秒级** |
| **T4** | Responder硬件层 | ACK包发送完成时间 | 远端RNIC硬件CQE发送事件 | **纳秒级** |
| **T5** | Prober硬件层 | ACK包接收时间 | 本地RNIC硬件CQE接收事件 | **纳秒级** |
| **T6** | Prober应用层 | 两个ACK处理完成时间 | `time.Now()` (软件时钟) | 微秒级 |

### 关键设计点

1. **硬件时间戳 (T2, T3, T4, T5)**: 由RNIC硬件直接记录，精度达到纳秒级，用于精确的网络RTT测量
2. **软件时间戳 (T1, T6)**: 用于计算应用层处理延迟
3. **T3和T4的传递**: 这两个时间戳在远端Responder测量，通过ACK包携带回Prober

## 🔄 两个Agent之间的探测流程

### 场景设置
- **Agent A (Host A)**: 作为Prober，主动发送探测包
- **Agent B (Host B)**: 作为Responder，接收探测包并回复ACK

### 完整探测时序图

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Agent A (Prober)                             │
└─────────────────────────────────────────────────────────────────────┘

T1: [应用层] time.Now() → 记录发送请求时间
    ↓
    调用 SendProbePacket()
    ↓
T2: [硬件层] RNIC CQE发送完成 → 记录硬件时间戳
    ↓
    ┌───────────────────────────────────────────────────────────────┐
    │          Probe包通过网络传输 (RoCE Fabric)                      │
    └───────────────────────────────────────────────────────────────┘
    ↓

┌─────────────────────────────────────────────────────────────────────┐
│                        Agent B (Responder)                          │
└─────────────────────────────────────────────────────────────────────┘

T3: [硬件层] RNIC CQE接收完成 → 记录接收时间戳
    ↓
    [应用层] 处理Probe包
    ↓
    [硬件层] 发送第一个ACK包 (AckType=1, 携带T3)
    ↓
T4: [硬件层] RNIC CQE发送完成 → 记录ACK发送时间戳
    ↓
    [硬件层] 发送第二个ACK包 (AckType=2, 携带T3和T4)
    ↓
    ┌───────────────────────────────────────────────────────────────┐
    │          两个ACK包通过网络传输 (RoCE Fabric)                   │
    └───────────────────────────────────────────────────────────────┘
    ↓

┌─────────────────────────────────────────────────────────────────────┐
│                        Agent A (Prober)                             │
└─────────────────────────────────────────────────────────────────────┘

T5: [硬件层] RNIC CQE接收完成 → 记录第一个到达的ACK时间戳
    ↓
    [应用层] 等待两个ACK都到达
    ↓
T6: [应用层] time.Now() → 两个ACK都处理完成
    ↓
    计算指标:
    - Network RTT = (T5-T2) - (T4-T3)
    - Prober Delay = (T6-T1) - (T5-T2)
    - Responder Delay = T4-T3
```

### 为什么需要两个ACK包？

1. **ACK1 (AckType=1)**: 立即发送，携带T3时间戳（接收时间），用于快速响应
2. **ACK2 (AckType=2)**: 延迟发送，携带T3和T4时间戳（接收和发送时间），用于计算Responder处理延迟

这样可以区分：
- **网络延迟** (纯网络传输时间)
- **Responder处理延迟** (Agent B处理probe包的时间)

## 📊 Agent最终采集到的指标

### 1. 时间戳指标 (6个)

每个成功的probe都会记录所有6个时间戳：

```go
ProbeResult {
    T1: timestamp,  // Prober应用层发送时间
    T2: timestamp,    // Prober硬件层发送完成时间
    T3: timestamp,   // Responder硬件层接收时间 (从ACK1中提取)
    T4: timestamp,    // Responder硬件层ACK发送时间 (从ACK2中提取)
    T5: timestamp,   // Prober硬件层ACK接收时间
    T6: timestamp,   // Prober应用层处理完成时间
}
```

### 2. 计算指标 (3个)

基于时间戳计算出的核心性能指标：

| 指标名称 | 计算公式 | 含义 | 单位 |
|---------|---------|------|------|
| **Network RTT** | `(T5 - T2) - (T4 - T3)` | 纯网络往返时间，排除了Responder处理延迟 | 纳秒 |
| **Prober Delay** | `(T6 - T1) - (T5 - T2)` | Agent A应用层处理延迟 | 纳秒 |
| **Responder Delay** | `T4 - T3` | Agent B处理probe包的时间 | 纳秒 |

### 3. 状态指标 (1个)

```go
ProbeStatus {
    OK = 0,        // 成功收到两个ACK，所有时间戳完整
    TIMEOUT = 1,   // 超时未收到ACK
    ERROR = 2,     // 发送失败或错误
    UNKNOWN = 3,   // 未知状态
}
```

### 4. 元数据指标

#### 5元组信息 (用于ECMP和路径识别)
```go
FiveTuple {
    SrcGid: "fe80::1:2:3:4",      // Agent A的RNIC GID
    SrcQpn: 1025,                  // Agent A的Queue Pair号
    DstGid: "fe80::5:6:7:8",      // Agent B的RNIC GID
    DstQpn: 1026,                  // Agent B的Queue Pair号
    FlowLabel: 12345,             // 流量标签 (用于ECMP)
}
```

#### RNIC标识信息
```go
SourceRnic {
    Gid: "fe80::1:2:3:4",
    Qpn: 1025,
    IpAddress: "10.1.1.10",
    HostName: "host-a",
    TorId: "tor-switch-1",
    DeviceName: "mlx5_0",
}

DestinationRnic {
    Gid: "fe80::5:6:7:8",
    Qpn: 1026,
    IpAddress: "10.1.1.20",
    HostName: "host-b",
    TorId: "tor-switch-2",
    DeviceName: "mlx5_1",
}
```

#### Probe类型
```go
ProbeType: "TOR_MESH" | "INTER_TOR" | "SERVICE"
```

### 5. 路径追踪指标 (可选)

如果启用了traceroute功能：

```go
PathInfo {
    FiveTuple: {...},              // 对应的5元组
    Hops: [
        {IpAddress: "10.1.1.1", RttNs: 100000},  // 第一跳
        {IpAddress: "10.1.1.2", RttNs: 200000},  // 第二跳
        ...
    ],
    Timestamp: timestamp,
}
```

## 🔄 双向探测机制

### 场景1: Agent A探测Agent B

```
Agent A (Prober) → Probe包 → Agent B (Responder)
Agent B (Responder) → ACK1 + ACK2 → Agent A (Prober)

结果: Agent A获得从A到B的网络RTT和Agent B的处理延迟
```

### 场景2: Agent B探测Agent A

```
Agent B (Prober) → Probe包 → Agent A (Responder)
Agent A (Responder) → ACK1 + ACK2 → Agent B (Prober)

结果: Agent B获得从B到A的网络RTT和Agent A的处理延迟
```

### 关键点

1. **每个Agent同时充当Prober和Responder**:
   - 作为Prober时：主动探测其他Agent，收集网络RTT
   - 作为Responder时：被动响应其他Agent的探测，在ACK中携带自己的时间戳

2. **对称性测量**:
   - A→B和B→A的路径可能不同（ECMP）
   - 两个方向可以分别测量，识别单向网络问题

3. **Controller协调**:
   - Controller生成pinglist，决定每个Agent应该探测哪些目标
   - 确保足够的覆盖度（ToR-mesh, Inter-ToR）

## 📈 指标输出方式

### 方式1: OpenTelemetry Metrics (实时)

通过OTLP协议导出到OpenTelemetry Collector (端口4317):

```go
// 每10秒批量导出
Metrics {
    rpingmesh.nwrtt (Gauge + Histogram)          // Network RTT
    rpingmesh.prober_delay (Gauge + Histogram)    // Prober Delay
    rpingmesh.responder_delay (Gauge + Histogram)  // Responder Delay
    rpingmesh.timeout (Counter)                   // Timeout计数
}
```

**Attributes** (标签):
- `src_agent_id`, `dst_agent_id`
- `src_hostname`, `dst_hostname`
- `src_gid`, `dst_gid`
- `src_device_name`, `dst_device_name`
- `probe_type`

### 方式2: Analyzer数据上传 (批量)

通过gRPC上传到Analyzer (端口50052):

```go
UploadDataRequest {
    AgentId: "agent-host-a",
    ProbeResults: [ProbeResult1, ProbeResult2, ...],  // 批量结果
    PathInfos: [PathInfo1, PathInfo2, ...],             // 路径信息
}
```

**上传间隔**: 默认10秒，可配置
**批量大小**: 可配置

## 💡 实际测量示例

假设Agent A探测Agent B的一次完整流程：

```
时间轴:
T1: 1000000000 ns (1秒) - Agent A发送请求
T2: 1000000500 ns - Agent A硬件发送完成 (+500ns)
    [网络传输: 10微秒]
T3: 1000100000 ns - Agent B硬件接收完成
    [Agent B处理: 2微秒]
T4: 1000102000 ns - Agent B硬件ACK发送完成
    [网络传输: 10微秒]
T5: 1000202000 ns - Agent A硬件ACK接收完成
    [Agent A处理: 1微秒]
T6: 1000203000 ns - Agent A处理完成

计算结果:
Network RTT = (T5-T2) - (T4-T3)
            = (1000202000 - 1000000500) - (1000102000 - 1000100000)
            = 201500 - 2000
            = 199500 ns = 199.5 微秒

Prober Delay = (T6-T1) - (T5-T2)
             = (1000203000 - 1000000000) - 201500
             = 203000 - 201500
             = 1500 ns = 1.5 微秒

Responder Delay = T4 - T3
                = 1000102000 - 1000100000
                = 2000 ns = 2 微秒
```

## ⚠️ 注意事项

1. **时间戳同步**: T3和T4在远端Agent B测量，需要通过ACK包传递。如果ACK丢失，无法计算Network RTT

2. **两个ACK必须都收到**: Prober会等待两个ACK包（ACK1和ACK2），如果任何一个丢失，会标记为TIMEOUT

3. **时钟偏差**: 虽然使用硬件时间戳精度高，但如果两个Agent的系统时钟不同步，T3和T4的绝对时间可能不准确，但**差值计算不受影响**（因为Network RTT = (T5-T2) - (T4-T3)，时钟偏差会抵消）

4. **失败情况**:
   - 如果probe包发送失败 → Status = ERROR，只有T1可能有值
   - 如果ACK超时 → Status = TIMEOUT，T1-T2可能有值，但T3-T6缺失
   - 如果收到ACK但时间戳不完整 → 可能无法计算Network RTT，但会记录其他可用指标
