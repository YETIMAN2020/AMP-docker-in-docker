# AMP-Docker-in-Docker (with Dockers inside Dockers & Dune Awakening Admin)

This is a customized, modified fork of [MitchTalmadge/AMP-dockerized](https://github.com/MitchTalmadge/AMP-dockerized). 

The primary goal of this modified version is to allow **AMP (Cubecoders Application Management Panel)** to run nested containers internally (via Podman), specifically tailored to deploy and manage a **Dune: Awakening** dedicated server on an **Unraid** host.

The **dune-admin web panel** is provided as a separate **custom AMP template**
(see [`amp-templates/dune-admin`](amp-templates/dune-admin)) that you add to AMP
and run as its own application — it is no longer built into the image. Letting
AMP manage the panel fixes the start-ordering and DB-reconnect problems the old
embedded launcher had.

Yes, it's duct-taped together. Yes, it shouldn't work. **But it does.**

---

##  Features

- **Upstream AMP Core:** Built on top of MitchTalmadge's excellent Dockerized AMP base.
- **Podman-in-Docker Capability:** Modified to allow AMP to launch and manage its own nested (Podman) containers inside an isolated environment (crucial for modern AMP game instances on Unraid).
- **Dune-Admin as an AMP app:** The [Icehunter/dune-admin](https://github.com/Icehunter/dune-admin) control panel ships as a custom AMP Generic template ([`amp-templates/dune-admin`](amp-templates/dune-admin)) so AMP downloads, configures, starts and restarts it like any other instance.

##  Unraid Deployment Notes

Because this container runs Docker daemons inside a Docker container (on top of Unraid's Slackware-based Docker host), you need to ensure proper permissions and storage drivers are configured. (just give it privleged unless u really want to sort perms out)

### Prerequisites & Template Settings

When adding this as a custom Docker container in Unraid, ensure the following configuration options are met:

also please read the setup guide for [AMP-dockerized](https://github.com/MitchTalmadge/AMP-dockerized) as it could take a got minute to get to work

1. **Privileged Mode:** You **must** turn on `Privileged` mode (`--privileged`) in your Unraid Docker template. Nested virtualization and container routing require full host kernel capabilities.
2. **Docker Storage Driver:** If you experience issues with sub-containers failing to pull or extract images, add the following environment variable to your template:
   - **Key:** `DOCKER_MODS` or override the storage driver via execution flags using `--storage-driver=overlay2` (depending on how you have your nested engine structured).
3. **Volume Mounts:** Map your AMP data directory (`/home/amp`) to a **real disk path that preserves Unix permissions**, e.g. a cache/pool path like `/mnt/cache/appdata/amp` (or a dedicated disk), and always move/restore that data with a permission-preserving tool (`cp -a`, `rsync -a`, `tar`). Copying game data without preserving permissions strips the execute bits off the server binaries and breaks startup.
4. please please please make backups this could straight up implode also store your instances outside of the main AMP docker

## Dune Admin web panel

The dune-admin panel runs as its own AMP application, not as part of this image.
See [`amp-templates/dune-admin/README.md`](amp-templates/dune-admin/README.md)
for how to add the custom template to AMP and create a Dune Admin instance.

##  Credits & Disclaimers

- Massive credit to **[MitchTalmadge](https://github.com/MitchTalmadge)** for the foundational [AMP-dockerized](https://github.com/MitchTalmadge/AMP-dockerized) architecture.
- Credit to **[Icehunter](https://github.com/Icehunter)** for the excellent [dune-admin](https://github.com/Icehunter/dune-admin) control panel integration.
- This repository is provided as-is. It is highly experimental, heavily tailored for Unraid environments, and might require manual troubleshooting if nested image registries implode.
