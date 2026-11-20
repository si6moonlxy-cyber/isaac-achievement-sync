param(
    [ValidateSet('Interactive', 'Scan', 'Repair')][string]$Mode = 'Interactive',
    [string]$SteamRoot = '',
    [string]$GameRoot = '',
    [string]$SaveRoot = '',
    [ValidateRange(60, 3600)][int]$DelaySeconds = 120,
    [ValidateRange(1, 641)][int]$MaxChanges = 10
)

$ErrorActionPreference = 'Stop'
$AppId = '250900'
$MaxAchievementId = 641
$AchievementOffset = 32
$ReportRoot = Join-Path $PSScriptRoot 'reports'

if ([Environment]::Is64BitProcess) {
    throw '请运行仓库中的 run.cmd；它会调用游戏所需的 32 位 PowerShell。'
}

function Resolve-SteamRoot([string]$override) {
    if ($override) {
        $resolved = [IO.Path]::GetFullPath($override)
        if (-not (Test-Path -LiteralPath (Join-Path $resolved 'steam.exe'))) { throw "SteamRoot 不是 Steam 安装目录：$resolved" }
        return $resolved
    }
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    try {
        $reg = Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction Stop
        if ($reg.SteamPath) { $candidates.Add($reg.SteamPath) }
        if ($reg.SteamExe) { $candidates.Add((Split-Path $reg.SteamExe -Parent)) }
    } catch { }
    $steamProcess = Get-Process -Name steam -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($steamProcess -and $steamProcess.Path) { $candidates.Add((Split-Path $steamProcess.Path -Parent)) }
    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($programFilesX86) { $candidates.Add((Join-Path $programFilesX86 'Steam')) }
    if ($env:ProgramFiles) { $candidates.Add((Join-Path $env:ProgramFiles 'Steam')) }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ($candidate -and (Test-Path -LiteralPath (Join-Path $candidate 'steam.exe'))) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    throw '找不到 Steam 安装目录。请指定 -SteamRoot。'
}

