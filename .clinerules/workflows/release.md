# Release Workflow
When this command is called, perform the following steps:
1. Ask the user what the next version number should be (e.g., 1.1 or 1.4).
2. Update the `MARKETING_VERSION` in the Xcode project settings.
3. Increment the `CURRENT_PROJECT_VERSION` (build number).
4. Run a `git add .` and `git commit -m "chore: bump version to [version]"` via the terminal.
5. Ask the user for permission to `git push`.