---
name: release
description: Use when the user wants to release, publish or ship a new version of Rackmate ("udělej release", "vydej novou verzi", "make a release"), or to build the signed and notarized DMG for distribution.
---

# Releasing Rackmate

A release is: version bump → tests → signed + notarized DMG + appcast →
merge + tag → GitHub Release → website → live checks. Every step
below has a check; a step is not done until its check passed.

**Pushing needs the user's explicit OK** (global rule). Before step 5 ask
one bold question that names all three pushes of this release (tag, GitHub
Release, `main`) and, on the first release, turning on Pages, unless the user
has already said yes to exactly that in the conversation.

## First publish (one time)

Skip this when `git remote get-url origin` already says
`https://github.com/jiripisa/rackmate.git`.

Otherwise `origin` still points at the old repository, and nothing of Rackmate
may go there. Before step 1, ask one bold question that names creating the
public repository, then:

1. `gh repo create jiripisa/rackmate --public --description "Your plugins as instruments in the studio."`
2. `git remote set-url origin https://github.com/jiripisa/rackmate.git`

Check: `git remote -v` shows the new URL for fetch and push, and
`gh repo view jiripisa/rackmate --json visibility,description` shows `PUBLIC`
and the description.

Push nothing here. `main`'s history reaches the new repository only through
step 5, in its order: the tag, the GitHub Release, then `main`. Pages goes on
after `main` is pushed, in the last item of step 5.

## 1. Prepare

1. `git status` clean, on `main`, up to date. On the first release the new
   repository is empty, so there is nothing to compare with. Create the branch
   `release/vX.Y.Z`.
2. Pick the version. The **first release of this repo is 0.2.0** (the version
   the website links already point at). After that: patch for fixes and small
   additions, minor for new features or removed UI, major only when the user
   says so. Say which and why.
3. `CHANGELOG.md`: rename `## Unreleased` to `## X.Y.Z — YYYY-MM-DD`. If there
   is no Unreleased section, write the entries from `git log` since the last tag
   first. These lines become the GitHub Release notes and the text of the update
   dialog.
4. Bump `CFBundleShortVersionString` **and** `CFBundleVersion` in
   `Resources/Info.plist`.
5. Replace the old version in the website: `grep -rn "<old version>" docs/*.html docs/cs/*.html`
   (download links `releases/download/v…/Rackmate-….dmg` and version texts).
   On the first release the pages already say 0.2.0, and the lines about
   Pluginarium 0.1.0 stay as they are.

Check: `swift test` green (redirect the output to a file, read the summary line).

## 2. Build the DMG

`./build.sh dist` — takes several minutes (two notarizations); run it in the
background and wait for it to finish.

Check, all of them:
- the log shows `status: Accepted` twice and ends with `Done!`;
- `spctl -a -vv build/release/Rackmate.app` says `source=Notarized Developer ID`;
- read `docs/appcast.xml`, because on the first release the file is new and
  `git diff` shows nothing: `grep -E "sparkle:version|enclosure" docs/appcast.xml`
  shows the new version, the new download URL and a new `sparkle:edSignature`.

A `403 … agreement is missing or has expired` from notarytool means the user
must accept the new Apple agreement at developer.apple.com/account — stop and
tell them.

## 3. Screenshot (when the UI changed)

Open `build/release/Rackmate.app`, capture only its window
(`screencapture -x -o -l <window id>`; the window id from
`CGWindowListCopyWindowInfo`), look at the image, then copy it to
`docs/assets/rackmate-window.png`. Never capture the whole screen or other
apps' windows. Quit the app afterwards.

## 4. Commit, merge, tag

1. `git status`, then commit (never with AI attribution trailers):
   `chore(release): vX.Y.Z — version bump, CHANGELOG, appcast, website`.
   On the first release `docs/appcast.xml` is untracked, so stage it by name.
2. `git switch main && git merge --no-ff <branch> -m "chore: merge … — vX.Y.Z release"`,
   delete the branch, `git tag vX.Y.Z` (lightweight).

## 5. Publish (order matters)

1. `git push origin vX.Y.Z`
2. Copy `build/Rackmate.dmg` to a scratch folder as `Rackmate-X.Y.Z.dmg` and run
   `gh release create vX.Y.Z <that file> --title "Rackmate X.Y.Z" --notes-file <CHANGELOG section>`.
3. Check: `curl -sIL -o /dev/null -w "%{http_code}" https://github.com/jiripisa/rackmate/releases/download/vX.Y.Z/Rackmate-X.Y.Z.dmg` → `200`.
4. Only now `git push origin main` (it carries the appcast; the DMG must
   already exist).
5. On the first release only, turn on Pages:
   `gh api -X POST repos/jiripisa/rackmate/pages -f "source[branch]=main" -f "source[path]=/docs"`.

## 6. Live checks

1. Wait for the Pages deploy: `gh run list --limit 1`, then `gh run watch <id> --exit-status`.
   After turning on Pages the first run can take a moment to appear.
2. `curl -s "https://jiripisa.github.io/rackmate/?x=$RANDOM" | grep -o "X.Y.Z"` shows the new version;
   the same for `https://jiripisa.github.io/rackmate/cs/`.
3. Download the DMG from the release URL and the live appcast
   (`https://jiripisa.github.io/rackmate/appcast.xml`), then
   `.build/artifacts/sparkle/Sparkle/bin/sign_update --verify <dmg> <edSignature from the live appcast>`
   must print nothing and exit 0 — the feed's signature matches the published bytes.

## Report

Tell the user: the release URL, what was pushed, the results of every check,
the version choice and why, and how the update check went.

**Update check, later releases:** ask the user to confirm that an installed
older version offers the update.

**Update check, first release:** no older Rackmate is installed anywhere, so
the check is a fake older copy against the live feed. Run it yourself, with
`<scratch>` a new folder outside the repository:

1. Copy the release app and make a scratch home:
   `mkdir -p <scratch>/home && cp -R build/release/Rackmate.app <scratch>/`
2. Set both version keys lower in the copy, for example to 0.1.9:
   `/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.1.9" -c "Set :CFBundleVersion 0.1.9" <scratch>/Rackmate.app/Contents/Info.plist`
3. Re-sign the copy ad hoc, inside out, as `build.sh` does:
   ```
   F=<scratch>/Rackmate.app/Contents/Frameworks/Sparkle.framework
   codesign --force --sign - "$F/Versions/B/Autoupdate"
   codesign --force --sign - "$F/Versions/B/Updater.app"
   codesign --force --sign - "$F"
   codesign --force --sign - --entitlements Resources/Rackmate.entitlements <scratch>/Rackmate.app
   ```
4. Run it from the shell, in the scratch home. Never with `open`, and never
   with the real home:
   `CFFIXED_USER_HOME=<scratch>/home HOME=<scratch>/home <scratch>/Rackmate.app/Contents/MacOS/Rackmate`
5. Choose Rackmate > Check for Updates…. The dialog offers X.Y.Z with its
   release notes. Choose Install Update.
6. Sparkle puts the new version in place and relaunches it. That launch may not
   carry the scratch home, so touch nothing in it and quit it right away; the
   Start screen opens no audio device.
7. Confirm that the notarized version replaced the copy:
   `/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" <scratch>/Rackmate.app/Contents/Info.plist`
   says X.Y.Z, and `spctl -a -vv <scratch>/Rackmate.app` says
   `source=Notarized Developer ID`.
