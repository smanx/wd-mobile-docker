# Restore the SDK domain hijack inside the MuMu emulator.
#
# WHY: the SDK login endpoint is https://loginali.leiting1.com (and sibling
# *.leiting1.com domains). Those domains do not exist on the public Internet,
# so they must resolve to the private server. Windows' hosts file does NOT
# affect Android - the emulator reads its own /system/etc/hosts.
#
# MuMu resets /system/etc/hosts on every emulator reboot (and its ADB port
# changes, e.g. 16384 -> 16448). After a reboot the game reaches the patch/
# config stage but SDK login fails with a network error, and NO login request
# ever reaches nginx/aaa. Run this script once after each emulator restart.
#
# /dev/block/sda6 (system) is block-level read-only, so we cannot remount rw.
# Instead we bind-mount a writable file over /system/etc/hosts (no system
# partition modification). The mount lives until the emulator VM restarts.
#
# Usage (PowerShell):
#   powershell -ExecutionPolicy Bypass -File .\fix_emulator_hosts.ps1
#   powershell -ExecutionPolicy Bypass -File .\fix_emulator_hosts.ps1 -ClientIp 172.29.220.175

param(
    [string]$ClientIp = "10.0.0.240",
    [string]$Adb = "C:\mydata\tools\MuMuPlayer\nx_device\12.0\shell\adb.exe"
)

if (-not (Test-Path $Adb)) {
    $cmd = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($cmd) { $Adb = $cmd.Source }
    else { Write-Error "adb.exe not found. Pass -Adb <path>."; exit 1 }
}

$domains = @(
    "static.leiting1.com", "login.leiting1.com", "loginali.leiting1.com",
    "loginsjhl.leiting1.com", "member.leiting1.com", "pay.leiting1.com",
    "payali.leiting1.com", "paysjhl.leiting1.com", "logmonitor.leiting1.com",
    "testlogin.leiting1.com", "testmember.leiting1.com", "testpay.leiting1.com",
    "testlogmonitor.leiting1.com", "testkernel.leiting1.com",
    "webproxy.leiting1.com", "helper.leiting1.com", "www.leiting1.com"
)

$lines = @("127.0.0.1       localhost", "::1             ip6-localhost")
foreach ($d in $domains) { $lines += "$ClientIp $d" }
$tmp = Join-Path $env:TEMP "wd_hosts"
[System.IO.File]::WriteAllText($tmp, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))

# --- locate the emulator ADB device -------------------------------------
$dev = $null
foreach ($l in (& $Adb devices)) {
    if ($l -match '^127\.0\.0\.1:(\d+)\s+device') { $dev = "127.0.0.1:$($Matches[1])"; break }
}
if (-not $dev) {
    $proc = Get-Process -Name MuMuNxDevice -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $proc) { Write-Error "MuMu emulator is not running."; exit 1 }
    $ports = @()
    foreach ($l in (netstat -ano)) {
        if ($l -match "TCP\s+\S+:(\d+)\s+\S+\s+LISTENING\s+$($proc.Id)\s*$") {
            $ports += [int]$Matches[1]
        }
    }
    foreach ($p in ($ports | Sort-Object -Unique)) {
        & $Adb connect "127.0.0.1:$p" 2>&1 | Out-Null
        $chk = & $Adb -s "127.0.0.1:$p" shell "echo OK" 2>&1
        if ("$chk" -match "OK") { $dev = "127.0.0.1:$p"; break }
    }
}
if (-not $dev) { Write-Error "Cannot find emulator ADB device."; exit 1 }
Write-Host "device: $dev"

# --- root adbd, push hosts, bind mount ----------------------------------
& $Adb -s $dev root 2>&1 | Out-Null
Start-Sleep -Seconds 2
& $Adb connect $dev 2>&1 | Out-Null
& $Adb -s $dev push $tmp /data/local/tmp/wd_hosts 2>&1 | Out-Null

# unmount first so repeated runs do not stack bind mounts
$out = & $Adb -s $dev shell 'chmod 644 /data/local/tmp/wd_hosts; chown root:root /data/local/tmp/wd_hosts; umount /system/etc/hosts 2>/dev/null; mount -o bind /data/local/tmp/wd_hosts /system/etc/hosts; echo RC=$?' 2>&1
Write-Host $out

# --- verify --------------------------------------------------------------
$ping = & $Adb -s $dev shell "ping -c 1 -W 2 loginali.leiting1.com" 2>&1
if ("$ping" -match [regex]::Escape($ClientIp)) {
    Write-Host "OK: SDK domains resolve to $ClientIp."
    Write-Host "Now force-stop and reopen the game app, then login again."
} else {
    Write-Host "FAILED: SDK domain still does not resolve to $ClientIp"
    Write-Host "$ping"
    exit 1
}
