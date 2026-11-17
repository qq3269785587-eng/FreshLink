# FreshLink 生鲜仓储与配送管理系统

正式题目：**面向连锁餐饮的生鲜食材仓储与配送管理系统**。

本仓库是三人协作使用的完整源码基线，包含当前有效的前后端源码、业务规格、数据库结构、P1 迁移、脱敏演示资料和开发脚本。**P0、P1 已独立验收通过；P2 尚未开始。** 当前功能基线是基础资料与角色权限，后续完成入库批次、申领配货、配送签收、追溯看板和只读 AI。原出库分配仍有占位实现，不能把当前代码当作完整业务已经交付。

仓库地址：https://github.com/yukisuki7/FreshLink 。这是私有仓库，负责人需要先邀请两位开发同学。加入后可克隆、按下列步骤初始化各自环境，再从 `p1-accepted` 标签开始开发。

## 三人分工

| 成员 | 工作范围 | 提交方式 |
|---|---|---|
| 开发 A | `apps/backend`、数据库与业务规则、后端测试 | 每个任务书小批次一个 PR，先自测再提交审查 |
| 开发 B | `apps/web`、页面、接口联调和浏览器验证 | 每个任务书小批次一个 PR，附实际操作证据 |
| 项目负责人 | 接口合同确认、PR 审查、阶段验收与合并 | 前后端组合版本通过后才进入下一阶段 |

两份任务书在 [docs/tasks](docs/tasks/)，各有 Word 与 Markdown。先由 A 提交当前阶段接口合同，B 确认后可在同一阶段并行。各自完成 P2-A 就可以提交本批 PR，不必等整阶段；整个 P2 完成后仍要做阶段验收。任务书中的“GitHub 尚未准备”和原本机双仓状态属于交接时背景，**当前仓库、分支和开工方式以本 README 为准**。

## 克隆和配置

本机入口适用于 Windows 和 PowerShell 7。每位同学准备 JDK 17、Maven、Node.js、pnpm 11.25.0、MySQL 8 与 Redis。仓库不包含这些工具、下载缓存或本机数据库密码。实际验证使用 Node 25.8.2；依赖版本保持锁文件，不自行升级。

```powershell
git clone -c core.longpaths=true https://github.com/yukisuki7/FreshLink.git
cd FreshLink
git switch -c feat/p2-a-backend p1-accepted
# 前端同学使用 feat/p2-a-frontend 等自己的分支名
pwsh -NoProfile -File .\scripts\team\Setup-Team.ps1
pwsh -NoProfile -File .\scripts\team\Initialize-TeamDatabase.ps1
pwsh -NoProfile -File .\scripts\team\Install-TeamFrontend.ps1
pwsh -NoProfile -File .\scripts\team\Build-TeamBackend.ps1
pwsh -NoProfile -File .\scripts\team\Build-TeamFrontend.ps1
```

Setup 会询问一个新的小写 `freshlink_*` 数据库名及本机应用账号密码；工具不在 PATH 时用参数指定路径。初始化时另行输入 MySQL 管理员账号，脚本只创建尚不存在的新库和缺失的受限应用账号，拒绝已有数据库。已有应用账号不会被改密码或扩大权限。**不要导入原始课程数据库 dump，不使用其他人的本机凭据。**

本机配置和演示密码以 Windows DPAPI 加密保存于被 Git 忽略的 `runtime/config/`。每个人都要单独初始化，不能相互复制此文件。在自己的电脑明确执行以下命令，才能查看自己的登录密码：

```powershell
pwsh -NoProfile -File .\scripts\team\Show-TeamDemoAccounts.ps1
```

账号：`admin`（系统管理）、`fresh_hq`（总部）、`fresh_wh`（仓管）、`fresh_store_a` 和 `fresh_store_b`。门店账号分别绑定 A/B。密码各机随机生成。AI Key 可在 P6 本机配置，未配置不影响基础业务启动。

## 启动和验证

在两个终端分别运行，按 Ctrl+C 停止各自服务：

```powershell
pwsh -NoProfile -File .\scripts\team\Start-TeamBackend.ps1
pwsh -NoProfile -File .\scripts\team\Start-TeamFrontend.ps1
```

默认前端 http://127.0.0.1:13102/ ，后端 http://127.0.0.1:18081/jeecg-boot ，Redis DB 14。使用 Setup 中记录的实际端口；它们与原开发机 P1 验收实例隔离。运行时关闭 Flyway 自动迁移与 Quartz 自动任务，数据库由明确列出的 SQL 初始化。

```powershell
pwsh -NoProfile -File .\scripts\team\Test-Team.ps1 -EvidenceDirectory work\test-evidence\P2-A-first
```

这会真正运行 fresh 白名单测试。默认 Maven `package` 跳过测试，不能只凭构建成功判定业务通过。当前有可比较的全量类型存量错误；后续不得新增诊断，也不能把存量错误基线说成全量类型通过。

详细环境与参数见 [团队本机开发指南](docs/团队本机开发指南.md)。根 `scripts/` 中旧 P0/P1 探针和本机脚本保留供参考，包含历史路径和账号约束；**新同学使用 `scripts/team/`，不要直接运行旧普通启动入口或原库恢复脚本**。

## 提交和验收

从负责人确认的基线开个人分支，逐个暂存本人修改的文件，commit 后 push 本人分支并创建 PR。PR 模板会要求批次、接口合同、配套前后端 SHA、真实命令/测试数、脱敏证据及回退方式。开发者负责先完成自测；负责人审查通过后继续下一批。已有批次合并后，从最新 `main` 开下一批分支。

阶段规则以 [specs/生鲜课设改造/README.md](specs/生鲜课设改造/README.md)、`mission.md`、`state-contract.md` 和 `validation.md` 为准。历史规格中的 `D:\Yuki\...`、固定测试库及双 Git 仓库描述是原机证据背景；本克隆副本的实际工作根是此 README 所在目录，本机配置以团队入口为准。业务边界和验收断言保持原合同，不能借目录适配删减。

本机验收材料放 `work/`，不上传原始密码、Token、用户数据或完整私有快照；需要共享的脱敏摘要放 `docs/acceptance/`。历史 P1 验收摘要已保留，原机完整证据没有上传。导出后的配置脱敏与初始化另行验证，不把它称为 P2 验收。

## 目录和来源

```text
apps/backend/       Java 后端及 db/team、db/fresh 数据库脚本
apps/web/           Vue 前端及 pnpm 锁文件
scripts/team/       新克隆环境的初始化、构建、启动和测试入口
specs/              业务合同、P2～P7 计划与验收标准
docs/tasks/         两位开发同学的独立任务书
docs/acceptance/    可分享的验收摘要
runtime/            各人本机配置和缓存，Git 忽略
work/               各人自测证据，Git 忽略
```

上游许可与来源见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。本仓库保留原许可证，不包含原仓库 `.git` 历史、原始数据库、缓存、JAR 或前端构建产物。
