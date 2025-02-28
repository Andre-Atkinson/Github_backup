# Load .env file
Set-Location -Path $PSScriptRoot

Start-Transcript -Path "$PSScriptRoot\restore_log.txt" -Append

$envFile = ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $name, $value = $_ -split '=', 2
        Set-Item -Path "Env:\$name" -Value $value
    }
}
else {
    Write-Error "Missing .env file. Please create one with GITHUB_USERNAME, GITHUB_TOKEN, AWS_ACCESS_KEY_ID, and AWS_SECRET_ACCESS_KEY."
    exit 1
}

# GitHub credentials
$githubUser = $env:GITHUB_USERNAME
$githubToken = $env:GITHUB_TOKEN

if (-not $githubUser -or -not $githubToken) {
    Write-Error "GitHub credentials not found in .env file."
    exit 1
}

# AWS Credentials
$awsAccessKey = $env:AWS_ACCESS_KEY_ID
$awsSecretKey = $env:AWS_SECRET_ACCESS_KEY
$awsBucket = "github-backups-homelabpro"

if (-not $awsAccessKey -or -not $awsSecretKey) {
    Write-Error "AWS credentials not found in .env file."
    exit 1
}

# Input: Repo name
$repoName = Read-Host "Enter the name of the repository to restore"

# Download SHA JSON from S3
$shaJsonFile = "./github_backup.json"
aws s3 cp "s3://$awsBucket/github_backups/github_backup.json" $shaJsonFile --quiet

if (-not (Test-Path $shaJsonFile)) {
    Write-Error "SHA JSON file not found in S3. Cannot proceed with restore."
    exit 1
}

# Load JSON and find latest backup for the repo
$shaData = Get-Content -Raw -Path $shaJsonFile | ConvertFrom-Json
$latestBackup = $shaData | Where-Object { $_.repo -eq $repoName } | Sort-Object date -Descending | Select-Object -First 1

if (-not $latestBackup) {
    Write-Error "No backup found for $repoName."
    exit 1
}

# Download latest backup
$backupDate = $latestBackup.date
$zipFile = "./$repoName.zip"
Write-Host "Downloading latest backup for $repoName..."
aws s3 cp "s3://$awsBucket/github_backups/$backupDate/$repoName.zip" $zipFile --quiet

if (-not (Test-Path $zipFile)) {
    Write-Error "Failed to download backup zip file."
    exit 1
}

# Unzip the backup
$unzipDir = "./$repoName-unzipped"
Expand-Archive -Path $zipFile -DestinationPath $unzipDir -Force

# Find the inner folder (mirrored git repo)
$innerFolder = Get-ChildItem -Path $unzipDir | Where-Object { $_.PSIsContainer } | Select-Object -First 1
$mirrorPath = if ($innerFolder) { "$unzipDir/$($innerFolder.Name)" } else { $unzipDir }

# Check if repo exists on GitHub
$repoExists = $false
$githubApiUrl = "https://api.github.com/repos/$githubUser/$repoName"
$headers = @{ Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$githubUser`:$githubToken")) }

try {
    Invoke-RestMethod -Uri $githubApiUrl -Headers $headers -Method Get
    $repoExists = $true
}
catch {
    $repoExists = $false
}

# Create repo if it doesn't exist
if (-not $repoExists) {
    Write-Host "Repository $repoName does not exist. Creating a new private repo..."
    $createRepoBody = @{ name = $repoName; private = $true } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri "https://api.github.com/user/repos" -Headers $headers -Method Post -Body $createRepoBody -ContentType "application/json"
}

# Clone the bare repository (mirror) into a non-bare repository with a working tree
$restoredDir = "./$repoName-restored"
git clone $mirrorPath $restoredDir

# Change directory to the restored repository
Set-Location -Path $restoredDir

# Set the remote URL for GitHub with embedded credentials
$remoteUrl = "https://$githubUser`:$githubToken@github.com/$githubUser/$repoName.git"
git remote set-url origin $remoteUrl

# Push all branches and tags
git push --force --all
git push --force --tags

Write-Host "Repository $repoName restored successfully."

# Cleanup
Set-Location -Path $PSScriptRoot
Remove-Item -Recurse -Force $unzipDir
Remove-Item -Recurse -Force $restoredDir
Remove-Item -Force $zipFile

Stop-Transcript
