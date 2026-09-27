$ErrorActionPreference = 'Stop'
$env:PYTHONUTF8 = '1'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$repoRoot = Split-Path $PSScriptRoot -Parent
$python = Join-Path $repoRoot '.venv\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw "找不到仓库虚拟环境 Python：$python"
}

Push-Location $PSScriptRoot
try {
    & $python -m app.main
    $exitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

exit $exitCode
