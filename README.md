# PokéRogue for iPhone (offline)

An unofficial iPhone and iPad wrapper for [PokéRogue](https://github.com/pagefaultgames/pokerogue), built straight
from the official source. It is not made by or affiliated with the PokéRogue team.

- **Plays fully offline.** The whole game (code, art, audio, translations) is inside the app and served from the
  app itself. You play as a local Guest and your saves stay on the device.
- **Stays current.** Once a day a check looks for a new PokéRogue release. When there is one, the game is rebuilt
  and uploaded to TestFlight, which updates the app on its own. Events are dated in the game's source, so each one
  switches on and off by itself, with or without a connection.
- **Bring your save.** Manage Data has Import Data and Import Session (upstream's app mode). Export your data on
  pokerogue.net (Menu > Manage Data > Export Data / Export Session), then import the `.prsv` file in the app.
- **Saves are backed up.** The app keeps its own copy of the game's storage (plus 14 daily backups) and puts it
  back if iOS ever clears web storage. Exports land in Files > On My iPhone > PokéRogue > Exports.

## How it builds

No Mac is involved. Everything runs on GitHub Actions:

| Workflow | What it does |
| --- | --- |
| `Upstream check` | Daily. Starts `TestFlight` for a PokéRogue release that hasn't been built yet. |
| `TestFlight` | Clones the release with its assets, runs `pnpm build:app` in offline mode (`ci/build_game.sh`), makes the icon, archives with XcodeGen + xcodebuild, signs with the App Store Connect API key and uploads. |
| `Compile check` | Unsigned compile of the app on every push. |

The version shown in TestFlight is the PokéRogue release (v1.12.2.6 shows as 1.12.2); the build number is the
workflow run number. The exact upstream commits are in the run summary.

Repository settings (names only; values never go in the repo): variables `BUNDLE_ID`, `TEAM_ID`; secrets
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (an App Store Connect Team Key with Admin access).

## Licence

PokéRogue's code is AGPL-3.0-only and this wrapper is released under the same licence (see `LICENSE`). Game assets
come from PokéRogue's own repositories at build time under their own terms and are never stored here. Pokémon and
all related names and art belong to Nintendo, Game Freak and The Pokémon Company.
