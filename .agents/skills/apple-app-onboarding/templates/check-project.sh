#!/bin/sh
#
# Project doctor — verifies the mechanical setup rules that otherwise only fail
# on Xcode Cloud or at TestFlight upload (docs/apple-multiplatform-ci-gotchas.md).
# Toolchain-free (grep/awk over the pbxproj), so it runs in cloud sessions too.
#
# Usage:  Tools/check-project.sh
# Exit 1 on FAIL lines; warnings don't fail the run.

set -e
cd "$(dirname "$0")/.."

APP_DIR="{{APP_NAME}}"
PBXPROJ="$APP_DIR/$APP_DIR.xcodeproj/project.pbxproj"

status=0
err()  { echo "FAIL: $1"; status=1; }
warn() { echo "warn: $1"; }
ok()   { echo "  ok: $1"; }

[ -f "$PBXPROJ" ] || { err "no project at $PBXPROJ"; exit 1; }

# 1. Local package references must not climb above the repo root (gotchas §1).
#    Xcode Cloud checks out to a fixed path; '../<anything>' resolves only by
#    accident of the local checkout's folder name.
climbers=$(grep -o 'relativePath = [^;]*' "$PBXPROJ" | grep '\.\./' || true)
if [ -n "$climbers" ]; then
  err "package reference climbs above the repo root (breaks Xcode Cloud): $climbers"
elif grep -q 'XCLocalSwiftPackageReference' "$PBXPROJ"; then
  ok "local package reference stays inside the repo"
else
  warn "no local Swift package reference in the project — is the app linked to the package yet?"
fi

# 1b. Project file format must not exceed the declared preferred version (gotchas §13):
#     a beta Xcode can stamp a future objectVersion that release-Xcode cloud images
#     cannot open ("future Xcode project file format").
objv=$(grep -m1 -o 'objectVersion = [0-9]*' "$PBXPROJ" | grep -o '[0-9]*')
prefv=$(grep -m1 -o 'preferredProjectObjectVersion = [0-9]*' "$PBXPROJ" | grep -o '[0-9]*' || true)
if [ -n "$prefv" ] && [ -n "$objv" ] && [ "$objv" -gt "$prefv" ]; then
  err "objectVersion = $objv exceeds preferredProjectObjectVersion = $prefv — beta Xcode upgraded the format; release-Xcode cloud builds can't open it (set objectVersion back to $prefv)"
elif [ -n "$objv" ]; then
  ok "project file format objectVersion = $objv${prefv:+ (preferred $prefv)}"
fi

# 2. Deployment targets consistent across every target and build config (gotchas §2),
#    and matching Package.swift's platform floors.
for pair in "IPHONEOS iOS iphoneos" "MACOSX macOS macosx" "TVOS tvOS appletvos" \
            "XROS visionOS xros" "WATCHOS watchOS watchos"; do
  plat=$(echo "$pair" | awk '{ print $1 }')
  swift_name=$(echo "$pair" | awk '{ print $2 }')
  sdk=$(echo "$pair" | awk '{ print $3 }')
  vals=$(grep -o "${plat}_DEPLOYMENT_TARGET = [0-9.]*" "$PBXPROJ" | awk '{ print $3 }' | sort -u)
  if [ -z "$vals" ]; then
    # An ABSENT setting is not a pass: a target that builds this platform silently
    # inherits the SDK's default floor (a beta SDK's, typically), diverging from
    # Package.swift with nothing in the pbxproj to grep for. Only silence is the tell.
    if grep -q "SUPPORTED_PLATFORMS = \"[^\"]*${sdk}" "$PBXPROJ" 2>/dev/null; then
      pkg=$(grep -o "\.${swift_name}(\"[0-9.]*\")" Package.swift 2>/dev/null | grep -o '[0-9][0-9.]*' || true)
      msg="${plat}_DEPLOYMENT_TARGET is never set, but SUPPORTED_PLATFORMS builds ${sdk} — it inherits the SDK default"
      [ -n "$pkg" ] && msg="$msg, not Package.swift's $pkg"
      warn "$msg. Set it explicitly."
    fi
    continue
  fi
  if [ "$(echo "$vals" | wc -l)" -gt 1 ]; then
    err "mixed ${plat}_DEPLOYMENT_TARGET values: $(echo "$vals" | tr '\n' ' ')"
  else
    pkg=$(grep -o "\.${swift_name}(\"[0-9.]*\")" Package.swift 2>/dev/null | grep -o '[0-9][0-9.]*' || true)
    if [ -n "$pkg" ] && [ "$pkg" != "$vals" ]; then
      warn "${plat}_DEPLOYMENT_TARGET is $vals but Package.swift declares .$swift_name(\"$pkg\")"
    else
      ok "${plat}_DEPLOYMENT_TARGET = $vals everywhere"
    fi
  fi
