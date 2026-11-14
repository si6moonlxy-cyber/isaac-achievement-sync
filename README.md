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
- Interactive：默认模式；扫描后询问是否同步。
- Repair：明确指定后直接补报差异项，适合自己写自动化脚本时使用。

自动定位失败时，可指定 -SteamRoot "D:\Steam"、-GameRoot "E:\SteamLibrary\steamapps\common\The Binding of Isaac Rebirth" 或 -SaveRoot "...\remote"。参数传给 run.cmd 即可。

默认每项成就单独提交，并间隔 120 秒；可用 -DelaySeconds 调整，最小为 60 秒。一次最多补报 10 项；要处理更多项需显式指定 -MaxChanges。工具不修改游戏存档，也不清除 Steam 已有成就。

## 差异含义

| 状态 | 含义 | 工具操作 |
| --- | --- | --- |
| save_only | 存档已解锁，Steam 未解锁 | 经确认后可补报到 Steam |
| steam_only | Steam 已解锁，当前三个存档槽均未解锁 | 仅报告 |
| both / neither | 两边状态相同 | 不操作 |

Steam 的接口只接受新的解锁状态，不能指定过去的解锁时间。补报后显示的是**执行时间**；间隔提交可以得到不同的新时间，无法还原历史完成时间。

## 适用范围

本工具针对 Windows Steam 版《忏悔+》目前的 641 项成就和 ISAACNGSAVE09R 存档格式。它会校验存档校验值、Steam 当前账户和成就总数；游戏版本或存档格式变化时会停止，避免误报。它使用游戏安装目录自带的 steam_api.dll，仓库不包含 Steam DLL、游戏文件、个人存档或账户数据。
