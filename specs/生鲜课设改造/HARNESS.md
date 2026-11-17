# DeepSeek Harness 执行说明

## 当前入口：P1 独立验收通过 后续改为团队协作

2026-11-17：P1 attempt-02 已由 Codex 独立复验通过，当前结论为 `work/fresh-acceptance/P1/attempt-02/codex-review.md`。后续用户计划由两位开发同学分工、自己负责验收，分别使用 `outputs/fresh/协作任务书/` 中任务书；GitHub 仓库及已验收基线尚未准备，本次不自动实施 P2。以下 P1 首次/修复指令保留作历史，不应当作当前待执行任务。

2026-11-17：早期 Harness P0 曾部分执行并撤销，记录保留在 `work/rollback-p0-20261117-144457/`。随后 Codex 重新实施 P0，并完成独立验收；有效报告为 `work/fresh-acceptance/P0/attempt-01/codex-review.md`，结论仅覆盖基线阶段。旧快照、旧试验库与撤销材料保留作历史，不作为当前验收依据。

历史上 P1 attempt-01 独立验收**未通过**；报告 `work/fresh-acceptance/P1/attempt-01/codex-review.md`。四项阻断为无角色账号跨店读数据、禁用食材仍可新增入库业务、编辑空规格/单位及非法状态落库、小数临期阈值截断。attempt-02 已修复并独立复验通过；全量类型仍有 2691 条存量诊断，本次新增 0。保留 attempt-01 及执行者自测报告，不回写历史。下方首次实施指令仅保留作原阶段范围参考。

## 给 Harness 的 P1 指令（可直接复制）

```text
工作根：D:\Yuki\Codex\Project\FreshLink。
本轮只执行 P1，完成自测、交付证据后停止，等待 Codex 独立验收。

先读根 AGENTS.md，再完整读取 specs/生鲜课设改造/README.md 及索引文件。
P0 已通过，依据 work/fresh-acceptance/P0/attempt-01/codex-review.md；同时读 delivery.md、manifest.json 和 independent-review/review-manifest.json。
当前接手说明以 specs/生鲜课设改造/HARNESS.md 为准。P0 evidence 中的“待验收”等是冻结的历史自测状态，不能覆盖独立验收结论。

先保存当前两个仓库的差异、未跟踪源码以及根脚本/规格到新的阶段快照。P0 v2 是当时交付源码；验收重建后的产物另绑定 independent-review/rebuild-manifest.json。验收及 v1.2 交接说明修改已改变根文档，按 CHANGELOG 核对，不要求它们仍与旧快照逐字节相同；不明差异先定位，不能 reset/clean 覆盖。

活动代码仅 apps/backend 与 apps/web。沿用现有技术栈、未提交修复和工作区。
先按 test-environment.md 完成启动、运行版本、测试库实际连接和页面代理校验，全部满足后才做业务写入测试。沿用现有受限测试库；原3100/8080不是写入验收环境。
沿用 P0 数据合同，后续数量例外及取消/终止规则以 mission.md、state-contract.md 为准；后者是目标合同，不代表代码已经实现。

按 roadmap.md 的 P1 与 validation.md 的 P1-01～06 实现基础资料、门店绑定、角色权限、数据库/菜单迁移、真实页面联调和测试。
同时处理 P0 验收报告归属 P1 的全量类型检查基线、旧 CRUD 权限、敏感验证码日志问题；原库存差异不自行平账，P2/P3/P4业务不提前铺开。
自动测试只执行 fresh 白名单；命令必须指定本次证据目录。不要直接运行会覆盖 P0 证据的旧探针/审计/Finalize 脚本。

证据写入 work/fresh-acceptance/P1/attempt-01/，若已存在则使用下一个未占用编号，保留全部历史。交付完整源码/根规格快照、命令退出码、实际断言数、真实接口/数据库和页面证据、未验证项。
按阶段交付模板生成 delivery.md，P1 状态记为待验收，然后停止。没有下一次明确授权不进入 P2。
```

## 后续阶段指令

每次替换 Pn 和上阶段验收报告路径；不要一次授权所有剩余阶段。

```text
上阶段 P(n-1) 已由 Codex 验收通过，报告位于：[真实路径]。
请先核对报告绑定的版本与当前工作区是否一致，阅读规格与 CHANGELOG，处理报告中属于本阶段的事项。

本轮只执行 Pn，严格按 roadmap.md 的任务及 validation.md 对应用例完成。
沿用既有测试数据库、角色和夹具，但各用例隔离，不破坏原业务数据。
前后端接口/SQL/菜单/权限/业务测试一起交付，不只制作页面。
如出现新发现，先补规格中的实施映射；若改变用户已确认范围或验收规则，列出问题交用户决定，不得自行删减。

完成后提交 work/fresh-acceptance/Pn/attempt-XX/delivery.md 及证据（XX 使用本阶段未占用编号），将状态记为待验收并停止。
等待 Codex 的独立验收，不自行进入下一阶段或宣称整个系统已完成。
```

