# Clust installer for Windows.
#
#   irm https://raw.githubusercontent.com/YuriAlvesBordin/clust-releases/main/install.ps1 | iex
#
# Downloads the newest signed release, checks its ed25519 signature with the same key
# `clust update` uses (in plain PowerShell, nothing to install), puts clust.exe in
# %LOCALAPPDATA%\Programs\clust and adds that folder to your user PATH.
#
# Settings (environment variables):
#   CLUST_VERSION       a release tag such as v0.1.4 (default: the latest release)
#   CLUST_INSTALL_DIR   where clust.exe goes
#   CLUST_NO_MODIFY_PATH=1   never change PATH

& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Add-Type -AssemblyName System.Numerics

    $Repo = 'YuriAlvesBordin/clust-releases'
    # Public half of the release signing key: the same 32 bytes as UPDATE_PUBLIC_KEY in clust.
    $PublicKey = [byte[]](216, 142, 150, 200, 58, 237, 179, 83, 216, 152, 60, 185, 47, 201, 91, 88,
        93, 190, 172, 122, 190, 223, 227, 120, 181, 87, 78, 211, 247, 180, 25, 229)

    function Say($m) { Write-Host "clust: $m" }

    # ---------------------------------------------------------------- ed25519 (RFC 8032), verify only
    $BI = [System.Numerics.BigInteger]
    $P = $BI::Pow(2, 255) - 19
    $L = $BI::Pow(2, 252) + $BI::Parse('27742317777372353535851937790883648493')
    function M($a) { $r = $a % $P; if ($r.Sign -lt 0) { $r + $P } else { $r } }
    function Inv($a) { $BI::ModPow((M $a), $P - 2, $P) }
    $D = M ([System.Numerics.BigInteger](-121665) * (Inv 121666))
    $SqrtM1 = $BI::ModPow(2, ($P - 1) / 4, $P)

    function LeInt([byte[]]$b) { $BI::new([byte[]]($b + [byte]0)) }

    function Add($p1, $p2) {
        $a = M (($p1[1] - $p1[0]) * ($p2[1] - $p2[0]))
        $b = M (($p1[1] + $p1[0]) * ($p2[1] + $p2[0]))
        $c = M ($p1[3] * 2 * $D * $p2[3])
        $dd = M ($p1[2] * 2 * $p2[2])
        $e = $b - $a; $f = $dd - $c; $g = $dd + $c; $h = $b + $a
        , @((M ($e * $f)), (M ($g * $h)), (M ($f * $g)), (M ($e * $h)))
    }
    function Mul($s, $pt) {
        $q = @($BI::Zero, $BI::One, $BI::One, $BI::Zero)
        while ($s.Sign -gt 0) {
            if (-not $s.IsEven) { $q = Add $q $pt }
            $pt = Add $pt $pt
            $s = $s / 2
        }
        , $q
    }
    function Decode([byte[]]$b) {
        $y = (LeInt $b) % $BI::Pow(2, 255)
        $sign = ($b[31] -shr 7) -band 1
        if ($y -ge $P) { return $null }
        $y2 = M ($y * $y)
        $x2 = M (($y2 - 1) * (Inv ($D * $y2 + 1)))
        if ($x2.IsZero) { if ($sign -eq 1) { return $null }; return , @($BI::Zero, $y, $BI::One, $BI::Zero) }
        $x = $BI::ModPow($x2, ($P + 3) / 8, $P)
        if (-not (M ($x * $x - $x2)).IsZero) { $x = M ($x * $SqrtM1) }
        if (-not (M ($x * $x - $x2)).IsZero) { return $null }
        if ([int]($x % 2) -ne $sign) { $x = $P - $x }
        , @($x, $y, $BI::One, (M ($x * $y)))
    }
    function Same($p1, $p2) {
        (M ($p1[0] * $p2[2] - $p2[0] * $p1[2])).IsZero -and (M ($p1[1] * $p2[2] - $p2[1] * $p1[2])).IsZero
    }
    $By = M (4 * (Inv 5))
    $ByBytes = $By.ToByteArray()[0..31]
    $EdBase = Decode ([byte[]]$ByBytes)

    function Test-Signature([byte[]]$msg, [byte[]]$sig, [byte[]]$pub) {
        if ($sig.Length -ne 64) { return $false }
        $A = Decode $pub; $R = Decode ([byte[]]$sig[0..31])
        if ($null -eq $A -or $null -eq $R) { return $false }
        $S = LeInt ([byte[]]$sig[32..63])
        if ($S -ge $L) { return $false }
        # streamed, so the binary is never copied into a PowerShell array
        $sha = [System.Security.Cryptography.SHA512]::Create()
        [void]$sha.TransformBlock($sig, 0, 32, $null, 0)
        [void]$sha.TransformBlock($pub, 0, 32, $null, 0)
        [void]$sha.TransformFinalBlock($msg, 0, $msg.Length)
        $h = (LeInt $sha.Hash) % $L
        Same (Mul $S $EdBase) (Add $R (Mul $h $A))
    }

    function FromUrlBase64([string]$s) {
        $s = $s.Trim().Replace('-', '+').Replace('_', '/')
        switch ($s.Length % 4) { 2 { $s += '==' } 3 { $s += '=' } }
        [Convert]::FromBase64String($s)
    }

    # ---------------------------------------------------------------- install
    if (-not [Environment]::Is64BitOperatingSystem) { throw 'clust needs 64-bit Windows.' }
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { Say 'Windows on ARM: installing the x64 build (it runs under emulation)' }
    $file = 'clust-x86_64-pc-windows-msvc.exe'
    $base = if ($env:CLUST_VERSION) { "https://github.com/$Repo/releases/download/$($env:CLUST_VERSION)" } else { "https://github.com/$Repo/releases/latest/download" }
    $dir = if ($env:CLUST_INSTALL_DIR) { $env:CLUST_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'Programs\clust' }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("clust-install-" + [Guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $exe = Join-Path $tmp 'clust.exe'
        Say "downloading $file $(if ($env:CLUST_VERSION) { $env:CLUST_VERSION } else { '(latest)' })"
        Invoke-WebRequest -UseBasicParsing -Uri "$base/$file" -OutFile $exe
        $sigText = (Invoke-WebRequest -UseBasicParsing -Uri "$base/$file.sig").Content
        if ($sigText -is [byte[]]) { $sigText = [Text.Encoding]::ASCII.GetString($sigText) }

        Say 'checking the signature'
        $ok = $false
        try { $ok = Test-Signature ([IO.File]::ReadAllBytes($exe)) (FromUrlBase64 $sigText) $PublicKey } catch { $ok = $false }
        if (-not $ok) { throw 'the signature does not match: the download is damaged or was tampered with. Nothing was installed.' }
        Say 'signature verified'

        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $target = Join-Path $dir 'clust.exe'
        # a running clust.exe cannot be overwritten, but it can be renamed out of the way
        if (Test-Path $target) {
            $old = "$target.old"
            Remove-Item $old -Force -ErrorAction SilentlyContinue
            Rename-Item $target $old -ErrorAction SilentlyContinue
        }
        Move-Item $exe $target -Force
        Remove-Item "$target.old" -Force -ErrorAction SilentlyContinue
        Say "installed $target"

        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $parts = @($userPath -split ';' | Where-Object { $_ })
        if ($parts -notcontains $dir) {
            if ($env:CLUST_NO_MODIFY_PATH -eq '1') {
                Say "add $dir to your PATH to run clust from anywhere"
            } else {
                [Environment]::SetEnvironmentVariable('Path', (($parts + $dir) -join ';'), 'User')
                Say "added $dir to your user PATH (new terminals will see it)"
            }
        }
        if (($env:Path -split ';') -notcontains $dir) { $env:Path = "$env:Path;$dir" }

        $first = (Get-Command clust -ErrorAction SilentlyContinue | Select-Object -First 1).Source
        if ($first -and $first -ne $target) { Say "note: another clust at $first comes first on your PATH" }

        & $target --version
        Say 'done. Run: clust login'
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
