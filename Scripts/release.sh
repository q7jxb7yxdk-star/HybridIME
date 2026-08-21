#!/bin/zsh

set -euo pipefail

readonly HYBRIDIME_VERSION="1.1.2"
readonly HYBRIDIME_BUILD="20260821"
readonly HYBRIDIME_DEPLOYMENT_TARGET="26.0"
readonly HYBRIDIME_TEAM_ID="WX793X49GJ"
readonly HYBRIDIME_BUNDLE_ID="com.sunny.inputmethod.hybridime"
readonly HYBRIDIME_INPUT_SOURCE_ID="com.sunny.inputmethod.hybridime.input"
readonly HYBRIDIME_SIGNING_IDENTITY="Developer ID Application: Yan Yin Yu (WX793X49GJ)"
readonly HYBRIDIME_NOTARY_PROFILE="${HYBRIDIME_NOTARY_PROFILE:-HybridIME-notary}"
readonly HYBRIDIME_RESUME_AFTER_APP_NOTARIZATION="${HYBRIDIME_RESUME_AFTER_APP_NOTARIZATION:-0}"

readonly HYBRIDIME_SCRIPT_DIR="${0:A:h}"
readonly HYBRIDIME_PROJECT_ROOT="${HYBRIDIME_SCRIPT_DIR:h}"
if [[ -n "${HYBRIDIME_RELEASE_ROOT_OVERRIDE:-}" ]]; then
    readonly HYBRIDIME_RELEASE_ROOT="${HYBRIDIME_RELEASE_ROOT_OVERRIDE}"
else
    readonly HYBRIDIME_RELEASE_ROOT="$(mktemp -d "/private/tmp/HybridIME-v${HYBRIDIME_VERSION}.XXXXXX")"
fi
readonly HYBRIDIME_DERIVED_DATA="${HYBRIDIME_RELEASE_ROOT}/DerivedData"
readonly HYBRIDIME_ARCHIVE="${HYBRIDIME_RELEASE_ROOT}/HybridIME.xcarchive"
readonly HYBRIDIME_APP="${HYBRIDIME_ARCHIVE}/Products/Applications/HybridIME.app"
readonly HYBRIDIME_APP_ZIP="${HYBRIDIME_RELEASE_ROOT}/HybridIME-v${HYBRIDIME_VERSION}.zip"
readonly HYBRIDIME_DMG_ROOT="${HYBRIDIME_RELEASE_ROOT}/dmg-root"
readonly HYBRIDIME_DMG="${HYBRIDIME_RELEASE_ROOT}/HybridIME-v${HYBRIDIME_VERSION}.dmg"
readonly HYBRIDIME_APP_NOTARY_RESULT="${HYBRIDIME_RELEASE_ROOT}/app-notary.plist"
readonly HYBRIDIME_DMG_NOTARY_RESULT="${HYBRIDIME_RELEASE_ROOT}/dmg-notary.plist"
readonly HYBRIDIME_CHECKSUM="${HYBRIDIME_RELEASE_ROOT}/HybridIME-v${HYBRIDIME_VERSION}.sha256.txt"

typeset HYBRIDIME_MOUNT_POINT=""
typeset -i HYBRIDIME_IS_MOUNTED=0
typeset HYBRIDIME_APP_SIGNATURE=""
typeset HYBRIDIME_IDENTITIES=""
typeset HYBRIDIME_BUILD_INFO=""

