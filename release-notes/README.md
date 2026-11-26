# Release notes

One Markdown file per version, named after `CFBundleShortVersionString`: `release-notes/<version>.md`.

`scripts/release.sh` requires it, embeds it in the appcast (Sparkle shows it in the update window)
and the go-live steps use it as the GitHub release description. Write for people using ShotZ:
what's new and what's fixed, in plain language. No internal details.
