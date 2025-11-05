# Agent数据指标采集分析

根据代码和README描述，以下表格详细说明了Agent可以采集到的数据指标、采集状态、数据流程和输出方式。

## 数据指标采集完整分析表

| 指标类别 | 指标名称 | 指标类型 | 是否可采集 | 采集条件/限制 | 数据来源 | 主要数据流程 | 输出方式 |
|---------|---------|---------|-----------|--------------|---------|------------|---------|
| **时间戳指标** | T1 (Probe Post Time) | Timestamp | ✅ 可以采集 | 需要成功发送probe包 | Application层 `time.Now()` | **Prober流程**: T1 → post send → T2 | 上传到Analyzer (ProbeResult) |
| | T2 (Prober CQE Send) | Timestamp | ✅ 可以采集 | CQE发送完成事件成功 | RNIC硬件CQE事件 | **RDMA层**: post send → **CQE** → T2 | 上传到Analyzer (ProbeResult) |
| | T3 (Responder Receive) | Timestamp | ✅ 可以采集 | 需要收到第一个ACK包且AckType=1 | 远端Responder的CQE接收时间戳 | **Responder流程**: 接收probe → CQE → T3 (在ACK包中携带) | 上传到Analyzer (ProbeResult) |
| | T4 (Responder ACK Send) | Timestamp | ✅ 可以采集 | 需要收到第二个ACK包且AckType=2 | 远端Responder的CQE发送时间戳 | **Responder流程**: 处理probe → post ACK → CQE → T4 (在ACK包中携带) | 上传到Analyzer (ProbeResult) |
| | T5 (Prober ACK Receive) | Timestamp | ✅ 可以采集 | 需要收到任意一个ACK包 | RNIC硬件CQE事件 | **RDMA层**: ACK到达 → **CQE** → T5 | 上传到Analyzer (ProbeResult) |
| | T6 (Prober Poll Complete) | Timestamp | ✅ 可以采集 | 需要两个ACK都收到 | Application层 `time.Now()` | **Prober流程**: 收到两个ACK → 处理完成 → T6 | 上传到Analyzer (ProbeResult) |
| **计算指标** | Network RTT | 计算值 (ns) | ✅ 可以采集 | 需要T2, T3, T4, T5都存在 | 公式: `(T5-T2) - (T4-T3)` | **Prober**: 收集所有时间戳 → 计算Network RTT | 1. OpenTelemetry Metrics (Gauge + Histogram)<br/>2. 上传到Analyzer (ProbeResult) |
| | Prober Delay | 计算值 (ns) | ✅ 可以采集 | 需要T1, T2, T5, T6都存在 | 公式: `(T6-T1) - (T5-T2)` | **Prober**: T1→T6总时间减去网络时间 → 计算处理延迟 | 1. OpenTelemetry Metrics (Gauge + Histogram)<br/>2. 上传到Analyzer (ProbeResult) |
| | Responder Delay | 计算值 (ns) | ✅ 可以采集 | 需要T3, T4都存在 | 公式: `T4 - T3` | **Responder**: 接收处理时间 → T4-T3 | 1. OpenTelemetry Metrics (Gauge + Histogram)<br/>2. 上传到Analyzer (ProbeResult) |
| **状态指标** | Probe Status | 枚举值 | ✅ 可以采集 | 所有probe都有状态 | OK/TIMEOUT/ERROR/UNKNOWN | **Prober**: 根据probe结果判断状态 | 上传到Analyzer (ProbeResult) |
| | Timeout Count | Counter | ✅ 可以采集 | Status=TIMEOUT时记录 | 超时事件计数 | **Prober**: 检测超时 → 记录计数 | OpenTelemetry Metrics (Counter) |
| **网络拓扑指标** | Path Hops | 路径信息 | ✅ 可以采集 | 需要traceroute功能启用且目标可达 | traceroute/tracepath命令输出 | **Tracer**: 执行traceroute → 解析输出 → 提取hops | 上传到Analyzer (PathInfo) |
| | Hop RTT | RTT值 (ns) | ✅ 可以采集 | 需要traceroute成功且能解析RTT | traceroute每跳的RTT值 | **Tracer**: 解析traceroute输出 → 提取每跳RTT | 上传到Analyzer (PathInfo.Hop) |
| | Hop IP Address | IP地址 | ✅ 可以采集 | 需要traceroute成功且中间节点响应 | traceroute显示的IP地址 | **Tracer**: 解析traceroute输出 → 提取IP | 上传到Analyzer (PathInfo.Hop) |
| **5元组信息** | Source GID | 标识符 | ✅ 可以采集 | 总是可用 | Agent本地RNIC的GID | **Agent State**: 检测RNIC → 获取GID | 1. 上传到Analyzer (ProbeResult.FiveTuple)<br/>2. OpenTelemetry Attributes |
| | Source QPN | 标识符 | ✅ 可以采集 | 总是可用 | Agent分配的QP号码 | **RDMA Manager**: 创建QP → 分配QPN | 1. 上传到Analyzer (ProbeResult.FiveTuple)<br/>2. OpenTelemetry Attributes |
| | Destination GID | 标识符 | ✅ 可以采集 | 需要Controller提供目标RNIC信息 | Controller注册的RNIC GID | **Controller Client**: 查询目标RNIC → 获取GID | 1. 上传到Analyzer (ProbeResult.FiveTuple)<br/>2. OpenTelemetry Attributes |
| | Destination QPN | 标识符 | ✅ 可以采集 | 需要Controller提供目标RNIC信息 | Controller注册的RNIC QPN | **Controller Client**: 查询目标RNIC → 获取QPN | 1. 上传到Analyzer (ProbeResult.FiveTuple)<br/>2. OpenTelemetry Attributes |
| | Flow Label | 标识符 | ✅ 可以采集 | 总是可用 | Agent生成的流量标签 | **Prober**: 为每个probe生成flow label | 1. 上传到Analyzer (ProbeResult.FiveTuple)<br/>2. OpenTelemetry Attributes |
| **RNIC标识信息** | Source RNIC Info | 元数据 | ✅ 可以采集 | 总是可用 | Agent本地RNIC信息 | **Agent State**: 检测RNIC → 获取所有信息 | 上传到Analyzer (ProbeResult.SourceRnic) |
| | Destination RNIC Info | 元数据 | ✅ 可以采集 | 需要Controller提供 | Controller注册的RNIC信息 | **Controller Client**: 查询 → 获取目标信息 | 上传到Analyzer (ProbeResult.DestinationRnic) |
| **Probe类型** | Probe Type | 字符串 | ✅ 可以采集 | 总是可用 | TOR_MESH / INTER_TOR / SERVICE | **Monitor**: 根据pinglist类型确定 | 1. 上传到Analyzer (ProbeResult)<br/>2. OpenTelemetry Attributes |
| **统计数据** | Successful Probes | Counter | ⚠️ 部分采集 | 仅在代码内部统计，不对外暴露 | Prober内部atomic计数器 | **Prober**: 成功probe → 原子计数 | ❌ **不输出** (仅内部统计) |
| | Failed Probes | Counter | ⚠️ 部分采集 | 仅在代码内部统计，不对外暴露 | Prober内部atomic计数器 | **Prober**: 失败probe → 原子计数 | ❌ **不输出** (仅内部统计) |
| | Session Statistics | 统计数据 | ⚠️ 部分采集 | 仅在代码内部统计，不对外暴露 | Prober内部统计 | **Prober**: 会话管理 → 内部统计 | ❌ **不输出** (仅内部统计) |
| **Service Flow信息** | Service 5-tuple Discovery | eBPF事件 | ⚠️ 需要eBPF启用 | 需要eBPF功能启用且内核支持 | eBPF hooks modify_qp/destroy_qp | **eBPF Tracer**: 内核事件 → ring buffer → userspace | ✅ **可以采集** (用于Service Tracing，但不直接作为metrics) |
| **聚合统计** | Aggregated Local Statistics | 聚合数据 | ❌ 未实现 | README中提到但代码中未实现 | N/A | N/A | ❌ **未实现** (README中提到但代码中不存在) |

