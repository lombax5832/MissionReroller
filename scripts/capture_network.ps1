[CmdletBinding()]
param(
    [ValidateRange(10,120)][int]$BaselineSeconds = 30,
    [ValidateRange(10,180)][int]$RerollSeconds = 60,
    [ValidateRange(10,120)][int]$AfterSeconds = 30,
    [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from PowerShell opened as Administrator. No capture was started.'
}
$games = @(Get-Process -Name helldivers2 -ErrorAction SilentlyContinue)
if ($games.Count -ne 1) { throw 'Expected exactly one running helldivers2 process.' }
$gameProcessId = $games[0].Id
$gameStarted = $games[0].StartTime.ToUniversalTime().ToString('o')
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path (Split-Path $PSScriptRoot) ('artifacts/network/' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Output directory already exists; choose a new directory.' }
$output = (New-Item -ItemType Directory -Path $OutputDirectory).FullName
$pktmon = Join-Path $env:SystemRoot 'System32/PktMon.exe'
function Invoke-PacketMonitor([string[]]$Arguments) {
    $result = & $pktmon @Arguments 2>&1
    $code = $LASTEXITCODE
    $result | Out-String | Add-Content -LiteralPath (Join-Path $output 'pktmon.txt')
    if ($code -ne 0) { throw "pktmon $($Arguments -join ' ') failed ($code). See pktmon.txt." }
    return ($result | Out-String)
}
$filters = Invoke-PacketMonitor @('filter','list')
# Refuse unknown/localized output instead of silently capturing through old filters.
if ($filters -notmatch '(?im)(no\s+(packet\s+)?filters|^\s*(none|<none>)\s*$)') {
    throw "Cannot establish that packet filters are empty. Inspect 'pktmon filter list'; this script does not remove existing filters. Output: $filters"
}
Invoke-PacketMonitor @('status') | Out-Null
Invoke-PacketMonitor @('list','--json') | Set-Content -LiteralPath (Join-Path $output 'components.json')
$logPath = Join-Path $env:LOCALAPPDATA 'CowboyBingus/Helldivers2/Logs/MissionRerollerExperiment.log'
if (-not (Test-Path -LiteralPath $logPath)) { throw 'Reroller log missing; run the combined addon first.' }
$stream = [IO.File]::Open($logPath, 'Open', 'Read', 'ReadWrite')
$null = $stream.Seek(0, 'End')
$reader = [IO.StreamReader]::new($stream)
$events = [IO.StreamWriter]::new((Join-Path $output 'events.jsonl'), $false, [Text.UTF8Encoding]::new($false))
$events.AutoFlush = $true
function Write-Event($record) { $events.WriteLine(($record | ConvertTo-Json -Depth 8 -Compress)) }
function Save-Dns([string]$Name) {
    try { @(Get-DnsClientCache) | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output $Name) }
    catch { Write-Event @{type='warning'; message="DNS cache unavailable: $_"; utc=[DateTime]::UtcNow.ToString('o')} }
}
$started = $false
$completed = $false
$partial = ''
$lastLogRead = [DateTime]::UtcNow.ToString('o')
try {
    Write-Event @{type='metadata'; game_pid=$gameProcessId; game_started=$gameStarted;
        baseline_seconds=$BaselineSeconds; reroll_seconds=$RerollSeconds; after_seconds=$AfterSeconds;
        note='All NIC traffic, headers up to 128 bytes; socket ownership is sampled, not packet-level attribution.'}
    Save-Dns 'dns-before.json'
    Write-Host 'Select a planet and open the reroller. Do not start a search yet.'
    Write-Host "Capture: ${BaselineSeconds}s idle, ${RerollSeconds}s reroll window, ${AfterSeconds}s idle. Watch/listen for phase cues."
    Write-Host 'Packet headers from other applications may also be captured. Files stay local.'
    $null = Read-Host 'Press Enter when ready, then return to the game'
    $null = $reader.ReadToEnd() # Discard events preceding this capture window.
    $lastLogRead = [DateTime]::UtcNow.ToString('o')
    # Start fails if another session owns PktMon; only stop when OUR start succeeded.
    Invoke-PacketMonitor @('start','--capture','--comp','nics','--pkt-size','128',
        '--file-name',(Join-Path $output 'traffic.etl'),'--file-size','256','--log-mode','multi-file') | Out-Null
    $started = $true
    $captureStart = [DateTime]::UtcNow
    $phase = ''
    $total = $BaselineSeconds + $RerollSeconds + $AfterSeconds
    while (([DateTime]::UtcNow - $captureStart).TotalSeconds -lt $total) {
        $sampleStart = [DateTime]::UtcNow
        $elapsed = ($sampleStart - $captureStart).TotalSeconds
        $nextPhase = if ($elapsed -lt $BaselineSeconds) {'baseline'} elseif ($elapsed -lt ($BaselineSeconds+$RerollSeconds)) {'reroll'} else {'after'}
        if ($nextPhase -ne $phase) {
            $phase = $nextPhase
            Write-Event @{type='phase'; phase=$phase; utc=$sampleStart.ToString('o')}
            Write-Host "PHASE: $phase"
            if ($phase -eq 'reroll') { Write-Host 'Start a two-mission search now.'; [Console]::Beep(1000,300) }
            if ($phase -eq 'after') { Write-Host 'Cancel searching now and leave the map idle.'; [Console]::Beep(600,500) }
        }
        $running = Get-Process -Id $gameProcessId -ErrorAction Stop
        if ($running.StartTime.ToUniversalTime().ToString('o') -ne $gameStarted) { throw 'Game process changed.' }
        $sockets = @(
            Get-NetTCPConnection | ForEach-Object {
                @{protocol='TCP'; pid=$_.OwningProcess; local=$_.LocalAddress; port=$_.LocalPort;
                  remote=$_.RemoteAddress; remote_port=$_.RemotePort; state=[string]$_.State}
            }
            Get-NetUDPEndpoint | ForEach-Object {
                @{protocol='UDP'; pid=$_.OwningProcess; local=$_.LocalAddress; port=$_.LocalPort}
            }
        )
        Write-Event @{type='sockets'; begin=$sampleStart.ToString('o'); utc=[DateTime]::UtcNow.ToString('o'); sockets=$sockets}
        $observed = [DateTime]::UtcNow.ToString('o')
        $partial += $reader.ReadToEnd()
        $lines = $partial -split "`n", 0, 'SimpleMatch'
        $partial = $lines[-1]
        if ($lines.Count -gt 1) {
            foreach ($line in $lines[0..($lines.Count-2)]) {
                Write-Event @{type='mod_log'; earliest=$lastLogRead; utc=$observed; text=$line.TrimEnd("`r")}
            }
        }
        $lastLogRead = $observed
        Start-Sleep -Milliseconds 500
    }
    $completed = $true
} catch {
    Write-Event @{type='error'; utc=[DateTime]::UtcNow.ToString('o'); message=[string]$_}
    throw
} finally {
    try {
        if ($started) {
            try {
                # Even a counters failure must not skip stopping our capture.
                try { Invoke-PacketMonitor @('counters') | Out-Null }
                finally { Invoke-PacketMonitor @('stop') | Out-Null }
                Write-Event @{type='end'; utc=[DateTime]::UtcNow.ToString('o'); completed=$completed}
            } finally { Save-Dns 'dns-after.json' }
        }
    } finally { $reader.Dispose(); $events.Dispose() }
}
# Convert every segment; multi-file mode does not overwrite earlier evidence.
foreach ($etl in Get-ChildItem -LiteralPath $output -Filter '*.etl') {
    Invoke-PacketMonitor @('etl2pcap',$etl.FullName,'--out',([IO.Path]::ChangeExtension($etl.FullName,'pcapng'))) | Out-Null
}
Write-Host "Capture complete: $output"
Write-Host 'Send this directory path to the agent for analysis. No data has been uploaded.'
