Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"
if ($env:CLOUDFLARE_SETUP_PROJECT_ROOT -and (Test-Path -LiteralPath $env:CLOUDFLARE_SETUP_PROJECT_ROOT)) {
    $ProjectRoot = Resolve-Path $env:CLOUDFLARE_SETUP_PROJECT_ROOT
} else {
    $ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
}
$DefaultProjectName = "v2ray-subscription-manager"

function New-ControlFont($size, $style = [System.Drawing.FontStyle]::Regular) {
    return New-Object System.Drawing.Font("Segoe UI", $size, $style)
}

function Append-Log($text) {
    $time = Get-Date -Format "HH:mm:ss"
    $logBox.AppendText("[$time] $(Remove-Ansi $text)`r`n")
    $logBox.SelectionStart = $logBox.Text.Length
    $logBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Remove-Ansi($text) {
    if ($null -eq $text) {
        return ""
    }
    $escape = [char]27
    return ([string]$text) -replace "$escape\[[0-9;?]*[ -/]*[@-~]", ""
}

function Set-Status($text) {
    $statusLabel.Text = $text
    [System.Windows.Forms.Application]::DoEvents()
}

function Run-Command($fileName, $arguments, $stdin = $null) {
    $resolvedFile = Resolve-ToolPath $fileName
    Append-Log "> $fileName $arguments"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $resolvedFile
    $psi.Arguments = $arguments
    $psi.WorkingDirectory = $ProjectRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $null -ne $stdin
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()

    if ($null -ne $stdin) {
        $proc.StandardInput.WriteLine($stdin)
        $proc.StandardInput.Close()
    }

    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    $stdout = Remove-Ansi $stdout
    $stderr = Remove-Ansi $stderr

    if ($stdout.Trim()) { Append-Log $stdout.Trim() }
    if ($stderr.Trim()) { Append-Log $stderr.Trim() }

    if ($proc.ExitCode -ne 0) {
        throw "Command failed with exit code $($proc.ExitCode): $fileName $arguments"
    }

    return "$stdout`n$stderr"
}

function Resolve-ToolPath($fileName) {
    $nodeDir = Join-Path $env:ProgramFiles "nodejs"
    $candidates = @(
        (Join-Path $nodeDir "$fileName.exe"),
        (Join-Path $nodeDir "$fileName.cmd"),
        (Join-Path $nodeDir $fileName),
        (Join-Path $nodeDir "$fileName.ps1")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    $command = Get-Command $fileName -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw "Could not find $fileName. Install Node.js LTS, close this app, and open it again."
}

function Run-Command-AllowFailure($fileName, $arguments, $stdin = $null) {
    try {
        return Run-Command $fileName $arguments $stdin
    } catch {
        Append-Log "Non-fatal: $($_.Exception.Message)"
        return ""
    }
}

function Parse-KvId($output) {
    $match = [regex]::Match($output, 'id\s*=\s*"([^"]+)"')
    if (-not $match.Success) {
        throw "Could not find KV namespace id in Wrangler output."
    }
    return $match.Groups[1].Value
}

function Load-WranglerToml-Into-Fields {
    $path = Join-Path $ProjectRoot "wrangler.toml"
    if (-not (Test-Path -LiteralPath $path)) {
        return
    }

    $content = Get-Content -LiteralPath $path -Raw
    $nameMatch = [regex]::Match($content, '(?m)^name\s*=\s*"([^"]+)"')
    $idMatch = [regex]::Match($content, '(?m)^id\s*=\s*"([^"]+)"')
    $previewMatch = [regex]::Match($content, '(?m)^preview_id\s*=\s*"([^"]+)"')

    if ($nameMatch.Success) {
        $projectNameBox.Text = $nameMatch.Groups[1].Value
    }
    if ($idMatch.Success -and $idMatch.Groups[1].Value -notlike "replace_with_*") {
        $prodKvBox.Text = $idMatch.Groups[1].Value
    }
    if ($previewMatch.Success -and $previewMatch.Groups[1].Value -notlike "replace_with_*") {
        $previewKvBox.Text = $previewMatch.Groups[1].Value
    }
}

function Get-Kv-NamespaceMap {
    $output = Run-Command "npx" "wrangler kv namespace list"
    $namespaces = Convert-WranglerJsonArray $output
    $map = @{}
    foreach ($namespace in $namespaces) {
        if ($namespace.title -and $namespace.id) {
            $map[$namespace.title.Trim()] = $namespace.id
        }
    }
    return $map
}

function Convert-WranglerJsonArray($output) {
    $clean = Remove-Ansi $output
    $start = $clean.IndexOf("[")
    $end = $clean.LastIndexOf("]")
    if ($start -lt 0 -or $end -lt $start) {
        throw "Could not find JSON array in Wrangler output."
    }
    return $clean.Substring($start, $end - $start + 1) | ConvertFrom-Json
}

function Fill-Kv-Fields-From-Cloudflare {
    $map = Get-Kv-NamespaceMap
    if ([string]::IsNullOrWhiteSpace($prodKvBox.Text) -and $map.ContainsKey("SUB_KV")) {
        $prodKvBox.Text = $map["SUB_KV"]
        Append-Log "Found existing SUB_KV namespace."
    }
    if ([string]::IsNullOrWhiteSpace($previewKvBox.Text) -and $map.ContainsKey("SUB_KV_preview")) {
        $previewKvBox.Text = $map["SUB_KV_preview"]
        Append-Log "Found existing SUB_KV_preview namespace."
    }
}

function Save-WranglerToml($projectName, $prodId, $previewId) {
    $content = @"
name = "$projectName"
compatibility_date = "2026-06-11"
pages_build_output_dir = "public"

[[kv_namespaces]]
binding = "SUB_KV"
id = "$prodId"
preview_id = "$previewId"
"@
    Set-Content -LiteralPath (Join-Path $ProjectRoot "wrangler.toml") -Value $content -Encoding UTF8
    Append-Log "Saved KV binding to wrangler.toml."
}

function Extract-PagesUrl($output, $projectName) {
    $matches = [regex]::Matches($output, 'https://[A-Za-z0-9.-]+\.pages\.dev')
    if ($matches.Count -gt 0) {
        return $matches[$matches.Count - 1].Value
    }
    return "https://$projectName.pages.dev"
}

function Get-StableAdminUrl($projectName) {
    return "https://$projectName.pages.dev/admin"
}

function Ensure-AdminPath($url) {
    return $url.TrimEnd("/") + "/admin"
}

function Require-Password() {
    if ([string]::IsNullOrWhiteSpace($passwordBox.Text)) {
        throw "Enter a password first, or click Reset Panel Password to make the web panel ask you to create one."
    }
}

function New-RandomPassword() {
    $bytes = New-Object byte[] 24
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    } finally {
        $rng.Dispose()
    }
    return [Convert]::ToBase64String($bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}

function Require-ProjectName() {
    if ([string]::IsNullOrWhiteSpace($projectNameBox.Text)) {
        throw "Enter a Pages project name first."
    }
    $name = $projectNameBox.Text.Trim().ToLowerInvariant()
    if ($name -notmatch '^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$') {
        throw "Use a project name with lowercase letters, numbers, and hyphens only. Example: v2ray-subscription-manager"
    }
    return $name
}

function Run-Step($name, [scriptblock]$work) {
    try {
        Set-Status $name
        Append-Log ""
        Append-Log "=== $name ==="
        & $work
        Set-Status "Ready"
    } catch {
        Set-Status "Stopped: $name failed"
        Append-Log "ERROR: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Setup failed", "OK", "Error") | Out-Null
    }
}

function Check-Tools {
    Run-Command "node" "--version" | Out-Null
    Run-Command "npm" "--version" | Out-Null
    Append-Log "Node.js and npm are available."
}

function Install-Dependencies {
    Run-Command "npm" "install" | Out-Null
}

function Login-Cloudflare {
    if (Test-Wrangler-Logged-In) {
        Append-Log "Cloudflare login is already active."
        return
    }
    Run-Command "npx" "wrangler login" | Out-Null
    Append-Log "Cloudflare login finished."
}

function Test-Wrangler-Logged-In {
    try {
        Run-Command "npx" "wrangler whoami --json" | Out-Null
        return $true
    } catch {
        Append-Log "Cloudflare login is required."
        return $false
    }
}

function Create-Kv {
    Load-WranglerToml-Into-Fields

    if (-not [string]::IsNullOrWhiteSpace($prodKvBox.Text) -and -not [string]::IsNullOrWhiteSpace($previewKvBox.Text)) {
        Append-Log "KV IDs are already filled. Reusing them."
        Save-Kv-From-Fields
        return
    }

    Fill-Kv-Fields-From-Cloudflare

    if ([string]::IsNullOrWhiteSpace($prodKvBox.Text)) {
        try {
            $prodOut = Run-Command "npx" "wrangler kv namespace create SUB_KV"
            $prodKvBox.Text = Parse-KvId $prodOut
        } catch {
            Append-Log "Could not create SUB_KV. Checking existing namespaces."
            Fill-Kv-Fields-From-Cloudflare
            if ([string]::IsNullOrWhiteSpace($prodKvBox.Text)) {
                throw
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($previewKvBox.Text)) {
        try {
            $previewOut = Run-Command "npx" "wrangler kv namespace create SUB_KV --preview"
            $previewKvBox.Text = Parse-KvId $previewOut
        } catch {
            Append-Log "Could not create SUB_KV_preview. Checking existing namespaces."
            Fill-Kv-Fields-From-Cloudflare
            if ([string]::IsNullOrWhiteSpace($previewKvBox.Text)) {
                throw
            }
        }
    }

    $prodId = $prodKvBox.Text.Trim()
    $previewId = $previewKvBox.Text.Trim()
    $prodKvBox.Text = $prodId
    $previewKvBox.Text = $previewId
    Save-WranglerToml (Require-ProjectName) $prodId $previewId
}

function Save-Kv-From-Fields {
    $prodId = $prodKvBox.Text.Trim()
    $previewId = $previewKvBox.Text.Trim()
    if (-not $prodId -or -not $previewId) {
        throw "Production and preview KV IDs are required."
    }
    Save-WranglerToml (Require-ProjectName) $prodId $previewId
}

function Create-Pages-Project {
    $projectName = Require-ProjectName
    if (Test-Pages-Project-Exists $projectName) {
        Append-Log "Pages project already exists: $projectName"
        return
    }
    Run-Command "npx" "wrangler pages project create $projectName --production-branch main" | Out-Null
    Append-Log "Created Pages project: $projectName"
}

function Set-Admin-Secret([bool]$deployAfter = $false) {
    if ($deployAfter) {
        Append-Log "Deploying before setting the panel password."
        Deploy-Project
    }
    if ([string]::IsNullOrWhiteSpace($passwordBox.Text)) {
        Reset-Panel-Password
        Append-Log "No password was entered. The web panel will ask you to create one on first login."
        return
    }
    Set-Panel-Password $true
}

function Set-Panel-Password([bool]$allowReset = $false) {
    $projectName = Require-ProjectName
    $loginUrl = "https://$projectName.pages.dev/api/admin/login"
    $body = @{ password = $passwordBox.Text } | ConvertTo-Json -Compress

    try {
        $status = Invoke-RestMethod -Uri $loginUrl -Method Get
        if ($status.configured -eq $true) {
            if (-not $allowReset) {
                Append-Log "Panel password already exists. Open /admin to log in."
                return
            }
            Append-Log "Panel password already exists. Resetting stored password first."
            Reset-Panel-Password
            Start-Sleep -Seconds 2
        }

        Invoke-RestMethod -Uri $loginUrl -Method Put -ContentType "application/json" -Body $body | Out-Null
        Append-Log "Saved first-run panel password in Cloudflare KV."
    } catch {
        Append-Log "Could not save panel password automatically: $($_.Exception.Message)"
        Append-Log "Open /admin and create the password there."
    }
}

function Reset-Panel-Password {
    $prodId = $prodKvBox.Text.Trim()
    if (-not $prodId) {
        Load-WranglerToml-Into-Fields
        $prodId = $prodKvBox.Text.Trim()
    }
    if (-not $prodId) {
        Fill-Kv-Fields-From-Cloudflare
        $prodId = $prodKvBox.Text.Trim()
    }
    if (-not $prodId) {
        throw "Production KV ID is required before resetting the panel password."
    }

    Run-Command-AllowFailure "npx" "wrangler kv key delete admin_auth --namespace-id $prodId --remote" | Out-Null
    Append-Log "Cleared stored panel password. Open /admin to create a new one."
}

function Deploy-Project {
    $projectName = Require-ProjectName
    $output = Run-Command "npx" "wrangler pages deploy public --project-name $projectName"
    $deploymentUrl = Extract-PagesUrl $output $projectName
    $adminUrl = Get-StableAdminUrl $projectName
    $adminUrlBox.Text = $adminUrl
    Append-Log "Latest deployment URL: $deploymentUrl"
    Append-Log "Admin panel: $adminUrl"
    Test-Admin-Login $false
    [System.Windows.Forms.MessageBox]::Show("Deployment finished.`n`nAdmin panel:`n$adminUrl", "Cloudflare setup complete", "OK", "Information") | Out-Null
}

function Test-Admin-Login([bool]$showSuccessMessage = $true) {
    Require-Password
    $adminUrl = $adminUrlBox.Text.Trim()
    if (-not $adminUrl) {
        $adminUrl = Ensure-AdminPath "https://$(Require-ProjectName).pages.dev"
        $adminUrlBox.Text = $adminUrl
    }

    $loginUrl = $adminUrl.TrimEnd("/") -replace "/admin$", "/api/admin/login"
    Append-Log "Testing admin password at $loginUrl"

    try {
        $body = @{ password = $passwordBox.Text } | ConvertTo-Json -Compress
        $result = Invoke-RestMethod -Uri $loginUrl -Method Post -ContentType "application/json" -Body $body -SessionVariable session
        if ($result.ok -eq $true) {
            $configsUrl = $loginUrl -replace "/api/admin/login$", "/api/admin/configs"
            Invoke-RestMethod -Uri $configsUrl -WebSession $session | Out-Null
            Append-Log "Admin password and session cookie test passed."
            if ($showSuccessMessage) {
                [System.Windows.Forms.MessageBox]::Show("Admin password works.", "Password test passed", "OK", "Information") | Out-Null
            }
            return
        }
        throw "Unexpected login response."
    } catch {
        Append-Log "Admin password test failed: $($_.Exception.Message)"
        Append-Log "If you just changed the password, click Set Password, then Deploy, then Test Admin Login again."
        if ($showSuccessMessage) {
            [System.Windows.Forms.MessageBox]::Show("Admin login failed. Click Set Password, then Deploy, then test again.", "Password test failed", "OK", "Warning") | Out-Null
        }
    }
}

function Refresh-Pages-Projects {
    $projectListBox.Items.Clear()
    $output = Run-Command "npx" "wrangler pages project list --json"
    $projects = Convert-WranglerJsonArray $output
    foreach ($project in $projects) {
        $name = $project."Project Name"
        $domain = $project."Project Domains"
        if ($name) {
            [void]$projectListBox.Items.Add("$name | $domain")
        }
    }
    Append-Log "Loaded $($projectListBox.Items.Count) Pages project(s)."
}

function Test-Pages-Project-Exists($projectName) {
    $output = Run-Command "npx" "wrangler pages project list --json"
    $projects = Convert-WranglerJsonArray $output
    foreach ($project in $projects) {
        if ($project."Project Name" -eq $projectName) {
            return $true
        }
    }
    return $false
}

function Delete-Selected-Pages-Projects {
    if ($projectListBox.CheckedItems.Count -eq 0) {
        throw "Select one or more Pages projects first."
    }

    $names = @()
    foreach ($item in $projectListBox.CheckedItems) {
        $names += (($item.ToString() -split "\|")[0].Trim())
    }

    $message = "Delete these Cloudflare Pages projects?`n`n" + ($names -join "`n")
    $confirm = [System.Windows.Forms.MessageBox]::Show($message, "Confirm delete", "YesNo", "Warning")
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        Append-Log "Delete canceled."
        return
    }

    foreach ($name in $names) {
        Run-Command "npx" "wrangler pages project delete $name --yes" | Out-Null
        Append-Log "Deleted Pages project: $name"
    }

    Refresh-Pages-Projects
}

function Run-All {
    Check-Tools
    Install-Dependencies
    Login-Cloudflare
    Create-Kv
    Create-Pages-Project
    Set-Admin-Secret
    Deploy-Project
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Cloudflare V2Ray Subscription Manager Setup"
$form.Size = New-Object System.Drawing.Size(1180, 760)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(1040, 700)
$form.Font = New-ControlFont 9

$title = New-Object System.Windows.Forms.Label
$title.Text = "Cloudflare Setup"
$title.Font = New-ControlFont 18 ([System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(18, 16)
$title.Size = New-Object System.Drawing.Size(520, 34)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "Deploy the Pages + Functions project, create KV storage, set the admin password, and get the admin URL."
$subtitle.Location = New-Object System.Drawing.Point(20, 54)
$subtitle.Size = New-Object System.Drawing.Size(1100, 24)
$form.Controls.Add($subtitle)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Ready"
$statusLabel.Location = New-Object System.Drawing.Point(20, 86)
$statusLabel.Size = New-Object System.Drawing.Size(1100, 22)
$form.Controls.Add($statusLabel)

$labels = @(
    @{ Text = "Pages project name"; Y = 122 },
    @{ Text = "Admin password"; Y = 164 },
    @{ Text = "Production KV ID"; Y = 206 },
    @{ Text = "Preview KV ID"; Y = 248 },
    @{ Text = "Admin panel URL"; Y = 290 }
)

foreach ($item in $labels) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $item.Text
    $label.Location = New-Object System.Drawing.Point(20, $item.Y)
    $label.Size = New-Object System.Drawing.Size(150, 24)
    $form.Controls.Add($label)
}

$projectNameBox = New-Object System.Windows.Forms.TextBox
$projectNameBox.Text = $DefaultProjectName
$projectNameBox.Location = New-Object System.Drawing.Point(180, 118)
$projectNameBox.Size = New-Object System.Drawing.Size(360, 26)
$form.Controls.Add($projectNameBox)

$passwordBox = New-Object System.Windows.Forms.TextBox
$passwordBox.UseSystemPasswordChar = $true
$passwordBox.Location = New-Object System.Drawing.Point(180, 160)
$passwordBox.Size = New-Object System.Drawing.Size(360, 26)
$form.Controls.Add($passwordBox)

$copyPasswordButton = New-Object System.Windows.Forms.Button
$copyPasswordButton.Text = "Copy Password"
$copyPasswordButton.Location = New-Object System.Drawing.Point(552, 158)
$copyPasswordButton.Size = New-Object System.Drawing.Size(118, 30)
$copyPasswordButton.Add_Click({
    Require-Password
    [System.Windows.Forms.Clipboard]::SetText($passwordBox.Text)
    Append-Log "Copied admin password."
})
$form.Controls.Add($copyPasswordButton)

$showPasswordCheck = New-Object System.Windows.Forms.CheckBox
$showPasswordCheck.Text = "Show"
$showPasswordCheck.Location = New-Object System.Drawing.Point(684, 162)
$showPasswordCheck.Size = New-Object System.Drawing.Size(72, 24)
$showPasswordCheck.Add_CheckedChanged({
    $passwordBox.UseSystemPasswordChar = -not $showPasswordCheck.Checked
})
$form.Controls.Add($showPasswordCheck)

$prodKvBox = New-Object System.Windows.Forms.TextBox
$prodKvBox.Location = New-Object System.Drawing.Point(180, 202)
$prodKvBox.Size = New-Object System.Drawing.Size(590, 26)
$form.Controls.Add($prodKvBox)

$previewKvBox = New-Object System.Windows.Forms.TextBox
$previewKvBox.Location = New-Object System.Drawing.Point(180, 244)
$previewKvBox.Size = New-Object System.Drawing.Size(590, 26)
$form.Controls.Add($previewKvBox)

$adminUrlBox = New-Object System.Windows.Forms.TextBox
$adminUrlBox.ReadOnly = $true
$adminUrlBox.Location = New-Object System.Drawing.Point(180, 286)
$adminUrlBox.Size = New-Object System.Drawing.Size(490, 26)
$form.Controls.Add($adminUrlBox)

$copyUrlButton = New-Object System.Windows.Forms.Button
$copyUrlButton.Text = "Copy"
$copyUrlButton.Location = New-Object System.Drawing.Point(680, 284)
$copyUrlButton.Size = New-Object System.Drawing.Size(74, 30)
$copyUrlButton.Add_Click({
    if ($adminUrlBox.Text) {
        [System.Windows.Forms.Clipboard]::SetText($adminUrlBox.Text)
        Append-Log "Copied admin URL."
    }
})
$form.Controls.Add($copyUrlButton)

$openUrlButton = New-Object System.Windows.Forms.Button
$openUrlButton.Text = "Open"
$openUrlButton.Location = New-Object System.Drawing.Point(760, 284)
$openUrlButton.Size = New-Object System.Drawing.Size(74, 30)
$openUrlButton.Add_Click({
    if ($adminUrlBox.Text) {
        Start-Process $adminUrlBox.Text
    }
})
$form.Controls.Add($openUrlButton)

$buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$buttonPanel.Location = New-Object System.Drawing.Point(20, 328)
$buttonPanel.Size = New-Object System.Drawing.Size(805, 86)
$buttonPanel.WrapContents = $true
$form.Controls.Add($buttonPanel)

$projectGroup = New-Object System.Windows.Forms.GroupBox
$projectGroup.Text = "Cloudflare Pages Projects"
$projectGroup.Location = New-Object System.Drawing.Point(850, 118)
$projectGroup.Size = New-Object System.Drawing.Size(290, 296)
$form.Controls.Add($projectGroup)

$projectListBox = New-Object System.Windows.Forms.CheckedListBox
$projectListBox.CheckOnClick = $true
$projectListBox.Location = New-Object System.Drawing.Point(12, 24)
$projectListBox.Size = New-Object System.Drawing.Size(266, 210)
$projectListBox.HorizontalScrollbar = $true
$projectGroup.Controls.Add($projectListBox)

$refreshProjectsButton = New-Object System.Windows.Forms.Button
$refreshProjectsButton.Text = "List Pages"
$refreshProjectsButton.Location = New-Object System.Drawing.Point(12, 248)
$refreshProjectsButton.Size = New-Object System.Drawing.Size(126, 32)
$refreshProjectsButton.Add_Click({ Run-Step "List Pages" { Refresh-Pages-Projects } })
$projectGroup.Controls.Add($refreshProjectsButton)

$deleteProjectsButton = New-Object System.Windows.Forms.Button
$deleteProjectsButton.Text = "Delete Selected"
$deleteProjectsButton.Location = New-Object System.Drawing.Point(148, 248)
$deleteProjectsButton.Size = New-Object System.Drawing.Size(130, 32)
$deleteProjectsButton.Add_Click({ Run-Step "Delete Selected Pages" { Delete-Selected-Pages-Projects } })
$projectGroup.Controls.Add($deleteProjectsButton)

function Add-Button($text, [scriptblock]$action, $width = 132) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $text
    $button.Size = New-Object System.Drawing.Size($width, 34)
    $button.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 8)
    $button.Add_Click({ Run-Step $text $action }.GetNewClosure())
    $buttonPanel.Controls.Add($button)
}

Add-Button "Run All" { Run-All } 100
Add-Button "Check Tools" { Check-Tools }
Add-Button "Install npm" { Install-Dependencies }
Add-Button "Cloudflare Login" { Login-Cloudflare } 150
Add-Button "Create KV" { Create-Kv } 110
Add-Button "Save KV IDs" { Save-Kv-From-Fields } 120
Add-Button "Create Pages" { Create-Pages-Project } 130
Add-Button "Set Password" { Set-Admin-Secret $true } 125
Add-Button "Deploy" { Deploy-Project } 100
Add-Button "Test Admin Login" { Test-Admin-Login $true } 145
Add-Button "Reset Panel Password" { Reset-Panel-Password } 170

$hint = New-Object System.Windows.Forms.Label
$hint.Text = "Empty password means first-run setup in /admin. If locked out, click Reset Panel Password, then open /admin and create a new password."
$hint.Location = New-Object System.Drawing.Point(20, 418)
$hint.Size = New-Object System.Drawing.Size(1120, 30)
$form.Controls.Add($hint)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.Font = New-Object System.Drawing.Font("Cascadia Mono", 9)
$logBox.Location = New-Object System.Drawing.Point(20, 456)
$logBox.Size = New-Object System.Drawing.Size(1120, 220)
$logBox.Anchor = "Left, Top, Right, Bottom"
$form.Controls.Add($logBox)

Load-WranglerToml-Into-Fields
$adminUrlBox.Text = Get-StableAdminUrl $projectNameBox.Text.Trim()

Append-Log "Project folder: $ProjectRoot"
Append-Log "Click Run All for a full setup, or run the steps one by one."

[void]$form.ShowDialog()
