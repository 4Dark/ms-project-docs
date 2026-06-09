# AI 研发任务：Token 计量与时间展示 (Task Timeline)

## 背景与目的 (Background & Objective)
随着 ms-ai-devops 常驻服务和多智能体协作机制的上线，单个 AI 开发任务可能涉及多次大模型调用（如规划、头脑风暴、代码生成、代码评审）。
为了让用户清楚地了解各个节点的资源消耗、时间花费，并进一步做成本核算和性能瓶颈分析，我们开发了 "Token 计量与时间展示" 功能。

## 特性描述 (Feature Description)
- **精准计量**：全面采集任务执行生命周期中，各 Agent (规划者、生成器、评审者等) 在各阶段 (PLANNING, GENERATING 等) 的 Token 消耗情况。
- **时间度量**：记录每次模型调用的耗时 (durationMs)，进而可以分析各个环节的执行效率。
- **前端可视化 Timeline**：在 Chat 界面左侧，基于获取的统计结果生成任务的时间与消耗流视图，给用户直观的财务和时间成本反馈。
- **SSE 增量推送**：支持在模型执行期间，通过 Webhook/SSE 将 Token 消耗增量实时推送到前端。

## 涉及子工程架构设计 (Architecture & Cross-project Changes)

该特性的实现横跨了三大子系统：

### 1. 自动化节点编排端 (ms-ai-devops)
- 负责在大模型 API 返回时（基于 LangChain/LangGraph 返回的 `usage_metadata`），采集 promptToken、completionToken 和 duration，并估算 Cost。
- 调用 webhook 接口 `POST /rest/biz/v1/ai-dev/tasks/callback`，`eventType` 定义为 `TOKEN_USAGE`，推送详细的资源消耗负载。

### 2. Java 业务中枢 (ms-java-biz)
- **数据库扩展**：通过 Flyway (`V1.22__create_ai_dev_audit_log.sql`) 创建表 `ai_dev_audit_log` 存储计量明细。
- **应用服务调整**：
  - 更新 `AdapterAiDevIntegrationUseCaseImpl.java` 的 `processWebhookEvent` 方法，拦截 `TOKEN_USAGE` 并将数据落库。
  - 顺便更新任务的主表 `ai_dev_task` 累加 `total_cost`。
  - 通过 SSE (Server-Sent Events) 广播增量消息到前端页面。
- **REST 接口提供**：提供新的汇总 API `GET /rest/biz/v1/ai-dev/tasks/{taskId}/token-summary`，聚合按阶段的消耗情况。
- **相关核心类**：
  - `AiDevAuditLog` (Entity), `AiDevAuditLogPO` (DO)
  - `AiDevTokenSummaryResponse` (DTO)

### 3. Angular 前端大屏 (ms-ng-view)
- **领域模型 (Model)**：扩展了 `PhaseMetric` 和 `TokenSummary` 接口。
- **适配器 (Adapter)**：`AiDevRepository` 新增 `getTokenSummary`。
- **用例 (UseCase)**：`AiDevUseCase` 增加 `tokenSummary` 状态 Signal，并在 SSE 流解析中拦截 `TOKEN_USAGE` 进行本地缓存增量更新。
- **视图展示 (UI)**：
  - 新建 `TaskTimelineComponent`，将收集到的阶段数据通过可视化图表、彩色条带渲染。
  - 嵌入到 `AiDevChatComponent` 的左侧侧边栏中。

## 接口变动 (API Contracts)
**新增接口**：
`GET /rest/biz/v1/ai-dev/tasks/{taskId}/token-summary`
- 返回类型: `AiDevTokenSummaryResponse`
- 结构包含总 Token 数、总花费、以及按阶段聚合的明细列表 `phases: [{phase, agentRole, promptTokens, completionTokens, cost, durationMs, callCount}]`

## 影响评估 (Impact)
- **数据库层面**：新增 `ai_dev_audit_log` 数据量可能随智能体活跃度剧增。后续若系统压力变大，可能需要对此日志表执行定时清理或归档策略。
- **兼容性影响**：轨道B (Native 模式) 不记录这些耗费，其实现 `NativeAiDevIntegrationServiceImpl` 的对应接口返回空。

## 部署与验证步骤
1. 执行 `ms-java-biz` 的 Flyway 数据库迁移脚本。
2. 重启 `ms-java-biz` 和 `ms-ng-view`。
3. 触发一次智能体流水线操作，检查页面是否弹出任务 Timeline 的进度和 Cost 累加效果。
