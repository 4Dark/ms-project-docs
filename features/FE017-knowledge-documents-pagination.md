# 知识文档分页 (Knowledge Documents Pagination)

## 特性定义
知识文档分页特性负责在查询知识库主题下的文档列表时，通过分页机制限制单次返回的数据量。这不仅能提升大规模知识文档场景下的系统响应速度，还能减轻前端页面一次性渲染大量数据的压力。

## 业务逻辑
1. **分页参数支持**：`/rest/biz/v1/knowledge/documents` 接口支持可选的 `page`（页码，从 1 开始）和 `size`（每页条数）参数。
2. **向下兼容**：若未提供 `page` 和 `size` 参数，接口默认返回当前主题下的全部文档列表（数组格式），确保对旧有调用方的 100% 兼容。
3. **分页响应格式**：若指定了分页参数，接口以 `PageResult` 统一结构返回，其中包含 `records`（当前页数据列表）、`total`（总条数）、`size`（每页大小）、`current`（当前页码）以及 `pages`（总页数）。
4. **MyBatis-Plus 分页插件集成**：在基础设施层注册 `PaginationInnerInterceptor` 插件，提供底层的物理分页查询支撑。

## 涉及子工程
- **ms-java-biz**: 实现分页控制器、应用服务与仓储层数据库分页。
- **ms-project-docs**: 更新 API 契约文档 (`MsJavaBiz-KnowledgeBase-v1.yaml`)。
