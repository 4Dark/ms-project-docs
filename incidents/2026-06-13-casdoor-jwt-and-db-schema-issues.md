# 故障复盘：Casdoor 头像/昵称丢失与数据库结构不同步问题

## 1. 现象描述 (Symptoms)
1. **前端展示异常**：`ms-ng-view` 的右上角和对话记录中，未能展示 Casdoor 用户的头像与中文昵称，而是展示了一串 UUID（作为名称）和默认图标（头像）。
2. **后端报错 500**：`ms-java-biz` 查询 `ai_dev_task` 时，抛出 `PSQLException: ERROR: column "engine_mode" does not exist`。

## 2. 根因分析 (Root Cause Analysis - RCA)

### 2.1 用户信息丢失（网关与业务层解耦引起的 OIDC 数据断层）
- **架构约定**：网关 (`ms-java-gateway`) 遵循“零业务逻辑”原则，在路由转发时只透传基础身份（如 `X-User-Id`）和 JWT Token，要求下游自行解析业务字段。
- **网关漏洞**：网关在处理完 Casdoor 的 OAuth2 登录后，会基于内部 `app.jwt.secret` 签发自己的内部 JWT。但在打包载荷时，网关只提取了 Casdoor 返回的 `name`（对应为 ID UUID）和 `picture`，完全遗漏了 `displayName`。
- **业务端漏洞**：`ms-java-biz` 的 `/rest/biz/v1/user/me` 接口早期试图从 `X-User-Name` 获取数据（与网关约束不符）。同时，在提取头像时，错误地索取了 `avatar` 而不是 Casdoor 标准规范的 `picture`。

### 2.2 数据库字段不存在（初始化脚本无法用于增量更新）
- 在 `ms-ai-devops` 维护的 `V1.0__init_ai_devops_schema.sql` 脚本中，直接添加了 `engine_mode VARCHAR(50)`。
- 开发测试环境下，由于表 `ai_dev_task` 已经存在，`CREATE TABLE IF NOT EXISTS` 被触发时会直接跳过执行，导致 Java Entity/Mapper 更新了，但底层 Postgres 数据库结构没有更新，引发 MyBatis 拼接 SQL 错误。

## 3. 解决步骤 (Resolution Steps)

1. **改造 `ms-java-gateway` 的 JWT 签发逻辑**：
   - 修改 `SecurityConfig.java`：从 Casdoor `OidcUser` 中按顺序提取 `displayName` 或 `preferred_username`，并将其塞入自定义生成的内部 JWT 载荷中。
2. **重构 `ms-java-biz` 的 `/me` 接口**：
   - 废弃对请求头的依赖，直接从 `SecurityContext` 提取 JWT 并进行验签解析。
   - 正确读取 `displayName` 和 `picture` 字段并返回给前端 `UserDto`。
3. **修复 `ms-ng-view` 前端展示**：
   - 调整 `AiDevChatComponent` 逻辑，让人类用户的消息可以读取 `UserService` 中的真实 `avatar`。
4. **数据库增量修复**：
   - 对已有开发环境的数据库手动执行 `ALTER TABLE ai_dev_task ADD COLUMN engine_mode VARCHAR(50) DEFAULT 'HERMES_SINGLE';` 进行补丁修复。

## 4. 经验教训 (Lessons Learned)
- **OIDC/OAuth2 字段映射**：Casdoor 的 `name` 往往是不可读标识符，`displayName` 才是真名；法定的头像字段是 `picture`。
- **网关作为 BFF 的职责**：网关在生成内部统一 Token 时，必须承担“身份属性翻译与打包”的基础设施职责，以满足下游服务的基本业务解析需求。
- **数据库增量演进**：对已有环境不能通过修改 `CREATE TABLE IF NOT EXISTS` 脚本来实现加字段操作。任何字段调整必须编写显式的 `ALTER TABLE` 升级脚本，或由研发手动执行对齐。
