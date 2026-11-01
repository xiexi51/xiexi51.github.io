[CmdletBinding()]
param([string]$ToolsRoot = (Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) '.homepage-tools'))
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$ToolsRoot = [IO.Path]::GetFullPath($ToolsRoot)
$siteRoot = Join-Path $repoRoot '_site'
$manifestPath = Join-Path $repoRoot '.jekyll-cache/local-build.json'
function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments)] [string[]]$GitArguments)
    & git -c credential.helper= -c 'credential.helper=!gh auth git-credential' @GitArguments
    if ($LASTEXITCODE -ne 0) { throw "Git command failed: $($GitArguments -join ' ')" }
}
Push-Location $repoRoot
try {
    $dirty = @(Invoke-Git status --porcelain=v1 --untracked-files=all)
    if ($dirty.Count) { throw 'Commit all source changes before publishing.' }
    $headCommit = (Invoke-Git rev-parse HEAD).Trim()
    if (!(Test-Path -LiteralPath $manifestPath)) { throw 'Run bin/build-windows.ps1 first.' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
    if ($manifest.preview_only -or $manifest.source_commit -ne $headCommit) { throw 'Build the current clean source commit before publishing.' }
    $actualFiles = @(Get-ChildItem -LiteralPath $siteRoot -File -Recurse -Force)
    if ($actualFiles.Count -ne $manifest.files.Count) { throw 'Build output changed after validation. Rebuild first.' }
    foreach ($file in $actualFiles) {
        $relative = [IO.Path]::GetRelativePath($siteRoot, $file.FullName).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        if (!$manifest.files.ContainsKey($relative) -or $manifest.files[$relative] -ne $hash) { throw "Build output changed: $relative" }
    }
    $remoteMaster = (Invoke-Git ls-remote origin refs/heads/master) -split '\s+'
    if ($remoteMaster[0] -ne $headCommit) { throw 'Push this source commit to master before publishing its build.' }
    Invoke-Git fetch origin gh-pages
    $publishRoot = Join-Path $ToolsRoot ('publish-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    if (Test-Path -LiteralPath $publishRoot) { throw 'Refusing to overwrite an existing worktree.' }
    Invoke-Git worktree add --detach $publishRoot origin/gh-pages
    $resolvedPublish = (Resolve-Path -LiteralPath $publishRoot).Path
    $resolvedTools = (Resolve-Path -LiteralPath $ToolsRoot).Path.TrimEnd('\') + '\'
    if (!$resolvedPublish.StartsWith($resolvedTools, [StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath (Join-Path $resolvedPublish '.git') -PathType Leaf)) {
        throw 'Publish staging directory failed its workspace safety check.'
    }
    # This fresh, dedicated generated-site worktree is the only directory cleared.
    Get-ChildItem -LiteralPath $resolvedPublish -Force | Where-Object Name -ne '.git' | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
    Get-ChildItem -LiteralPath $siteRoot -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $resolvedPublish -Recurse -Force }
    Push-Location $resolvedPublish
    try {
        Invoke-Git add --force --all
        & git diff --cached --quiet
        if ($LASTEXITCODE -eq 0) { Write-Host 'Published content already matches this build.'; return }
        if ($LASTEXITCODE -ne 1) { throw 'Cannot inspect staged publication.' }
        Invoke-Git commit -m "Publish homepage from personal computer (source $($headCommit.Substring(0,12)))"
        Invoke-Git push origin HEAD:refs/heads/gh-pages
        $publishedCommit = (Invoke-Git rev-parse HEAD).Trim()
        Write-Host "Published $publishedCommit from source $headCommit"
        Write-Host 'Check the GitHub Pages deployment result and https://xiexi51.github.io/ .'
        Write-Host "The publication worktree remains available at $resolvedPublish"
    }
    finally { Pop-Location }
}
finally { Pop-Location }
