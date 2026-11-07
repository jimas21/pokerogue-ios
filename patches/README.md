# Patches to the official PokéRogue source

Applied in order by `ci/build_game.sh` to each release before it is built. Each is small and changes no game rules,
data or save format. If one stops applying to a new release, the build fails with its name instead of shipping.

| Patch | What it does |
| --- | --- |
| `offline-username.patch` | Offline play uses the trainer's own name instead of "Guest" (`localStorage.offlineUsername`, set by the app from an imported `data_<name>.prsv` or Settings > PokéRogue). When the name changes, each save key moves from the old name to the new one, never overwriting. |
