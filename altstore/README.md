# Sideload Hermes Mobile (AltStore / SideStore / Feather)

Hermes Mobile CI publishes an **unsigned** IPA on a rolling GitHub Release. You
re-sign it on your machine with AltStore, SideStore, or
[Feather](https://github.com/claration/Feather) — no Apple Developer Program
account is required for the CI build.

## Source URL

Paste this as a source in AltStore, SideStore, or Feather:

```
https://github.com/dylanl321/hermes-mobile/releases/download/hermes-mobile-sideload/source.json
```

If you forked the repo, replace `dylanl321/hermes-mobile` with your
`owner/repo`.

## Steps

1. Install AltStore, SideStore, or Feather on your iPhone.
2. Add the source URL above.
3. Install **Hermes Mobile** from that source.
4. The sideload tool re-signs the IPA with your certificate and installs it.
5. Open the app, enter your Hermes dashboard URL, and sign in.

Updates appear when CI publishes a newer build (`CFBundleVersion` tracks the
GitHub Actions run number). Refresh the source in your sideload tool to see
them.

## Do not use Actions artifact URLs

GitHub Actions artifact download links expire and require authentication. Always
use the **Release** `source.json` URL above — never an Actions artifact link.

## Notes

- The IPA is unsigned by design. It will not install on a stock iPhone without
  re-signing.
- Push notifications need an APNs identity tied to the signing certificate you
  use on device; sideload builds may not receive pushes until you configure that
  separately. Chat and management features work without push.
- Bundle id: `me.honcharenko.HermesMobile`. If you already have a TestFlight or
  App Store build of the same id, sideload may conflict — remove one first.
