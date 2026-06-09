# FE020 - Agent 知识挂载渐进式加载架构改造

## 1. 背景与目标
在多工程并行开发的环境下，此前所有规范（无论前后端、部署或测试）大量采用 `trigger: always_on` 机制。这导致了两个核心痛点：
1. **Token 爆炸**：系统指令体积随着规范的增加日益庞大（单工程曾超 500 Tokens）。
2. **上下文污染**：比如在写 Java 后端时加载了 Angular 前端规范，容易导致 AI 混淆和幻觉。

**目标**：将所有微服务项目的 `.agent` 体系改造为**三级渐进式加载机制**（L0/L1/L2），实现按需触发、精准挂载，全面优化上下文整洁度。

---

## 2. 三级加载架构设计

### 2.1 L0 层：核心基础 (Always On)
负责维持 AI 对工程最核心的认知边界。严格控制在 100 Tokens 左右。
* **文件命名**: `role-context.md` (前身为 `core.md`)
* **适用内容**: AI 的角色定义、核心技术栈、绝对禁区（边界）和关联规则的导航指南。
* **全局特例 (ms-project-docs)**: `global-project-workflow.md`、`terminal-execution-rules.md`、`ai-behavior-guidelines.md` 作为工作流底座，保持 Always On。

### 2.2 L1 层：精准匹配 (Glob Matching)
负责按当前用户操作的文件后缀动态加载规范。
* **代码编写**: 
  - `coding-java.md` (触发: `**/*.java`)
  - `coding-ts.md` (触发: `**/*.ts`)
  - `coding-py.md` (触发: `**/*.py`)
* **测试用例**: 
  - `testing-java.md` (触发: `**/*Test.java`)
  - `testing-ts.md` (触发: `**/*.spec.ts`)
  - `testing-py.md` (触发: `**/test_*.py`)
* **基础设施**: 
  - `local-dev-guide.md` (触发: `**/*.yaml`, `**/*.json`)
  - `db-migration-rules.md` (触发: `**/*.sql`)
  - `angular-html-rules.md` (触发: `**/*.html`)

### 2.3 L2 层：深度参考 (On-Demand Skills)
负责存放完整的发展史与深度架构指南。
* **形式**: 以标准的 Agent Skill 包形式存在，通过 `skills/{skill-name}/SKILL.md` 管理。
* **触发机制**: `on_demand`。AI 在进行复杂架构设计、重构或调试时，可主动决定挂载调用。
* **示例**: `ms-java-biz/skills/deep-reference`，`ms-project-docs/skills/global-coding-standards`。

---

## 3. 覆盖工程清单
本次改造已全量覆盖以下核心工程：
1. `ms-project-docs`（全局）
2. `ms-java-biz`
3. `ms-java-gateway`
4. `ms-ng-view`
5. `ms-py-agent`
6. `ms-ai-devops`（全新补齐）
7. `ms-java-yaml2code-sdk`（全新补齐）

---

## 4. 优化收益
* **见文知意**: 摒弃了晦涩或泛化的命名（如 `core.md`, `devops.md`），改为 `role-context.md`, `local-dev-guide.md`，从文件名即可直观了解用途。
* **Token 消耗锐减**: 通过摘除历史遗留的全量 `CODING_STANDARDS.md` 强制挂载，节省了大量常驻 Token，显著降低每次交互的延迟和成本。
* **开发专注度提升**: 避免跨端规则的交叉干扰，测试时加载测试准则，写代码时专注代码准则。