done

# 3. MARKETING_VERSION identical across targets (ci_pre_xcodebuild.sh stamps them all;
#    a stray value means someone hand-edited one target).
mv_count=$(grep -o 'MARKETING_VERSION = [^;]*' "$PBXPROJ" | sort -u | wc -l | tr -d ' ')
if [ "$mv_count" -gt 1 ]; then
  warn "targets disagree on MARKETING_VERSION: $(grep -o 'MARKETING_VERSION = [^;]*' "$PBXPROJ" | sort -u | tr '\n' ' ')"
elif [ "$mv_count" -eq 1 ]; then
  ok "MARKETING_VERSION consistent across targets"
fi

# 4. No Info.plist key set BOTH in a target's plist file and as an INFOPLIST_KEY_*
#    build setting on the SAME target (gotchas §12 — one home per key; studio
#    convention: the plist file wins, build settings only for per-config values).
#    Compared per buildSettings block so one target's plist keys don't
#    false-positive against another target's build settings.
dupes=$(awk '
  /buildSettings = \{/ { inbs = 1; plist = ""; keys = "" }
  inbs && /INFOPLIST_FILE = / {
    line = $0; sub(/^.*INFOPLIST_FILE = /, "", line); sub(/;.*$/, "", line)
    gsub(/"/, "", line); plist = line
  }
  inbs && match($0, /INFOPLIST_KEY_[A-Za-z0-9_]+/) {
    keys = keys " " substr($0, RSTART + 14, RLENGTH - 14)
  }
  inbs && /^[\t ]+\};/ {
    if (plist != "" && keys != "") {
      n = split(keys, k, " ")
      for (i = 1; i <= n; i++) print plist, k[i]
    }
    inbs = 0
  }
' "$PBXPROJ" | sort -u | while read -r plist key; do
  f="$APP_DIR/$plist"
  if [ -f "$f" ] && grep -q "<key>$key</key>" "$f"; then
    echo "'$key' in both $f and its target's build settings"
  fi
done || true)
if [ -n "$dupes" ]; then
  echo "$dupes" | while IFS= read -r d; do echo "FAIL: $d"; done
  status=1
else
  ok "no Info.plist key doubled between a plist file and its target's build settings"
fi

# 5. Privacy manifest present in the app target (gotchas §7).
if find "$APP_DIR" -name 'PrivacyInfo.xcprivacy' 2>/dev/null | grep -q .; then
  ok "PrivacyInfo.xcprivacy present"
else
  warn "no PrivacyInfo.xcprivacy found — required-reason APIs (UserDefaults etc.) need one"
fi

# 5b. App Store category + export-compliance must live in one home (plist or INFOPLIST_KEY).
has_cat=0
has_its=0
grep -q 'INFOPLIST_KEY_LSApplicationCategoryType' "$PBXPROJ" && has_cat=1
grep -q 'INFOPLIST_KEY_ITSAppUsesNonExemptEncryption' "$PBXPROJ" && has_its=1
if [ "$has_cat" -eq 0 ] && grep -rl '<key>LSApplicationCategoryType</key>' "$APP_DIR" --include='Info.plist' >/dev/null 2>&1; then
  has_cat=1
fi
if [ "$has_its" -eq 0 ] && grep -rl '<key>ITSAppUsesNonExemptEncryption</key>' "$APP_DIR" --include='Info.plist' >/dev/null 2>&1; then
  has_its=1
fi
[ "$has_cat" -eq 1 ] && ok "LSApplicationCategoryType is set" \
  || err "no LSApplicationCategoryType (plist or INFOPLIST_KEY) — macOS archive is invalid (ITMS-90242)"
[ "$has_its" -eq 1 ] && ok "ITSAppUsesNonExemptEncryption is set" \
  || err "no ITSAppUsesNonExemptEncryption (plist or INFOPLIST_KEY) — every upload prompts for export compliance"

# 5c. Watch AppIcon slots must have a file on disk (gotchas §17/§18). Empty iOS/mac
#     slots next to a .icon are fine; a watchos slot with no filename fails the iOS archive.
if command -v python3 >/dev/null 2>&1; then
  icon_issues=$(python3 - "$APP_DIR" <<'PY'
import json, os, sys
root = sys.argv[1]
skip = {".build", "DerivedData", "build", ".git"}
issues = []
saw_watch = False
for dirpath, dirnames, files in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in skip]
    if "Widget" in dirpath.split(os.sep):
        continue
    if not dirpath.endswith("AppIcon.appiconset") or "Contents.json" not in files:
        continue
    path = os.path.join(dirpath, "Contents.json")
    try:
        data = json.load(open(path))
    except Exception as e:
        issues.append(f"{path}: {e}")
        continue
    for im in data.get("images") or []:
        plat = (im.get("platform") or "").lower()
        if plat != "watchos":
            continue
        saw_watch = True
        fn = im.get("filename")
        if not fn:
            issues.append(f"{path}: watchos {im.get('size')} slot has no filename")
        elif not os.path.isfile(os.path.join(dirpath, fn)):
            issues.append(f"{path}: missing {fn}")
if not saw_watch:
    print("NONE")
else:
    print("\n".join(issues))
PY
)
  if [ "$icon_issues" = "NONE" ]; then
    ok "no Watch AppIcon catalog to check"
  elif [ -n "$icon_issues" ]; then
    echo "$icon_issues" | while IFS= read -r d; do echo "FAIL: $d"; done
    status=1
  else
    ok "Watch AppIcon watchos slots have files on disk"
  fi
