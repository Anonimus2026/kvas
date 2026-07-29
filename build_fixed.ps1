param(
    [string]$Variant = "all"
)

$ErrorActionPreference = "Stop"
$base = "C:\Users\Pavel\AppData\Local\Temp\opencode\ipk_build"
$outDir = "C:\Users\Pavel\kvas"
$sevenZip = "C:\Program Files\7-Zip\7z.exe"

function Write-FileSafe($path, $content) {
    [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
}

function Build-Variant {
    param($Version, $Desc, [scriptblock]$ModifyAction)

    Write-Host "`n=== $Desc ==="

    $workDir = Join-Path $env:TEMP "kvas_var_$Version"
    if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force }
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    # Copy base files using robocopy to preserve binary integrity
    robocopy (Join-Path $base "opt") (Join-Path $workDir "opt") /E /NP /NFL /NDL /NJH /NJS 2>$null | Out-Null
    Copy-Item (Join-Path $base "control") "$workDir\control" -Force
    Copy-Item (Join-Path $base "postinst") "$workDir\postinst" -Force
    Copy-Item (Join-Path $base "debian-binary") "$workDir\debian-binary" -Force

    # Apply modification
    & $ModifyAction $workDir

    # Update version in control (using WriteAllText to preserve LF)
    $content = [System.IO.File]::ReadAllText((Join-Path $workDir "control"), [System.Text.Encoding]::UTF8)
    $content = $content -replace 'Version: .*', "Version: 1.1.9_beta-10-$Version"
    $content = $content -replace 'Description: .*', "Description: KVAS v$Version - $Desc"
    if (-not $content.EndsWith("`n")) { $content = $content + "`n" }
    Write-FileSafe (Join-Path $workDir "control") $content

    # Build data.tar.gz: tar of opt/ 
    $tmpData = Join-Path $env:TEMP "kvas_data_$Version"
    New-Item $tmpData -ItemType Directory -Force 2>$null | Out-Null
    Push-Location $workDir
    & $sevenZip a -ttar "$tmpData\data.tar" "opt" -r 2>&1 | Out-Null
    Pop-Location
    & $sevenZip a -tgzip "$tmpData\data.tar.gz" "$tmpData\data.tar" 2>&1 | Out-Null

    # Build control.tar.gz: tar of control + postinst
    $tmpCtrl = Join-Path $env:TEMP "kvas_ctrl_$Version"
    New-Item $tmpCtrl -ItemType Directory -Force 2>$null | Out-Null
    Copy-Item (Join-Path $workDir "control") "$tmpCtrl\control" -Force
    Copy-Item (Join-Path $workDir "postinst") "$tmpCtrl\postinst" -Force
    Push-Location $tmpCtrl
    & $sevenZip a -ttar "$tmpCtrl\control.tar" "control" "postinst" 2>&1 | Out-Null
    Pop-Location
    & $sevenZip a -tgzip "$tmpCtrl\control.tar.gz" "$tmpCtrl\control.tar" 2>&1 | Out-Null

    # Build inner tar
    $tmp = Join-Path $env:TEMP "kvas_ipk_$Version"
    New-Item $tmp -ItemType Directory -Force 2>$null | Out-Null
    Copy-Item (Join-Path $workDir "debian-binary") "$tmp\debian-binary"
    Copy-Item "$tmpCtrl\control.tar.gz" "$tmp\control.tar.gz"
    Copy-Item "$tmpData\data.tar.gz" "$tmp\data.tar.gz"
    Push-Location $tmp
    & $sevenZip a -ttar "$tmp\kvas.tar" "debian-binary" "control.tar.gz" "data.tar.gz" 2>&1 | Out-Null
    Pop-Location
    & $sevenZip a -tgzip "$tmp\kvas.ipk" "$tmp\kvas.tar" 2>&1 | Out-Null

    Copy-Item "$tmp\kvas.ipk" (Join-Path $outDir "kvas_1.1.9_beta-10-${Version}_all.ipk") -Force
    Write-Host "  -> $(Join-Path $outDir "kvas_1.1.9_beta-10-${Version}_all.ipk")"

    Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $tmpData -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $tmpCtrl -Recurse -Force -ErrorAction SilentlyContinue
}

