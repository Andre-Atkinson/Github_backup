# 🕐 GitHub Backup & Restore with AWS S3

This project automates the **backup** of all your GitHub repositories to **AWS S3** and allows you to **restore** them when needed.

👉 **Features:**

- Automatically **fetches all GitHub repositories** and **creates ZIP backups**.
- Stores backups in **AWS S3** for safe, long-term storage.
- Restores a repository from **any backup date** by **force-pushing to GitHub**.
- Uses **`.env` file** for credentials (GitHub & AWS) to keep things secure.

---

## 🚀 **Setup Instructions**

### 1️⃣ Install Required Dependencies

Make sure you have the AWS CLI and Git installed. Then, run:

```bash
aws configure
```

### 2️⃣ Set Up Environment Variables

Create a `.env` file in the root directory and add the following:

```ini
# GitHub Credentials
GITHUB_USERNAME=your-github-username
GITHUB_TOKEN=your-github-token  # Create a personal access token with repo read/write permissions

# AWS S3 Credentials
AWS_ACCESS_KEY_ID=your-aws-access-key
AWS_SECRET_ACCESS_KEY=your-aws-secret-key
AWS_REGION=your-region

# S3 Bucket Settings
S3_BUCKET=github-backups-homelabpro
BACKUP_DIR=github_backups  # Folder inside the S3 bucket
```

🚨 **Important:** Keep this `.env` file private. Never commit it to GitHub.

---

## 📄 **Backup Script (`github_backup.ps1`)**

This script:

1. Fetches all repositories from your GitHub account.
2. Clones each repo as a bare repository.
3. Compresses the cloned repo into a ZIP file.
4. Uploads the ZIP file to your **AWS S3 bucket**.
5. Deletes the local ZIP after upload (so no local storage is used).

### 💡 Run the Backup Script

```powershell
./github_backup.ps1
```

### 📂 S3 Folder Structure

```
s3://github-backups-homelabpro/github_backups/YYYY-MM-DD/repo_name_YYYY-MM-DD_HH-mm-ss.zip
```

For example:

```
s3://github-backups-homelabpro/github_backups/2025-02-18/awesome-repo_2025-02-18_10-00-00.zip
```

---

## 🔄 **Restore Script (`github_restore.ps1`)**

This script:

1. Prompts the user for a **repo name**.
2. Downloads the latest backup ZIP file from S3.
3. Extracts the repo, deletes current GitHub content, and restores from the backup.
4. **Force-pushes** the restored content to GitHub.

### 💡 Run the Restore Script

```powershell
./github_restore.ps1
```

### 📏 Example Input

```
Enter the name of the repository to restore: awesome-repo
```

### 🔍 What Happens?

- The script **downloads** the ZIP from S3.
- It **extracts and overwrites** the main branch with the backup.
- A **force push** updates GitHub with a commit message:

  ```
  🔄 Restore from S3 backup by Your Name on 2025-02-19 10:00:00
  ```

---

## 🔥 **Automating Backups with a Scheduled Task**

You can schedule the **backup script** to run automatically every day using Task Scheduler (Windows):

1. Open Task Scheduler and create a new task.
2. Set the trigger to run daily at your preferred time.
3. Set the action to start a program and point it to `powershell.exe` with the argument `-File "C:\path\to\github_backup.ps1"`.

For Linux/macOS, use `cron`.

---

## 🔎 **Troubleshooting**

- **GitHub API Errors** → Ensure your `GITHUB_TOKEN` has `repo` access.
- **S3 Upload Errors** → Check if your AWS credentials are correct.
- **Restore Not Working?** → Ensure the backup exists in S3 and the repo name matches.

---

## ✨ **Future Improvements**

- Improve **error handling** for failed S3 uploads.
- Implement **incremental backups** instead of full backups.

---

## 🤝 **Contributing**

Feel free to fork this repo and submit pull requests! 🛠️  

---

## 🐟 **License**

This project is licensed under the **MIT License**.

---
