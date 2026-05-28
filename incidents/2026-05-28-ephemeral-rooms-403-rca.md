# 事故复盘：阅后即焚短链资源加载失败、403 Forbidden 与 WebSocket 握手故障

## 1. 现象描述
**日期**：2026-05-28
**症状**：
1. **MIME 资源加载错误**：访问阅后即焚短链 `https://122577.xyz/s/{code}` 时，页面白屏，控制台报错：
   - `Refused to apply style from 'https://122577.xyz/s/styles-UNDNJPPI.css' because its MIME type ('text/html') is not a supported stylesheet MIME type...`
   - `Failed to load module script: Expected a JavaScript-or-Wasm module script but the server responded with a MIME type of "text/html"...`
2. **403 Forbidden 拦截**：匿名创建房间接口 `POST /rest/biz/v1/ephemeral/rooms` 频繁被网关与后端服务拦截并返回 `403 Forbidden`。
3. **重定向路径丢失与 404**：在 Cloudflare Pages 预览环境（如 `feature-ephemerallink.ms-ng-view.pages.dev`）下：
   - 使用 `_redirects` 配置的 `200` 代理外部地址时，发生 302 丢失路径，重定向无法正确路由；
   - 将 `_redirects` 改为 `302` 重定向时，浏览器会跳转到网关域名 `https://dark.122577.xyz/s/{code}`，但由于后端返回相对重定向路径 `/room/{code}`，导致浏览器解析为 `https://dark.122577.xyz/room/{code}`（API 网关域名），引发 404 故障。
4. **WebSocket 握手失败**：页面在生产环境或预览分支尝试建立 WebSocket (STOMP) 握手时频繁失败并循环重连：
   - `WebSocket connection to 'wss://122577.xyz/ws/ephemeral/websocket' failed:`
   - `WebSocket connection to 'wss://feature-ephemerallink.ms-ng-view.pages.dev/ws/ephemeral/websocket' failed:`

---

## 2. 根因分析（RCA）

### 根本原因 1：SPA 路由重写规则劫持了短链物理重定向
在前端静态托管配置 `_redirects` 中，通配符单页应用（SPA）重写规则为 `/* /index.html 200`。因为没有显式拦截处理 `/s/*` 的短链接口重定向，导致直接以 `200 OK` 返回了 `index.html`。
浏览器在当前 URL `https://122577.xyz/s/{code}` 下尝试解析相对路径的资源，发起了对 `/s/styles-UNDNJPPI.css` 的请求。该请求再次被 `/*` 规则劫持，又返回了 `index.html`（HTML 文本，MIME 类型为 `text/html`），进而触发了严格的 MIME 类型安全校验报错。

### 根本原因 2：Angular index.html 缺失 `<base href>`
在 `index.html` 中未声明 `<base href="/">`，导致处于 `/s/{code}` 或 `/room/{code}` 等深度路径下的 SPA 应用解析相对路径资源时，会自动在其当前路径上下文（如 `/s/` 或 `/room/`）下拼接，产生了错误的静态资源请求路径（如 `/s/styles-...`）。

### 根本原因 3：Nacos 后端安全白名单未同步
网关本地配置虽放行了 `/rest/biz/v1/ephemeral/**` 匿名请求，但该配置在 Nacos 配置中心中未同步。导致运行环境拉取 Nacos 的 stale 配置覆盖了本地白名单，使匿名 POST 请求到达 `ms-java-biz` 后，在 Spring Security 过滤器链中被判定为需要认证，由于无状态匿名访问无 Token 凭证，从而返回了 `403 Forbidden`。

### 根本原因 4：Cloudflare Pages 对外部 200 隐式代理与 WebSocket 的物理限制
1. **短链 200 隐式代理限制**：Cloudflare Pages 仅支持本地 URL 的 `200` 隐式重写（如路由到 `/index.html`）。若配置外部目标（如 `https://dark.122577.xyz`），Pages 不支持充当反向代理服务器，会导致 `:splat` 参数在跳转时丢失。
2. **网关相对路径重定向限制**：若采用 `302` 将 `/s/*` 重定向至 API 网关域名，网关/后端返回的是相对路径重定向 Location `/room/{code}`。此时由于浏览器当前请求 of the Host 已变为 `dark.122577.xyz`，会将相对路径解析在网关域名下（`https://dark.122577.xyz/room/{code}`），从而因网关无法提供前端静态资源而引发 404 错误。
3. **WebSocket 代理限制**：Pages 仅提供纯静态资源托管，不支持进行 WebSocket 协议升级（`ws` / `wss`）的动态代理，任何指向 Pages 域名的 WebSocket 连接均会被直接断开。

---