# Variant 331: postinst cp fix
$mod331 = {
    param($workDir)
    $postinst = [System.IO.File]::ReadAllText((Join-Path $workDir "postinst"), [System.Text.Encoding]::UTF8)
    $newLine = "`n    cp -f /opt/apps/kvas/etc/ndm/ndm /opt/apps/kvas/bin/libs/ndm"
    $postinst = $postinst -replace '(chmod -R \+x /opt/apps/kvas/etc/ndm/\* 2>/dev/null)', "`$1$newLine"
    Write-FileSafe (Join-Path $workDir "postinst") $postinst
    Write-Host "  postinst: added cp line"
}

# Variant 332: remove conntrack flush
$mod332 = {
    param($workDir)
    $routeFile = Join-Path $workDir "opt\apps\kvas\bin\libs\route"
    $lines = [System.IO.File]::ReadAllLines($routeFile, [System.Text.Encoding]::UTF8)
    $newLines = New-Object System.Collections.Generic.List[string]
    $skip = $false
    foreach ($line in $lines) {
        if ($line -match "echo -n 'Сброс") { $skip = $true }
        if ($skip) {
            if ($line -match "echo 'сделано.'") { $skip = $false; continue }
            continue
        }
        $newLines.Add($line)
    }
    [System.IO.File]::WriteAllText($routeFile, ($newLines -join "`n"), [System.Text.UTF8Encoding]::new($false))
    Write-Host "  route: conntrack block removed"
}

# Variant 340: fix RULE_PRIORITY from 1778 to 99 (above system rule 104)
$mod340 = {
    param($workDir)
    @("opt\apps\kvas\etc\ndm\ndm", "opt\apps\kvas\bin\libs\ndm") | ForEach-Object {
        $p = Join-Path $workDir $_
        if (Test-Path $p) {
            $content = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
            $content = $content -replace 'RULE_PRIORITY=1778', 'RULE_PRIORITY=99'
            [System.IO.File]::WriteAllText($p, $content, [System.Text.UTF8Encoding]::new($false))
            Write-Host "  $_ : RULE_PRIORITY 1778 -> 99"
        }
    }
}

# Variant 341: priority fix + no conntrack flush
$mod341 = {
    param($workDir)
    # Apply ndm priority fix (both copies)
    @("opt\apps\kvas\etc\ndm\ndm", "opt\apps\kvas\bin\libs\ndm") | ForEach-Object {
        $p = Join-Path $workDir $_
        if (Test-Path $p) {
            $content = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
            $content = $content -replace 'RULE_PRIORITY=1778', 'RULE_PRIORITY=99'
            [System.IO.File]::WriteAllText($p, $content, [System.Text.UTF8Encoding]::new($false))
            Write-Host "  ndm: RULE_PRIORITY 1778 -> 99"
        }
    }
    # Remove conntrack flush from route
    $routeFile = Join-Path $workDir "opt\apps\kvas\bin\libs\route"
    $lines = [System.IO.File]::ReadAllLines($routeFile, [System.Text.Encoding]::UTF8)
    $newLines = New-Object System.Collections.Generic.List[string]
    $skip = $false
    foreach ($line in $lines) {
        if ($line -match "echo -n 'Сброс") { $skip = $true }
        if ($skip) {
            if ($line -match "echo 'сделано.'") { $skip = $false; continue }
            continue
        }
        $newLines.Add($line)
    }
    [System.IO.File]::WriteAllText($routeFile, ($newLines -join "`n"), [System.Text.UTF8Encoding]::new($false))
    Write-Host "  route: conntrack block removed"
}

