# P1 修复独立验收报告

日期：2026-11-17，Asia/Shanghai。结论：**通过**。P1-01～06 在本阶段范围内满足验收要求，上次四项阻断均已解决；全量类型检查仍有存量错误，但可比较基线和本次无新增诊断要求已满足。本报告只覆盖 P1 基础资料和权限骨架，不代表 P2～P7 已完成。

## 版本与证据

- 后端 HEAD `4c9b88fe5e2bb41d878551b7990b306e80aa50e2`，前端 HEAD `82ecedc4c62c03b1de1e02164d24299610c1545d`；两者均以包含未提交及未跟踪文件的实际工作区为准。
- 独立核对最终源码快照列明的 3,647 个文件，差异 0。源码 manifest SHA256 `0f5af87d482340d3614fb57c210ce862b784a7d7c3bd561c82ae6ad708e4fc93`。核对原交付清单 230 个文件、生产包 1,583 个文件，差异均为 0。见 `independent-review/delivery-verification.json`。本轮新增验收文件不属于原冻结清单，不回写原 manifest。
- 写入前重新核验进程、JAR、受限数据库连接、生产预览代理及 P0 单据标记，全部通过。后端 127.0.0.1:18080，生产包预览 13101，测试库 `freshlink_p0_codex_20261117_b`；实际 PID 和会话数见 `independent-review/environment.json`。原 3100/8080 未用于业务写入验收。
- 业务和页面测试使用运行 JAR SHA256 `d26cc6f27a66819881ef6f0b44a6276d5a7940d29ae424b610076962931a241c`，开始测试时与 target 相同。后续独立重建 target 为 `1c6853721b54e077dc61298bc7a5423e060eae8622527617893aa8f427147b6c`；递归解包比较 203,739 个叶文件，新增、缺失、内容差异均为 0，差异仅在 ZIP 包装元数据。不能把重建后的 target 哈希写成已经重启的运行 JAR。见 `independent-review/build/jar-content-comparison.json`。

## 上次四项阻断的复验

| 问题 | 本轮独立复查与动态结果 | 结论 |
|---|---|---|
| F1 无角色账号跨店读取 | 服务端显式检查总部、仓管、门店角色；零角色、仅绑定、未绑定、悬空及失效绑定拒绝；总部/仓管两店可读，A/B 仅本店，跨店请求拒绝 | 修复通过 |
| F2 禁用食材新增入库业务 | 新增/导入和编辑共用存在、货主、启用状态检查；新增禁用品、替换、增量及伪造明细 ID/状态均不能绕过；失败后单据不变；旧承诺保持/减少且提交审核可达 | 修复通过 |
| F3 编辑清空规格单位和写非法状态 | 新增与编辑共享必填和状态枚举校验；非法请求拒绝，数据库无脏数据 | 修复通过 |
| F4 小数阈值静默截断 | 局部严格整数反序列化；新增和编辑小数、负数、空值及越界拒绝，合法 0 可保存；不依赖截断后的 Integer 再校验 | 修复通过 |

静态审查由独立审查智能体完成，动态验收由主验收执行者独立运行现有测试及真实 API/DB、浏览器探针。专项证据在 `independent-review/repair-api/`，共 72/72 条断言，失败 0；包括失败请求前后数据库检查及临时数据清理。未发现新的 P1 阻断缺陷。

## 逐项结果

| 用例 | 结果 | 证据与边界 |
|---|---|---|
| P1-01 基础资料 | 通过 | 原 API 69/69 与生产页面 16/16 覆盖保存重查、食材温区/规格、W1/库位、供应商、门店和菜单。真实浏览器实际空提交供应商表单、填写保存、列表刷新，并登录门店 A；已查看关键截图。 |
| P1-02 非法输入与唯一性 | 通过 | 原非法值和重复编码测试、专项新增/编辑反例、单元测试通过；失败后数据库不变。 |
| P1-03 禁用与引用保护 | 通过当前阶段范围 | 禁用食材新入库和编辑增量拒绝，旧承诺可保持/减少并提交审核；门店绑定/食材引用删除保护通过。P2/P3 新增批次和申领引用、旧单收货/配送完成路径须在所属阶段继续补齐和验证。 |
| P1-04 角色隔离 | 通过 | A/B 本店过滤、默认拒绝无角色账号、旧库存 CRUD/导入、系统管理和自改门店绑定均由后端拒绝；页面门店 A 只见本店。 |
| P1-05 迁移 | 通过 | 本轮三个 SQL 各执行两遍，6 次执行均退出 0；每遍结束即取数，角色授权不重复、菜单字典及计数稳定、旧出库菜单保留。初次从基线库升级采用既有 P1 交付及上次独立审查证据复核，本轮未重新恢复另一干净库，不冒称本轮重做初次升级。 |
| P1-06 构建与测试 | 通过 | 前后端独立构建均退出 0；真实后端 12 执行/12 通过/0 失败错误跳过；前端 2 套件 4 测试全部通过。独立全量类型诊断与交付最终基线逐条一致，无新增。重建生产包后实际浏览器重新登录并打开食材页，只读断言通过，见 rebuilt-ui/。 |

## 类型检查的准确结论

独立重新运行完整 vue-tsc：2,691 条诊断，与交付最终日志按文件、行列、错误码及消息逐条比较，新增 0、移除 0。比较脚本退出 0，原始检查器本轮退出 **2**，交付自测记录为退出 1；两者均为非零，**全量类型检查仍未通过**。这是可比较存量基线通过，不是全量类型无错误。

