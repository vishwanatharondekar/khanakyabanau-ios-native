#!/usr/bin/env bash
#
# release.sh — local release pipeline for the Khana Kya Banau iOS app.
#
# Bumps MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml, regenerates
# the Xcode project, archives Release, exports an App Store .ipa, uploads it to
# TestFlight, then commits the version bump, tags it and pushes both to the
# current branch's remote.
#
# With no version flags, CURRENT_PROJECT_VERSION increments by one and
# MARKETING_VERSION gets its patch component bumped (1.0.0 -> 1.0.1).
#
# Usage:
#   ./release.sh                          # bump patch + build, then archive and export
#   ./release.sh --version=1.2.0          # auto-bump build, set marketing version
#   ./release.sh --keep-version           # auto-bump build, reuse marketing version
#   ./release.sh --build=42               # set explicit build number
#   ./release.sh --archive-only           # archive, skip the .ipa export
#   ./release.sh --no-clean               # reuse existing build intermediates
#   ./release.sh --no-build               # bump versions only, don't archive
#   ./release.sh --no-analytics           # allow a build with no Mixpanel token
#   ./release.sh --dry-run                # show what would change, don't write or build
#   ./release.sh --no-upload              # build and export, don't upload
#   ./release.sh --no-git                 # skip the git commit, tag and push
#   ./release.sh --no-tag                 # commit and push, but don't tag
#   ./release.sh --help
#
# For the first submission of 1.0.0, pass --keep-version: a bare run would bump it
# to 1.0.1. App Store Connect only requires the *build* to be unique per version,
# which --keep-version still does.
#
# Assumptions:
#   - Run from the project root (where this script lives, alongside project.yml).
#   - project.yml contains literal `MARKETING_VERSION: "X.Y.Z"` and
#     `CURRENT_PROJECT_VERSION: "N"` lines. This script edits those in place.
#     project.yml is the source of truth: the .xcodeproj is generated and gitignored,
#     so the project is regenerated here rather than trusted.
#   - xcodegen and Xcode's command line tools are on PATH.
#
# Git:
#   The version bump is committed on its own — anything else dirty in the tree is
#   left alone — and that commit is tagged `<version>+<build>`, e.g. `1.0.4+13`.
#
#   The build number is part of the tag because it is part of the identity: App
#   Store Connect calls this build "1.0.4 (13)", and the same marketing version can
#   ship several builds (that is what --keep-version is for), so a bare `1.0.4`
#   would collide on the second one.
#
#   The tag is annotated, and both the branch and the tag are pushed. A tag of that
#   name already existing is a hard error raised *before* anything is built, which
#   also makes --dry-run a tag preflight. --no-tag commits and pushes without
#   tagging; --no-git skips all of it.
#
# Signing:
#   The export needs an Apple Distribution certificate and an App Store provisioning
#   profile for in.khanakyabanau.app in your keychain — a paid Apple Developer
#   Program membership. Signing is automatic; Xcode fetches what it can. An
#   "Apple Development" identity alone is not enough and the export will fail.
#
#   Pass --archive-only to stop at the .xcarchive, which is still openable in
#   Xcode's Organizer and distributable from there.
#
# Analytics:
#   A release with no Mixpanel token ships blind: AnalyticsService silently no-ops.
#   Nothing else fails, so this script refuses to build without one. Supply it in
#   Secrets.xcconfig (see README) or export MIXPANEL_TOKEN. Pass --no-analytics to
#   build anyway.
#
# TestFlight:
#   Every exported .ipa is uploaded to App Store Connect with `xcrun altool`, which
#   is the same path Transporter takes. Credentials come from the environment, in
#   this order:
#
#     1. An API key — ASC_KEY_ID and ASC_ISSUER_ID, with the matching
#        AuthKey_<key-id>.p8 in ~/.appstoreconnect/private_keys (override the
#        directory with ASC_KEY_DIR). Create the key under App Store Connect >
#        Users and Access > Integrations, with the App Manager role.
#     2. An Apple ID — ASC_APPLE_ID and ASC_APP_PASSWORD, where the password is an
#        app-specific password from appleid.apple.com, not your Apple ID password.
#        ASC_APP_PASSWORD also accepts altool's own @keychain:<name> form.
#
#   Prefer the API key: it survives a password change and is scoped to App Store
#   Connect. Credentials are resolved before the archive, so a missing one costs a
#   second rather than a five-minute build, and neither secret is ever printed or
#   passed as a literal argument.
#
#   Pass --no-upload to stop at the .ipa. Note that --archive-only and --no-build
#   have nothing to upload and skip it implicitly.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_YML="$SCRIPT_DIR/project.yml"
SECRETS_XCCONFIG="$SCRIPT_DIR/Secrets.xcconfig"
SCHEME="KhanaKyaBanau"
XCODEPROJ="$SCRIPT_DIR/$SCHEME.xcodeproj"
OUT_DIR="$SCRIPT_DIR/build/release"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# ---- args -------------------------------------------------------------------

