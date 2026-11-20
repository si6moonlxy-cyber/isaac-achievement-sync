param([string]$SaveRoot = '')

$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'IsaacAchievements.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw 'Main script has parse errors.' }

# Load only the checksum and save readers. Never initialize Steam in these tests.
$checksum = $ast.Find({
    param($node)
    $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$crcSource'
}, $true)
. ([scriptblock]::Create($checksum.Extent.Text))
Add-Type -TypeDefinition $crcSource
foreach ($name in @('Read-SaveAchievements', 'Read-GameSaves')) {
    $functionAst = $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    if (-not $functionAst) { throw "Save reader function missing: $name" }
    . ([scriptblock]::Create($functionAst.Extent.Text))
}
$MaxAchievementId = 641
$AchievementOffset = 32

Add-Type -TypeDefinition @'
using System;
using System.Text;
public static class SaveFixture {
    public static void Seal(byte[] data) {
        uint[] table = new uint[256];
        for (int i = 0; i < 256; i++) {
            int c = i;
            for (int bit = 0; bit < 8; bit++)
                c = (c >> 1) ^ ((c & 1) != 0 ? unchecked((int)0xEDB88320) : 0);
            table[i] = unchecked((uint)c);
        }
        uint crc = ~0xFEDCBA76U;
        for (int i = 16; i < data.Length - 4; i++)
            crc = table[(crc ^ data[i]) & 255] ^ (crc >> 8);
        Buffer.BlockCopy(BitConverter.GetBytes(~crc), 0, data, data.Length - 4, 4);
    }
    public static byte[] Create(string header) {
        byte[] data = new byte[32 + 642 + 4];
        Buffer.BlockCopy(Encoding.ASCII.GetBytes(header), 0, data, 0, 16);
        Buffer.BlockCopy(BitConverter.GetBytes(1), 0, data, 20, 4);
        Buffer.BlockCopy(BitConverter.GetBytes(642), 0, data, 24, 4);
        Buffer.BlockCopy(BitConverter.GetBytes(642), 0, data, 28, 4);
        data[33] = 1;
        data[32 + 641] = 1;
        Seal(data);
        return data;
    }
}
'@

foreach ($version in @('09', '10')) {
    $data = [SaveFixture]::Create("ISAACNGSAVE${version}R  ")
    $parsed = Read-SaveAchievements $data 'synthetic.dat'
    if ($parsed.Format -ne "ISAACNGSAVE${version}R" -or $parsed.State.Length -ne 642 -or
        -not $parsed.State[1] -or -not $parsed.State[641] -or $parsed.State[2]) {
        throw "Incorrect achievement mapping for $version."
    }
}

function Assert-Rejected([string]$name, [byte[]]$data, [string]$messagePattern) {
    $rejected = $false
    try { $null = Read-SaveAchievements $data 'synthetic.dat' }
    catch {
        if ($_.Exception.Message -notmatch $messagePattern) { throw "$name failed for an unexpected reason: $_" }
        $rejected = $true
    }
    if (-not $rejected) { throw "$name was incorrectly accepted." }
}

Assert-Rejected 'unknown version' ([SaveFixture]::Create('ISAACNGSAVE11R  ')) 'ISAACNGSAVE11R'
Assert-Rejected 'short file' (New-Object byte[] 20) 'synthetic.dat'

$corrupt = [SaveFixture]::Create('ISAACNGSAVE10R  ')
$corrupt[40] = 1
Assert-Rejected 'checksum corruption' $corrupt 'synthetic.dat'

foreach ($offset in @(20, 24, 28)) {
    $malformed = [SaveFixture]::Create('ISAACNGSAVE10R  ')
    [Buffer]::BlockCopy([BitConverter]::GetBytes([int]638), 0, $malformed, $offset, 4)
    [SaveFixture]::Seal($malformed)
    Assert-Rejected "malformed block at $offset" $malformed 'synthetic.dat'
}

$invalidFlag = [SaveFixture]::Create('ISAACNGSAVE10R  ')
$invalidFlag[40] = 2
[SaveFixture]::Seal($invalidFlag)
Assert-Rejected 'non-boolean achievement flag' $invalidFlag 'synthetic.dat'

$empty = [SaveFixture]::Create('ISAACNGSAVE10R  ')
$empty[33] = 0
$empty[32 + 641] = 0
[SaveFixture]::Seal($empty)
$parsed = Read-SaveAchievements $empty 'empty.dat'
if (@($parsed.State | Where-Object { $_ }).Count -ne 0) { throw 'Empty slot reported unlocks.' }

if ($SaveRoot) {
    $save = Read-GameSaves $SaveRoot
    Write-Output "Real saves read: $($save.Paths.Count); formats: $($save.Formats -join ', '); union unlocks: $(@($save.State | Where-Object { $_ }).Count)"
}
Write-Output 'Save format tests passed.'
