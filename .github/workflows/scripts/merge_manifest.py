"""
Merges android_manifest_snippet.xml into the AndroidManifest.xml that
`flutter create` just generated. Runs automatically in CI — nobody has
to do this by hand.
"""
import re
import sys

MANIFEST_PATH = "android/app/src/main/AndroidManifest.xml"
SNIPPET_PATH = "android_manifest_snippet.xml"

with open(MANIFEST_PATH, encoding="utf-8") as f:
    manifest = f.read()

with open(SNIPPET_PATH, encoding="utf-8") as f:
    snippet = f.read()

permissions = re.findall(r"<uses-permission[^/]*/>", snippet)
if not permissions:
    sys.exit("No <uses-permission> lines found in snippet — check the file.")

meta_data_match = re.search(
    r'<meta-data\s+android:name="com\.google\.android\.gms\.ads\.APPLICATION_ID".*?/>',
    snippet,
    re.DOTALL,
)
if not meta_data_match:
    sys.exit("AdMob <meta-data> block not found in snippet — check the file.")
meta_data = meta_data_match.group(0)

if "RECORD_AUDIO" in manifest:
    print("Manifest already patched — skipping.")
else:
    manifest = re.sub(
        r"(<manifest[^>]*>)",
        lambda m: m.group(1) + "\n    " + "\n    ".join(permissions),
        manifest,
        count=1,
    )
    manifest = manifest.replace(
        "</application>", f"    {meta_data}\n</application>"
    )
    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        f.write(manifest)
    print("AndroidManifest.xml patched successfully.")

print(manifest)