NEW_VERSION=""
NEW_BUILD=""
KEEP_VERSION=0
DO_CLEAN=1
DO_BUILD=1
DO_EXPORT=1
REQUIRE_ANALYTICS=1
DRY_RUN=0
DO_GIT=1
DO_TAG=1
DO_UPLOAD=1

print_help() {
  # Everything from line 2 up to the first non-comment line, so growing the header
  # above never desyncs --help from it.
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

for arg in "$@"; do
  case "$arg" in
    --version=*)     NEW_VERSION="${arg#*=}" ;;
    --keep-version)  KEEP_VERSION=1 ;;
    --build=*)       NEW_BUILD="${arg#*=}" ;;
    --archive-only)  DO_EXPORT=0 ;;
    --no-clean)      DO_CLEAN=0 ;;
    --no-build)      DO_BUILD=0 ;;
    --no-analytics)  REQUIRE_ANALYTICS=0 ;;
    --dry-run)       DRY_RUN=1 ;;
    --no-upload)     DO_UPLOAD=0 ;;
    --no-git)        DO_GIT=0 ;;
    --no-tag)        DO_TAG=0 ;;
    -h|--help)       print_help; exit 0 ;;
    *)
      echo "error: unknown argument: $arg" >&2
      echo "run with --help for usage." >&2
      exit 2
      ;;
  esac
done

# ---- preconditions ----------------------------------------------------------

if [[ ! -f "$PROJECT_YML" ]]; then
  echo "error: cannot find $PROJECT_YML" >&2
  exit 1
fi

if [[ $DO_BUILD -eq 1 ]]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen is not on PATH (brew install xcodegen)" >&2
    echo "       project.yml is the source of truth; the .xcodeproj is generated." >&2
    exit 1
  fi
  if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "error: xcodebuild is not on PATH — install Xcode's command line tools" >&2
    exit 1
  fi
fi

# ---- analytics token --------------------------------------------------------
#
# Resolved the same way the build resolves it: Secrets.xcconfig, or an exported
# MIXPANEL_TOKEN. This only reports which source will supply it — the value itself
# is never printed, and never passed on the command line.

ANALYTICS_SOURCE=""
if [[ -f "$SECRETS_XCCONFIG" ]] \
   && grep -qE '^[[:space:]]*MIXPANEL_TOKEN[[:space:]]*=[[:space:]]*[^[:space:]]' "$SECRETS_XCCONFIG"; then
  ANALYTICS_SOURCE="Secrets.xcconfig"
elif [[ -n "${MIXPANEL_TOKEN:-}" ]]; then
  ANALYTICS_SOURCE="MIXPANEL_TOKEN in the environment"
fi

if [[ -z "$ANALYTICS_SOURCE" ]]; then
  if [[ $REQUIRE_ANALYTICS -eq 1 && $DO_BUILD -eq 1 ]]; then
    echo "error: no Mixpanel token found." >&2
    echo "       A release without one ships with analytics silently disabled —" >&2
    echo "       nothing fails, you simply get no data." >&2
    echo "       Put it in Secrets.xcconfig (see README) or export MIXPANEL_TOKEN," >&2
    echo "       or pass --no-analytics to build without it." >&2
    exit 1
  fi
  ANALYTICS_SOURCE="(none — analytics will be disabled)"
fi

