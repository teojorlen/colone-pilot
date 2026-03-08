# GitHub Integration with Continue

This guide shows how to use the GitHub issue integration with Continue.

---

## 🚀 Quick Start

The Continue extension now has a **GitHub Issue context provider** that lets you fetch and analyze GitHub issues.

### Usage

1. **Open Continue** in VS Code (press `Ctrl+L`)

2. **Type:** `@github-issue` 

3. **Enter:** `owner/repo#issuenumber`
   - Example: `facebook/react#28000`
   - Example: `microsoft/vscode#12345`

4. **Press Enter** - The issue details are fetched and added to context

5. **Ask questions** like:
   - "Suggest a detailed plan to fix this issue"
   - "What files would need to be modified?"
   - "Write a step-by-step implementation guide"
   - "What are the potential edge cases?"

---

## 📝 Example Session

```
User: @github-issue facebook/react#28000

[Issue details are fetched and displayed]

User: Analyze this issue and provide:
1. Root cause analysis
2. Step-by-step fix plan
3. Files that need modification
4. Testing strategy
5. Potential risks

[Mistral analyzes the issue and provides comprehensive plan]
```

---

## 🔑 GitHub Token (Optional)

**Why set a token?**
- Access private repositories
- Higher API rate limits (5000/hour vs 60/hour)
- Access to more issue details

### Get a GitHub Token

1. Go to: https://github.com/settings/tokens
2. Click **"Generate new token (classic)"**
3. Give it a name: `Continue Extension`
4. Select scopes:
   - ✅ `repo` (for private repos)
   - ✅ `public_repo` (for public repos only)
5. Click **"Generate token"**
6. **Copy the token** (you won't see it again!)

### Set the Token (Windows)

**Option A: Environment Variable (Persistent)**

```powershell
# Run in PowerShell
[System.Environment]::SetEnvironmentVariable('GITHUB_TOKEN', 'ghp_your_token_here', 'User')
```

**Restart VS Code** for the change to take effect.

**Option B: User Profile (Session-based)**

Add to `$PROFILE` (`notepad $PROFILE`):
```powershell
$env:GITHUB_TOKEN = "ghp_your_token_here"
```

**Option C: VS Code Settings**

Add to `.vscode/settings.json`:
```json
{
  "terminal.integrated.env.windows": {
    "GITHUB_TOKEN": "ghp_your_token_here"
  }
}
```

⚠️ **Security Note:** Don't commit tokens to git! Add to `.gitignore`.

---

## 💡 Use Cases

### 1. Bug Fix Planning

```
@github-issue owner/repo#123
Create a detailed bug fix plan including reproduction steps and test cases.
```

### 2. Feature Implementation

```
@github-issue owner/repo#456
Suggest an implementation approach and identify affected components.
```

### 3. Code Review Prep

```
@github-issue owner/repo#789
What should I focus on when reviewing code for this issue?
```

### 4. Testing Strategy

```
@github-issue owner/repo#101
Create a comprehensive testing plan for this issue.
```

### 5. Impact Analysis

```
@github-issue owner/repo#202
Analyze the potential impact of this issue on the codebase.
```

---

## 🔧 Advanced: Fetch Multiple Issues

You can reference multiple issues in one conversation:

```
@github-issue facebook/react#28000
[Issue 1 loaded]

@github-issue facebook/react#28001
[Issue 2 loaded]

Compare these two issues and suggest which should be prioritized.
```

---

## 🐛 Troubleshooting

| Problem | Solution |
|---------|----------|
| "Invalid format" error | Use format: `owner/repo#123` (no spaces) |
| "GitHub API error: 404" | Issue doesn't exist or repo is private (set token) |
| "Rate limit exceeded" | Set GITHUB_TOKEN for higher limits |
| Token not working | Restart VS Code after setting environment variable |
| "Failed to fetch" | Check internet connection or GitHub status |

---

## 📖 What Information is Fetched?

The context provider fetches:
- ✅ Issue title and description
- ✅ Status (open/closed)
- ✅ Author and assignees
- ✅ Labels and milestones
- ✅ Creation/update timestamps
- ✅ Comment count
- ✅ Direct link to GitHub

**Note:** Issue comments are NOT fetched to keep context size manageable. You can manually copy important comments into the chat if needed.

---

## 🔐 Security

- Tokens are stored in environment variables (not in config files)
- Requests go directly from your machine to GitHub (not through any proxy)
- Your local Mistral model processes the data (nothing sent to cloud)
- **100% private** - only you and GitHub see the issue data

---

## 🚀 Future Enhancements

Possible additions (not yet implemented):
- Fetch pull request details
- Fetch issue comments
- Search issues by keywords
- List repository issues
- Create issues from Continue

---

## 📚 Learn More

- **Continue Context Providers:** https://docs.continue.dev/features/context-providers
- **GitHub API:** https://docs.github.com/en/rest/issues
- **Continue Config:** https://docs.continue.dev/reference/config

---

## 🤝 Contributing

Found a bug or want to add features? The context provider is in:
```
C:\Users\tjorl\.continue\config.ts
```

Feel free to modify and extend it!
