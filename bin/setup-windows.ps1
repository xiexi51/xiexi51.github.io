[CmdletBinding()]
param([string]$ToolsRoot = (Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) '.homepage-tools'))
$ErrorActionPreference = 'Stop'
$ToolsRoot = [IO.Path]::GetFullPath($ToolsRoot)
$downloads = Join-Path $ToolsRoot 'downloads'
New-Item -ItemType Directory -Path $downloads -Force | Out-Null
function Get-CheckedDownload([string]$Url, [string]$Name, [string]$Sha256) {
    $target = Join-Path $downloads $Name
    if (!(Test-Path -LiteralPath $target) -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $Sha256) {
        & curl.exe --fail --location --http1.1 --retry 2 --continue-at - --output $target $Url
        if ($LASTEXITCODE -ne 0) { throw "Download failed: $Name" }
    }
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $Sha256) { throw "Checksum mismatch: $target" }
    return $target
}
$rubyRoot = Join-Path $ToolsRoot 'ruby-3.3.5-x64'
if (!(Test-Path -LiteralPath (Join-Path $rubyRoot 'bin/ruby.exe'))) {
    $installer = Get-CheckedDownload 'https://github.com/oneclick/rubyinstaller2/releases/download/RubyInstaller-3.3.5-1/rubyinstaller-devkit-3.3.5-1-x64.exe' 'rubyinstaller-devkit-3.3.5-1-x64.exe' '8D4F99BE006596D40604665C4D25257385EB4EE81C6F38FAD9AC84413A2C0961'
    $arguments = @('/verysilent','/suppressmsgboxes','/currentuser','/norestart','/noicons','/tasks=noassocfiles,nomodpath,noridkinstall',('/dir="' + $rubyRoot + '"'))
    $process = Start-Process -FilePath $installer -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Ruby install failed: $($process.ExitCode)" }
    & (Join-Path $rubyRoot 'bin/ridk.cmd') install 1
    if ($LASTEXITCODE -ne 0) { throw 'MSYS2 initialization failed.' }
}
$nodeRoot = Join-Path $ToolsRoot 'node-v22.9.0-win-x64'
if (!(Test-Path -LiteralPath (Join-Path $nodeRoot 'node.exe'))) {
    $archive = Get-CheckedDownload 'https://nodejs.org/dist/v22.9.0/node-v22.9.0-win-x64.zip' 'node-v22.9.0-win-x64.zip' '8AF226C0AA71FEFE5228E881F4B5C5D90A8B41C290B96F44F56990D8DC3FAC1C'
    Expand-Archive -LiteralPath $archive -DestinationPath $ToolsRoot
}
$pythonRoot = Join-Path $ToolsRoot 'python-3.10.11'
if (!(Test-Path -LiteralPath (Join-Path $pythonRoot 'python.exe'))) {
    $archive = Get-CheckedDownload 'https://www.python.org/ftp/python/3.10.11/python-3.10.11-embed-amd64.zip' 'python-3.10.11-embed-amd64.zip' '608619F8619075629C9C69F361352A0DA6ED7E62F83A0E19C63E0EA32EB7629D'
    Expand-Archive -LiteralPath $archive -DestinationPath $pythonRoot
}
$pthPath = Join-Path $pythonRoot 'python310._pth'
[IO.File]::WriteAllText($pthPath, [IO.File]::ReadAllText($pthPath).Replace('#import site','import site'), [Text.UTF8Encoding]::new($false))
$python = Join-Path $pythonRoot 'python.exe'
& $python -B -m pip --version 2>$null
if ($LASTEXITCODE -ne 0) {
    $bootstrap = Join-Path $downloads 'get-pip.py'
    & curl.exe --fail --location --http1.1 --output $bootstrap https://bootstrap.pypa.io/get-pip.py
    if ($LASTEXITCODE -ne 0) { throw 'pip bootstrap download failed.' }
    & $python -B $bootstrap 'pip==26.2.2'
    if ($LASTEXITCODE -ne 0) { throw 'pip setup failed.' }
}
$originalPath = $env:Path
$originalBundlePath = $env:BUNDLE_PATH
$originalFrozen = $env:BUNDLE_FROZEN
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $env:Path = (Join-Path $rubyRoot 'bin') + ';' + $nodeRoot + ';' + $pythonRoot + ';' + (Join-Path $pythonRoot 'Scripts') + ';' + $originalPath
    $env:BUNDLE_PATH = Join-Path $ToolsRoot 'bundle-windows'
    $env:BUNDLE_FROZEN = 'true'
    & (Join-Path $rubyRoot 'bin/gem.cmd') install bundler -v 2.5.7 --no-document
    if ($LASTEXITCODE -ne 0) { throw 'Bundler setup failed.' }
    & (Join-Path $rubyRoot 'bin/ridk.cmd') exec bundle _2.5.7_ install
    if ($LASTEXITCODE -ne 0) { throw 'Ruby dependency setup failed.' }
    & $python -B -m pip install -r bin/requirements-build.txt
    if ($LASTEXITCODE -ne 0) { throw 'Python dependency setup failed.' }
    & (Join-Path $nodeRoot 'npm.cmd') ci --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw 'Node dependency setup failed.' }
}
finally {
    Pop-Location
    $env:Path = $originalPath
    $env:BUNDLE_PATH = $originalBundlePath
    $env:BUNDLE_FROZEN = $originalFrozen
}
Write-Host "Build environment ready: $ToolsRoot"