# ---- App Store Connect credentials ------------------------------------------
#
# Resolved the same way the analytics token is: report which source will supply it,
# never the value. altool reads the app-specific password out of the environment
# through its own @env: form, so the secret stays out of this process's argv and
# out of `ps` output.
#
# --archive-only and --no-build produce no .ipa, so there is nothing to upload and
# no credential to require.

ASC_KEY_DIR="${ASC_KEY_DIR:-$HOME/.appstoreconnect/private_keys}"
UPLOAD_SOURCE=""
UPLOAD_BLOCKER=""
ALTOOL_AUTH_ARGS=()

if [[ $DO_BUILD -eq 0 ]]; then
  DO_UPLOAD=0
  UPLOAD_SOURCE="(skipped — --no-build)"
elif [[ $DO_EXPORT -eq 0 ]]; then
  DO_UPLOAD=0
  UPLOAD_SOURCE="(skipped — --archive-only leaves no .ipa)"
elif [[ $DO_UPLOAD -eq 0 ]]; then
  UPLOAD_SOURCE="(skipped — --no-upload)"
else
  if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
    ASC_KEY_FILE="$ASC_KEY_DIR/AuthKey_${ASC_KEY_ID}.p8"
    if [[ -f "$ASC_KEY_FILE" ]]; then
      UPLOAD_SOURCE="API key $ASC_KEY_ID"
      ALTOOL_AUTH_ARGS=(--apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID")
    else
      UPLOAD_BLOCKER="ASC_KEY_ID is set but its private key is missing: $ASC_KEY_FILE"
    fi
  elif [[ -n "${ASC_APPLE_ID:-}" && -n "${ASC_APP_PASSWORD:-}" ]]; then
    # altool's indirection forms (@env:VAR, @keychain:NAME) are handed through
    # untouched; a bare value is referenced as @env: so it never reaches argv.
    if [[ "$ASC_APP_PASSWORD" == @* ]]; then
      ALTOOL_PASSWORD_REF="$ASC_APP_PASSWORD"
    else
      ALTOOL_PASSWORD_REF="@env:ASC_APP_PASSWORD"
    fi
    UPLOAD_SOURCE="Apple ID $ASC_APPLE_ID"
    ALTOOL_AUTH_ARGS=(-u "$ASC_APPLE_ID" -p "$ALTOOL_PASSWORD_REF")
  elif [[ -n "${ASC_APPLE_ID:-}" ]]; then
    UPLOAD_BLOCKER="ASC_APPLE_ID is set but ASC_APP_PASSWORD is not"
  elif [[ -n "${ASC_ISSUER_ID:-}" || -n "${ASC_KEY_ID:-}" ]]; then
    UPLOAD_BLOCKER="ASC_KEY_ID and ASC_ISSUER_ID must both be set"
  else
    UPLOAD_BLOCKER="no App Store Connect credentials in the environment"
  fi

  if [[ -z "$UPLOAD_SOURCE" && $DRY_RUN -eq 1 ]]; then
    # A dry run writes nothing and builds nothing, so there is no failure to head
    # off — reporting the gap in the plan makes --dry-run a credential preflight
    # you can run without spending a build number.
    DO_UPLOAD=0
    UPLOAD_SOURCE="(unavailable — $UPLOAD_BLOCKER)"
  fi

  if [[ -z "$UPLOAD_SOURCE" ]]; then
    echo "error: cannot upload to TestFlight — $UPLOAD_BLOCKER." >&2
    echo "       Set either an API key (preferred):" >&2
    echo "         export ASC_KEY_ID=ABC123DEFG ASC_ISSUER_ID=<issuer-uuid>" >&2
    echo "         # with AuthKey_ABC123DEFG.p8 in $ASC_KEY_DIR" >&2
    echo "       or an Apple ID with an app-specific password:" >&2
    echo "         export ASC_APPLE_ID=you@example.com ASC_APP_PASSWORD=abcd-efgh-ijkl-mnop" >&2
    echo "       See the TestFlight section of --help, or pass --no-upload to stop" >&2
    echo "       at the .ipa and upload it yourself." >&2
    exit 1
  fi
fi

# ---- read current versions --------------------------------------------------

# Match lines like:    MARKETING_VERSION: "1.0.0"
CURRENT_VERSION="$(
  grep -E '^[[:space:]]*MARKETING_VERSION[[:space:]]*:[[:space:]]*"[^"]+"' "$PROJECT_YML" \
  | head -n1 \
  | sed -E 's/.*MARKETING_VERSION[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
)"

