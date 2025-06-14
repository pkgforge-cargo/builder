<div align="center">

[discord-shield]: https://img.shields.io/discord/1313385177703256064?logo=%235865F2&label=discord
[discord-url]: https://discord.gg/djJUs48Zbu
[doc-shield]: https://img.shields.io/badge/docs-soar.qaidvoid.dev-blue
[doc-url]: https://soar.qaidvoid.dev
[issues-shield]: https://img.shields.io/github/issues/pkgforge-cargo/builder.svg
[issues-url]: https://github.com/pkgforge-cargo/builder/issues
[license-shield]: https://img.shields.io/github/license/pkgforge-cargo/builder.svg
[license-url]: https://github.com/pkgforge-cargo/builder/blob/main/LICENSE
[stars-shield]: https://img.shields.io/github/stars/pkgforge-cargo/builder.svg
[stars-url]: https://github.com/pkgforge-cargo/builder/stargazers

[![Discord][discord-shield]][discord-url]
[![Documentation][doc-shield]][doc-url]
[![Issues][issues-shield]][issues-url]
[![License: MIT][license-shield]][license-url]
[![Stars][stars-shield]][stars-url]

</div>

<p align="center">
    <a href="https://soar.qaidvoid.dev/installation">
        <img src="https://soar.pkgforge.dev/gif?version=v0.6.3" alt="soar-list" width="750">
    </a><br>
</p>

<h4 align="center">
  <a href="https://soar.qaidvoid.dev">📘 Documentation</a> |
  <a href="https://docs.pkgforge.dev">🔮 PackageForge</a>
</h4>

<p align="center">
    Soar is a Fast, Modern, Bloat-Free Distro-Independent Package Manager that <a href="https://docs.pkgforge.dev/soar/comparisons"> <i>Just Works</i></a><br>
    Supports <a href="https://docs.pkgforge.dev/formats/binaries/static">Static Binaries</a>, <a href="https://docs.pkgforge.dev/formats/packages/appimage">AppImages</a>, and other <a href="https://docs.pkgforge.dev/formats/packages">Portable formats</a> on any <a href="https://docs.pkgforge.dev/repositories/soarpkgs/faq#portability"><i>*Unix-based</i> Distro</a>
</p>


## ℹ️ About