else
  warn "python3 not found — skipped Watch AppIcon catalog check"
fi

# 5d. Purpose strings when the matching API is referenced (ITMS-90683).
needs_music=$(grep -rlE 'MusicAuthorization\.request|MusicAuthorization\.currentStatus' \
  --include='*.swift' Sources "$APP_DIR" 2>/dev/null | grep -v Tests || true)
needs_homekit=$(grep -rlE 'HMHomeManager|import HomeKit' \
  --include='*.swift' Sources "$APP_DIR" 2>/dev/null | grep -v Tests || true)
needs_loc=$(grep -rlE 'CLLocationManager|CLMonitor\(|CLCircularRegion' \
  --include='*.swift' Sources "$APP_DIR" 2>/dev/null | grep -v Tests || true)
needs_speech=$(grep -rlE 'SFSpeechRecognizer|SFSpeechURLRecognitionRequest|SFSpeechAudioBufferRecognitionRequest' \
  --include='*.swift' Sources "$APP_DIR" 2>/dev/null | grep -v Tests || true)
plist_or_key() {
  k="$1"
  grep -q "INFOPLIST_KEY_$k" "$PBXPROJ" && return 0
  grep -rl "<key>$k</key>" "$APP_DIR" --include='Info.plist' >/dev/null 2>&1
}
if [ -n "$needs_music" ]; then
  plist_or_key NSAppleMusicUsageDescription \
    && ok "NSAppleMusicUsageDescription present (MusicKit is referenced)" \
    || err "MusicKit authorization is referenced but NSAppleMusicUsageDescription is missing (ITMS-90683)"
fi
if [ -n "$needs_homekit" ]; then
  plist_or_key NSHomeKitUsageDescription \
    && ok "NSHomeKitUsageDescription present (HomeKit is referenced)" \
    || err "HomeKit is referenced but NSHomeKitUsageDescription is missing (ITMS-90683)"
fi
if [ -n "$needs_loc" ]; then
  if plist_or_key NSLocationWhenInUseUsageDescription \
    || plist_or_key NSLocationAlwaysAndWhenInUseUsageDescription \
    || plist_or_key NSLocationAlwaysUsageDescription; then
    ok "location usage description present (Core Location is referenced)"
  else
    err "Core Location is referenced but no NSLocation*UsageDescription is set (ITMS-90683)"
  fi
fi
if [ -n "$needs_speech" ]; then
  plist_or_key NSSpeechRecognitionUsageDescription \
    && ok "NSSpeechRecognitionUsageDescription present (Speech is referenced)" \
    || err "SFSpeechRecognizer is referenced but NSSpeechRecognitionUsageDescription is missing (ITMS-90683)"
fi

