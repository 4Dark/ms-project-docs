# FE019-ai-devops-orchestration

## 目标
构建 `ms-ai-devops` 编排引擎，实现多智能体团队端到端自动化开发流程，提升跨工程特性研发效率。

## 架构决策与选型
1. **纯客户端编排**：基于 **Hermes Agent** 框架构建客户端 AI 引擎（Python 栈），通过 CLI 运行在本地环境。
2. **三角色隔离编排 (P/G/E)**：采用 Planner (高推理模型) -> Generator (快速编码模型) -> Evaluator (隔离审查模型) 的架构。通过 `delegate_task` 隔离上下文。
3. **多 LLM 引擎抽象**：支持配置不同任务角色的底层 Provider (例如 Anthropic、Gemini、DeepSeek 等)，以优化成本与能力配比。
4. **混合模式同步状态 (Server Sync)**：在 `ms-java-biz` 新增 `ms_dev_task`、`ms_dev_audit_log` 等表，提供持久化看板、成本审计与安全回滚。`ms-ng-view` 前端提供可视化的 AI Dev Team 页面。

## Pilot Task 落地验证
首个由该编排流接管的端到端开发验证任务为：
**"Chat 消息 Like/Dislike 反馈 + 对话重新生成"** (涉及 ms-ng-view UI组件, ms-py-agent 会话处理, ms-java-biz 持久化)

详细的技术架构和实施方案见：`ms-ai-devops/docs/features/FE001-ai-dev-team.md`
