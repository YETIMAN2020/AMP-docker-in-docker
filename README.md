> [!CAUTION]
> **This is a community-made unofficial image, and is NOT endorsed by CubeCoders.**
> **Please DO NOT ask CubeCoders for support if you use this image. They do not support nor endorse this image and will understandably tell you that you are on your own.**
> 
> This project is community driven by people who have full time responsibilities elsewhere. You should be able to navigate Docker, Linux, bash, etc. and feel comfortable debugging containers on your own if you intend to use this image. I will help if I get time, but I have a full time job and some family and kitty cats that I want to hang out with! 😸
>
> That said, if you have time and are able to help, please feel free! I love PRs!

> [!NOTE]  
> A lack of commits & releases does not mean this project is dead. This image is effectively an "operating system" for AMP to run on. AMP itself can be updated through its web UI at any time. Infrequently, we may need to push a new image update to support a new version of AMP.

# AMP-dockerized
This repository bundles [CubeCoders AMP](https://cubecoders.com/AMP) into a Debian-based [Docker image.](https://hub.docker.com/r/mitchtalmadge/amp-dockerized)
(`mitchtalmadge/amp-dockerized:latest`) so that you can set up game servers with ease! 

In a nutshell, AMP (Application Management Panel) allows you to manage one or more game servers from a web UI. You need a [CubeCoders AMP Licence](https://cubecoders.com/AMP) to use AMP; this image does not bypass that requirement.

> [!WARNING]
> **This is a community-made unofficial image, and is not endorsed by CubeCoders.**

# Getting Help

You can make an issue if you need help, but I am not always available for quick assistance. Using AMP in this unofficial docker container is an advanced endeavour and you may need to do a little self-debugging and experimentation. Please remember to make backups of important data.

If you need help with AMP when using this image, please [create an issue](https://github.com/MitchTalmadge/AMP-dockerized/issues/new) in this repository.

If you have coding skills and find this repository useful, please consider helping out by answering questions in the issues or making pull requests to fix bugs. I really can't do this alone.

> [!WARNING]
> **Please DO NOT ask CubeCoders for support. They do not support nor endorse this image and will tell you that you are on your own.**

## Unraid Support
If you are using Unraid, you may want to check out the [support topic](https://forums.unraid.net/topic/98290-support-amp-application-management-panel-corneliousjd-repo/) on their forums.

This image works great on Unraid and I even bought the software just to make sure it worked (and now I use Unraid for all sorts of things!)

> [!WARNING]
> If you are using an automatic Docker-image updater on Unraid, please exclude this image. I would strongly prefer that everyone read my changelogs before updating.

I will try to help out where I am able.
 
# Supported Game Servers

**Tested and Working:**

- Factorio
- Garry's Mod (GMod)
- McMyAdmin 
- Minecraft Java Edition
- Minecraft Bedrock Edition
- Satisfactory
- StarBound
- Team Fortress 2
- Valheim
 
**Untested:**
 
- Basically everything else. Please see [CubeCoders' own compatibility list](https://discourse.cubecoders.com/t/supported-applications-compatibility/1828). If it runs on Linux according to this table, it _should_ work on this image. Probably.

If you are able to get an untested game working, let me know so I can help make an example for everyone else!

If you are *not* able to get a game working, make an issue and we can work together to figure out a solution!

# Configuration

I recommend using Unraid or Docker Compose to set up the image. You could also just use `docker run`. [Example scripts and configurations can be found here.](./examples).

## MAC Address (Required! Please read!)
> [!CAUTION]
> You must follow these instructions or AMP will be de-activated every time it boots!

AMP is designed to detect hardware changes and will de-activate all instances when something significant changes. By default, Docker assigns a new MAC address to a container every time it is restarted, which is detected as a significant change, and triggers a licence key reset. Therefore, unless you want to painstakingly re-activate all your instances on every server reboot, you need to assign a permanent MAC address.

For most people, this can be accomplished by generating a random MAC address in Docker's acceptable range.
The instructions to do so are as follows:

1. Visit this page: https://miniwebtool.com/mac-address-generator/
2. Put `02:42:AC` in as the prefix
3. Choose the format with colons `:`
4. Generate
5. Copy the generated MAC and use it when starting the container.
   - For `docker run`, use the following flag: (Substitute your generated MAC)
  
    `--mac-address="02:42:AC:XX:XX:XX"`
   - For Docker Compose, you need to add a `networks` section like so:
  
    ```yaml
    # Your config may look a little different -- focus on the networks section
    services:
      amp:
        image: mitchtalmadge/amp-dockerized
        networks:
          default:
            mac_address: 02:42:AC:XX:XX:XX
        ...
    ```
    
If you have a unique network situation, a random MAC may not work for you. In that case you will need to come up with your own solution to prevent address conflicts.

Please refer to the [example configurations](./examples) if needed.

For additional help with any of this, please make an issue.

## Ports

When using this image, you need to configure Docker ahead of time to expose the ports that your game servers will use. Any changes to the port mappings will require the container to be restarted.

You can find most game server ports on the [Port Forward](https://portforward.com/ports/) website. Alternatively, you could google "[game name] server ports".

For example, with Minecraft, click on the "M" section, then scroll to "Minecraft: Java Edition Server". The ports listed are `TCP: 25565, UDP: 25565`. In this case, you would need to map both TCP and UDP port `25565` from the container to the host:

- For Unraid, you would create two port mappings for `25565`; one using TCP and one using UDP.
- For Docker Compose, you need to add a `ports` section like so:
  ```yaml
  # Your config may look a little different; focus on the ports section
  services:
    amp:
      image: mitchtalmadge/amp-dockerized
      ports:
        - "25565:25565/tcp"
        - "25565:25565/udp"
      ...
  ```
- For `docker run`, use the following flags:
  `-p 25565:25565/tcp -p 25565:25565/udp`


> [!IMPORTANT]
> Make sure you are using the right protocol. If you accidentally map a TCP port for a UDP game, you won't be able to connect!

## Environment Variables

### User/Group

| Name  | Description                                                          | Default Value |
|-------|----------------------------------------------------------------------|---------------|
| `UID` | The ID of the user (on the host) who will own the ampdata volume.    | `1000`        |
| `GID` | The ID of the group for the user above.                              | `1000`        |

When not specified, these both default to ID `1000`; i.e. the first non-system user on the host.

### Timezone
| Name | Description                                                          | Default Value |
|------|----------------------------------------------------------------------|---------------|
| `TZ` | The timezone to use in the container. Pick from the "TZ database name" column on [this page](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)   | `Etc/UTC`        |

Example: `TZ=America/Denver`

### Web UI

| Name       | Description                                                                                                                                             | Default Value |
|------------|---------------------------------------------------------------------------------------------------------------------------------------------------------|---------------|
| `PORT`     | The port of the Web UI for the main instance. Since you can map this to any port on the host, there's hardly a reason to change it.                     | `8080`        |
| `IPBINDING`| Which IP address the main instance will bind to. In almost all cases you should leave this as the default, unless you are doing something advanced.     | `0.0.0.0`     |
| `USERNAME` | The username of the admin user created on first boot.                                                                                                   | `admin`       |
| `PASSWORD` | The password of the admin user. This value is only used when creating the new user. If you use the default value, please change it after first sign-in. | `password`    |

### Auto-Update
| Name              | Description                                                                                     | Default Value |
|-------------------|-------------------------------------------------------------------------------------------------|---------------|
| `AMP_AUTO_UPDATE` | Set to `false` if you would like to disable automatic updates on container reboot. You will still be able to update AMP manually through the web UI. | `true`        |

By default, AMP will automatically update when this container reboots. You can update AMP using the web UI as well - AMP will alert you when an update is available through its UI. The updates to this container image are not directly tied to AMP updates. Think of this container more like an all-in-one "operating system" for AMP. New versions of this container are only necessary when AMP is not working correctly. If you would like to disable automatic updates on container reboot, you can set `AMP_AUTO_UPDATE` to `false`.

## Volumes

> [!CAUTION]
> If you do not set up a volume as described, your game data will be wiped every time the container updates.

| Mount Point  | Description                                                                                                                                                                                                                  |
|--------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `/home/amp/` | **Required!** This volume contains everything AMP needs to run. This includes all your instances, all their game & save files, the web UI sign-in info, etc. Without creating this volume, AMP would be wiped on every boot. |

# Podman Variant (Containerized Instances)

AMP can run its instances "in a container" (the *Runs in Container* option), which internally uses [Podman](https://podman.io/). Because this image itself runs inside Docker, getting Podman working inside it normally requires manually installing Podman and re-applying a few fixes **every time the container is recreated or updated**.

To avoid that, this repository provides a **Podman variant** ([`Dockerfile.podman`](./Dockerfile.podman)) that bakes Podman and the required fixes into the image, so they persist across container rebuilds. Build it yourself with:

```bash
docker build -f Dockerfile.podman -t amp-dockerized:podman .
```

Then use `amp-dockerized:podman` as your image in the examples below.

> [!NOTE]
> If you don't use AMP's "containerized" instances, you don't need this variant. Stick with the regular `mitchtalmadge/amp-dockerized:latest` image.

## What the Podman variant does for you

- **Installs Podman** (and the packages needed to run it rootless inside a container), so you never have to reinstall it after a rebuild.
- **Pre-configures the container registry** by baking in `/etc/containers/registries.conf` with `unqualified-search-registries = ["docker.io"]`, so "short-name" images (like `cubecoders/ampbase:debian`) resolve correctly.
- **Sets up subuid/subgid ranges** for the `amp` user at startup, which rootless Podman requires.
- **Applies the shared-mount fix** (`mount --make-rshared /`) at startup, which resolves the `"/" is not a shared mount` error.

The registry, subuid/subgid, and shared-mount fixes are applied automatically on every boot by the entrypoint, so they always stay in place.

## Host permissions (required!)

Podman needs permission to create user namespaces. This is the one thing that **cannot** be baked into the image; you must grant it when starting the container. Choose **one** of the following:

- **Privileged mode:** Turn on the *Privileged* toggle (Unraid) or add `--privileged` (`docker run`) / `privileged: true` (Compose).
- **Least privilege (recommended):** Add the following instead of privileged mode:
  - `docker run`: `--cap-add=SYS_ADMIN --security-opt seccomp=unconfined`
  - Compose:
    ```yaml
    cap_add:
      - SYS_ADMIN
    security_opt:
      - seccomp=unconfined
    ```
  - Unraid *Extra Parameters* box: `--cap-add=SYS_ADMIN --security-opt seccomp=unconfined`

It also helps to pass `/dev/fuse` into the container so Podman can use the `fuse-overlayfs` storage driver.

## Unraid notes

On Unraid, in addition to the permission flags above, set your AMP data path mapping's **Access Mode** to **Read/Write: Shared** (`RW: Shared`). This is the Unraid-side equivalent of the shared-mount fix and prevents the `"/" is not a shared mount` warning.

See [`examples/docker-compose.podman.yml`](./examples/docker-compose.podman.yml) and [`examples/docker-run.podman.sh`](./examples/docker-run.podman.sh) for complete examples.

## dune-admin (Dune: Awakening admin panel)

The Podman variant also bundles [**dune-admin**](https://github.com/Icehunter/dune-admin), an optional web admin panel for a Dune: Awakening private server managed by AMP (players, inventory, world, market bot, database, server settings, start/stop/restart, log streaming). Because it's baked into the image, updating the image updates dune-admin — no reinstalling after a container rebuild.

It is **off by default**. Enable it with `DUNE_ADMIN_ENABLED=true` and configure it with the environment variables below. When enabled, the entrypoint writes `~/.dune-admin/config.yaml` (under `/home/amp`, so it persists on your volume) and launches dune-admin after AMP starts, using the `amp` provider (it runs `ampinstmgr`/`podman` via `sudo` as the AMP user).

| Name | Description | Default |
|------|-------------|---------|
| `DUNE_ADMIN_ENABLED` | Set to `true` to run dune-admin. | `false` |
| `DUNE_ADMIN_PORT` | Port for the dune-admin web UI. | `18080` |
| `DUNE_ADMIN_INSTANCE` | AMP instance name of your Dune server (from `ampinstmgr -l`). | `Arrakis01` |
| `DUNE_ADMIN_CONTAINER` | Podman container name for the instance. | `AMP_<instance>` |
| `DUNE_ADMIN_DB_HOST` / `_PORT` / `_USER` / `_PASS` / `_NAME` / `_SCHEMA` | Game PostgreSQL connection. | `127.0.0.1` / `15432` / `dune` / `dune` / `dune` / `dune` |
| `DUNE_ADMIN_API_USER` / `_PASS` / `_PORT` | AMP panel login used only for the Server Settings tab (the instance's ADS API). | *(unset)* / *(unset)* / `8086` |
| `DUNE_ADMIN_AUTH_USER` | Dashboard login username (enables auth when set with the hash below). | *(unset)* |
| `DUNE_ADMIN_AUTH_PASSWORD_HASH` | bcrypt hash of the dashboard password (`dune-admin --set-password` prints one). | *(unset)* |

> [!CAUTION]
> dune-admin has **full control** of your game server (edit inventories, run SQL, restart). If auth is not configured, anyone who can reach `DUNE_ADMIN_PORT` has that control. Set `DUNE_ADMIN_AUTH_USER` + `DUNE_ADMIN_AUTH_PASSWORD_HASH` (or configure Discord OAuth in `~/.dune-admin/config.yaml`) before exposing it.

With Host networking, the panel is reachable directly at `http://<host-ip>:<DUNE_ADMIN_PORT>`. On bridge networking, map the port like any other. To pin/upgrade the dune-admin version, rebuild the image with `--build-arg DUNE_ADMIN_VERSION=vX.Y.Z`.

### Unraid template

An Unraid container template with all of the above already laid out as editable fields (AMP data path, UID/GID/TZ, the Podman permission flags, and every `DUNE_ADMIN_*` option) lives at [`unraid/amp-dockerized-podman.xml`](./unraid/amp-dockerized-podman.xml). To use it, copy it into `/boot/config/plugins/dockerMan/templates-user/` on your Unraid server (edit the `<Repository>` to point at your published image first), then in the Unraid **Docker** tab choose **Add Container → Template: AMP-Podman**. The dune-admin port and options then appear as normal fields, so you can change them without adding variables by hand.

# Advanced Configuration
Please see the [advanced configuration wiki page](https://github.com/MitchTalmadge/AMP-dockerized/wiki/Advanced-Configuration) for more that you can do with this container.

# Contributing

I welcome contributors! Just open an issue first, or post in one of the contibution welcome / help wanted issues, so that we can discuss before you start coding. Thank you for helping!! 

