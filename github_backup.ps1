# Load .env file
Set-Location -Path $PSScriptRoot

Start-Transcript -Path "$PSScriptRoot\script_log.txt"

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
$awsBucket = $env:S3_BUCKET

if (-not $awsAccessKey -or -not $awsSecretKey) {
    Write-Error "AWS credentials not found in .env file."
    exit 1
}

# API URL and Headers
$githubApiUrl = "https://api.github.com/user/repos?per_page=100"
$headers = @{ Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$githubUser`:$githubToken")) }

# Backup directory
$backupRoot = "github_backups"
$backupDate = Get-Date -Format "yyyy-MM-dd"
$backupDir = "$backupRoot/$backupDate"
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }

# JSON file for SHAs
$shaJsonFile = "$backupRoot/github_backup.json"

# Download SHA JSON from S3
Write-Host "Downloading SHA JSON from S3..."
aws s3 cp "s3://$awsBucket/github_backups/github_backup.json" $shaJsonFile --quiet

if (-not (Test-Path $shaJsonFile)) {
    "[]" | Set-Content -Path $shaJsonFile
}

# Load existing JSON
$shaData = Get-Content -Raw -Path $shaJsonFile | ConvertFrom-Json
if (-not $shaData) { $shaData = @() }

# Determine if today is Friday for forced backup
$forceBackup = ((Get-Date).DayOfWeek -eq "Friday")
if ($forceBackup) {
    Write-Host "Today is Friday. Forcing full backup of all repositories."
}

# Function to fetch all repos with pagination
function Get-AllRepos {
    $repos = @()
    $url = $githubApiUrl
    do {
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        $repos += $response
        $linkHeader = ($response.PSObject.Properties["Link"].Value)
        if ($linkHeader -match '<(https[^>]+)>; rel="next"') {
            $url = $matches[1]
        }
        else {
            $url = $null
        }
    } while ($url)
    return $repos
}

# Fetch all repositories
$repos = Get-AllRepos
if ($repos.Count -eq 0) {
    Write-Host "No repositories found. Exiting."
    exit 0
}

foreach ($repo in $repos) {
    $repoName = $repo.name
    $repoCloneUrl = $repo.clone_url
    $repoDir = "$backupDir/$repoName"

    # Create repo-specific directory
    if (-not (Test-Path $repoDir)) { New-Item -ItemType Directory -Path $repoDir | Out-Null }

    # Get latest commit SHA (assumes default branch is main)
    $commitUrl = $repo.commits_url -replace "{/sha}", "/main"
    $commitData = Invoke-RestMethod -Uri $commitUrl -Headers $headers -Method Get
    $latestSha = $commitData.sha

    # Skip backup if SHA hasn't changed, unless today is Friday
    if (-not $forceBackup -and ($shaData | Where-Object { $_.repo -eq $repoName -and $_.sha -eq $latestSha })) {
        Write-Host "Skipping $repoName (no changes)."
        continue
    }

    # Save new SHA entry
    $shaEntry = @{ repo = $repoName; sha = $latestSha; date = $backupDate }
    $shaData += $shaEntry

    # Reformat the clone URL to include credentials
    $repoCloneUrlWithCreds = $repoCloneUrl -replace "https://", "https://$githubUser`:$githubToken@"

    # Git clone --mirror using the updated URL
    Write-Host "Cloning $repoName..."
    git clone --mirror $repoCloneUrlWithCreds $repoDir

    # Zip the mirrored repo
    $timestamp = Get-Date -Format "HH-mm-ss"
    $zipFile = "$repoDir/${repoName}_$backupDate`_$timestamp.zip"
    Compress-Archive -Path $repoDir -DestinationPath $zipFile

    Write-Host "Backup completed for $repoName."

    Start-Sleep -Seconds 1

    # Verify file exists before uploading
    if (Test-Path $zipFile) {
        Write-Host "☁️ Uploading $zipFile to S3..."
        $zipFileCorrected = $zipFile -replace '\\', '/'
        aws s3 cp $zipFileCorrected "s3://$awsBucket/github_backups/$backupDate/$repoName.zip" --quiet
    }
    else {
        Write-Host "⚠️ Error: File $zipFile does not exist. Skipping upload."
    }
}

# Save updated SHA JSON file and upload to S3
$shaData | ConvertTo-Json -Depth 10 | Set-Content -Path $shaJsonFile
aws s3 cp $shaJsonFile "s3://$awsBucket/github_backups/github_backup.json" --storage-class STANDARD --acl private

# Clean up local backup files
Write-Host "Cleaning up local backup files..."
Remove-Item -Recurse -Force $backupDir
Remove-Item -Force $shaJsonFile
Remove-Item -Path ./github_backups

Write-Host "All backups completed and uploaded to S3."

Stop-Transcript
