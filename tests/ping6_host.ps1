$targets = @('2400:3200::1', '2409:8080::8', '240e:f:a::6', '240c::6666', '2001:4860:4860::8888')
foreach ($t in $targets) {
    Write-Output "===== $t ====="
    $out = & ping.exe -6 -n 2 -w 2000 $t 2>&1
    $out | ForEach-Object { Write-Output ("  " + $_) }
}
