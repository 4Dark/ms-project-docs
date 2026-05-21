# 菜谱知识库构建与可视化进度展示

## 1. 业务背景与目标
将挂载到 Docker 容器内的指定目录（通过 Nacos 配置 `config.data_path`）下的 Markdown 菜谱文件进行扫描、读取、数据清洗、分块（Chunking）、向量化（Embedding）处理，并构建基于 PostgreSQL (pgvector) 的向量检索索引。
为提高系统的可观测性，前端需要提供可视化界面，实时展示知识库构建的处理过程与进度（如：总文件数、当前正在处理的文件、处理完成百分比等）。支持增量追加更新，避免每次全量处理。

## 2. 涉及子工程与职责
- **ms-py-agent**: 负责核心的解析与大模型能力，以及进度状态的写库操作。
  - 读取与清洗：复用并改造 `data_preparation.py`，支持基于文件 Hash 的增量比对。
  - 向量化与索引：废弃 FAISS 本地存储，改用 PostgreSQL 的 `pgvector` 进行向量存储。
  - 进度回传：在遍历处理文件时，实时将处理进度（总数、已处理数、当前文件名、状态）更新至数据库任务表中。
- **ms-java-biz**: 负责进度展示及状态流转（不涉及大模型直接调用的逻辑）。
  - 进度查询：提供进度查询接口，供前端轮询。直接查询数据库中的任务进度表。
- **ms-ng-view**: 提供用户界面。
  - 触发按钮：一键发起知识库构建。
  - 可视化进度面板：通过定时轮询（方案B）获取进度数据，展示文件总数、进度条、当前处理文件名称等。

## 3. 核心业务流程
1. **任务触发与初始化**：用户在 `ms-ng-view` 界面发起“开始构建知识库”请求，直接调用 `ms-py-agent` 暴露的触发构建接口。
2. **扫描与增量比对 (`ms-py-agent`)**：
   - 接收到请求后，在数据库中初始化构建任务记录。
   - 从 Nacos 读取 `config.data_path` 配置。
   - 扫描挂载路径下所有的 `.md` 文件，计算每个文件的 Hash 值。
   - 与数据库中记录的已有文件 Hash 比对，筛选出新增或已修改的文件列表，得出**本次需处理的总文件数**。
   - 在数据库中更新当前构建任务的总数信息。
4. **向量化处理与进度写库 (`ms-py-agent`)**：
   - 遍历需处理的增量文档：
     - 利用 `MarkdownHeaderTextSplitter` 感知分块。
     - 调用 Embedding 模型生成向量。
     - **大一统向量落库**：插入到 PostgreSQL (pgvector) 的通用文档主表 `ms_knowledge_document` 和分块表 `ms_knowledge_chunk`。设置 `doc_type = 'recipe'`，菜名作为 `title`，并使用 JSONB `metadata` 存储 `{"difficulty": "..."}` 等垂直领域专属元数据。
   - **进度更新**：处理每个文件后，实时 `UPDATE` 数据库中的任务进度字段（`processed_count`, `current_item_name` 等）。
5. **进度展示 (`ms-ng-view` & `ms-java-biz`)**：
   - `ms-ng-view` 启动定时器（如每 2 秒轮询一次）。
   - 调用 `ms-java-biz` 的进度查询接口。
   - `ms-java-biz` 直接 `SELECT` 数据库中的任务进度表并返回结果。
   - 前端动态渲染进度条和状态。

## 4. 数据库设计与重构方案 (PostgreSQL)
经过消除冗余大一统重构，原先专属于食谱领域的表并入了通用知识表，以保持极致的可扩展性。数据库表结构由 `ms-java-biz` 的 Flyway 统一管理：

1. **`ms_task_record`** (通用后台任务表)
   - 记录各种异步后台任务的进度，包括 `id`, `task_type` (如 'KNOWLEDGE_BUILD'), `status` (RUNNING, SUCCESS, FAILED), `total_count` (总数), `processed_count` (已处理数), `current_item_name` (当前处理项), `error_message` 等。