function Resolve-GameRoot([string]$override, [string]$steamPath) {
    if ($override) {
        $resolved = [IO.Path]::GetFullPath($override)
        if (-not (Test-Path -LiteralPath (Join-Path $resolved 'steam_api.dll'))) { throw "GameRoot 中没有 steam_api.dll：$resolved" }
        return $resolved
    }
    $libraries = New-Object 'System.Collections.Generic.List[string]'
    $libraries.Add($steamPath)
    $foldersFile = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $foldersFile) {
        foreach ($line in [IO.File]::ReadAllLines($foldersFile)) {
            if ($line -match '^\s*"path"\s*"([^"]+)"') {
                $libraries.Add($matches[1].Replace('\\', '\'))
            }
        }
    }
    foreach ($library in ($libraries | Select-Object -Unique)) {
        $manifest = Join-Path $library "steamapps\appmanifest_$AppId.acf"
        if (-not (Test-Path -LiteralPath $manifest)) { continue }
        $content = [IO.File]::ReadAllText($manifest)
        if ($content -notmatch '(?m)^\s*"installdir"\s*"([^"]+)"') { continue }
        $folderName = $matches[1]
        $candidate = Join-Path (Join-Path $library 'steamapps\common') $folderName
        if (Test-Path -LiteralPath (Join-Path $candidate 'steam_api.dll')) { return [IO.Path]::GetFullPath($candidate) }
    }
    throw '找不到已安装的《以撒的结合：重生》。请指定 -GameRoot。'
}

function Resolve-SaveRoot([string]$override, [string]$steamPath, [uint64]$steamId) {
    if ($override) {
        $resolved = [IO.Path]::GetFullPath($override)
        if (-not (Test-Path -LiteralPath $resolved)) { throw "SaveRoot 不存在：$resolved" }
        return $resolved
    }
    [uint64]$base = 76561197960265728
    if ($steamId -lt $base) { throw "SteamID 无效：$steamId" }
    $accountId = ($steamId - $base).ToString()
    $cloudRoot = Join-Path $steamPath "userdata\$accountId\$AppId\remote"
    $documents = [Environment]::GetFolderPath('MyDocuments')
    $localRoot = Join-Path $documents 'My Games\Binding of Isaac Repentance+'
    $options = Join-Path $localRoot 'options.ini'
    $cloudSetting = ''
    if (Test-Path -LiteralPath $options) {
        $setting = Select-String -LiteralPath $options -Pattern '^SteamCloud\s*=\s*([01])\s*$' | Select-Object -Last 1
        if ($setting) { $cloudSetting = $setting.Matches[0].Groups[1].Value }
    }
    $cloudHasSave = @(Get-ChildItem -LiteralPath $cloudRoot -Filter 'rep+persistentgamedata*.dat' -File -ErrorAction SilentlyContinue).Count -gt 0
    $localHasSave = @(Get-ChildItem -LiteralPath $localRoot -Filter 'persistentgamedata*.dat' -File -ErrorAction SilentlyContinue).Count -gt 0
    if ($cloudSetting -eq '1') {
        if ($cloudHasSave) { return $cloudRoot }
        throw "options.ini 指定 SteamCloud=1，但找不到当前账户的云存档：$cloudRoot"
    }
    if ($cloudSetting -eq '0') {
        if ($localHasSave) { return $localRoot }
        throw "options.ini 指定 SteamCloud=0，但找不到本地存档：$localRoot"
    }
    if ($cloudHasSave -and -not $localHasSave) { return $cloudRoot }
    if ($localHasSave -and -not $cloudHasSave) { return $localRoot }
    throw "无法确定当前《忏悔+》存档目录。SteamCloud=$cloudSetting；云存档=$cloudRoot；本地存档=$localRoot。请指定 -SaveRoot。"
}

$SteamRoot = Resolve-SteamRoot $SteamRoot
$GameRoot = Resolve-GameRoot $GameRoot $SteamRoot
$ApiDll = Join-Path $GameRoot 'steam_api.dll'

$crcSource = @'
using System;

public static class IsaacSaveChecksum {
    public static bool IsValid(byte[] data) {
        if (data == null || data.Length < 24) return false;
        uint[] table = new uint[256];
        for (uint i = 0; i < 256; i++) {
            uint c = i;
            for (int bit = 0; bit < 8; bit++) {
                uint shifted = unchecked((uint)(unchecked((int)c) >> 1));
                c = shifted ^ ((c & 1) == 1 ? 0xEDB88320U : 0U);
            }
            table[i] = c;
        }
        uint crc = ~0xFEDCBA76U;
        for (int i = 16; i < data.Length - 4; i++) {
            crc = table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
        }
        return (~crc) == BitConverter.ToUInt32(data, data.Length - 4);
    }
}
'@
Add-Type -TypeDefinition $crcSource

function Read-SaveAchievements([byte[]]$data, [string]$path) {
    if ($data.Length -lt ($AchievementOffset + $MaxAchievementId + 1 + 4)) {
        throw "存档长度异常：$path"
    }
    $header = [Text.Encoding]::ASCII.GetString($data, 0, 16)
    if ($header -cnotin @('ISAACNGSAVE09R  ', 'ISAACNGSAVE10R  ')) {
        throw "不支持的存档格式 '$($header.Trim())'：$path；支持 ISAACNGSAVE09R 和 ISAACNGSAVE10R。"
    }
    if (-not [IsaacSaveChecksum]::IsValid($data)) { throw "存档校验值不匹配：$path" }

    # Both supported Repentance+ formats store block #1 at byte 20:
    # block ID, byte length, entry count, then one byte per achievement (including #0).
    $blockId = [BitConverter]::ToInt32($data, 20)
    $chunkLength = [BitConverter]::ToInt32($data, 24)
    $entryCount = [BitConverter]::ToInt32($data, 28)
    $expectedCount = $MaxAchievementId + 1
    if ($blockId -ne 1 -or $chunkLength -ne $expectedCount -or $entryCount -ne $expectedCount -or
        ($AchievementOffset + $chunkLength) -gt ($data.Length - 4)) {
        throw "成就数据块结构不符：$path；ID=$blockId，长度=$chunkLength，条目数=$entryCount，预期 $expectedCount。"
    }
    $state = New-Object 'bool[]' $expectedCount
    for ($id = 0; $id -le $MaxAchievementId; $id++) {
        $value = $data[$AchievementOffset + $id]
        if ($value -gt 1) { throw "成就 #$id 的状态值异常：$value；$path" }
        if ($id -gt 0) { $state[$id] = $value -eq 1 }
    }
    return [pscustomobject]@{ State = $state; Format = $header.Trim() }
}

function Read-GameSaves([string]$root) {
    $state = New-Object 'bool[]' ($MaxAchievementId + 1)
    $paths = @()
    $formats = @()
    for ($slot = 1; $slot -le 3; $slot++) {
        $path = Join-Path $root "rep+persistentgamedata$slot.dat"
        if (-not (Test-Path -LiteralPath $path)) {
            $path = Join-Path $root "persistentgamedata$slot.dat"
        }
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $data = [IO.File]::ReadAllBytes($path)
        $parsed = Read-SaveAchievements $data $path
        $paths += $path
        $formats += $parsed.Format
        for ($id = 1; $id -le $MaxAchievementId; $id++) {
            if ($parsed.State[$id]) { $state[$id] = $true }
        }
    }
    if ($paths.Count -eq 0) { throw "没有找到《忏悔+》存档：$root" }
    return [pscustomobject]@{ State = $state; Paths = $paths; Formats = @($formats | Select-Object -Unique) }
}

$escapedApiDll = $ApiDll.Replace('"', '""')
$source = @'
using System;
using System.Runtime.InteropServices;

public static class IsaacSteamApi {
    private const string Dll = @"__API_DLL__";

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, EntryPoint = "SteamAPI_InitSafe")]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool Init();

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, EntryPoint = "SteamAPI_Shutdown")]
    public static extern void Shutdown();

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, EntryPoint = "SteamAPI_RunCallbacks")]
    public static extern void RunCallbacks();

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, EntryPoint = "SteamAPI_SteamUserStats_v013")]
    public static extern IntPtr UserStats();

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, EntryPoint = "SteamAPI_SteamUser_v023")]
    public static extern IntPtr User();

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, EntryPoint = "SteamAPI_ISteamUser_GetSteamID")]
    public static extern ulong GetSteamId(IntPtr self);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, EntryPoint = "SteamAPI_ISteamUser_BLoggedOn")]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool IsLoggedOn(IntPtr self);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, EntryPoint = "SteamAPI_ISteamUserStats_GetNumAchievements")]
    public static extern uint GetNumAchievements(IntPtr self);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, EntryPoint = "SteamAPI_ISteamUserStats_GetAchievementDisplayAttribute", CharSet = CharSet.Ansi)]
    public static extern IntPtr GetAchievementDisplayAttribute(IntPtr self, string name, string key);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, EntryPoint = "SteamAPI_ISteamUserStats_GetAchievementAndUnlockTime", CharSet = CharSet.Ansi)]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool GetAchievementAndUnlockTime(IntPtr self, string name, out byte achieved, out uint unlockTime);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, EntryPoint = "SteamAPI_ISteamUserStats_SetAchievement", CharSet = CharSet.Ansi)]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool SetAchievement(IntPtr self, string name);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl, EntryPoint = "SteamAPI_ISteamUserStats_StoreStats")]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool StoreStats(IntPtr self);
}
'@.Replace('__API_DLL__', $escapedApiDll)