# 5e–5h. Upload rejects that are mechanical: reserved CFBundleName (ITMS-90129),
#    App Intent "apple" wording (ITMS-90626), empty CloudKit environment
#    (ITMS-90046), tvOS/visionOS Back + Top Shelf alpha at every scale.
if command -v python3 >/dev/null 2>&1; then
  extra=$(python3 - "$APP_DIR" "$PBXPROJ" <<'PY'
import os, re, subprocess, sys
from pathlib import Path

app_dir = Path(sys.argv[1])
pbx = Path(sys.argv[2])
root = Path(".").resolve()
skip_dirs = {".build", "DerivedData", "build", ".git", "Playground"}
issues = []

RESERVED = {
    "watch", "stocks", "music", "news", "maps", "weather", "wallet", "health",
    "home", "fitness", "contacts", "mail", "calendar", "photos", "notes",
    "reminders", "files", "settings", "clock", "phone", "messages", "facetime",
    "safari", "books", "podcasts", "tv", "tips", "shortcuts", "find my",
    "app store", "testflight", "xcode", "itunes", "imovie", "keynote", "pages",
    "numbers", "garageband", "calculator", "compass", "measure", "translate",
    "voice memos", "camera", "apple tv", "apple music", "apple watch",
}

def is_test(name: str) -> bool:
    n = name.lower().replace(" ", "")
    return n.endswith("tests") or "uitest" in n

# --- 5e reserved PRODUCT_NAME / display name (ITMS-90129) ---
# Watch template: PRODUCT_NAME=Watch is OK if CFBundleDisplayName is set and
# not reserved (SideQuest). Main-app PRODUCT_NAME=Stocks fails even with a
# distinct display name — CFBundleName is always PRODUCT_NAME.
# Config blocks are often just `/* Debug */`; map id → target via XCConfigurationList.
text = pbx.read_text() if pbx.is_file() else ""
id_to_target = {}
for m in re.finditer(
    r'/\* Build configuration list for PBXNativeTarget "([^"]+)" \*/ = \{'
    r'(.*?)\n\t\t\};',
    text,
    re.S,
):
    tname = m.group(1)
    for cid in re.findall(r'([A-F0-9]{24}) /\* (?:Debug|Release) \*/', m.group(2)):
        id_to_target[cid] = tname

meta = {}
cur = None
for line in text.splitlines():
    hm = re.match(
        r'\t\t([A-F0-9]{24}) /\* (?:Debug|Release)(?: configuration for PBXNativeTarget "([^"]+)")? \*/ = \{',
        line,
    )
    if hm:
        cur = hm.group(2) or id_to_target.get(hm.group(1))
        if cur:
            meta.setdefault(cur, {"products": set(), "displays": set()})
        continue
    tm = re.search(r'PBXNativeTarget "([^"]+)"', line)
    if tm and "Build configuration list" not in line:
        cur = tm.group(1)
        meta.setdefault(cur, {"products": set(), "displays": set()})
        continue
    if cur is None or is_test(cur):
        continue
    pm = re.search(r'PRODUCT_NAME = ([^;]+);', line)
    if pm:
        raw = pm.group(1).strip().strip('"')
        effective = cur if raw == "$(TARGET_NAME)" else raw
        meta[cur]["products"].add(effective)
    dm = re.search(r'INFOPLIST_KEY_CFBundleDisplayName = ([^;]+);', line)
    if dm:
        meta[cur]["displays"].add(dm.group(1).strip().strip('"'))

def is_watch(name: str) -> bool:
    n = name.lower().replace(" ", "")
    return n == "watch" or n.endswith("watch") or "watchapp" in n

def is_appex(name: str) -> bool:
    n = name.lower()
    return any(x in n for x in (
        "widget", "notification", "share", "message", "clip", "intent",
        "extension", "download",
    ))

seen_name = set()
for target, vals in meta.items():
    if is_test(target) or is_appex(target):
        continue
    displays = {d for d in vals["displays"] if d}
    products = {p for p in vals["products"] if p}
    for d in displays:
        key = ("display", target, d)
        if d.lower() in RESERVED and key not in seen_name:
            seen_name.add(key)
            issues.append(
                f"CFBundleDisplayName '{d}' (target {target}) is an Apple app name (ITMS-90129)"
            )
    if is_watch(target):
        if not displays:
            issues.append(
                f"Watch target '{target}' has no CFBundleDisplayName "
                f"(ITMS-90129 — template default is Watch)"
            )
        continue
    for p in products:
        key = ("product", target, p)
        if p.lower() in RESERVED and key not in seen_name:
            seen_name.add(key)
            issues.append(
                f"PRODUCT_NAME '{p}' (target {target}) is an Apple app name "
                f"(ITMS-90129 — CFBundleName cannot be overridden)"
            )

# --- 5f App Intent title / IntentDescription must not contain "apple" (ITMS-90626) ---
intent_re = re.compile(
    r'(?:IntentDescription\s*\(\s*|static\s+(?:let|var)\s+title[^=]*=\s*(?:LocalizedStringResource\s*)?)'
    r'"([^"]*)"',
    re.S,
)
for dirpath, dirnames, files in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in skip_dirs]
    parts = set(Path(dirpath).parts)
    if "Tests" in parts or "Playground" in parts:
        continue
    for fn in files:
        if not fn.endswith(".swift"):
            continue
        path = Path(dirpath) / fn
        try:
            src = path.read_text()
        except OSError:
            continue
        if "AppIntent" not in src and "IntentDescription" not in src:
            continue
        for m in intent_re.finditer(src):
            s = m.group(1)
            if re.search(r"apple", s, re.I):
                issues.append(
                    f"{path}: App Intent title/description contains 'apple' "
                    f"(ITMS-90626): \"{s}\""
                )

