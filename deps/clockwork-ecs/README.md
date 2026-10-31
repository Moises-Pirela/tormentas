# clockwork snapshot

This is the exact clockwork core used by Tormentas. No download, sibling checkout,
Git credentials, or package manager is required. Its version is the file-by-file
SHA-256 manifest in `snapshot.json`; build and test scripts verify it.

Source: `ECS/clockwork` from the owner's OVERRIDE working tree, based on commit
`02488ae2b94cdc9ef4edaf56a749d889d8221c23` in
`git@gitlab.com:override-systems-group/override.git`, including local changes to
pool, reflection, world and editor tests. This is not an unmodified upstream
release. There was no independently published clockwork-ecs version or public URL.

On 2026-10-31 the owner explicitly authorized including this package under the
project's MIT license. See `LICENSE`. `snapshot.json` records the subsequent
vet compatibility patch and hashes of the files actually included here.

The absent `cw:ui/microui` and `cw:ui/raylib` adapters are replaced by project-owned
adapters in the repository's `ui/` directory.
