$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$python = Join-Path $repoRoot '.venv\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $python)) {
    throw "找不到仓库虚拟环境 Python：$python"
}

Push-Location $repoRoot
try {
    & $python -m scripts.dev_controller.controller @args
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
