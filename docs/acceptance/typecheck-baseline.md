# 协作导出类型诊断基线

本协作副本按锁文件干净安装依赖后实际运行完整 vue-tsc。当前 2691 条存量诊断，检查器非零退出；不是全量类型通过。与 P1 原基线比较时忽略位置移动，新增 0 条，移除 0 条。

原始基线为 typecheck-baseline.log。以后从仓库根执行以下命令比较，须自行安装 Python 3（脚本只用标准库）：

```powershell
python scripts/Test-FreshTypecheck.py --evidence work/typecheck/P2-A --reference docs/acceptance/typecheck-baseline.log
```

比较脚本退出0表示没有新增诊断，不代表底层检查器退出0。证据目录须使用新路径。不得裁剪 tsconfig 或屏蔽错误来通过，影响实际业务的错误仍需修复。
