# Publish to GitHub

This project can be published with Git only. GitHub CLI is optional.

## 1. Create a GitHub repository

1. Sign in to GitHub in your browser.
2. Open https://github.com/new
3. Repository name suggestion: `edge-killer`
4. Choose Public or Private.
5. Do not initialize with README, .gitignore, or license because this local
   project already has files.
6. Click "Create repository".

GitHub will show a repository URL such as:

```text
https://github.com/<your-user-name>/edge-killer.git
```

## 2. Initialize the local repository

Run these commands from `F:\edge-killer`:

```powershell
git init
git branch -M main
git add .
git commit -m "Initial Edge Killer MVP and WPF wrapper"
```

## 3. Connect to GitHub

Replace the URL with your actual repository URL:

```powershell
git remote add origin https://github.com/<your-user-name>/edge-killer.git
git push -u origin main
```

When Git asks you to authenticate, use the browser/device flow or a GitHub
personal access token if prompted. GitHub no longer accepts account passwords
for HTTPS Git pushes.

## 4. Release the executable

The repository intentionally ignores packaged `.exe` files. Source code belongs
in Git; release binaries should be uploaded as GitHub Releases assets.

After pushing the code:

1. Open the repository on GitHub.
2. Click "Releases".
3. Click "Draft a new release".
4. Tag suggestion: `v0.1.0`
5. Title suggestion: `Edge Killer v0.1.0`
6. Upload:

```text
windows-wrapper\EdgeKiller.UI\publish-single\EdgeKiller.exe
```

7. Publish the release.

## 5. Future updates

```powershell
git status
git add .
git commit -m "Describe the change"
git push
```
