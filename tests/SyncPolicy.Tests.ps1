$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'IsaacAchievements.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw "Main script has $($parseErrors.Count) parse error(s)." }

# Load only the confirmation function so tests cannot initialize Steam or change achievements.
$policy = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Confirm-SteamSync'
}, $true)
if (-not $policy) { throw 'Confirm-SteamSync function is missing.' }
. ([scriptblock]::Create($policy.Extent.Text))

$script:answers = New-Object 'System.Collections.Generic.Queue[string]'
function Read-Host {
    param([string]$Prompt)
    if ($script:answers.Count -eq 0) { throw 'Unexpected confirmation prompt.' }
    return $script:answers.Dequeue()
}

function Set-Answers([string[]]$values) {
    $script:answers.Clear()
    foreach ($value in $values) { $script:answers.Enqueue($value) }
}

function Assert-Result([string]$name, [bool]$expected, [bool]$actual) {
    if ($actual -ne $expected -or $script:answers.Count -ne 0) {
        throw "$name failed: expected=$expected actual=$actual remainingAnswers=$($script:answers.Count)"
    }
}

Set-Answers @('Y', '15')
Assert-Result 'interactive over limit with exact count' $true (Confirm-SteamSync -Mode Interactive -Count 15 -MaxChanges 10 -DelaySeconds 120)

Set-Answers @('Y', '')
Assert-Result 'interactive over limit without count' $false (Confirm-SteamSync -Mode Interactive -Count 15 -MaxChanges 10 -DelaySeconds 120)

Set-Answers @('Y')
Assert-Result 'interactive at limit' $true (Confirm-SteamSync -Mode Interactive -Count 10 -MaxChanges 10 -DelaySeconds 120)

Set-Answers @('')
Assert-Result 'interactive declined' $false (Confirm-SteamSync -Mode Interactive -Count 15 -MaxChanges 10 -DelaySeconds 120)

Set-Answers @()
Assert-Result 'scan never syncs' $false (Confirm-SteamSync -Mode Scan -Count 15 -MaxChanges 10 -DelaySeconds 120)

Set-Answers @()
try {
    $null = Confirm-SteamSync -Mode Repair -Count 15 -MaxChanges 10 -DelaySeconds 120
    throw 'Repair mode should have rejected a batch over MaxChanges.'
} catch {
    if ($_.Exception.Message -notmatch 'MaxChanges') { throw }
}

Set-Answers @()
Assert-Result 'repair with explicit limit' $true (Confirm-SteamSync -Mode Repair -Count 15 -MaxChanges 15 -DelaySeconds 120)

Write-Output 'Sync policy tests passed.'