This repo, builds [top crates](https://github.com/pkgforge-cargo/builder/blob/main/data/CRATES_DUMP.json) from [crates.io](https://crates.io/) as Statically Linked relocatable binaries for `aarch64-Linux`, `loongarch64-Linux`, `riscv64-Linux` & `x86_64-Linux`.<br>
The [build script](https://github.com/pkgforge-cargo/builder/blob/main/scripts/builder.sh) uses [Cross](https://github.com/cross-rs/cross) to compile the crates on [Github Actions](https://github.com/pkgforge-cargo/builder/actions) & then uploads the artifacts to [ghcr.io](https://github.com/orgs/pkgforge-cargo/packages?repo_name=builder) using [Oras](https://github.com/oras-project/oras).<br>
All of which are downloadable & installable with soar by adding `pkgforge-cargo` as an [external repo](https://docs.pkgforge.dev/repositories/external/pkgforge-cargo).

## 🧰 Stats
> [!NOTE]
> ℹ️ It is usual for most workflow run to `fail` since it's rare a crate builds for ALL `hosts`<br>
> 🗄️ Table of Crates (Sorted by Rank): https://github.com/pkgforge-cargo/builder/blob/main/data/CRATES_PROCESSED.md<br>

| Source 🗃️ | Total Packages 📦 |
|------------|-------------------|
| 🦀 [**Crates (`Total`)**](https://github.com/pkgforge-cargo/builder/blob/main/data/CRATES_DUMP.json) | [![Packages](https://img.shields.io/badge/dynamic/json?url=https://raw.githubusercontent.com/pkgforge-cargo/builder/refs/heads/main/data/COUNT.json&query=$[0].total&label=&color=crimson&style=flat)](#) |
| 🦀 [**Crates (`Bin Only`)**](https://github.com/pkgforge-cargo/builder/blob/main/data/CRATES_BIN_ONLY.json) | [![Packages](https://img.shields.io/badge/dynamic/json?url=https://raw.githubusercontent.com/pkgforge-cargo/builder/refs/heads/main/data/COUNT.json&query=$[1].total&label=&color=orange&style=flat)](#) |
| 🦀 [**Crates (`Processed`)**](https://github.com/pkgforge-cargo/builder/blob/main/data/CRATES_PROCESSED.json) | [![Packages](https://img.shields.io/badge/dynamic/json?url=https://raw.githubusercontent.com/pkgforge-cargo/builder/refs/heads/main/data/COUNT.json&query=$[2].total&label=&color=purple&style=flat)](#) |
| 🦀 [**Crates (`Built`)**](https://github.com/pkgforge-cargo/builder/blob/main/data/CRATES_BUILT.json) | [![Packages](https://img.shields.io/badge/dynamic/json?url=https://raw.githubusercontent.com/pkgforge-cargo/builder/refs/heads/main/data/COUNT.json&query=$[3].total&label=&color=blue&style=flat)](#) |
| 🦀 [**Packages (`aarch64-Linux`)**](https://github.com/pkgforge-cargo/builder/blob/main/data/aarch64-Linux.json) | [![Packages](https://img.shields.io/badge/dynamic/json?url=https://raw.githubusercontent.com/pkgforge-cargo/builder/refs/heads/main/data/COUNT.json&query=$[4].total&label=&color=green&style=flat)](#) |
| 🦀 [**Packages (`loongarch64-Linux`)**](https://github.com/pkgforge-cargo/builder/blob/main/data/loongarch64-Linux.json) | [![Packages](https://img.shields.io/badge/dynamic/json?url=https://raw.githubusercontent.com/pkgforge-cargo/builder/refs/heads/main/data/COUNT.json&query=$[5].total&label=&color=green&style=flat)](#) |
| 🦀 [**Packages (`riscv64-Linux`)**](https://github.com/pkgforge-cargo/builder/blob/main/data/riscv64-Linux.json) | [![Packages](https://img.shields.io/badge/dynamic/json?url=https://raw.githubusercontent.com/pkgforge-cargo/builder/refs/heads/main/data/COUNT.json&query=$[6].total&label=&color=green&style=flat)](#) |
| 🦀 [**Packages (`x86_64-Linux`)**](https://github.com/pkgforge-cargo/builder/blob/main/data/x86_64-Linux.json) | [![Packages](https://img.shields.io/badge/dynamic/json?url=https://raw.githubusercontent.com/pkgforge-cargo/builder/refs/heads/main/data/COUNT.json&query=$[7].total&label=&color=green&style=flat)](#) |
| 🦀 [**Packages (`Total`)**](#) | [![Packages](https://img.shields.io/badge/dynamic/json?url=https://raw.githubusercontent.com/pkgforge-cargo/builder/refs/heads/main/data/COUNT.json&query=$[8].total&label=&color=teal&style=flat)](#) |

## 🟢 Workflow
```mermaid
graph TD
    A[crates.io] -->|Top Crates List| B[CRATES_DUMP.json]
    B --> C[GitHub Repository<br/>pkgforge-cargo/builder]
    
    C --> D[Build Script<br/>builder.sh]
    D --> E[Cross Compiler]
    
    E --> F1[aarch64-Linux<br/>Static Binary]
    E --> F2[loongarch64-Linux<br/>Static Binary] 
    E --> F3[riscv64-Linux<br/>Static Binary]
    E --> F4[x86_64-Linux<br/>Static Binary]
    
    F1 --> G[GitHub Actions<br/>Build Pipeline]
    F2 --> G
    F3 --> G
    F4 --> G
    
    G --> H[Oras Tool]
    H --> I[ghcr.io<br/>Container Registry]
    
    I --> J[External Repository<br/>pkgforge-cargo]
    J --> K[Soar Package Manager]
    K --> L[End Users]
    
    style A fill:#ff6b6b,stroke:#333,stroke-width:2px,color:#fff
    style I fill:#4ecdc4,stroke:#333,stroke-width:2px,color:#fff
    style K fill:#45b7d1,stroke:#333,stroke-width:2px,color:#fff
    style L fill:#96ceb4,stroke:#333,stroke-width:2px,color:#fff
    
    classDef buildProcess fill:#ffd93d,stroke:#333,stroke-width:2px
    class D,E,G,H buildProcess
    
    classDef binary fill:#ff8fab,stroke:#333,stroke-width:2px,color:#fff
    class F1,F2,F3,F4 binary
```

## 🤖 Hosts
- `aarch64-Linux`
- `loongarch64-Linux`
- `riscv64-Linux`
- `x86_64-Linux`
