# Branch name and commit message conventions

## Language

Commit messages and PRs follow the language of the repository's existing commits and PRs. If there are none, use the user's language.

## Branch name

`<type>/<issue number>-<summary>`. Keep the summary short, in lowercase ASCII letters and hyphens.

Examples:

```
feat/123-user-login
fix/456-null-pointer
```

## Types

| type | Use |
|---|---|
| feat | New feature |
| fix | Bug fix |
| docs | Documentation only |
| style | Formatting that does not affect behavior (whitespace, semicolons, etc.) |
| refactor | Code improvement without a new feature or bug fix |
| perf | Performance improvement |
| test | Adding or fixing tests |
| build / ci | Build or CI configuration |
| chore | Other maintenance (dependency updates, etc.) |
| revert | Reverting a commit |

Another word may be used if it fits better.

## Commit message

```
<type>(<scope>): <subject>

<body>

<footer>
```

- The scope is optional.
- Keep the subject to about 50 characters, without a trailing period.
- In English, use the imperative mood ("add", not "added").
- The body explains why rather than what. The diff shows what; the why is lost unless written down.
- The footer names the related issue (`Closes #123`, etc.). Additional commits for review comments may use `Refs #123`.

Example:

```
feat(auth): add two-factor authentication at login

Supports both SMS and TOTP apps.
Existing users can enable it from the settings page.

Closes #123
```

Example of an additional commit for a review comment:

```
fix(auth): stop returning null when the token has expired

A review pointed out that callers may miss the null check,
so it throws an exception instead.

Refs #123
```