$env:SteamAppId = $AppId
$env:SteamGameId = $AppId
Add-Type -TypeDefinition $source
if (-not [IsaacSteamApi]::Init()) { throw 'Steam API 初始化失败。请确认 Steam 已登录，并从当前账户启动过游戏。' }

function Read-SteamAchievement([IntPtr]$stats, [int]$id) {
    [byte]$achieved = 0
    [uint32]$unixTime = 0
    $ok = [IsaacSteamApi]::GetAchievementAndUnlockTime($stats, [string]$id, [ref]$achieved, [ref]$unixTime)
    if (-not $ok) { throw "Steam 不认识成就 API 名称 $id；扫描已停止。" }
    return [pscustomobject]@{ Unlocked = ($achieved -ne 0); UnixTime = $unixTime }
}

function Get-AuditRows([IntPtr]$stats, [bool[]]$saveState) {
    $rows = New-Object 'System.Collections.Generic.List[object]'
    for ($id = 1; $id -le $MaxAchievementId; $id++) {
        $steam = Read-SteamAchievement $stats $id
        $namePtr = [IsaacSteamApi]::GetAchievementDisplayAttribute($stats, [string]$id, 'name')
        $displayName = if ($namePtr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::PtrToStringAnsi($namePtr) } else { '' }
        $game = $saveState[$id]
        if ($game -and -not $steam.Unlocked) { $status = 'save_only' }
        elseif (-not $game -and $steam.Unlocked) { $status = 'steam_only' }
        elseif ($game) { $status = 'both' }
        else { $status = 'neither' }
        $localTime = ''
        if ($steam.UnixTime -ne 0) {
            $localTime = [DateTimeOffset]::FromUnixTimeSeconds($steam.UnixTime).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss zzz')
        }
        $rows.Add([pscustomobject]@{
            Id = $id
            Name = $displayName
            SaveUnlocked = $game
            SteamUnlocked = $steam.Unlocked
            SteamUnlockUnix = $steam.UnixTime
            SteamUnlockLocal = $localTime
            Status = $status
        })
    }
    return $rows.ToArray()
}

