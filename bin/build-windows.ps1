[CmdletBinding()]
param(
    [string]$ToolsRoot = (Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) '.homepage-tools'),
    [switch]$AllowUncommitted
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$ToolsRoot = [IO.Path]::GetFullPath($ToolsRoot)
$rubyRoot = Join-Path $ToolsRoot 'ruby-3.3.5-x64'
$nodeRoot = Join-Path $ToolsRoot 'node-v22.9.0-win-x64'
$pythonRoot = Join-Path $ToolsRoot 'python-3.10.11'
foreach ($binary in @((Join-Path $rubyRoot 'bin/ruby.exe'), (Join-Path $nodeRoot 'node.exe'), (Join-Path $pythonRoot 'python.exe'))) {
    if (!(Test-Path -LiteralPath $binary)) { throw "Missing runtime: $binary. See bin/README.windows.md." }
}
$originalPath = $env:Path
$originalBundlePath = $env:BUNDLE_PATH
$originalFrozen = $env:BUNDLE_FROZEN
$originalJekyllEnv = $env:JEKYLL_ENV
$originalExecjs = $env:EXECJS_RUNTIME
Push-Location $repoRoot
try {
    $env:Path = (Join-Path $rubyRoot 'bin') + ';' + $nodeRoot + ';' + $pythonRoot + ';' + (Join-Path $pythonRoot 'Scripts') + ';' + $originalPath
    $env:BUNDLE_PATH = Join-Path $ToolsRoot 'bundle-windows'
    $env:BUNDLE_FROZEN = 'true'
    $env:JEKYLL_ENV = 'production'
    $env:EXECJS_RUNTIME = 'Node'
    $dirty = @(git status --porcelain=v1 --untracked-files=all)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read repository status.' }
    if ($dirty.Count -and !$AllowUncommitted) { throw 'Commit source changes before creating a publishable build, or use -AllowUncommitted for a preview.' }
    $startingCommit = (git rev-parse HEAD).Trim()
    & (Join-Path $rubyRoot 'bin/ridk.cmd') exec bundle _2.5.7_ check
    if ($LASTEXITCODE -ne 0) { throw 'Ruby dependencies are missing. See bin/README.windows.md.' }
    & (Join-Path $nodeRoot 'npm.cmd') ci --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw 'npm ci failed.' }
    & (Join-Path $rubyRoot 'bin/ridk.cmd') exec bundle _2.5.7_ exec jekyll build --trace
    if ($LASTEXITCODE -ne 0) { throw 'Jekyll build failed.' }
    & (Join-Path $nodeRoot 'node.exe') bin/purge-css.cjs
    if ($LASTEXITCODE -ne 0) { throw 'PurgeCSS failed.' }
    $siteRoot = Join-Path $repoRoot '_site'
    [IO.File]::WriteAllText((Join-Path $siteRoot '.nojekyll'), '')
    $commit = (git rev-parse HEAD).Trim()
    $endingDirty = @(git status --porcelain=v1 --untracked-files=all)
    if (!$AllowUncommitted -and ($commit -ne $startingCommit -or $endingDirty.Count)) {
        throw 'Source changed during the build. Rebuild the final clean commit before publishing.'
    }
    $files = [ordered]@{}
    Get-ChildItem -LiteralPath $siteRoot -File -Recurse -Force | Sort-Object FullName | ForEach-Object {
        $relative = [IO.Path]::GetRelativePath($siteRoot, $_.FullName).Replace('\', '/')
        $files[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $manifest = [ordered]@{source_commit=$commit; preview_only=[bool]$dirty.Count; built_at=[DateTime]::UtcNow.ToString('o'); files=$files}
    New-Item -ItemType Directory -Path '.jekyll-cache' -Force | Out-Null
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath '.jekyll-cache/local-build.json' -Encoding utf8
    Write-Host "Built $($files.Count) files from $commit. Preview only: $([bool]$dirty.Count)"
}
finally {
    Pop-Location
    $env:Path = $originalPath
    $env:BUNDLE_PATH = $originalBundlePath
    $env:BUNDLE_FROZEN = $originalFrozen
    $env:JEKYLL_ENV = $originalJekyllEnv
    $env:EXECJS_RUNTIME = $originalExecjs
}