cleanup() {
    if (( HYBRIDIME_IS_MOUNTED )); then
        hdiutil detach "${HYBRIDIME_MOUNT_POINT}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

step() {
    print "\n==> $1"
}

fail() {
    print -u2 "Release failed: $1"
    exit 1
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$2"
}

require_equal() {
    local actual="$1"
    local expected="$2"
    local description="$3"
    [[ "${actual}" == "${expected}" ]] || fail "${description}: expected '${expected}', got '${actual}'"
}

require_resource() {
    local resource="$1"
    [[ -f "${HYBRIDIME_APP}/Contents/Resources/${resource}" ]] || fail "missing packaged resource: ${resource}"
}

require_accepted_notarization() {
    local result_plist="$1"
    local artifact_name="$2"
    local notary_status
    notary_status="$(plutil -extract status raw -o - "${result_plist}")"
    [[ "${notary_status}" == "Accepted" ]] || fail "${artifact_name} notarization status is '${notary_status}'"
}

cd "${HYBRIDIME_PROJECT_ROOT}"

step "Preflight"
if [[ -n "${HYBRIDIME_RELEASE_ROOT_OVERRIDE:-}" ]]; then
    [[ "${HYBRIDIME_RELEASE_ROOT}" == /private/tmp/HybridIME-v${HYBRIDIME_VERSION}.* ]] || \
        fail "resume directory is outside the expected release path"
    [[ -d "${HYBRIDIME_RELEASE_ROOT}" && ! -L "${HYBRIDIME_RELEASE_ROOT}" ]] || \
        fail "resume directory is missing or unsafe"
fi
[[ "${HYBRIDIME_RESUME_AFTER_APP_NOTARIZATION}" == "0" || "${HYBRIDIME_RESUME_AFTER_APP_NOTARIZATION}" == "1" ]] || \
    fail "HYBRIDIME_RESUME_AFTER_APP_NOTARIZATION must be 0 or 1"
git diff --check
plutil -lint Info.plist >/dev/null
plutil -lint HybridIME/Base.lproj/InfoPlist.strings >/dev/null
plutil -lint HybridIME/en.lproj/InfoPlist.strings >/dev/null
plutil -lint HybridIME/zh-Hant.lproj/InfoPlist.strings >/dev/null

[[ "$(rg -c "MARKETING_VERSION = ${HYBRIDIME_VERSION};" HybridIME.xcodeproj/project.pbxproj)" == "2" ]] || \
    fail "MARKETING_VERSION is not ${HYBRIDIME_VERSION} in both configurations"
[[ "$(rg -c "CURRENT_PROJECT_VERSION = ${HYBRIDIME_BUILD};" HybridIME.xcodeproj/project.pbxproj)" == "2" ]] || \
    fail "CURRENT_PROJECT_VERSION is not ${HYBRIDIME_BUILD} in both configurations"
[[ "$(rg -c "MACOSX_DEPLOYMENT_TARGET = ${HYBRIDIME_DEPLOYMENT_TARGET};" HybridIME.xcodeproj/project.pbxproj)" == "2" ]] || \
    fail "target deployment version is not ${HYBRIDIME_DEPLOYMENT_TARGET} in both configurations"
HYBRIDIME_IDENTITIES="$(security find-identity -v -p codesigning)"
[[ "${HYBRIDIME_IDENTITIES}" == *"${HYBRIDIME_SIGNING_IDENTITY}"* ]] || \
    fail "Developer ID Application identity is unavailable"
xcrun notarytool history --keychain-profile "${HYBRIDIME_NOTARY_PROFILE}" --output-format plist >/dev/null

if [[ "${HYBRIDIME_RESUME_AFTER_APP_NOTARIZATION}" == "0" ]]; then
    step "Debug build"
    xcodebuild \
        -project HybridIME.xcodeproj \
        -scheme HybridIME \
        -configuration Debug \
        -destination "generic/platform=macOS" \
        -derivedDataPath "${HYBRIDIME_DERIVED_DATA}/Debug" \
        CODE_SIGNING_ALLOWED=NO \
        build

    step "Static analysis"
    xcodebuild \
        -project HybridIME.xcodeproj \
        -scheme HybridIME \
        -configuration Debug \
        -destination "generic/platform=macOS" \
        -derivedDataPath "${HYBRIDIME_DERIVED_DATA}/Analyze" \
        CODE_SIGNING_ALLOWED=NO \
        analyze

    step "Release build"
    xcodebuild \
        -project HybridIME.xcodeproj \
        -scheme HybridIME \
        -configuration Release \
        -destination "generic/platform=macOS" \
        -derivedDataPath "${HYBRIDIME_DERIVED_DATA}/Release" \
        CODE_SIGNING_ALLOWED=NO \
        build

    step "Developer ID archive"
    xcodebuild \
        -project HybridIME.xcodeproj \
        -scheme HybridIME \
        -configuration Release \
        -destination "generic/platform=macOS" \
        -derivedDataPath "${HYBRIDIME_DERIVED_DATA}/Archive" \
        -archivePath "${HYBRIDIME_ARCHIVE}" \
        CODE_SIGN_STYLE=Manual \
        DEVELOPMENT_TEAM="${HYBRIDIME_TEAM_ID}" \
        CODE_SIGN_IDENTITY="${HYBRIDIME_SIGNING_IDENTITY}" \
        archive
else
    step "Resume accepted app notarization"
    [[ -f "${HYBRIDIME_APP_NOTARY_RESULT}" ]] || fail "resume notarization result is missing"
fi

[[ -d "${HYBRIDIME_APP}" ]] || fail "archive does not contain HybridIME.app"

step "Validate archived app"
require_equal "$(plist_value CFBundleShortVersionString "${HYBRIDIME_APP}/Contents/Info.plist")" "${HYBRIDIME_VERSION}" "marketing version"
require_equal "$(plist_value CFBundleVersion "${HYBRIDIME_APP}/Contents/Info.plist")" "${HYBRIDIME_BUILD}" "build number"
require_equal "$(plist_value CFBundleIdentifier "${HYBRIDIME_APP}/Contents/Info.plist")" "${HYBRIDIME_BUNDLE_ID}" "bundle identifier"
require_equal "$(plist_value TISInputSourceID "${HYBRIDIME_APP}/Contents/Info.plist")" "${HYBRIDIME_BUNDLE_ID}" "root input source identifier"
require_equal \
    "$(plist_value "ComponentInputModeDict:tsInputModeListKey:${HYBRIDIME_INPUT_SOURCE_ID}:TISInputSourceID" "${HYBRIDIME_APP}/Contents/Info.plist")" \
    "${HYBRIDIME_INPUT_SOURCE_ID}" \
    "input mode identifier"
require_equal \
    "$(plist_value InputMethodConnectionName "${HYBRIDIME_APP}/Contents/Info.plist")" \
    "com.sunny.inputmethod.hybridime_Connection" \
    "InputMethodConnectionName"

for resource in \
    AppIcon.icns \
    Assets.car \
    HybridIMEIcon.tiff \
    LICENSE-CC-CEDICT.txt \
    LICENSE-Rime-Cangjie.txt \
    LICENSE-Rime-Essay.txt \
    NOTICE-CC-CEDICT.txt \
    NOTICE-Rime-Essay.txt \
    NOTICE-Tatoeba-CC0.txt \
    NOTICE.txt \
    cangjie-change-log.tsv \
    cangjie5.base.dict.yaml \
    cangjie5.extended.dict.yaml \
    cedict-index.tsv \
    chinese-associations.tsv \
    dictionary-overrides.tsv \
    english-associations.tsv \
    hybrid-cangjie5.dict.tsv
do
    require_resource "${resource}"
done

codesign --verify --deep --strict --verbose=2 "${HYBRIDIME_APP}"
HYBRIDIME_APP_SIGNATURE="$(codesign -dvvv "${HYBRIDIME_APP}" 2>&1)"
[[ "${HYBRIDIME_APP_SIGNATURE}" == *"Authority=${HYBRIDIME_SIGNING_IDENTITY}"* ]] || \
    fail "archived app is not signed with the expected Developer ID identity"
[[ "${HYBRIDIME_APP_SIGNATURE}" == *"TeamIdentifier=${HYBRIDIME_TEAM_ID}"* ]] || \
    fail "archived app has an unexpected Team ID"
[[ "${HYBRIDIME_APP_SIGNATURE}" =~ 'flags=.*runtime' ]] || \
    fail "archived app does not enable hardened runtime"
[[ "${HYBRIDIME_APP_SIGNATURE}" == *"Timestamp="* ]] || \
    fail "archived app signature has no secure timestamp"
file "${HYBRIDIME_APP}/Contents/MacOS/HybridIME"
lipo -archs "${HYBRIDIME_APP}/Contents/MacOS/HybridIME"
HYBRIDIME_BUILD_INFO="$(xcrun vtool -show-build "${HYBRIDIME_APP}/Contents/MacOS/HybridIME")"
[[ "$(print -r -- "${HYBRIDIME_BUILD_INFO}" | rg -c "minos ${HYBRIDIME_DEPLOYMENT_TARGET}$")" == "2" ]] || \
    fail "not every architecture has deployment target ${HYBRIDIME_DEPLOYMENT_TARGET}"

step "Notarize and staple app"
if [[ "${HYBRIDIME_RESUME_AFTER_APP_NOTARIZATION}" == "0" ]]; then
    ditto -c -k --sequesterRsrc --keepParent "${HYBRIDIME_APP}" "${HYBRIDIME_APP_ZIP}"
    xcrun notarytool submit \
        "${HYBRIDIME_APP_ZIP}" \
        --keychain-profile "${HYBRIDIME_NOTARY_PROFILE}" \
        --wait \
        --timeout 45m \
        --output-format plist > "${HYBRIDIME_APP_NOTARY_RESULT}"
fi
require_accepted_notarization "${HYBRIDIME_APP_NOTARY_RESULT}" "HybridIME.app"
xcrun stapler staple -v "${HYBRIDIME_APP}"
xcrun stapler validate -v "${HYBRIDIME_APP}"

step "Create, sign, notarize and staple DMG"
mkdir -p "${HYBRIDIME_DMG_ROOT}"
ditto "${HYBRIDIME_APP}" "${HYBRIDIME_DMG_ROOT}/HybridIME.app"
ditto README.md "${HYBRIDIME_DMG_ROOT}/README.md"
hdiutil create \
    -volname "HybridIME ${HYBRIDIME_VERSION}" \
    -srcfolder "${HYBRIDIME_DMG_ROOT}" \
    -format UDZO \
    -ov \
    "${HYBRIDIME_DMG}"
codesign --force --timestamp --sign "${HYBRIDIME_SIGNING_IDENTITY}" "${HYBRIDIME_DMG}"
codesign --verify --verbose=2 "${HYBRIDIME_DMG}"
xcrun notarytool submit \
    "${HYBRIDIME_DMG}" \
    --keychain-profile "${HYBRIDIME_NOTARY_PROFILE}" \
    --wait \
    --timeout 45m \
    --output-format plist > "${HYBRIDIME_DMG_NOTARY_RESULT}"
require_accepted_notarization "${HYBRIDIME_DMG_NOTARY_RESULT}" "HybridIME DMG"
xcrun stapler staple -v "${HYBRIDIME_DMG}"
xcrun stapler validate -v "${HYBRIDIME_DMG}"
hdiutil verify "${HYBRIDIME_DMG}"

step "Gatekeeper and mounted-DMG verification"
spctl -a -t exec -vv "${HYBRIDIME_APP}"
spctl -a -t open --context context:primary-signature -vv "${HYBRIDIME_DMG}"
HYBRIDIME_MOUNT_POINT="$(mktemp -d "/private/tmp/HybridIME-mount.XXXXXX")"
hdiutil attach -nobrowse -readonly -mountpoint "${HYBRIDIME_MOUNT_POINT}" "${HYBRIDIME_DMG}" >/dev/null
HYBRIDIME_IS_MOUNTED=1
codesign --verify --deep --strict --verbose=2 "${HYBRIDIME_MOUNT_POINT}/HybridIME.app"
spctl -a -t exec -vv "${HYBRIDIME_MOUNT_POINT}/HybridIME.app"
require_equal \
    "$(plist_value CFBundleIdentifier "${HYBRIDIME_MOUNT_POINT}/HybridIME.app/Contents/Info.plist")" \
    "${HYBRIDIME_BUNDLE_ID}" \
    "mounted app bundle identifier"
diff -qr "${HYBRIDIME_APP}" "${HYBRIDIME_MOUNT_POINT}/HybridIME.app"
hdiutil detach "${HYBRIDIME_MOUNT_POINT}" >/dev/null
HYBRIDIME_IS_MOUNTED=0

step "Checksum"
shasum -a 256 "${HYBRIDIME_DMG}" | tee "${HYBRIDIME_CHECKSUM}"

print "\nRelease artifacts are ready:"
print "  App:      ${HYBRIDIME_APP}"
print "  DMG:      ${HYBRIDIME_DMG}"
print "  SHA-256:  ${HYBRIDIME_CHECKSUM}"
print "  Work dir: ${HYBRIDIME_RELEASE_ROOT}"
