# Hydra offline toolchain

This document describes the public Linux x64 toolchain used to prepare a reproducible Hydra development environment.

The published bundle contains public runtimes, package-manager caches, compatibility metadata, and restore helpers. It is not intended to contain application source, credentials, or runtime secrets.

## Contents

The toolchain may include:

- Node.js and Yarn;
- Rust toolchain components;
- GTK4 / GTK4 Layer Shell build prerequisites;
- Yarn, Cargo, Electron, electron-builder, and node-gyp caches;
- activation, doctor, and offline-install helpers;
- integrity manifests and compatibility fingerprints.

## Restore

After downloading all parts of a toolchain generation, verify the supplied checksums before reconstruction and extraction.

Typical flow:

```bash
sha256sum -c SHA256SUMS.parts
cat hydra-toolchain-linux-x64.part-* > hydra-toolchain-linux-x64.tar.zst
sha256sum hydra-toolchain-linux-x64.tar.zst
tar --zstd -xf hydra-toolchain-linux-x64.tar.zst

source ./hydra-toolchain/scripts/activate.sh
./hydra-toolchain/scripts/doctor.sh
./hydra-toolchain/scripts/install-offline.sh /path/to/project
```

The installer should compare the target project's dependency fingerprints with the compatibility metadata bundled with the toolchain and fail closed when they do not match.

## Offline behavior

A valid toolchain generation should be able to install the supported dependency set without contacting package registries or mirrors during the offline validation phase.

Where practical, validation should cover:

- dependency restoration;
- TypeScript/type checks;
- project tests;
- Rust/Cargo resolution;
- native dependency discovery;
- representative build commands.

## Host requirements

Some system libraries remain host responsibilities. The bundled `doctor.sh` should report missing prerequisites such as Python, `pkg-config`, GTK 4, or GTK4 Layer Shell development metadata.

## Regeneration policy

Regenerate the toolchain when a material compatibility input changes, such as:

- Node or Yarn version;
- Rust toolchain requirements;
- Electron or native build dependencies;
- package-manager lockfile compatibility;
- GTK/native host requirements;
- restore or validation logic.

Small dependency changes should prefer incremental cache updates when the artifact format supports them.

## Public boundary

Documentation for this public artifact should cover only the reusable toolchain contract, integrity checks, restoration, and compatibility behavior. Private source handling, credential topology, operational handoffs, and privileged publication procedures are outside this public contract.
