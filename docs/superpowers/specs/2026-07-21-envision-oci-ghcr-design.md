# Envision-OCI GHCR and Upstream Compatibility Design

Date: 2026-07-21

## Objective

Restore the imported Envision-OCI fork to a buildable state, publish an amd64 image from GitHub Actions to `ghcr.io/johnneerdael/envision-oci`, and track the official `gabmus/envision` project through stable and edge channels.

The maintained image is intended for Fedora Atomic desktops and Bazzite systems where Envision needs a mutable environment containing its XR build dependencies.

## Current State and Findings

The GitHub import contains `.gitmodules`, but it does not contain the `vendor/envision` gitlink. A clean checkout therefore cannot satisfy the current `COPY vendor/envision /build/envision` instruction.

The original Envision-OCI repository intended to pin Envision at `373646a`. The official `gabmus/envision` repository is currently at `aa84e48`. The newer official revision adds three changes after the old pin:

- Search `/etc/udev/rules.d` as well as `/usr/lib/udev/rules.d` during dependency checks.
- Show the `setcap` warning only at appropriate times and only for an existing service binary.
- Render long profile names correctly in the profile dropdown.

The old pin already contains support for plugins that run after service shutdown and the Proton 11/Steam Linux Runtime 4 missing-environment-variable fix. No newer Envision feature requires a different container integration at this time.

Fedora 44 still provides the `envision-monado` and `envision-xrizer` build-dependency metapackages. The Fedora `envision` source build dependencies also resolve, so the existing Fedora-based OCI strategy remains viable.

The wrapper repository still points users and tools at MatrixFurry's GitLab registry and Tangled/Homebrew release infrastructure. Those endpoints cannot publish or serve this fork.

## Source Strategy

Restore `vendor/envision` as a submodule of:

```text
https://gitlab.com/gabmus/envision
```

Pin the committed gitlink initially to `aa84e48e8de86dd12d62604340a29748b599d298`.

Use the committed submodule revision for stable builds. For edge builds, fetch official upstream `main` inside the checked-out submodule and build the resulting detached revision. Both channels use the same `Containerfile` and source layout.

Do not carry over MatrixFurry's `/home/linuxbrew/.linuxbrew` system-profile prefix patch. The OCI image installs its system runtime under `/usr`, matching official Envision's behavior.

## Image Design

Build only `linux/amd64` images.

Use `fedora:44` for both build and runtime stages. Pinning the Fedora release avoids unreviewed major-version changes while allowing normal Fedora 44 package updates during rebuilds.

Continue to compile Envision into `/opt/envision` and keep the runtime image equipped to build the supported XR components. Remove the duplicate `bzip2-devel` entry and clean DNF caches without otherwise narrowing the dependency set during this change.

Set OCI metadata for the maintained fork, including:

- Source repository: `https://github.com/johnneerdael/envision-oci`
- License: `AGPL-3.0-only`
- Wrapper repository revision supplied by GitHub metadata
- A dedicated label containing the exact upstream Envision revision

## Publication Channels

Use one GitHub Actions workflow with logically separate validation and publishing jobs.

### Pull Requests

Build the pinned image for `linux/amd64` without logging into GHCR and without pushing. Grant only `contents: read`.

### Stable Main Channel

On pushes to `main`, build the committed submodule revision and publish:

- `ghcr.io/johnneerdael/envision-oci:latest`
- `ghcr.io/johnneerdael/envision-oci:sha-<wrapper-commit>`

The SHA tag provides a commit-addressed rollback target. For strict immutability, consumers can pin the published image digest because registry tags can be moved by a rebuild.

### Version Tags

On `v*` tags, build the committed submodule revision and publish semantic-version tags derived from the Git tag. A tag such as `v1.2.3` produces `1.2.3`, `1.2`, and `1` tags.

### Edge Channel

Run nightly at a non-peak minute. Update the submodule working tree to the current official Envision `main` revision, then publish:

