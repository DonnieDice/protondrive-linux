## PR Title Checklist

Your PR title must match: `^[A-Z].{9,}\s\(#\d+\)$`

- [ ] Starts with an uppercase letter
- [ ] At least 10 characters before the PR number
- [ ] Ends with the PR number in parentheses, e.g. `(#42)`

**Correct:** `Add Alpine 3.20 APK build target (#47)`
**Incorrect:** `Add Alpine 3.20 APK build target` (missing PR number)
**Incorrect:** `add alpine 3.20 apk build target (#47)` (lowercase start)

Edit your title after GitHub assigns the PR number.

If the change is tracked by an issue, mention it in the PR body with `Refs #123`
or `Closes #123`. The PR title itself should keep the `(#PR_NUMBER)` suffix so
it stays linkable.

## Summary

<!-- Describe your changes -->

## Testing

<!-- How did you verify this works? -->
