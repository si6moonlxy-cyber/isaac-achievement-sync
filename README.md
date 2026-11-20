# 以撒的结合：忏悔+ 成就对账工具

Windows 上的《以撒的结合：忏悔+》存档与 Steam 成就可能出现解锁状态不一致。此工具读取当前 Steam 账户的三个《忏悔+》存档槽，与 Steam 的 641 项成就逐项比较，并在命令行列出差异。只有用户输入 Y 后，才会补报“存档已解锁、Steam 未解锁”的成就。

## 使用

1. 退出游戏，保持 Steam 客户端登录。
2. 下载本仓库的 ZIP 并解压，双击 run.cmd。
3. 查看 CMD 中的差异列表。出现“是否启用 Steam 同步”时，输入 Y 才会补报；直接回车会跳过。
4. 完整 CSV 报告保存在本地 reports 文件夹。报告不会纳入 Git。

默认自动查找 Steam 安装目录、游戏所在的 Steam 库、当前登录账户，以及 options.ini 指定的云存档或本地存档。无需把路径改成作者电脑上的目录。

## 命令行选项

在仓库目录打开 CMD：

    run.cmd -Mode Scan
    run.cmd -Mode Interactive
    run.cmd -Mode Repair

- Scan：只读扫描，不询问同步。
- Interactive：默认模式；扫描后询问是否同步。超过 `-MaxChanges` 阈值时，会提示预计耗时，并要求再输入待补报数量确认。
- Repair：明确指定后直接补报差异项，适合自己写自动化脚本时使用；超过 `-MaxChanges` 时会停止，需显式调高该参数。

自动定位失败时，可指定 -SteamRoot "D:\Steam"、-GameRoot "E:\SteamLibrary\steamapps\common\The Binding of Isaac Rebirth" 或 -SaveRoot "...\remote"。参数传给 run.cmd 即可。

默认每项成就单独提交，并间隔 120 秒；可用 `-DelaySeconds` 调整，最小为 60 秒。`-MaxChanges` 默认是 10：交互模式超过 10 项时需要再次确认数量，自动补报的 Repair 模式超过 10 项时需要显式指定更高的 `-MaxChanges`。工具不修改游戏存档，也不清除 Steam 已有成就。

## 差异含义

| 状态 | 含义 | 工具操作 |
| --- | --- | --- |
| save_only | 存档已解锁，Steam 未解锁 | 经确认后可补报到 Steam |
| steam_only | Steam 已解锁，当前三个存档槽均未解锁 | 仅报告 |
| both / neither | 两边状态相同 | 不操作 |

Steam 的接口只接受新的解锁状态，不能指定过去的解锁时间。补报后显示的是**执行时间**；间隔提交可以得到不同的新时间，无法还原历史完成时间。

## 适用范围

本工具针对 Windows Steam 版《忏悔+》目前的 641 项成就，支持旧版 `ISAACNGSAVE09R` 和正式版 `ISAACNGSAVE10R` 存档格式。已用本机正式版 J510（Steam Build ID `26774712`）的当前存档验证；扫描时会显示实际读取的格式，无需转换存档或恢复旧备份。

工具会校验存档校验值、成就块 ID/长度/条目数、状态值、Steam 当前账户和成就总数；未知格式或数据结构不符时会停止，避免误报。它使用游戏安装目录自带的 steam_api.dll，仓库不包含 Steam DLL、游戏文件、个人存档或账户数据。

## 开发验证

以下测试只读取脚本中的解析和确认函数，不会初始化 Steam 或提交成就：

    powershell -NoProfile -ExecutionPolicy Bypass -File tests\SaveFormat.Tests.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\SyncPolicy.Tests.ps1

存档测试使用内存中生成的数据，覆盖 09R/10R、未知格式、校验值损坏、块结构不符和异常状态值。可添加 `-SaveRoot "...\remote"` 参数，只读验证本机当前的三个存档槽。
