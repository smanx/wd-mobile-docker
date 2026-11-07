$hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
$domains = @('static.leiting1.com','login.leiting1.com','loginali.leiting1.com','loginsjhl.leiting1.com','member.leiting1.com','pay.leiting1.com','payali.leiting1.com','paysjhl.leiting1.com','logmonitor.leiting1.com','testlogin.leiting1.com','testmember.leiting1.com','testpay.leiting1.com','testlogmonitor.leiting1.com','testkernel.leiting1.com','webproxy.leiting1.com','helper.leiting1.com','www.leiting1.com')
$content = Get-Content $hosts -Raw
$needs = $domains | Where-Object { $content -notmatch [regex]::Escape($_) }
if ($needs.Count -gt 0) {
    $lines = $domains | ForEach-Object { "172.29.220.175 $_" }
    Add-Content -Path $hosts -Value "`n# wd-local game SDK domains (added by wd-docker)`n$($lines -join "`n")" -Encoding ASCII
    Write-Output "ADDED $($needs.Count) entries"
} else { Write-Output "already present" }
Get-Content $hosts | Select-Object -Last 5