# --- 5g CloudKit claimed without Production environment / empty containers (ITMS-90046) ---
try:
    import plistlib
except ImportError:
    plistlib = None
if plistlib:
    for dirpath, dirnames, files in os.walk(app_dir):
        dirnames[:] = [d for d in dirnames if d not in skip_dirs]
        for fn in files:
            if not fn.endswith(".entitlements"):
                continue
            path = Path(dirpath) / fn
            try:
                data = plistlib.loads(path.read_bytes())
            except Exception as e:
                issues.append(f"{path}: {e}")
                continue
            services = data.get("com.apple.developer.icloud-services") or []
            if "CloudKit" not in services and "CloudKit-Anonymous" not in services:
                continue
            ids = data.get("com.apple.developer.icloud-container-identifiers")
            env = data.get("com.apple.developer.icloud-container-environment")
            if ids is not None and len(ids) == 0:
                issues.append(
                    f"{path}: CloudKit claimed with empty icloud-container-identifiers "
                    f"(ITMS-90046 — drop unused CloudKit or add a real container)"
                )
            if not env:
                issues.append(
                    f"{path}: CloudKit claimed but icloud-container-environment is missing "
                    f"(ITMS-90046 — set Production for upload)"
                )

# --- 5h tvOS/visionOS Back + Top Shelf must be opaque at every scale ---
def sips_alpha(p: Path):
    try:
        r = subprocess.run(
            ["sips", "-g", "hasAlpha", str(p)],
            capture_output=True, text=True, check=False,
        )
    except FileNotFoundError:
        return None
    if "hasAlpha: yes" in r.stdout:
        return True
    if "hasAlpha: no" in r.stdout:
        return False
    return None

sips_missing = False
for dirpath, dirnames, files in os.walk(app_dir):
    dirnames[:] = [d for d in dirnames if d not in skip_dirs]
    rel = dirpath
    is_back = "Back.imagestacklayer" in rel or "Back.solidimagestacklayer" in rel
    is_shelf = "Top Shelf Image" in rel
    if not (is_back or is_shelf):
        continue
    if "Front.imagestacklayer" in rel:
        continue
    for fn in files:
        if not fn.lower().endswith(".png"):
            continue
        p = Path(dirpath) / fn
        alpha = sips_alpha(p)
        if alpha is None:
            sips_missing = True
            continue
        if alpha:
            issues.append(
                f"{p}: Back/Top Shelf PNG has alpha (ITMS opaque-bitmap — flatten every scale)"
            )

if sips_missing and not any("has alpha" in i for i in issues):
    print("WARN_NO_SIPS")
print("\n".join(issues))
PY
)
  case "$extra" in
    *WARN_NO_SIPS*)
      extra=$(printf '%s\n' "$extra" | grep -v '^WARN_NO_SIPS' || true)
      warn "sips not found — skipped tvOS/visionOS Back/Top Shelf alpha check"
      ;;
  esac
  extra=$(printf '%s\n' "$extra" | sed '/^$/d' || true)
  if [ -n "$extra" ]; then
    printf '%s\n' "$extra" | while IFS= read -r d; do
      [ -n "$d" ] && echo "FAIL: $d"
    done
    status=1
  else
    ok "reserved names, App Intent wording, CloudKit environment, tvOS/visionOS opacity"
  fi
