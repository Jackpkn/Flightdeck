#!/bin/bash
# One-time setup for notarised releases. Run this once after you have an Apple
# Developer account; scripts/release.sh picks the credentials up from the keychain.
set -euo pipefail

cat <<'GUIDE'
Notarisation setup — one time only
==================================

1. Join the Apple Developer Program ($99/yr): https://developer.apple.com/programs/

2. Create a "Developer ID Application" certificate:
   Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application
   Then confirm it is installed:

       security find-identity -v -p codesigning

   Copy the full name, e.g. "Developer ID Application: Your Name (ABCDE12345)"

3. Create an app-specific password at https://appleid.apple.com > Sign-In and Security

4. Store the notary credentials in your keychain:

       xcrun notarytool store-credentials "flightdeck" \
           --apple-id "you@example.com" \
           --team-id "ABCDE12345" \
           --password "abcd-efgh-ijkl-mnop"

5. Cut a release:

       DEVELOPER_ID="Developer ID Application: Your Name (ABCDE12345)" \
       NOTARY_PROFILE="flightdeck" \
       ./scripts/release.sh

Without steps 1-4 release.sh still builds a working universal DMG, but macOS will
warn anyone who downloads it that the developer cannot be verified.
GUIDE

echo ""
echo "Current signing identities on this machine:"
security find-identity -v -p codesigning 2>/dev/null | sed 's/^/    /' || echo "    (none)"