function Confirm-SteamSync {
    param(
        [string]$Mode,
        [int]$Count,
        [int]$MaxChanges,
        [int]$DelaySeconds
    )

    if ($Count -eq 0) {
        if ($Mode -eq 'Interactive') { Write-Host '没有需要同步到 Steam 的成就。' }
        return $false
    }
    if ($Mode -eq 'Scan') { return $false }
    if ($Mode -eq 'Repair') {
        if ($Count -gt $MaxChanges) {
            throw "待补报 $Count 项，超过 MaxChanges=$MaxChanges；未提交任何成就。确认后可显式指定 -MaxChanges $Count 重试。"
        }
        return $true
    }

    Write-Host 'Steam 同步会为这些成就写入现在的解锁时间，无法恢复原始完成时间。'
    Write-Host "待补报 $Count 项。是否启用 Steam 同步？输入 Y 确认，直接回车跳过。"
    $answer = Read-Host
    if ($answer -notmatch '^(?i:y|yes)$') {
        Write-Host '已跳过 Steam 同步。'
        return $false
    }

    if ($Count -gt $MaxChanges) {
        $minutes = [Math]::Ceiling((8 * $Count + $DelaySeconds * ($Count - 1)) / 60)
        Write-Host "待补报 $Count 项，超过单批阈值 MaxChanges=$MaxChanges；按当前间隔预计至少约 $minutes 分钟。"
        $confirmation = Read-Host "请输入 $Count 再次确认；直接回车跳过"
        if ($confirmation.Trim() -cne $Count.ToString()) {
            Write-Host '已跳过 Steam 同步，未提交任何成就。'
            return $false
        }
    }
    return $true
}