## 3. 解决过程与落地实现

### 步骤 1：前端基础路径与代理规则治理
1. **静态资源基础路径修复**：在 `/ms-ng-view/index.html` 中添加 `<base href="/" />`，强制所有深度路由的资源请求解析为根域名下的绝对路径（如 `/styles-UNDNJPPI.css`），彻底规避 MIME 报错。
2. **SPA 路由与代理规则修正**：修改 `/ms-ng-view/public/_redirects` 配置文件，添加并完善 `/rest/*`、`/api/*`、`/s/*` 和 `/ws/ephemeral/*` 的规则。其中将 `/s/*` 从原来的 `200`（隐式代理，Pages 无法支持向外部 host 进行 200 反代）修改为标准的 `302`（显式重定向），其余 API 维持 `200` 以保留本地代理能力：
   ```
   /rest/*  https://dark.122577.xyz/rest/:splat  200
   /api/*   https://dark.122577.xyz/api/:splat   200
   /s/*     https://dark.122577.xyz/s/:splat  302
   /ws/ephemeral/*  https://dark.122577.xyz/ws/ephemeral/:splat  200
   ```

### 步骤 2：后端动态 Referer 解析及绝对路径与默认兜底重定向 (TDD 落地)
1. **配置属性定义**: 在 `application.yaml` 和 `application-test.yml` 中新增 `app.frontend-url` 默认前端基地址配置，默认指向生产前端 `https://122577.xyz`。
2. **控制器改造与默认兜底**: 在 `ShortLinkController.java` 中，注入 HTTP 请求头 `@RequestHeader(value = "Referer", required = false) String referer`，解析并提取请求来源前端域名（Scheme + Authority）。
   - 若解析出合法 Referer 域名，则执行 **绝对路径 302 重定向** 至 `[RefererBase]/room/{code}`，保证预览分支域名的高级还原；
   - 若无 Referer 请求头（如用户直接复制/粘贴链接或在社交应用内首次点击），自动回退并采用 `app.frontend-url` 默认前端基地址，同样发起 **绝对路径 302 重定向** 至 `[defaultFrontendUrl]/room/{code}`。这彻底解决了相对路径降级被网关解析在 `https://dark.122577.xyz/room/{code}` 下而引发 404 故障的问题。
3. **单元测试与集成测试**: 编写并重构了 `ShortLinkControllerTest.java` 中的测试场景，全量覆盖了带 Referer 的跨子域绝对路径重定向、不带 Referer 的默认配置绝对路径重定向及 410 过期短链逻辑，所有测试 100% 通过。

### 步骤 3：自适应 WebSocket 连接优化
在前端 `ephemeral.adapter.ts` 中实现了自适应 WebSocket 连接逻辑：
- **localhost 开发环境**：仍连接当前域名端口（如 `http://localhost:3000`），从而配合本地 `proxy.conf.json` 中配置的本地网关代理规则转发；
- **生产与预览环境**：直接从前端环境变量 `environment.VITE_API_URL` 中抽取后端网关真实域名，强制建立安全的直连 WebSocket 连接（`wss://dark.122577.xyz/ws/ephemeral/websocket`），成功规避了 Pages 平台对 WebSocket 代理的阻断。

### 步骤 4：安全配置治理建议
开发人员需同步更新 Nacos 配置中心 `ms-java-biz.yaml` 中 `app.security.ignore.urls` 的配置，追加 `/rest/biz/v1/ephemeral/**`、`/s/**` 和 `/ws/ephemeral/**` 三个阅后即焚匿名接口，保证开发/测试/生产环境配置一致。

---

## 4. 经验总结与后续行动

- **开发与部署配置同步**：凡是涉及微服务间新路由、匿名 API 等白名单更改，**必须在修改本地 `application.yml` 的同时，立即同步更新 Nacos 配置中心中对应环境的配置**，防止本地配置在运行时被 stale 的配置拉取覆盖引发 403 故障。
- **前端部署最佳实践**：所有的 Angular 混合部署应用，在 `index.html` 中**必须严谨包含 `<base href="/">` 标签**，确保路由和静态资源加载的高健壮性，防止深度路径下发生 MIME 解析错误。
- **重定向安全与跨域控制**：在跨域名重定向的业务场景中，后端应具备**动态 Referer 感知能力**以决定重定向的完整 host，避免硬编码域名或相对重定向导致的预览分支环境失效或网关 404 故障。
- **WebSocket 连接解耦**：当客户端与服务端运行于不同域名（如 CDN 托管静态页与独立微服务 API 网关）时，WebSocket 连接应当**直接指向后端接口地址**，而不应依赖 CDN/静态托管平台的代理转发。
