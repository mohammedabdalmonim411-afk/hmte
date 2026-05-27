# GitHub Repository Rename Guide

This document explains how to rename the GitHub repository from `mavis-team-engine` to `hmte` (or keep the current name).

## Option 1: Rename Repository on GitHub (Recommended)

### Steps to Rename

1. **Go to Repository Settings**
   - Navigate to: `https://github.com/YOUR_USERNAME/mavis-team-engine`
   - Click on **Settings** tab
   - Scroll down to the **Repository name** section

2. **Change Repository Name**
   - Current name: `mavis-team-engine`
   - New name: `hmte` (or `hermes-mavis-team-engine`)
   - Click **Rename**

3. **Update Local Repository**
   ```bash
   # GitHub automatically redirects, but update your remote URL
   cd /path/to/mavis-team-engine
   
   # Check current remote
   git remote -v
   
   # Update remote URL (if needed)
   git remote set-url origin https://github.com/YOUR_USERNAME/hmte.git
   
   # Or for SSH
   git remote set-url origin git@github.com:YOUR_USERNAME/hmte.git
   ```

4. **Update Documentation References**
   - Update any external documentation that references the old URL
   - GitHub will redirect old URLs automatically, but it's best to update

### What GitHub Handles Automatically

- ✅ All existing issues, PRs, and commits remain intact
- ✅ Old repository URL redirects to new URL
- ✅ Stars, watchers, and forks are preserved
- ✅ Clone URLs are automatically updated

### What You Need to Update Manually

- ❌ Local git remotes (see step 3 above)
- ❌ CI/CD configurations that use the repository URL
- ❌ External documentation or links
- ❌ Package manager references (if applicable)

## Option 2: Keep Current Repository Name

If you prefer to keep the repository name as `mavis-team-engine`:

### Pros
- No need to update external links
- GitHub redirects work indefinitely
- Simpler migration path

### Cons
- Repository name doesn't match project name (HMTE)
- May cause confusion for new users

### If Keeping Current Name

The project code and documentation already use "HMTE" internally. The repository name is just a URL identifier and doesn't affect functionality.

You can add a note in the README:

```markdown
> **Note**: This repository is named `mavis-team-engine` for historical reasons. 
> The project is now called **HMTE (Hermes Mavis Team Engine)**.
```

## Recommended Approach

**We recommend Option 1** (renaming to `hmte`) because:

1. **Consistency**: Repository name matches project name
2. **Clarity**: New users won't be confused by the old name
3. **Branding**: Establishes HMTE as the official name
4. **SEO**: Better search engine optimization with consistent naming

The redirect feature means old links will continue to work, minimizing disruption.

## Timeline

- **Immediate**: All code and documentation already use "HMTE"
- **After GitHub rename**: Update local git remotes (5 minutes)
- **Within 1 week**: Update any external documentation
- **Ongoing**: GitHub handles redirects automatically

## Questions?

If you encounter issues during the rename:

1. Check GitHub's official documentation: https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository
2. Verify your local remote: `git remote -v`
3. Test the new URL: `git fetch origin`

---

**Status**: Ready to rename ✅  
**Risk Level**: Low (GitHub handles most of the work)  
**Estimated Time**: 10 minutes
