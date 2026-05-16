## PR Title Checklist

Your PR title must match: `^\(#\d+\)\s[A-Z].{9,}$`

- [ ] Starts with the PR number prefix
- [ ] At least 10 characters after the prefix
- [ ] Keeps the PR number prefix first, with the descriptive title after it,
  e.g. `(#42) Title here`

**Correct:** `(#47) Add Alpine 3.20 APK build target`
**Incorrect:** `Add Alpine 3.20 APK build target` (missing PR number)
**Incorrect:** `(#47) add alpine 3.20 apk build target` (lowercase start)

Edit your title after GitHub assigns the PR number. Keep the `(#PR_NUMBER)`
prefix at the front, then append the title text.

If the change is tracked by an issue, mention it in the PR body with `Refs #123`
or `Closes #123`. The PR title itself should keep the `(#PR_NUMBER)` prefix so
it stays linkable.

## Summary

<!-- Describe your changes -->

## Testing

<!-- How did you verify this works? -->