## 验收未通过后的修复指令

```text
Pn 未通过，验收报告：[真实路径]。
请只修复该报告的阻断问题和受影响回归，不提前实现下一阶段。
保留原 attempt-01，新增 attempt-02 证据，逐条写明问题、原因、修改位置、回归用例及结果。
修复完成后停止，重新交 Codex 验收。
```

## 给 Codex 的验收请求

```text
请按 D:\Yuki\Codex\Project\FreshLink\specs\生鲜课设改造\validation.md 验收 Pn。
Harness 交付报告：[delivery.md 的真实路径]
前后端版本/快照：[报告中的版本]
测试库、启动与角色说明：[说明文件路径，不在聊天贴密码]

先检查交付证据与当前代码/运行版本是否一致，再独立复查本阶段规则并重跑关键测试；涉及新页面的检查要实际操作页面。
不要只复述 Harness 自测结论。指出阻断缺陷、未验证项和必要修复，给出“通过/未通过/待验证”。
把结果保存为该 attempt 目录下 codex-review.md；未通过则不要进入下一阶段，也不要擅自替 Harness 大范围改代码。
```

## 实施纪律

1. 用户三天目标约束的是范围和安排，不是允许跳过验证。P0 暴露重大缺口时立刻报告，先保核心链，不暗中扩大改造。
2. 只有 P0～P7 对应任务是必做；资料中的 IoT、RAG、复杂波次、快递面单不是自动追加范围。缺功能页按本次角色菜单处理，不批量修复所有历史示例模块。
3. 每阶段开始记录基线，结束记录 diff。两个 Git 仓库分别记录版本，规格在仓库外单独归档。可以采用本地阶段提交或完整文件快照，但不得覆盖未归档的现状；不推送远端、不部署公网，除非用户另行要求。
4. 并行实现时可拆“后端＋SQL”“前端＋联调”“独立测试”，先锁定接口/字段/状态合同并明确文件所有权，避免多个执行者同时改同一文件；所有人保留其他人的修改。P0 和阶段依赖不能用并行跳过。
5. 每阶段的验收证据必须来自本阶段交付版本；开发环境 Vite 页面不等于生产包可用，旧 JAR 成功响应也不能证明新代码生效。
6. 写失败测试时验证业务状态和余额都未改变；只断言返回报错不够。并发测试必须同时发起请求/事务并校验最终数据库，不能用顺序请求声称证明并发。
7. 模型集成提前提醒用户准备配置，但不索要聊天中的明文密钥。仅在后端本地配置，前端不代理暴露密钥；无凭据保留未验证标记。
8. 每次阶段报告写清“做了什么、怎么验证、尚缺什么、下一步需验收什么”。不要用“完成度 100%”替代断言结果，不把自动化通过写成人工/实际答辩设备已验收。

## 推荐交付目录

```text
apps/backend/                # 活动后端源码
apps/web/                    # 活动前端源码
docs/course/                 # 原课程讲义
resources/course-materials/  # 原始参考资料
specs/生鲜课设改造/          # 方案、验收标准与规格变更
work/migration-20261117/     # 本次迁移清单和迁移前差异快照
work/fresh-baseline/         # P0 快照与恢复材料，敏感内容仅本地保存
work/fresh-acceptance/
  P0/attempt-01/
    delivery.md
    manifest.json
    commands.md
    tests/
    api/
    db/
    screenshots/
    codex-review.md          # 由 Codex 验收时写，不由 Harness 伪填
  P1/attempt-01/...
runtime/config/              # 本机数据库、Maven 配置（不得打进交付包）
runtime/cache/               # Maven/npm/pnpm 本地缓存
runtime/redis/               # 本机 Redis 运行文件
runtime/run/                 # 当前后端运行 JAR
runtime/data/                # 本地上传及报表数据
archive/original-code/       # 同名源码原始副本，仅参考
archive/work-history/        # 迁移前日志、构建记录和修复报告
archive/downloads/           # 未完成的原始下载，仅留存待确认
outputs/fresh/               # P7 可运行交付物，包含说明与校验清单
```

目录中的数据库证据应是脱敏查询结果；含凭据/个人信息的原始本地备份不得自动打进分享包。