## 数据流程说明

### 1. Probe结果采集流程
```
Prober发送Probe包
    ↓
[T1] Application post time (time.Now())
    ↓
Post to RDMA UD Queue
    ↓
[T2] CQE send completion (硬件时间戳)
    ↓
Probe包通过网络传输
    ↓
Responder接收Probe包
    ↓
[T3] Responder CQE receive (硬件时间戳) → 包含在ACK1中
    ↓
Responder处理并发送ACK
    ↓
[T4] Responder CQE send ACK (硬件时间戳) → 包含在ACK2中
    ↓
ACK包通过网络传输回Prober
    ↓
[T5] Prober CQE receive ACK (硬件时间戳)
    ↓
[T6] Application poll complete (time.Now())
    ↓
计算指标: Network RTT, Prober Delay, Responder Delay
    ↓
生成ProbeResult → Agent.resultHandler() → OpenTelemetry Metrics + Analyzer Upload
```

### 2. OpenTelemetry Metrics导出流程
```
ProbeResult成功
    ↓
Agent.resultHandler()处理
    ↓
提取指标值 (Network RTT, Prober Delay, Responder Delay, Timeout)
    ↓
调用Metrics.RecordXXX()方法
    ↓
OpenTelemetry SDK处理
    ↓
PeriodicReader (10秒间隔) 批量导出
    ↓
OTLP Exporter (gRPC/HTTP)
    ↓
OpenTelemetry Collector (端口4317)
```