- `ghcr.io/johnneerdael/envision-oci:edge`

Record the resolved upstream revision in image metadata so every edge digest remains attributable even though its human-readable tag moves.

### Manual Runs

Support `workflow_dispatch` with a `pinned` or `edge` channel input. The default is `pinned`.

### Authentication and Supply Chain

Authenticate to GHCR with the repository `GITHUB_TOKEN`. The publishing job grants `contents: read`, `packages: write`, `attestations: write`, and `id-token: write`. Pull-request validation does not receive package write access.

Pin all third-party Actions to full commit SHAs. Use BuildKit's GitHub Actions cache and publish a provenance attestation for pushed images.

New GHCR packages are private by default. After the first successful publish, change the package visibility to Public in GitHub's package settings. No launcher authentication is then required.

## Launcher and Local Build Tools

Change the default launcher image to:

```text
ghcr.io/johnneerdael/envision-oci:latest
```

Allow `ENVISION_OCI_IMAGE` to override that default. For example, setting it to `ghcr.io/johnneerdael/envision-oci:edge` opts into the nightly channel without editing the launcher.

Retarget `build-oci.nu` to GHCR and the `johnneerdael/envision-oci` package. Keep explicit username/token and already-authenticated modes for local pushes.

Remove the obsolete Tangled publishing workflow and the Homebrew archive uploader that targets MatrixFurry's GitLab project. Retain the generic Homebrew install and uninstall helpers because they remain useful for local packaging.

## Documentation

Rewrite the README to:

- Describe this fork as maintained.
- Explain why the OCI wrapper is useful on Bazzite and Fedora Atomic desktops.
- Document the `latest`, immutable SHA, semantic-version, and `edge` channels.
- Provide Bazzite-oriented installation and update instructions.
- Document `ENVISION_OCI_IMAGE` for edge testing and rollback.
- Explain local builds and the pinned-submodule update procedure.
- Document the one-time GHCR visibility step.
- Credit the original Envision-OCI and official Envision projects.

Do not advertise the old Homebrew-XR `envision-oci` formula as an installation path because it resolves to the unmaintained upstream package and old registry image.

## Error Handling

Fail the workflow before building if the submodule cannot be initialized or its revision cannot be resolved. For edge builds, fail rather than silently falling back to the pinned revision when upstream `main` cannot be fetched.

Keep the launcher's existing pull and run error dialogs. Include the selected image reference in actionable error output where practical so failures on `latest`, `edge`, or rollback tags can be distinguished.

## Verification

Before declaring implementation complete:

1. Confirm the submodule URL and gitlink revision.
2. Confirm no active runtime or publishing path references the old GitLab registry or Tangled workflow.
3. Validate GitHub Actions workflow syntax with `actionlint` or an equivalent parser.
4. Parse or check all modified Nushell scripts with a current Nushell runtime.
5. Build the full image for `linux/amd64` from the pinned source.
6. Run `/opt/envision/bin/envision --version` from the built image and confirm that it reports the expected upstream revision suffix.
7. Inspect the built image labels, entrypoint, architecture, and default image name.
8. Review the final diff for accidental release credentials or unrelated changes.

The first actual registry push and public-visibility change occur through GitHub after the implementation is committed and pushed; local verification does not mutate GHCR.

## Out of Scope

- Publishing or maintaining a separate Homebrew tap.
- Supporting `linux/arm64`.
- Removing the launcher's privileged container mode or redesigning device/DBus isolation.
- Maintaining a downstream fork of Envision source code.
- Automatically committing upstream submodule updates to the wrapper repository.

## References

- Official Envision: https://gitlab.com/gabmus/envision
- Maintained wrapper: https://github.com/johnneerdael/envision-oci
- GitHub container publishing guidance: https://docs.github.com/en/actions/tutorials/publish-packages/publish-docker-images
- GitHub Container Registry guidance: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