try {
    $user = [IsaacSteamApi]::User()
    if ($user -eq [IntPtr]::Zero) { throw '无法识别当前 Steam 账户。' }
    if (-not [IsaacSteamApi]::IsLoggedOn($user)) { throw 'Steam 当前未联网登录；请先联机登录 Steam，以免读取或提交过期的成就状态。' }
    [uint64]$actualSteamId = [IsaacSteamApi]::GetSteamId($user)
    $SaveRoot = Resolve-SaveRoot $SaveRoot $SteamRoot $actualSteamId
    $save = Read-GameSaves $SaveRoot
    $stats = [IsaacSteamApi]::UserStats()
    if ($stats -eq [IntPtr]::Zero) { throw '无法读取当前账户的 Steam 成就。' }
    [uint32]$steamCount = [IsaacSteamApi]::GetNumAchievements($stats)
    if ($steamCount -ne $MaxAchievementId) { throw "Steam 当前成就数为 $steamCount，工具预期 $MaxAchievementId；已停止以避免误判。" }
    [IsaacSteamApi]::RunCallbacks()
    $rows = Get-AuditRows $stats $save.State
    $missingSteam = @($rows | Where-Object Status -EQ 'save_only')
    $missingSave = @($rows | Where-Object Status -EQ 'steam_only')

    Write-Output "Steam 目录：$SteamRoot"
    Write-Output "游戏目录：$GameRoot"
    Write-Output "存档目录：$SaveRoot"
    Write-Output "存档格式：$($save.Formats -join ', ')"
    Write-Output "已扫描 $($rows.Count) 项；存档已解锁 $(@($rows | Where-Object SaveUnlocked).Count) 项；Steam 已解锁 $(@($rows | Where-Object SteamUnlocked).Count) 项。"
    Write-Output "仅存档解锁：$($missingSteam.Count) 项；仅 Steam 解锁：$($missingSave.Count) 项。"
    foreach ($row in ($missingSteam + $missingSave)) {
        $description = if ($row.Status -eq 'save_only') { '存档已解锁，Steam 未解锁' } else { 'Steam 已解锁，当前存档未解锁' }
        Write-Output "差异：#$($row.Id) $($row.Name) —— $description"
    }

    New-Item -ItemType Directory -Path $ReportRoot -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $reportPath = Join-Path $ReportRoot "audit-$stamp.csv"
    $rows | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8
    Write-Output "报告：$reportPath"

    $shouldRepair = Confirm-SteamSync -Mode $Mode -Count $missingSteam.Count -MaxChanges $MaxChanges -DelaySeconds $DelaySeconds
    if ($shouldRepair -and $missingSteam.Count -gt 0) {
        for ($i = 0; $i -lt $missingSteam.Count; $i++) {
            $id = $missingSteam[$i].Id
            $name = [string]$id
            if (-not [IsaacSteamApi]::SetAchievement($stats, $name)) { throw "#$id SetAchievement 失败" }
            if (-not [IsaacSteamApi]::StoreStats($stats)) { throw "#$id StoreStats 失败" }
            Start-Sleep -Seconds 8
            [IsaacSteamApi]::RunCallbacks()
            $verified = Read-SteamAchievement $stats $id
            if (-not $verified.Unlocked -or $verified.UnixTime -eq 0) { throw "#$id 提交后验证失败，已停止后续补报" }
            Write-Output "已补报 #$id；Steam 时间：$([DateTimeOffset]::FromUnixTimeSeconds($verified.UnixTime).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss zzz'))"
            if ($i -lt ($missingSteam.Count - 1)) { Start-Sleep -Seconds $DelaySeconds }
        }
        $rows = Get-AuditRows $stats $save.State
    }

    if ($shouldRepair -and $missingSteam.Count -gt 0) {
        $rows | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8
        Write-Output "补报后报告已更新：$reportPath"
    }
    Write-Output "扫描存档：$($save.Paths -join ', ')"
}
finally {
    [IsaacSteamApi]::Shutdown()
}
