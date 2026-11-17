# 隔离测试启动与写入前核验

适用：Harness 执行 P1 及后续阶段的迁移、接口或页面写入测试。工作目录为 `D:\Yuki\Codex\Project\FreshLink`。此文规定核验步骤，不代表接手时服务仍在运行。

## 固定目标

| 对象 | 当前隔离目标 |
|---|---|
| MySQL | `127.0.0.1:3306/freshlink_p0_codex_20261117_b` |
| 应用账号 | `freshlink_p0_app_b`，配置 `runtime/config/p0-db-credentials.json`；只授权上述库 |
| 后端 | `http://127.0.0.1:18080/jeecg-boot`，JAR `runtime/run/p0/jeecg-system-start.jar` |
| 开发前端 | `http://127.0.0.1:13100/`，代理 `/jeecgboot` 到上述后端 |
| 生产包预览 | `http://127.0.0.1:13101/`，项目 Serve-P0Build.py 提供 dist 并代理上述后端 |
| Redis | DB 15；测试上传、webapp 在 `runtime/data/p0/` |

普通 `Start-FreshLink.cmd` 的 3100/8080 仍面向原业务库 `xingchenwms`。业务写入验收使用上表入口，不使用普通启动入口。仅建库或修改密码不能证明连接已切换。

隔离后端启动脚本已通过命令行覆盖完整 URL（不是只覆盖密码）：

```text
jdbc:mysql://127.0.0.1:3306/freshlink_p0_codex_20261117_b?characterEncoding=UTF-8&useUnicode=true&useSSL=false&tinyInt1isBit=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai
```

## 启动顺序

先确认本机 MySQL80 与 Redis 可用；沿用现有配置，缺失时查 `docs/本机环境与启动.md`，不要输出凭据文件。已有测试库直接使用，Initialize/Configure 脚本属于一次性恢复/配置操作，拒绝已有对象是保护，不是让执行者删库重试。

从项目根执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Backend.ps1 -Offline
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-P0Backend.ps1 -DatabaseName freshlink_p0_codex_20261117_b
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-P0Frontend.ps1
```

生产包检查则构建前端，并启动生产预览（开发前端与生产预览可二选一）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Frontend.ps1
python .\scripts\Serve-P0Build.py
```

最后一条在终端前台常驻；由自动化启动后台实例时用隐藏窗口并保留 PID。端口已占用时不要重复启动：先按下节核对现有实例。源码重建后，确认旧监听 PID 的命令路径属于本项目，再只停止该测试 PID、重新执行隔离启动；不按进程名批量结束 Java/Node，也不停止共享 MySQL/Redis。

## 每阶段首次写入前的四项证据

1. **进程与版本**：记录 18080 的监听地址/PID，确认进程命令行包含上述 JAR 路径、`--server.port=18080` 和精确测试库 URL；记录运行 JAR 与本次 target JAR 的 SHA256，一致才使用。只输出判定与必要字段，不输出整个可能含敏感值的命令行。P0 验收曾重建 target 而未替换运行 JAR，接手不能把历史 PID 或历史 hash 当作当前证明，应重新部署本阶段构建。
2. **数据库实际连接**：使用受限应用账号运行以下只读检查；记录数据库名、授权范围、应用会话数量。`SELECT DATABASE()` 单独只证明命令行客户端的连接，须结合应用连接池会话及第 1 项判断。

```powershell
$cfg = Get-Content runtime/config/p0-db-credentials.json -Raw | ConvertFrom-Json
if ($cfg.schema -cne 'freshlink_p0_codex_20261117_b' -or $cfg.host -cne '127.0.0.1' -or $cfg.username -cne 'freshlink_p0_app_b') { throw 'Unexpected test database configuration' }
$previousMysqlPwd = $env:MYSQL_PWD
try {
    $env:MYSQL_PWD = $cfg.password
    $query = "SELECT DATABASE() AS connected_schema,CURRENT_USER() AS authenticated_account; SHOW GRANTS FOR CURRENT_USER; SELECT COUNT(*) AS app_pool_connections FROM information_schema.processlist WHERE USER='freshlink_p0_app_b' AND DB='freshlink_p0_codex_20261117_b' AND ID<>CONNECTION_ID();"
    & 'D:\Yuki\MySQL\bin\mysql.exe' --no-defaults --host=127.0.0.1 --port=3306 --user=$cfg.username --database=$cfg.schema --batch --raw -e $query
    if ($LASTEXITCODE -ne 0) { throw 'Database identity check failed' }
} finally { $env:MYSQL_PWD = $previousMysqlPwd; $cfg = $null }
```

预期库名精确匹配，授权仅测试 schema（全局 USAGE 不代表全局业务权限），应用连接池会话数大于 0。若为 0，先做正常只读列表请求再核验，仍为 0 则停止写入排查。迁移若需额外 DDL 权限，仅使用隔离库授权，不用原库 root 凭据启动应用。

3. **页面至后端链路**：确认浏览器 URL 是 13100 或 13101；通过浏览器网络面板/代理配置核对 `/jeecgboot` 去向 18080。对 13100 查实际 Vite 启动环境和代理解析结果，不能仅凭 Node 命令路径判断代理。对 13101 核对 Python 进程确实执行本项目 Serve-P0Build.py。页面查询 P0 专用单据 `OBD202611170001`（来源 `FRESH_DEMO_P0_20261117_153622`），结果与测试库只读 SQL 对照；该单据只是只读连接标记，不再执行其业务动作。标记缺失时查明原因，不能跳过连接检查直接写入。
4. **证据与保护**：把上述脱敏结果、时间、命令/退出码、前后端版本写入本阶段 `attempt-XX/environment.md`。任一项失败/未知时停止迁移和业务写入，先修环境。通过后，每个写入用例再按专用业务 ID 对照测试库前后数量，保留原库不受影响的证据。

## 避免覆盖 P0 的证据

P0 的 `delivery.md`、`handoff.md`、`docs/state-map.md`、manifest 及截图是冻结历史材料，保留原文；当前状态以 `codex-review.md`、当前 roadmap 和 HARNESS 为准。P1 新证据不能写回 P0 目录。

测试入口有默认 P0 路径，接手必须显式指定新目录，例如：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Fresh.ps1 -EvidenceDirectory work\fresh-acceptance\P1\attempt-01\tests
python .\scripts\Save-P0Snapshot.py work\fresh-baseline\p1-attempt-01-before
```

目录名只作示例：若已存在，选择下一个未占用编号，不覆盖。Save-P0Snapshot.py 虽沿用 P0 名称，但可接收新的快照路径并拒绝覆盖；它保存两仓差异/未跟踪文件及根脚本/规格。新增后续独立文档目录时须扩展归档范围或另附清单。

`Get-P0DatabaseAudit.ps1`、`Finalize-P0Evidence.py` 等旧脚本含固定 P0 输出路径；`Invoke-P0BusinessProbe.ps1` 面向 P0 试验。它们不能直接作为 P1 证据生成器。后续阶段应提供可指定阶段/证据目录的入口，记录前后版本；保留原脚本及原证据。重建 dist/target 会改变产物 hash，阶段结束生成自己的 build manifest，不重写 P0 原清单。