else
  warn "python3 not found — skipped reserved-name / intent / iCloud / tvOS-alpha checks"
fi

# 6. The app scheme must be SHARED (gotchas §19). Xcode auto-creates schemes into
#    xcuserdata/, which is gitignored — so a scheme that works locally is simply
#    absent from the clone, and every Xcode Cloud action reports
#    "The scheme 'X' was not found in this project."
schemedir="$APP_DIR/$APP_DIR.xcodeproj/xcshareddata/xcschemes"
if [ -f "$schemedir/$APP_DIR.xcscheme" ]; then
  ok "app scheme is shared ($APP_DIR.xcscheme)"
else
  err "no shared scheme at $schemedir/$APP_DIR.xcscheme — Xcode Cloud can't see xcuserdata schemes (Xcode: Product > Scheme > Manage Schemes > tick Shared, then commit)"
fi

# 7. A watch app's WKCompanionAppBundleIdentifier must equal the app's bundle ID
#    (ITMS-90538, gotchas §18). It lives in its OWN build setting, so bundle-ID
#    renames anchored to PRODUCT_BUNDLE_IDENTIFIER miss it silently.
companion=$(grep -o 'INFOPLIST_KEY_WKCompanionAppBundleIdentifier = [^;]*' "$PBXPROJ" \
  | sed 's/.*= *//' | tr -d '"' | sort -u || true)
if [ -n "$companion" ]; then
  # The app's own bundle ID is the shortest one that is a prefix of the others.
  appid=$(grep -o 'PRODUCT_BUNDLE_IDENTIFIER = [^;]*' "$PBXPROJ" \
    | sed 's/.*= *//' | tr -d '"' | awk '{print length, $0}' | sort -n | head -1 | cut -d' ' -f2-)
  bad=0
  for c in $companion; do
    [ "$c" = "$appid" ] || { err "WKCompanionAppBundleIdentifier '$c' != app bundle ID '$appid' (ITMS-90538)"; bad=1; }
  done
  [ "$bad" -eq 0 ] && ok "WKCompanionAppBundleIdentifier matches the app bundle ID"
fi

# 8. No extension may ship NSExtensionActivationRule = TRUEPREDICATE (ITMS-90362,
#    gotchas §18). Xcode's template default; builds and runs, rejected at upload.
#    Match the plist VALUE, not the bare word — a comment explaining this trap is
#    the expected content of a correctly-fixed plist.
tp=$(grep -rl '<string>TRUEPREDICATE</string>' "$APP_DIR" --include='Info.plist' 2>/dev/null || true)
if [ -n "$tp" ]; then
  err "NSExtensionActivationRule = TRUEPREDICATE in: $(echo "$tp" | tr '\n' ' ')(ITMS-90362 — declare the content types actually handled)"
else
  ok "no TRUEPREDICATE activation rules"
fi

# 9. No leftover onboarding placeholders outside the skill itself.
#    -I skips binary files: PNG/USDZ master art contains stray '{{' bytes and would
#    otherwise report as a placeholder FAIL forever, training you to ignore the doctor.
left=$(grep -rlI '{{[A-Z_]*}}' . \
  --exclude-dir=.git --exclude-dir=.claude --exclude-dir=.build 2>/dev/null || true)
if [ -n "$left" ]; then
  err "unsubstituted template placeholders in: $(echo "$left" | tr '\n' ' ')"
else
  ok "no leftover template placeholders"
fi

# 10. CI + tooling scripts exist and are executable (Xcode Cloud silently skips a
#     non-executable ci_post_clone.sh).
for f in ci_scripts/ci_post_clone.sh ci_scripts/ci_pre_xcodebuild.sh Tools/*.sh; do
  if [ ! -f "$f" ]; then
    warn "$f missing"
  elif [ ! -x "$f" ]; then
    err "$f is not executable (chmod +x)"
  fi
done
ok "ci_scripts/ and Tools/ scripts checked"

echo ""
if [ "$status" -eq 0 ]; then
  echo "check-project: healthy."
else
  echo "check-project: FAILURES above — fix before pushing; these break cloud builds or uploads."
fi
exit $status