# Variant 342: priority fix + data.sh BusyBox fix
$mod342 = {
    param($workDir)
    @("opt\apps\kvas\etc\ndm\ndm", "opt\apps\kvas\bin\libs\ndm") | ForEach-Object {
        $p = Join-Path $workDir $_
        if (Test-Path $p) {
            $content = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
            $content = $content -replace 'RULE_PRIORITY=1778', 'RULE_PRIORITY=99'
            [System.IO.File]::WriteAllText($p, $content, [System.Text.UTF8Encoding]::new($false))
        }
    }
    Write-Host "  ndm: RULE_PRIORITY 1778 -> 99"

    $dataSh = Join-Path $workDir "opt\apps\kvas\bin\monitor\www\cgi-bin\data.sh"
    $content = [System.IO.File]::ReadAllText($dataSh, [System.Text.Encoding]::UTF8)
    $oldBlock = @'
			else
				_kvas_list=$(echo "$_kvas_bindings" | sed 's/.*"lease":\[//' | sed 's/\].*//' | \
					sed 's/},{/}\n{/g' | while IFS= read -r _kvas_entry; do
					_kvas_ip=$(echo "$_kvas_entry" | grep -o '"ip":"[^"]*"' | cut -d'"' -f4)
					_kvas_name=$(echo "$_kvas_entry" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
					[ -n "$_kvas_ip" ] && echo "${_kvas_ip}|${_kvas_name}"
				done)
			fi
'@
    $newBlock = @'
			else
				_kvas_list=$(echo "$_kvas_bindings" | awk -F'"' '
					/"ip":/ { ip = $4 }
					/"name":/ { name = $4; if (ip) { print ip "|" name; ip=""; name="" } }
				')
			fi
'@
    $content = $content.Replace($oldBlock, $newBlock)
    [System.IO.File]::WriteAllText($dataSh, $content, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  data.sh: fixed DHCP parse for BusyBox"
}

# Variant 343: priority fix + manage.sh route_devices JSON fix
$mod343 = {
    param($workDir)
    @("opt\apps\kvas\etc\ndm\ndm", "opt\apps\kvas\bin\libs\ndm") | ForEach-Object {
        $p = Join-Path $workDir $_
        if (Test-Path $p) {
            $content = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
            $content = $content -replace 'RULE_PRIORITY=1778', 'RULE_PRIORITY=99'
            [System.IO.File]::WriteAllText($p, $content, [System.Text.UTF8Encoding]::new($false))
        }
    }
    Write-Host "  ndm: RULE_PRIORITY 1778 -> 99"

    # Fix manage.sh: add missing JSON preamble for route_devices
    $manageSh = Join-Path $workDir "opt\apps\kvas\bin\monitor\www\cgi-bin\manage.sh"
    $content = [System.IO.File]::ReadAllText($manageSh, [System.Text.Encoding]::UTF8)
    $oldBlock = @'
			first=1
			awk -F'|' '!seen[$1]++{if(f++) printf ","; printf "{\"ip\":\"%s\",\"name\":\"%s\"}", $1, $2}' "$_tmpdev" 2>/dev/null
'@
    $newBlock = @'
			printf '{"ok":true,"devices":['
			awk -F'|' '!seen[$1]++{if(f++) printf ","; printf "{\"ip\":\"%s\",\"name\":\"%s\"}", $1, $2}' "$_tmpdev" 2>/dev/null
'@
    if ($content.Contains($oldBlock)) {
        $content = $content.Replace($oldBlock, $newBlock)
        [System.IO.File]::WriteAllText($manageSh, $content, [System.Text.UTF8Encoding]::new($false))
        Write-Host "  manage.sh: fixed route_devices JSON preamble"
    } else {
        Write-Host "  manage.sh: pattern not found, skipping"
    }
}

# Build
if ($Variant -eq "331" -or $Variant -eq "all") {
    Build-Variant -Version "331" -Desc "postinst cp fix" -ModifyAction $mod331
}
if ($Variant -eq "332" -or $Variant -eq "all") {
    Build-Variant -Version "332" -Desc "no conntrack flush" -ModifyAction $mod332
}
if ($Variant -eq "340" -or $Variant -eq "all") {
    Build-Variant -Version "340" -Desc "RULE_PRIORITY 99 fix" -ModifyAction $mod340
}
if ($Variant -eq "341" -or $Variant -eq "all") {
    Build-Variant -Version "341" -Desc "priority 99 + no conntrack" -ModifyAction $mod341
}
if ($Variant -eq "342" -or $Variant -eq "all") {
    Build-Variant -Version "342" -Desc "priority 99 + data.sh BusyBox fix" -ModifyAction $mod342
}
if ($Variant -eq "343" -or $Variant -eq "all") {
    Build-Variant -Version "343" -Desc "priority 99 + route_devices JSON fix" -ModifyAction $mod343
}

Write-Host "`n=== Done ==="
Get-ChildItem $outDir -Filter "kvas_1.1.9_beta-10-34*.ipk" | Select-Object Name, Length
