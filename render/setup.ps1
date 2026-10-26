# Earshot storyteller renderer: one-time setup on a Windows PC with an NVIDIA GPU.
#
# Run in PowerShell (not as administrator):
#   irm https://raw.githubusercontent.com/QAPro/earshot/main/render/setup.ps1 | iex
#
# Safe to run again: it skips what's already installed and refreshes the
# renderer's own files (that's also how you update it).
#
# Everything goes in one folder: D:\earshot-render if there is a D: drive,
# otherwise %LOCALAPPDATA%\earshot-render. Set EARSHOT_RENDER_HOME first to
# choose another place. Nothing is added to PATH or the registry; to remove it,
# delete that folder and the "Earshot Render" desktop shortcut.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # much faster downloads

function Step($msg) { Write-Host ""; Write-Host "== $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host ""; Write-Host "SETUP STOPPED: $msg" -ForegroundColor Red; throw $msg }
function Run($exe, [string[]]$argList) {
    & $exe @argList
    if ($LASTEXITCODE -ne 0) { Fail "'$exe $($argList -join ' ')' failed (exit code $LASTEXITCODE)." }
}

# ---------------------------------------------------------------- where
if ($env:EARSHOT_RENDER_HOME) { $Base = $env:EARSHOT_RENDER_HOME }
elseif (Test-Path 'D:\') { $Base = 'D:\earshot-render' }
else { $Base = Join-Path $env:LOCALAPPDATA 'earshot-render' }
New-Item -ItemType Directory -Force -Path $Base | Out-Null
Write-Host "Installing into $Base" -ForegroundColor Green

# Keep every download inside $Base (not on C: by default).
$env:EARSHOT_RENDER_HOME = $Base
$env:UV_CACHE_DIR = Join-Path $Base 'uv-cache'
$env:UV_PYTHON_INSTALL_DIR = Join-Path $Base 'python'
$env:HF_HOME = Join-Path $Base 'models'
$env:HF_HUB_DISABLE_TELEMETRY = '1'

# ---------------------------------------------------------------- GPU
Step 'Checking the graphics card'
try { $gpu = & nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>$null } catch { $gpu = $null }
if (-not $gpu) { Fail 'nvidia-smi not found. Install or update the NVIDIA driver, then run this again.' }
Write-Host "  $gpu"

# ---------------------------------------------------------------- uv
Step 'Getting uv (Python installer tool, kept inside the folder)'
$Bin = Join-Path $Base 'bin'
$Uv = Join-Path $Bin 'uv.exe'
if (-not (Test-Path $Uv)) {
    New-Item -ItemType Directory -Force -Path $Bin | Out-Null
    $zip = Join-Path $Base 'uv.zip'
    Invoke-WebRequest 'https://github.com/astral-sh/uv/releases/download/0.8.13/uv-x86_64-pc-windows-msvc.zip' -OutFile $zip
    Expand-Archive -Force $zip $Bin
    Remove-Item $zip
}
Run $Uv @('--version')

# ---------------------------------------------------------------- renderer files
Step 'Getting the latest Earshot renderer files'
$zip = Join-Path $Base 'earshot.zip'
$tmp = Join-Path $Base 'src-tmp'
Invoke-WebRequest 'https://github.com/QAPro/earshot/archive/refs/heads/main.zip' -OutFile $zip
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
Expand-Archive -Force $zip $tmp
$App = Join-Path $Base 'app'
if (Test-Path $App) { Remove-Item -Recurse -Force $App }
Copy-Item -Recurse (Join-Path $tmp 'earshot-main\render') $App
Remove-Item -Recurse -Force $tmp, $zip
Write-Host "  Renderer files in $App"

# ---------------------------------------------------------------- environments
# Two separate Python environments: the two voice engines need different
# versions of the same libraries. Both use PyTorch built for CUDA 12.8, which
# RTX 50-series cards need.
foreach ($name in @('qwen', 'chatterbox')) {
    Step "Python environment: $name (first time: a few GB, several minutes)"
    $envDir = Join-Path $Base "envs\$name"
    if (-not (Test-Path (Join-Path $envDir 'Scripts\python.exe'))) {
        Run $Uv @('venv', '--python', '3.12', $envDir)
    }
    $env:VIRTUAL_ENV = $envDir
    Run $Uv @('pip', 'sync', (Join-Path $App "env\$name.lock"),
              '--index-strategy', 'unsafe-best-match',
              '--extra-index-url', 'https://download.pytorch.org/whl/cu128')
    Remove-Item Env:\VIRTUAL_ENV
}
$PyQwen = Join-Path $Base 'envs\qwen\Scripts\python.exe'
$PyCbox = Join-Path $Base 'envs\chatterbox\Scripts\python.exe'

# ---------------------------------------------------------------- models
Step 'Downloading the voice models (about 8 GB, first time only)'
Run $PyQwen @('-c', "from huggingface_hub import snapshot_download as d; [print('  ok', d(r)) for r in ['Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign','Qwen/Qwen3-TTS-Tokenizer-12Hz']]")
Run $PyCbox @('-c', "from huggingface_hub import snapshot_download as d; print('  ok', d('ResembleAI/chatterbox'))")

# ---------------------------------------------------------------- test
Step 'Testing both voice engines on the GPU'
Run $PyQwen @((Join-Path $App 'check.py'), 'qwen')
Run $PyCbox @((Join-Path $App 'check.py'), 'chatterbox')

# ---------------------------------------------------------------- shortcut
Step 'Desktop shortcut'
$Cmd = Join-Path $Base 'earshot-render.cmd'
@"
@echo off
rem Drag documents onto the "Earshot Render" shortcut, or run: earshot-render.cmd file1 file2 ...
set EARSHOT_RENDER_HOME=$Base
set HF_HOME=$Base\models
set HF_HUB_DISABLE_TELEMETRY=1
"$PyQwen" "$App\render.py" %*
echo.
pause
"@ | Set-Content -Encoding ASCII $Cmd
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Earshot Render.lnk'
$sh = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
$sh.TargetPath = $Cmd
$sh.WorkingDirectory = $Base
$sh.Description = 'Drop a document here to turn it into storyteller audio for Earshot'
$sh.Save()
Write-Host "  'Earshot Render' is on your desktop."

Step 'Done'
Write-Host "Two test recordings are in $Base\output (check-qwen.mp3, check-chatterbox.mp3)." -ForegroundColor Green
Write-Host "Play them to confirm both engines work on the GPU."
