# 4+1 视图架构总览

## 系统定位

基于 Philippe Kruchten 的 "4+1" 视图模型方法论，对当前 AI 智能助手平台进行了多维度、结构化的架构剖析。此文档集旨在帮助外部开发者、架构师以及利益相关者从不同视角快速、全面地了解项目全貌。

## 文档导航

| 视图 | 文档链接 | 关注点 | 核心产出 |
|---|---|---|---|
| **上下文视图** | [context-view.md](./context-view.md) | **系统边界**: 4+1模型的前置输入，界定系统边界与外部 Actor 的交互范围。 | 系统级上下文图 (1) |
| **用例视图** | [01-usecase-view.md](./01-usecase-view.md) | **驱动源 (外部视角)**: 识别核心业务需求，定义关键场景并驱动其他四大视图的设计。 | 核心用例清单、用例概览图 (1) |
| **逻辑视图** | [02-logical-view.md](./02-logical-view.md) | **功能组织 (内部视角)**: 系统功能解耦，提炼限界上下文，设计领域模型及系统间交互。 | 领域分层图、逻辑边界图 (2) |
| **过程视图** | [03-process-view.md](./03-process-view.md) | **运行组织 (运行时视角)**: 关注系统的并发、同步、数据流、流式传输 (SSE) 与高可用机制。 | RAG与MCP时序流转图 (1) |
| **开发视图** | [03-development-view.md](./03-development-view.md) | **代码组织 (开发视角)**: 代码模块划分、组件包依赖、编程语言结构及架构卫兵规范。 | 包结构依赖图、思维导图 (1) |
| **物理视图** | [03-physical-view.md](./03-physical-view.md) | **部署架构 (部署视角)**: 关注系统的物理部署拓扑，网络虚拟化、容灾隔离、反向代理及中间件。 | Docker集群与网络拓扑图 (1) |

## 架构目标

*   **模型无关性 (Model Agnosticism)**：系统底层的大模型推理能力（LLM）实现接口化解耦，运行时基于 Nacos 动态切换不同供应商的 LLM（如 OpenAI/DashScope），避免深度绑定。
*   **极致插件化 (Pluggability)**：基于 MCP (Model Context Protocol) 构建灵活的能力集中心。AI 大脑动态发现与调用业务工具集，新增业务能力完全无需修改 AI 大脑层代码。
*   **端到端全链路解耦**：彻底贯彻 DDD 原则与 4-Layer 前端架构，做到表现层、应用层、领域层与基础设施层的完全正向依赖隔离。

## 技术栈概览

| 层次 | 技术选型 |
|---|---|
| **核心语言** | Java 17+, Python 3.10+, TypeScript |
| **核心框架** | Angular 21 (前端), Spring Cloud Gateway (网关), FastAPI + LangGraph (Python 大脑), Spring Boot 3 + LangChain4j (Java 业务) |
| **包管理** | npm (Frontend), Maven (Java), uv (Python) |
| **状态/数据中心** | PostgreSQL 16 + pgvector, Casdoor (OAuth2), Nacos (服务发现与配置) |
| **测试框架** | Jest (前端), JUnit5 + ArchUnit (Java), pytest (Python), Testcontainers (集成测试) |
| **代码规范 (Lint)** | ESLint + Prettier (前端), Ruff (Python), checkstyle (Java) |
| **构建与部署** | Docker 多架构镜像 (amd64/arm64), GitHub Actions (CI/CD), Cloudflare Pages (CDN) |
| **可观测性** | 统一全局 `TraceIdFilter`, INFO 级全链路耗时与状态日志追踪 |

## 架构约束

*   **TypeScript ESM Only**: 严格要求全站 ESM 模块化，禁用 CommonJS。
*   **严格防腐边界**: `ms-java-biz` 中强制使用 ArchUnit 卫兵切断 `application` 对 `interfaces` 的反向依赖；领域模型禁止引入持久化框架依赖。
*   **全异步/非阻塞优先**: Python 大脑层全面采用 `async def` 和 `asyncpg`，网关层坚持 WebFlux 响应式模型，避免高并发流式生成阶段的线程池枯竭。

## 用例驱动架构 (Use-Case Driven)

本工程深度贯彻 Philippe Kruchten 的 "4+1" 视图模型，以**用例视图**作为所有架构设计的源动力与检验标准。

**架构追溯要求**：所有的架构决策（包括逻辑领域的拆分、并发进程的优化、开发结构的限制）必须能追溯到具体的业务场景。所有的 4+1 视图文档末尾，均应包含**用例追溯矩阵**，确保架构设计的每一步都不会偏离真正的产品价值与系统用例。
