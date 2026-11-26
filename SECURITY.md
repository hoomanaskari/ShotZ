# Security

## Supported versions

Only the latest release of ShotZ gets security fixes. ShotZ updates itself, so staying on the latest version is the default.

## Reporting a vulnerability

Please report security problems privately, not in a public issue: use **Report a vulnerability** on this repository's [Security tab](https://github.com/hoomanaskari/ShotZ/security/advisories/new). Include the ShotZ and macOS versions, what you found and how to reproduce it.

You'll get a reply within a week. Once a fix is released, we'll credit you in the release notes unless you'd rather we didn't.

## Scope

ShotZ has no accounts and no server of its own. Its only network access is the update check against this repository's releases. Captures stay in `~/Library/Application Support/Shotz/` until you export them. Problems in those areas, in how updates are verified, or anything that exposes captures to other apps or users are in scope.