2. **`ms_knowledge_document`** (大一统通用文档主表)
   - 记录文档基本元数据，包含 `id` (VARCHAR(64)), `topic_id`, `title` (菜名), `status`, `author`, `file_path`, `file_hash` (用于增量比对), `doc_type` (标记领域，如 `'recipe'`), `category` (食谱分类)，以及核心的 **`metadata` (JSONB)** 字段用于灵活记录领域专属属性（例如 `{"difficulty": "简单"}`）。
3. **`ms_knowledge_chunk`** (大一统通用分块向量表)
   - 记录具体分块文本与 512 维向量，包括 `document_id` (关联主表), `chunk_index`, `content`, `embedding` (vector(512) 类型)。支持通过文档级联删除（`ON DELETE CASCADE`）实现批量清理。

## 5. 接口变动规划
- **ms-java-biz**:
  - `GET /rest/biz/v1/tasks/{taskId}`: 获取通用任务的当前进度信息。
- **ms-py-agent**:
  - `POST /rest/agent/v1/knowledge/build` (前端经由网关调用): 触发知识库构建。后端在 `ms_task_record` 中初始化任务并异步启动，同步返回 `taskId` 供前端轮询。

## 6. RAG 提示词检索与错误码提醒优化 (2026-05-19)
为了提升美食 AI 助手对提示词定制以及底层异常的感知与容错性，我们在 RAG (检索增强生成) 流程的生成集成阶段落地了多项架构级重构：

1. **动态模板获取与变量替换纯净化**：
   - **清除本地兜底**：彻底删除了 Python 端硬编码的经典主厨和烹饪导师系统提示词，强制所有人格与系统提示词由 `ms-java-biz` 的统一管理端从 PostgreSQL 中读取并进行外部下发。
   - **双级检索逻辑**：优先使用 `topic_id` 查询匹配该主题的专属格式提示词，若无专属模板，则自动降级匹配通用的知识库提示词。
   - **动态数据库变量注入**：支持将格式变量保存在数据库中维护，并在此基础上系统级自动注入 `{{current_time}}` (当前时间) 与 `{{today}}` (今天日期) 等时间元数据。

2. **全局错误码适配与可观测性集成**：
   - 重构了 `PromptService` 跨服务调用逻辑，提供 `error_context` 捕获链。
   - **全链路错误映射**：
     - `DEP_0100` (提示词不存在)：模板未找到。
     - `DEP_0102` (格式校验失败)：模板中包含未定义或冲突的变量。
     - `DEP_0503` (服务暂不可用)：微服务未向 Nacos 注册或发生连接/读取超时。
     - `DEP_0500` (外部调用异常)：意外的服务器内部错误。
   - 所有异常与错误码信息已与 [/docs/api-contracts/MsJavaBiz-PromptManagement-v1.yaml](file:///Users/pei/projects/docs/api-contracts/MsJavaBiz-PromptManagement-v1.yaml) 及全局 [/docs/api-contracts/ErrorCodeRegistry.md](file:///Users/pei/projects/docs/api-contracts/ErrorCodeRegistry.md) 完成完美对齐与同步维护。

3. **前端零侵入“虚拟源级警示”传播方案**：
   - 检索子图在捕获到提示词加载异常时，会主动在回复消息的召回来源 `sources` 最上方拼接“虚拟警示来源”（例如 `⚠️ 格式模板加载异常` 或 `⚠️ 主题模板加载异常`），详细指明故障错误码（如 `DEP_0503`）以及系统采取的自动降级问答机制。
   - 该方案在保障**前端整洁架构 (4-Layer Clean Architecture)** 零逻辑改动的前提下，使得前端在渲染对话卡片折叠面板时，能将错误原因及排查方案醒目、美观地展现给终端用户，达成了极高可用性的故障自愈感知。
