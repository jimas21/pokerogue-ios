"""Reports where the latest PokeRogue builds are in TestFlight: Apple's processing state, the internal-testing state,
the internal groups, and whether testers are in them. Read-only. Prints no emails or names (logs are public).

Environment: ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID, BUNDLE_ID. Needs PyJWT and cryptography.
"""
import os
import sys

from asc_setup import call, find_app


def main() -> int:
    app_id = find_app(os.environ["BUNDLE_ID"])
    if not app_id:
        print("::error::No App Store Connect app for this bundle ID.")
        return 1

    builds = call("GET", "/builds", query={
        "filter[app]": app_id, "sort": "-uploadedDate", "limit": "5",
        "include": "preReleaseVersion,buildBetaDetail",
        "fields[builds]": "version,uploadedDate,processingState,expired,preReleaseVersion,buildBetaDetail",
        "fields[preReleaseVersions]": "version",
        "fields[buildBetaDetails]": "internalBuildState,externalBuildState"})
    included = {(i["type"], i["id"]): i["attributes"] for i in builds.get("included", [])}
    lines = []
    if not builds.get("data"):
        lines.append("No builds yet: Apple has not registered the upload.")
    for b in builds.get("data", []):
        a = b["attributes"]
        rel = b.get("relationships", {})
        pre = (rel.get("preReleaseVersion", {}).get("data") or {})
        beta = (rel.get("buildBetaDetail", {}).get("data") or {})
        version = included.get(("preReleaseVersions", pre.get("id")), {}).get("version", "?")
        internal = included.get(("buildBetaDetails", beta.get("id")), {}).get("internalBuildState", "?")
        lines.append(f"{version} ({a.get('version')}): processing={a.get('processingState')}, "
                     f"internal testing={internal}, expired={a.get('expired')}, uploaded={a.get('uploadedDate')}")

    groups = call("GET", f"/apps/{app_id}/betaGroups", query={"limit": "50"}).get("data", [])
    for g in groups:
        ga = g["attributes"]
        testers = call("GET", f"/betaGroups/{g['id']}/betaTesters",
                       query={"limit": "50", "fields[betaTesters]": "state"}).get("data", [])
        states = sorted({t["attributes"].get("state") for t in testers})
        lines.append(f"Group '{ga.get('name')}': internal={ga.get('isInternalGroup')}, "
                     f"gets every build={ga.get('hasAccessToAllBuilds')}, testers={len(testers)} {states}")

    print("\n".join(lines))
    with open(os.environ.get("GITHUB_STEP_SUMMARY", os.devnull), "a", encoding="utf-8") as s:
        s.write("### PokeRogue on TestFlight\n\n" + "\n".join(f"- {line}" for line in lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