### 3. Analyzer数据上传流程
```
ProbeResult生成
    ↓
Agent.resultHandler()处理
    ↓
添加到Uploader队列 (probeResults)
    ↓
UploadLoop定期执行 (默认10秒)
    ↓
批量打包 (batchSize个结果)
    ↓
gRPC调用 AnalyzerService.UploadData()
    ↓
Analyzer存储到数据库
```

### 4. Path Trace采集流程
```
Tracer收到trace请求
    ↓
执行traceroute/tracepath命令
    ↓
解析命令输出
    ↓
提取每跳IP和RTT
    ↓
生成PathInfo
    ↓
发送到traceResults channel
    ↓
Agent.resultHandler()处理
    ↓
添加到Uploader队列 (pathInfos)
    ↓
随ProbeResults一起上传到Analyzer
```

## 采集状态说明

### ✅ 可以采集的指标
- **所有时间戳** (T1-T6): 都可以采集，但需要probe成功且收到两个ACK
- **所有计算指标** (Network RTT, Prober Delay, Responder Delay): 基于时间戳计算，只要时间戳齐全即可
- **状态和计数**: Probe Status和Timeout Count都可以采集
- **5元组信息**: 所有5元组字段都可以采集
- **路径信息**: 如果启用了traceroute功能，路径信息可以采集

### ⚠️ 部分采集的指标
- **内部统计数据**: 代码中有统计（如SuccessfulProbes, FailedProbes），但不对外暴露，仅用于内部诊断

### ❌ 无法采集或未实现的指标
- **聚合本地统计**: README中提到"Agent uploads aggregated local statistics"，但代码中未实现此功能

## 注意事项

1. **时间戳依赖关系**:
   - Network RTT计算需要: T2, T3, T4, T5
   - Prober Delay计算需要: T1, T2, T5, T6
   - Responder Delay计算需要: T3, T4
   - 如果任何必需时间戳缺失，对应指标无法计算

2. **OpenTelemetry Metrics导出**:
   - 需要OpenTelemetry Collector运行在4317端口
   - 如果Collector不可达，Metrics初始化会失败但Agent会继续运行（只记录警告）

3. **Analyzer数据上传**:
   - 需要`analyzer-enabled=true`配置
   - 如果Analyzer不可达，数据会在队列中缓存，直到连接恢复

4. **Path Trace**:
   - 需要`tracer-enabled=true`配置
   - 需要系统安装`traceroute`或`tracepath`命令
   - 某些网络环境可能限制traceroute功能

5. **Service Flow Discovery**:
   - 需要`ebpf-enabled=true`和`service-flow-monitor-enabled=true`
   - 需要内核支持eBPF和相应的kprobes
   - 用于发现服务流量，但不直接作为metrics导出
