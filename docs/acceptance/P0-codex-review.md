# P0 独立验收报告

日期：2026-11-17（Asia/Shanghai）。结论：**通过，仅限 P0 基线阶段**。

按 `specs/生鲜课设改造/validation.md` 的 P0-01～06 评定。P0 允许记录原有业务断点并分配后续阶段；本结论不表示生鲜业务闭环或原出库链已经完成，不授权自动进入 P1。

## 验收版本与证据

- 后端 HEAD：`4c9b88fe5e2bb41d878551b7990b306e80aa50e2`；前端 HEAD：`82ecedc4c62c03b1de1e02164d24299610c1545d`，均包含交付时未提交及未跟踪源码。
- 交付基线：`work/fresh-baseline/codex-p0-20261117-delivery-v2/manifest.json`。独立核对当前工程 3,594 个文件，缺失/内容不符均为 0；详见 `independent-review/source-verification.md`。
- 原交付 evidence manifest 的 122 份证据逐一校验通过；重建前 build manifest 的 1,578 个文件全部匹配。结果在 `evidence-integrity.json`、`build-integrity-before.json`。
- 原交付后端实例 PID 19256，监听 `127.0.0.1:18080`，JAR SHA256 `464546445853618c667c7ada9dbfa852236e29bed6dc9aa8a90236bfdb2b0950`。已复核实际进程路径和克隆库参数，不以端口存在代替身份验证。
- 生产包预览 PID 48880，`127.0.0.1:13101`，由项目 `Serve-P0Build.py` 提供并代理隔离后端。只读在线查询确认测试账号限于克隆库。

## 逐项结论

| 编号 | 结论 | 独立复核及证据 |
|---|---|---|
| P0-01 | 通过 | 活动目录、两仓 HEAD、未提交/未跟踪源码及根规格/脚本均有快照；当前文件与 v2 manifest 一致。见 source-verification.md。 |
| P0-02 | 通过 | 复查备份/恢复退出码及原库保护记录；在线只读确认克隆库 148 表、权限隔离，连接原库被拒绝。原库前后表清单及关键计数记录一致。见 independent-review/db/verification.md。 |
| P0-03 | 通过 | 独立重跑前后端构建均退出 0；核对运行身份与原交付产物。浏览器沿用已有管理员登录会话，实际打开出库列表及新增弹窗，空提交提示 8 项必填错误；刷新新构建后查询专用单据成功。原登录操作证据已审阅，本轮未退出并重新输入验证码登录。 |
| P0-04 | 通过 | 对既有 API 请求/响应和真实数据库结果交叉复核：专用 SKU 收货 +3、上架 -3/+3，同批次，最终库存 3/0/3。出库已审核、分配失败，未伪造下游成功；断点已归 P3。本轮不重复写入业务数据。 |
| P0-05 | 通过 | 独立运行 Test-Fresh.ps1：后端执行 2、失败 0、错误 0、跳过 0；前端执行 2、失败 0。测试确实调用现有库存服务及前端合同，满足最小入口要求。前端生产构建成功。 |
| P0-06 | 通过 | 数量 INT 上限及 long 汇总、现状与目标状态映射、旧/新批次唯一键、迁移及历史待核验策略、单单拣货路线明确；后续落实不冒充当前实现。 |

## 本轮实际命令与运行边界

在项目根执行，未安装依赖、未下载文件：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Fresh.ps1 -EvidenceDirectory work\fresh-acceptance\P0\attempt-01\independent-review\tests
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Backend.ps1 -Offline
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Frontend.ps1
```

以上退出码均为 0。构建日志与测试日志分别保存于 `independent-review/backend-build.log`、`frontend-build.log`、`tests/`；独立 Surefire XML 已复制。默认 package 仍跳过测试，测试结论来自单独执行的 p0-tests profile。

重建会改写 target/dist：本轮后端 target SHA256 为 `8d4ea1d24d6b0318955689c5fe9373d0fa0790de02298b9685da28d090424d56`，运行实例继续使用原交付 JAR。递归解包比较确认无文件新增/删除、全部叶子文件内容相同，差异仅 ZIP 打包信息，见 `jar-content-comparison.json`。前端重建也改变产物哈希/资源名，已刷新浏览器检查新 dist 可用；**没有声称新旧产物逐字节相同**。重建后的完整绑定另存 `rebuild-manifest.json`，未覆盖原交付 manifest。

浏览器实测：出库列表含专用单号 `OBD202611170001`、状态“审核通过”、来源 `FRESH_DEMO_P0_20261117_153622`；筛选后仅 1 条。空表错误检查后取消新增，没有业务保存。截图为 `independent-review/form-validation.jpg` 和 `rebuilt-order.jpg`。本轮捕获的浏览器 error 日志为空，不代表整个系统所有页面无错误。

## 必须带入后续阶段的问题

1. **P1**：全量类型检查仍未通过，既有 `MyComment.vue` 空 v-show 和检查器栈问题必须建立/处理明确基线；生产构建及局部 Jest 不能替代全量类型检查。验证码日志问题需安全收口。
2. **P2**：原库已有 2 行库存不平衡、总差 31，空批次历史库存不得自动当作新鲜可配库存，也不得擅自平账。
3. **P3/P4**：订单分配仍为失败占位、波次创建仍有 TODO，拣货/发货批次贯通未通过。需补整单分配、单单拣货任务及发货追溯；原工作量估计不再可作为保证。
4. **后续测试**：当前库存服务测试使用 mock 持久层，不能证明真实 MySQL 事务、幂等或并发安全。P2～P4 对应用例必须实际执行。
5. 首次开发自测曾调用旧顺丰接口，其外部副作用未知，原报告已披露；本轮只运行 fresh 白名单测试，未再次调用该接口。未知外部影响未被本次验收消除。

数据库恢复实操采用原交付日志并通过在线结果复核，本轮没有再次创建/恢复第二套库；未做全库逐行 checksum。原登录证据采用交付记录，本轮验证已认证会话及页面真实查询。未验证干净安装、门店 A/B 权限、新生鲜闭环、真实模型、用户答辩设备。这些边界不扩大为 P0 已完成事项。

验收期间未修改生产业务源码或原业务库，未进入 P1。验收后仅同步 README 与 roadmap 的 P0 状态；该文档变更发生在快照核对后，原冻结快照及历史自测记录保持不变。下一阶段须经用户明确授权继续。