# Match lines like:    CURRENT_PROJECT_VERSION: "1"
CURRENT_BUILD="$(
  grep -E '^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*:[[:space:]]*"[0-9]+"' "$PROJECT_YML" \
  | head -n1 \
  | sed -E 's/.*CURRENT_PROJECT_VERSION[[:space:]]*:[[:space:]]*"([0-9]+)".*/\1/'
)"

if [[ -z "$CURRENT_VERSION" || -z "$CURRENT_BUILD" ]]; then
  echo "error: failed to parse MARKETING_VERSION/CURRENT_PROJECT_VERSION from $PROJECT_YML" >&2
  echo "       expected literal lines like:" >&2
  echo "         MARKETING_VERSION: \"1.0.0\"" >&2
  echo "         CURRENT_PROJECT_VERSION: \"1\"" >&2
  exit 1
fi

TEAM_ID="$(
  grep -E '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*:' "$PROJECT_YML" \
  | head -n1 \
  | sed -E 's/.*DEVELOPMENT_TEAM[[:space:]]*:[[:space:]]*"?([A-Za-z0-9]+)"?.*/\1/'
)"

if [[ -z "$TEAM_ID" && $DO_EXPORT -eq 1 && $DO_BUILD -eq 1 ]]; then
  echo "error: no DEVELOPMENT_TEAM in $PROJECT_YML — the export cannot be signed" >&2
  exit 1
fi

# ---- compute next versions --------------------------------------------------

if [[ -n "$NEW_BUILD" ]]; then
  if ! [[ "$NEW_BUILD" =~ ^[0-9]+$ ]] || [[ "$NEW_BUILD" -le 0 ]]; then
    echo "error: --build must be a positive integer (got: $NEW_BUILD)" >&2
    exit 2
  fi
  if [[ "$NEW_BUILD" -le "$CURRENT_BUILD" ]]; then
    echo "error: --build=$NEW_BUILD is not greater than current ($CURRENT_BUILD)" >&2
    echo "       App Store Connect rejects a build number it has already seen." >&2
    exit 2
  fi
  NEXT_BUILD="$NEW_BUILD"
else
  NEXT_BUILD="$((CURRENT_BUILD + 1))"
fi

