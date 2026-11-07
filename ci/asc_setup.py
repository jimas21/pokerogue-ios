"""Gets the Apple side ready before a build, using the App Store Connect API key. Safe to run every time.

1. Registers the bundle ID (Certificates, Identifiers & Profiles) if it is not there yet.
2. Checks that the App Store Connect app record exists. Apple's API cannot create one, so if it is missing this
   stops with the exact steps to make it (about a minute in App Store Connect), before any long build starts.
3. Makes sure the app has an internal TestFlight group that receives every build automatically, and that the
   team's users are in it. Problems here are reported as warnings and never stop the build.

Logs are public: this prints no emails, names or identifiers beyond what GitHub masks.

Environment: ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID, BUNDLE_ID. Needs PyJWT and cryptography.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"
GROUP_NAME = "Me"


def token() -> str:
    with open(os.environ["ASC_KEY_PATH"], encoding="utf-8") as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def call(method: str, path: str, body: dict | None = None, query: dict | None = None) -> dict:
    url = API + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", "pokerogue-ios-ci")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        try:
            errors = json.loads(detail).get("errors", [])
            detail = "; ".join(f"{x.get('title')}: {x.get('detail')}" for x in errors) or detail
        except ValueError:
            pass
        raise RuntimeError(f"{method} {path} -> HTTP {e.code}: {detail}") from None


def ensure_bundle_id(identifier: str) -> None:
    found = call("GET", "/bundleIds", query={"filter[identifier]": identifier, "limit": "200"})
    if any(b["attributes"]["identifier"] == identifier for b in found.get("data", [])):
        print("Bundle ID: registered.")
        return
    call("POST", "/bundleIds", {
        "data": {"type": "bundleIds",
                 "attributes": {"identifier": identifier, "name": "PokeRogue", "platform": "IOS"}}})
    print("Bundle ID: was missing, registered it now.")


def find_app(identifier: str) -> str | None:
    apps = call("GET", "/apps", query={"filter[bundleId]": identifier, "limit": "200"})
    for app in apps.get("data", []):
        if app["attributes"].get("bundleId") == identifier:
            return app["id"]
    return None


def ensure_internal_group(app_id: str) -> None:
    groups = call("GET", f"/apps/{app_id}/betaGroups", query={"limit": "200"}).get("data", [])
    internal = [g for g in groups if g["attributes"].get("isInternalGroup")]
    if internal:
        print(f"TestFlight: internal group present ({len(internal)}).")
        return
    group = call("POST", "/betaGroups", {
        "data": {"type": "betaGroups",
                 "attributes": {"name": GROUP_NAME, "isInternalGroup": True, "hasAccessToAllBuilds": True},
                 "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
    print("TestFlight: created an internal group that gets every build.")

    users = call("GET", "/users", query={"limit": "200"}).get("data", [])
    added = 0
    for user in users:
        a = user["attributes"]
        email = a.get("username") or a.get("email")
        if not email:
            continue
        try:
            call("POST", "/betaTesters", {
                "data": {"type": "betaTesters",
                         "attributes": {"email": email, "firstName": a.get("firstName") or "",
                                        "lastName": a.get("lastName") or ""},
                         "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group["id"]}]}}}})
            added += 1
        except RuntimeError as e:
            print(f"::warning::Could not add one team member to the TestFlight group ({str(e)[:200]}).")
    print(f"TestFlight: added {added} of {len(users)} team member(s) to the group.")


def upstream_numbers(ref: str) -> tuple[str, str]:
    """v1.12.2.6 -> ("1.12.2", "6"); v1.13.0 -> ("1.13.0", "0"). Apple allows three numbers in the version, so the
    fourth (PokeRogue's hotfix number) becomes the build number: TestFlight shows 1.12.2 (6) for v1.12.2.6."""
    parts = ref.lstrip("v").split(".")
    if len(parts) not in (3, 4) or not all(p.isdigit() for p in parts):
        raise SystemExit(f"::error::Unexpected PokeRogue release tag {ref!r} (expected vX.Y.Z or vX.Y.Z.H).")
    return ".".join(parts[:3]), (parts[3] if len(parts) == 4 else "0")


def choose_build_number(app_id: str) -> None:
    """Picks the build number for this upload and exports MARKETING_VERSION and BUILD_NUMBER for later steps.

    First build of a PokeRogue release: the release's own hotfix number (6 for v1.12.2.6). A rebuild of the same
    release (an app-only fix): 6.1, 6.2, ... Each stays tied to the release, sorts after the one before, and never
    repeats a number already on TestFlight (checked against App Store Connect itself)."""
    version, hotfix = upstream_numbers(os.environ["UPSTREAM_REF"])
    builds = call("GET", "/builds", query={"filter[app]": app_id, "filter[preReleaseVersion.version]": version,
                                           "limit": "200", "fields[builds]": "version"}).get("data", [])
    taken = {b["attributes"]["version"] for b in builds}
    number = hotfix
    n = 0
    while number in taken:
        n += 1
        number = f"{hotfix}.{n}"
    print(f"TestFlight version: {version} ({number}), from PokeRogue {os.environ['UPSTREAM_REF']}.")
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as env:
        env.write(f"MARKETING_VERSION={version}\nBUILD_NUMBER={number}\n")
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as summary:
        summary.write(f"**TestFlight version {version} ({number})** = PokeRogue {os.environ['UPSTREAM_REF']}\n\n")


def main() -> int:
    identifier = os.environ["BUNDLE_ID"]
    ensure_bundle_id(identifier)

    app_id = find_app(identifier)
    if not app_id:
        print("::error::There is no App Store Connect app for this bundle ID yet. Apple's API cannot create one.")
        print("Make it once (about a minute), then run this workflow again:")
        print("  1. appstoreconnect.apple.com > Apps > + > New App")
        print("  2. Platform iOS. Name: anything not taken on the App Store, e.g. 'PokéRogue Offline'.")
        print("  3. Bundle ID: pick the PokeRogue one this step just registered. SKU: pokerogue. Full Access.")
        return 3
    print("App record: present.")

    choose_build_number(app_id)

    try:
        ensure_internal_group(app_id)
    except RuntimeError as e:
        print(f"::warning::TestFlight group setup did not finish ({str(e)[:300]}). Add yourself under the app's "
              "TestFlight > Internal Testing in App Store Connect.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
