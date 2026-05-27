# Push Instructions for HMTE Migration

## Current Status

✅ All migration changes have been committed locally
- Commit: `1ac974a` - "feat: migrate to Hermes and rename to HMTE"
- 22 files changed, 1607 insertions(+), 152 deletions(-)
- Branch: `master`

## Pre-Push Checklist

Before pushing to GitHub, verify:

- [ ] All local changes are committed
- [ ] Commit message is clear and descriptive
- [ ] README.md renders correctly locally
- [ ] All links in documentation are valid
- [ ] Legal disclaimers are in place
- [ ] .gitignore is properly configured

## Step 1: Sync with Remote (Optional)

Your local branch is currently 1 commit behind origin/master. You can either:

**Option A: Merge remote changes first**
```bash
cd /f/AI/mavis-team-engine
git pull --rebase origin master
# Resolve any conflicts if they occur
git push origin master
```

**Option B: Force push (if you want to overwrite remote)**
```bash
cd /f/AI/mavis-team-engine
git push --force origin master
```

⚠️ **Warning**: Force push will overwrite the remote commit. Only use if you're certain the remote commit is not needed.

## Step 2: Push to GitHub

**Standard push:**
```bash
cd /f/AI/mavis-team-engine
git push origin master
```

**If this is the first push or remote tracking is not set:**
```bash
cd /f/AI/mavis-team-engine
git push -u origin master
```

## Step 3: Rename Repository on GitHub

After pushing, rename the repository on GitHub:

1. Go to: https://github.com/mohammedabdalmonim411-afk/mavis-team-engine
2. Click **Settings** (top right)
3. In the **General** section, find **Repository name**
4. Change from: `mavis-team-engine`
5. Change to: `hmte` or `hermes-mavis-team-engine`
6. Click **Rename**

⚠️ **Important**: GitHub will automatically set up redirects from the old URL to the new one, but update any local references.

## Step 4: Update Local Remote URL (After Rename)

After renaming on GitHub, update your local repository:

```bash
cd /f/AI/mavis-team-engine
git remote set-url origin https://github.com/mohammedabdalmonim411-afk/hmte.git
# Or if you chose the longer name:
# git remote set-url origin https://github.com/mohammedabdalmonim411-afk/hermes-mavis-team-engine.git
```

Verify the change:
```bash
git remote -v
```

## Step 5: Verify on GitHub

After pushing and renaming:

1. Visit the new repository URL
2. Check that README.md renders correctly
3. Verify all badges display properly
4. Test navigation links in documentation
5. Confirm PLATFORM_HISTORY.md is visible
6. Check that install-to-hermes.sh is accessible

## Recommended Repository Name

**Recommended**: `hmte`
- Short and memorable
- Matches the new project branding
- Easy to type and reference

**Alternative**: `hermes-mavis-team-engine`
- More descriptive
- Better for search/discovery
- Clearer about platform and purpose

## Post-Push Actions

After successful push and rename:

1. Update any external references to the old repository name
2. Update bookmarks and documentation links
3. Notify collaborators of the name change
4. Consider creating a GitHub release for this migration milestone
5. Update any CI/CD configurations with new repository name

## Troubleshooting

**If push is rejected due to remote changes:**
```bash
git pull --rebase origin master
# Resolve conflicts if any
git push origin master
```

**If you need to undo the local commit:**
```bash
git reset --soft HEAD~1  # Keeps changes staged
# or
git reset --hard HEAD~1  # Discards changes (dangerous!)
```

**If remote tracking is not set:**
```bash
git branch --set-upstream-to=origin/master master
```

## Migration Documentation

All migration details are documented in:
- `PLATFORM_HISTORY.md` - Complete migration history
- `GITHUB_RENAME.md` - Repository renaming guide
- `LEGAL_REVIEW.md` - Legal compliance measures
- `.phase_control/phases_hermes_migration.yaml` - Phase definitions

## Questions?

If you encounter issues:
1. Check git status: `git status`
2. Check remote configuration: `git remote -v`
3. Check commit history: `git log --oneline -5`
4. Review the migration documentation listed above