# Bump the patch component: 1.0.0 -> 1.0.1.
#
# Versions shorter than three components are padded first, so 1 -> 1.0.1 and
# 1.2 -> 1.2.1. Anything longer has its final component bumped instead, which
# keeps a trailing build number monotonic rather than silently discarding it.
bump_patch() {
  local version="$1"
  local -a parts
  IFS='.' read -r -a parts <<< "$version"
  while (( ${#parts[@]} < 3 )); do
    parts+=("0")
  done
  local last=$(( ${#parts[@]} - 1 ))
  parts[$last]=$(( parts[last] + 1 ))
  local IFS='.'
  echo "${parts[*]}"
}

if [[ -n "$NEW_VERSION" ]]; then
  if [[ $KEEP_VERSION -eq 1 ]]; then
    echo "error: --version and --keep-version are mutually exclusive" >&2
    exit 2
  fi
  # App Store marketing versions are up to three dot-separated integers. Anything
  # else is rejected at upload, long after this script has finished.
  if ! [[ "$NEW_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "error: --version must look like 1, 1.2 or 1.2.3 (got: $NEW_VERSION)" >&2
    echo "       App Store Connect does not accept pre-release suffixes here." >&2
    exit 2
  fi
  NEXT_VERSION="$NEW_VERSION"
elif [[ $KEEP_VERSION -eq 1 ]]; then
  NEXT_VERSION="$CURRENT_VERSION"
else
  if ! [[ "$CURRENT_VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "error: cannot bump version '$CURRENT_VERSION' automatically — it is not purely numeric." >&2
    echo "       Pass --version=... explicitly, or --keep-version to reuse it." >&2
    exit 2
  fi
  NEXT_VERSION="$(bump_patch "$CURRENT_VERSION")"
fi

ARCHIVE_PATH="$OUT_DIR/$SCHEME-$NEXT_VERSION-$NEXT_BUILD.xcarchive"
EXPORT_PATH="$OUT_DIR/$SCHEME-$NEXT_VERSION-$NEXT_BUILD"
IPA_PATH="$EXPORT_PATH/$SCHEME.ipa"

# ---- release tag ------------------------------------------------------------
#
# Resolved and checked here, before the plan is printed, so a name clash costs a
# second rather than a five-minute archive — the same reason the App Store Connect
# credential is resolved this early.

TAG="${NEXT_VERSION}+${NEXT_BUILD}"

if [[ $DO_GIT -eq 1 && $DO_TAG -eq 1 ]] \
   && git -C "$SCRIPT_DIR" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "error: tag $TAG already exists, on $(git -C "$SCRIPT_DIR" rev-parse --short "refs/tags/$TAG")." >&2
  echo "       Build numbers are spent on upload, so rerun with" >&2
  echo "       --build=$((NEXT_BUILD + 1)) rather than reusing this one, or pass" >&2
  echo "       --no-tag to release without tagging. Moving a tag that has already" >&2
  echo "       been pushed changes what everyone else has fetched." >&2
  exit 2
fi

# ---- print plan -------------------------------------------------------------

echo "=== release plan ==="
echo "  file:        $PROJECT_YML"
echo "  version:     $CURRENT_VERSION -> $NEXT_VERSION"
echo "  build:       $CURRENT_BUILD -> $NEXT_BUILD"
echo "  analytics:   $ANALYTICS_SOURCE"
if [[ $DO_BUILD -eq 1 ]]; then
  echo "  team:        $TEAM_ID (automatic signing)"
  echo "  archive:     $ARCHIVE_PATH"
  if [[ $DO_EXPORT -eq 1 ]]; then
    echo "  ipa:         $IPA_PATH"
  else
    echo "  ipa:         (skipped — --archive-only)"
  fi
  [[ $DO_CLEAN -eq 0 ]] && echo "  clean:       (skipped — --no-clean)"
else
  echo "  build:       (skipped — --no-build)"
fi
echo "  testflight:  $UPLOAD_SOURCE"
if [[ $DO_GIT -eq 1 ]]; then
  if [[ $DO_TAG -eq 1 ]]; then
    echo "  git:         commit version bump, tag $TAG, push both"
  else
    echo "  git:         commit version bump and push (untagged — --no-tag)"
  fi
else
  echo "  git:         (skipped — --no-git)"
fi
echo "===================="

if [[ $DRY_RUN -eq 1 ]]; then
  echo "dry-run: no files written, no build run."
  exit 0
fi

# ---- git commit + tag + push ------------------------------------------------
#
# Commits only the version bump in project.yml (other staged or dirty files are
# left untouched), tags that commit, and pushes the branch and the tag.

git_commit_tag_and_push() {
  if [[ $DO_GIT -eq 0 ]]; then
    echo "skipped git commit, tag and push (--no-git)."
    return 0
  fi

  if git -C "$SCRIPT_DIR" diff --quiet HEAD -- "$PROJECT_YML"; then
    echo "git: no changes to commit in project.yml."
  else
    git -C "$SCRIPT_DIR" commit \
      -m "chore: release ${NEXT_VERSION} (build ${NEXT_BUILD})" \
      -- "$PROJECT_YML"
  fi

  # Annotated rather than lightweight: it carries who cut the release and when,
  # and `git tag -n` then reads as a release list. Tagged after the commit, so it
  # lands on the commit that carries the bump.
  if [[ $DO_TAG -eq 1 ]]; then
    git -C "$SCRIPT_DIR" tag -a "$TAG" \
      -m "Khana Kya Banau iOS ${NEXT_VERSION} (build ${NEXT_BUILD})"
    echo "git: tagged $TAG."
  fi

  local branch
  branch="$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD)"
  if git -C "$SCRIPT_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    git -C "$SCRIPT_DIR" push
  else
    git -C "$SCRIPT_DIR" push -u origin "$branch"
  fi
  echo "git: pushed $branch."

  # Pushed by its full refspec, not with --follow-tags, which would also carry
  # along every other annotated tag reachable from this branch.
  if [[ $DO_TAG -eq 1 ]]; then
    if git -C "$SCRIPT_DIR" push origin "refs/tags/$TAG"; then
      echo "git: pushed tag $TAG."
    else
      echo "" >&2
      echo "error: the tag push failed. $TAG exists locally and the branch is already" >&2
      echo "       pushed, so the release itself is intact — only the tag is missing" >&2
      echo "       on origin. The usual cause is a tag of that name pushed from" >&2
      echo "       another machine. Compare the two before forcing anything:" >&2
      echo "         git ls-remote --tags origin refs/tags/$TAG" >&2
      echo "         git rev-parse $TAG" >&2
      return 1
    fi
  fi
}

# ---- write versions atomically ---------------------------------------------

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

awk -v newVersion="$NEXT_VERSION" -v newBuild="$NEXT_BUILD" '
  BEGIN { versionDone = 0; buildDone = 0 }
  {
    if (!versionDone && match($0, /^([[:space:]]*)MARKETING_VERSION[[:space:]]*:[[:space:]]*"[^"]+"/)) {
      indent = $0; sub(/MARKETING_VERSION.*/, "", indent)
      print indent "MARKETING_VERSION: \"" newVersion "\""
      versionDone = 1
      next
    }
    if (!buildDone && match($0, /^([[:space:]]*)CURRENT_PROJECT_VERSION[[:space:]]*:[[:space:]]*"[0-9]+"/)) {
      indent = $0; sub(/CURRENT_PROJECT_VERSION.*/, "", indent)
      print indent "CURRENT_PROJECT_VERSION: \"" newBuild "\""
      buildDone = 1
      next
    }
    print
  }
' "$PROJECT_YML" > "$TMP_FILE"

# Sanity-check that both lines were rewritten before replacing the original.
if ! grep -qE "^[[:space:]]*MARKETING_VERSION[[:space:]]*:[[:space:]]*\"${NEXT_VERSION//./\\.}\"" "$TMP_FILE"; then
  echo "error: MARKETING_VERSION rewrite failed; aborting without modifying $PROJECT_YML" >&2
  exit 1
fi
if ! grep -qE "^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*:[[:space:]]*\"${NEXT_BUILD}\"" "$TMP_FILE"; then
  echo "error: CURRENT_PROJECT_VERSION rewrite failed; aborting without modifying $PROJECT_YML" >&2
  exit 1
fi

mv "$TMP_FILE" "$PROJECT_YML"
trap - EXIT

echo "updated: $PROJECT_YML"

# ---- build ------------------------------------------------------------------

if [[ $DO_BUILD -eq 0 ]]; then
  echo "skipped build (--no-build). version bump written to project.yml."
  git_commit_tag_and_push
  exit 0
fi

# Not optional, unlike install-to-iphone.sh: the .xcodeproj is generated and
# gitignored, so skipping this would archive the previous version's project.
echo "==> xcodegen generate"
( cd "$SCRIPT_DIR" && xcodegen generate >/dev/null )

mkdir -p "$OUT_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

ARCHIVE_ARGS=(
  archive
  -project "$XCODEPROJ"
  -scheme "$SCHEME"
  -configuration Release
  -destination 'generic/platform=iOS'
  -archivePath "$ARCHIVE_PATH"
)
[[ $DO_CLEAN -eq 1 ]] && ARCHIVE_ARGS=(clean "${ARCHIVE_ARGS[@]}")

echo "==> xcodebuild archive"
( cd "$SCRIPT_DIR" && xcodebuild "${ARCHIVE_ARGS[@]}" )

if [[ ! -d "$ARCHIVE_PATH" ]]; then
  echo "error: xcodebuild reported success but $ARCHIVE_PATH is missing" >&2
  exit 1
fi

# ---- export -----------------------------------------------------------------

if [[ $DO_EXPORT -eq 1 ]]; then
  EXPORT_OPTIONS="$OUT_DIR/ExportOptions.plist"
  cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>uploadSymbols</key>
	<true/>
	<key>destination</key>
	<string>export</string>
</dict>
</plist>
PLIST

  echo "==> xcodebuild -exportArchive"
  if ! ( cd "$SCRIPT_DIR" && xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportOptionsPlist "$EXPORT_OPTIONS" \
        -exportPath "$EXPORT_PATH" ); then
    echo "" >&2
    echo "error: the export failed. The archive itself is fine and is still at:" >&2
    echo "         $ARCHIVE_PATH" >&2
    echo "" >&2
    echo "       The usual cause is signing: an App Store export needs an Apple" >&2
    echo "       Distribution certificate and a matching provisioning profile for" >&2
    echo "       in.khanakyabanau.app. Check what you have with:" >&2
    echo "         security find-identity -v -p codesigning" >&2
    echo "       An \"Apple Development\" identity alone is not enough." >&2
    echo "" >&2
    echo "       You can also distribute the archive above from Xcode's Organizer," >&2
    echo "       which will create the certificate for you." >&2
    exit 1
  fi
fi

# ---- upload to TestFlight ---------------------------------------------------
#
# The one irreversible step in this script. A build number is spent the moment the
# upload is accepted, whether or not the build is ever released — which is why the
# failure path below points at --build= rather than suggesting a retry.
#
# Upload finishing is not the build being testable: App Store Connect then runs its
# own processing, usually a few minutes, before TestFlight shows it to testers.

if [[ $DO_UPLOAD -eq 1 ]]; then
  if [[ ! -f "$IPA_PATH" ]]; then
    echo "error: expected an .ipa to upload at $IPA_PATH, but it is missing" >&2
    exit 1
  fi

  echo "==> xcrun altool --upload-app ($UPLOAD_SOURCE)"
  if ! xcrun altool --upload-app -f "$IPA_PATH" -t ios "${ALTOOL_AUTH_ARGS[@]}"; then
    echo "" >&2
    echo "error: the upload failed. The .ipa itself is fine and is still at:" >&2
    echo "         $IPA_PATH" >&2
    echo "" >&2
    echo "       The usual causes:" >&2
    echo "         - build $NEXT_BUILD already exists for version $NEXT_VERSION in App" >&2
    echo "           Store Connect. Build numbers are spent on upload, so rerun with" >&2
    echo "           --build=$((NEXT_BUILD + 1)) rather than retrying this one." >&2
    echo "         - the credential is not authorised: an API key needs the App" >&2
    echo "           Manager role, and a revoked key fails the same way." >&2
    echo "         - the export was not signed for the App Store. A development-signed" >&2
    echo "           .ipa is rejected at upload, not at export." >&2
    echo "" >&2
    echo "       You can also upload the .ipa above with Transporter." >&2
    exit 1
  fi
fi

# ---- report outputs ---------------------------------------------------------

echo ""
echo "=== build complete ==="
echo "  version:     $NEXT_VERSION"
echo "  build:       $NEXT_BUILD"
echo "  analytics:   $ANALYTICS_SOURCE"
echo "  archive:     $ARCHIVE_PATH"
if [[ $DO_EXPORT -eq 1 ]]; then
  if [[ -f "$IPA_PATH" ]]; then
    echo "  ipa:         $IPA_PATH"
    if [[ $DO_UPLOAD -eq 1 ]]; then
      echo "  testflight:  uploaded via $UPLOAD_SOURCE"
      echo ""
      echo "  App Store Connect is processing build $NEXT_BUILD now; TestFlight shows it"
      echo "  to testers once that finishes, usually within a few minutes."
    else
      echo "  testflight:  $UPLOAD_SOURCE"
      echo ""
      echo "  Upload it with Transporter, or:"
      echo "    xcrun altool --upload-app -f \"$IPA_PATH\" -t ios \\"
      echo "      --apiKey <key-id> --apiIssuer <issuer-id>"
    fi
  else
    echo "  ipa:         (expected at $IPA_PATH but not found — check the export output)"
  fi
fi
echo "======================"

git_commit_tag_and_push
