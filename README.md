# AMP-Docker-in-Docker (with Dockers inside Dockers & Dune Awakening Admin)

This is a customized, modified fork of [MitchTalmadge/AMP-dockerized](https://github.com/MitchTalmadge/AMP-dockerized). 

The primary goal of this modified version is to allow **AMP (Cubecoders Application Management Panel)** to run nested Docker containers internally, specifically tailored to deploy and manage a **Dune: Awakening** dedicated server on an **Unraid** host.

As an added bonus of absolute "jank,and duct tape" this image also pre-scripts and embeds the **DUNE-Admin web panel** directly into the container. 

Yes, it's duct-taped together. Yes, it shouldn't work. **But it does.**

---

##  Features

- **Upstream AMP Core:** Built on top of MitchTalmadge's excellent Dockerized AMP base.
- **Docker-in-Docker (DinD) Capability:** Modified to allow AMP to launch and manage its own sub-containers inside an isolated environment (crucial for modern AMP game instances on Unraid).
- **Embedded Dune-Admin:** Includes the custom web management panel scripted by [Icehunter/dune-admin](https://github.com/Icehunter/dune-admin) to control your Dune server instance out of the box.

##  Unraid Deployment Notes

Because this container runs Docker daemons inside a Docker container (on top of Unraid's Slackware-based Docker host), you need to ensure proper permissions and storage drivers are configured. (just give it privleged unless u really want to sort perms out)

### Prerequisites & Template Settings

When adding this as a custom Docker container in Unraid, ensure the following configuration options are met:

also please read the setup guide for [AMP-dockerized](https://github.com/MitchTalmadge/AMP-dockerized) as it could take a got minute to get to work

1. **Privileged Mode:** You **must** turn on `Privileged` mode (`--privileged`) in your Unraid Docker template. Nested virtualization and container routing require full host kernel capabilities.
2. **Docker Storage Driver:** If you experience issues with sub-containers failing to pull or extract images, add the following environment variable to your template:
   - **Key:** `DOCKER_MODS` or override the storage driver via execution flags using `--storage-driver=overlay2` (depending on how you have your nested engine structured).
3. **Volume Mounts:** Ensure your AMP data directory (`/home/amp/.ampdata`) is mapped to a fast cache pool user share (e.g., `/mnt/user/appdata/amp-dind/`) to prevent nested disk I/O bottlenecks.
4. please please please make backups this could straight up implode also store your instances outside of the main AMP docker

## 📜 Credits & Disclaimers

- Massive credit to **[MitchTalmadge](https://github.com/MitchTalmadge)** for the foundational [AMP-dockerized](https://github.com/MitchTalmadge/AMP-dockerized) architecture.
- Credit to **[Icehunter](https://github.com/Icehunter)** for the excellent [dune-admin](https://github.com/Icehunter/dune-admin) control panel integration.
- This repository is provided as-is. It is highly experimental, heavily tailored for Unraid environments, and might require manual troubleshooting if nested image registries implode.
