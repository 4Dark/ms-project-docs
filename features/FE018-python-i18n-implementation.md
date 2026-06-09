# ms-py-agent 国际化 (i18n) 实施计划

## 1. 特性定义
为 Python 服务端 `ms-py-agent` 提供完整的国际化 (i18n) 机制，支持通过 HTTP 请求头中的 `Accept-Language` 自动切换语言。首批支持 `zh_CN` 和 `en_US`，解决代码中大量硬编码中文字符串的问题，并将用户侧返回的消息与 Java 端 (`ms-java-biz`) 的错误码及国际化规范完全对齐。

## 2. 业务逻辑与设计方案

### 2.1 语言包存储与查找机制
使用 **YAML Key-Value** 格式，将消息定义在 `app/core/i18n/` 目录下。
- `app/core/i18n/zh_CN.yaml`: 中文语言包
- `app/core/i18n/en_US.yaml`: 英文语言包（兼作兜底语言）

### 2.2 动态语言解析与透传
1. **ContextVar 线程/协程安全存储**：
   - 定义 `request_locale = contextvars.ContextVar("request_locale", default="en_US")` 全局上下文变量。
   - **核心原理**：由于 FastAPI 运行在异步协程（`async/await`）架构上，传统的 `threading.local` 只能保障线程级隔离，在多协程并发交替执行时会发生脏读。使用 `ContextVar` 能确保每次独立的 HTTP 异步请求都拥有完全隔离的语言环境上下文，且在链式异步调用中无感透传。
2. **FastAPI HTTP 中间件 (`locale_middleware`)**：
   - 提取 `Accept-Language` 请求头。
   - 调用 `parse_accept_language` 将请求头映射为后台标准的 `"zh_CN"` 或 `"en_US"`，若缺失或无匹配则默认 fallback 到 `"en_US"`。
   - 每次请求进入时通过 `token = request_locale.set(locale)` 将解析结果注入当前协程上下文。
   - 包装在 `try/finally` 块中，在请求结束离开中间件时强制执行 `request_locale.reset(token)`。此举能够杜绝协程结束后的上下文泄露、内存污染或上一个请求残留带来的 Locale 脏数据问题。
3. **消息获取助手 `get_message`**：
   - 支持自动读取当前 `request_locale` 变量。
   - 查找对应的翻译 Key，若不存在，则 fallback 到 `en_US.yaml`；若仍然不存在，最终兜底返回 Key 本身。
   - 支持 Python `.format()` 命名占位符（如 `{detail}`、`{filename}` 等）。

### 2.3 待重构的硬编码消息
1. **`app/services/prompt_service.py`**：微服务网络异常、Nacos 服务发现失败等。
2. **`app/api/routers/kb.py`**：文件不存在、分块解析异常、向量化回写异常等。
3. **`app/agent/subgraphs/rag_graph.py`**：子图迭代上限提示、主题与格式 Prompt 加载警告。

## 3. 涉及子工程
- **ms-py-agent**:
  - `app/core/i18n/`：存放翻译文件及核心 `messages.py`
  - `main.py`：注册 Locale 中间件
  - `app/services/prompt_service.py`：重构硬编码消息
  - `app/api/routers/kb.py`：重构硬编码消息
  - `app/agent/subgraphs/rag_graph.py`：重构硬编码消息
- **ms-project-docs**:
  - 维护本文档

## 4. 实施步骤
1. **建立 i18n 目录与核心模块**：创建 `app/core/i18n/`，实现 `messages.py`。
2. **编写中英文 YAML 文件**：将首批提取的硬编码转换为 YAML 条目。
3. **配置 FastAPI 中间件**：在 `main.py` 中引入 `locale_middleware`。
4. **重构各模块的硬编码**：逐个替换 `prompt_service.py`、`kb.py` 和 `rag_graph.py` 中的提示语。
5. **单元测试与验证**：编写测试验证 ContextVar 在异步请求中的隔离性及 i18n 查找准确性。

## 5. 实施结果与验证
- **i18n 核心模块**：`app/core/i18n/messages.py` 中完美实现 `request_locale` contextvar 机制，完全兼容 `Accept-Language` 头信息解析与 fallback。
- **配置与国际化消息包**：`zh_CN.yaml` 与 `en_US.yaml` 对齐。
- **模块重构**：
  - `main.py` 正确挂载 `locale_middleware`。
  - `prompt_service.py` 已彻底消除 Nacos 不可用、HTTP 异常及网络超时等硬编码中文。
  - `kb.py` (/documents/ingest 端点) 已全面采用 `get_message` 替换所有文件异常、向量化异常与成功消息。
  - `rag_graph.py` (子图部分) 已全面重构格式模板加载异常、主题模板加载异常和迭代超限警告字样。
- **单元测试**：全新创建 `tests/test_i18n.py`。包含 header 解析、格式化、fallback 及并发协程上下文隔离验证。51 项测试套件全部通过 (Green)。