未升级依赖、裁剪 tsconfig 或屏蔽错误。完整日志和比较结果在 `independent-review/typecheck/`；P1 所需“可执行、可比较基线及无新增诊断”已经满足。后续开发必须维持无新增，并另行处理涉及实际业务的错误。

## 原库保护与遗留事项

验收前后对原库及隔离库共 68 张 wms_/fresh_ 业务表做只读 CHECKSUM TABLE EXTENDED。原业务库 32 张表全部一致；隔离库只有 wms_products、fresh_user_store 校验值变化，对应测试禁用后恢复和门店改绑后恢复引起的更新时间/绑定记录变化，业务计数和临时数据清理断言通过。该证据覆盖本轮采样区间，不覆盖系统登录日志、Redis 或更早操作，不声称整个测试库逐字节还原。见 `independent-review/database-comparison.json`。

下列不是本轮新增已证阻断，但必须如实保留：

- 新增批次、申领、配送后，要扩展主数据引用保护；现有 FreshReferenceGuard 尚不能自动保护未来表。
- FreshAccessService.requireBoundStore 当前同时要求门店启用。P3/P4 必须分开“本店身份及历史单据权限”和“允许创建新业务”，不能因禁用门店导致旧单无法读取/签收。
- 原出库分配为失败占位、复杂波次创建有 TODO，仍属于 P3 工作；不能把 P1 通过当作整个仓储配送链已能运行。
- 公共附件、jmreport 以及所有合法签名字典查询的业务数据隔离没有全面验证；本轮未证实泄露，不将疑点写成已复现漏洞。后续涉及相关入口时继续验证。
- 历史 WebSocket/CLodop/socket 资源告警仍保留，含旧资源 404；P1 新页面和接口测试无阻断错误，不等于全部历史模块无告警。原系统标题和主题收口归 P5。
- 未执行干净安装、全量历史页面、真实 AI/IoT、用户答辩设备验证；P7 需完成干净重建与最终组合版本 E2E。旧库存差异未自动平账。

## 实际命令和复跑说明

以下为本轮实际执行命令，均在项目根执行，证据显式写入 independent-review，不覆盖 P0 或原自测文件。重新执行时必须换成新的空证据目录，已有目录的覆盖保护拒绝属于预期。源码初始校验在验收状态文档更新前执行；当前代码与冻结快照之间的五份预期状态文档差异单列于 final-source-check.json，业务源码差异为 0。

```powershell
python work/fresh-acceptance/P1/attempt-02/independent-review/verify_delivery.py
pwsh -NoProfile -File scripts/Test-FreshP1Environment.ps1 -EvidenceDirectory work/fresh-acceptance/P1/attempt-02/independent-review -PageBase http://127.0.0.1:13101
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Test-Fresh.ps1 -EvidenceDirectory work/fresh-acceptance/P1/attempt-02/independent-review/tests
pwsh -NoProfile -File scripts/Get-FreshDatabaseProtection.ps1 -EvidenceDirectory work/fresh-acceptance/P1/attempt-02/independent-review/db-before
pwsh -NoProfile -File scripts/Invoke-FreshP1RepairProbe.ps1 -EvidenceDirectory work/fresh-acceptance/P1/attempt-02/independent-review/repair-api
pwsh -NoProfile -File scripts/Invoke-FreshP1ApiProbe.ps1 -EvidenceDirectory work/fresh-acceptance/P1/attempt-02/independent-review/api
pwsh -NoProfile -File scripts/Invoke-FreshP1UiProbe.ps1 -EvidenceDirectory work/fresh-acceptance/P1/attempt-02/independent-review/ui -BaseUrl http://127.0.0.1:13101
pwsh -NoProfile -File scripts/Invoke-FreshP1Migration.ps1 -EvidenceDirectory work/fresh-acceptance/P1/attempt-02/independent-review/migration
pwsh -NoProfile -File scripts/Get-FreshDatabaseProtection.ps1 -EvidenceDirectory work/fresh-acceptance/P1/attempt-02/independent-review/db-after
python scripts/Test-FreshTypecheck.py --evidence work/fresh-acceptance/P1/attempt-02/independent-review/typecheck --reference work/fresh-acceptance/P1/attempt-02/typecheck-after.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Build-Backend.ps1 -Offline
python work/fresh-acceptance/P1/attempt-02/independent-review/compare_builds.py
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Build-Frontend.ps1
node work/fresh-acceptance/P1/attempt-01/independent-review/Rebuilt-UI.mjs work/fresh-acceptance/P1/attempt-02/independent-review/rebuilt-ui
```

已完成命令退出 0，类型检查原始退出 2 已单列。首次专项探针因 environment.json 置于 environment 子目录而拒绝执行（退出 1），未进入业务写入；随后按探针约定在父目录重新执行环境核验，再执行成功。首次构建比较脚本遇一份内嵌 ZIP 不可解包而退出 1，修正为对该内嵌文件逐字节哈希比较后成功；不忽略该文件差异。

本轮未修改业务源码，不推送远端，不进入 P2。验收状态最终更新后，仅同步根 README 和规格 README/HARNESS/roadmap/CHANGELOG；原交付报告、快照、manifest 和 attempt-01 结论保持冻结。
