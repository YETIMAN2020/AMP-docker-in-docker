# Dune Admin — custom AMP template

This is a CubeCoders AMP **Generic module** template that runs the
[dune-admin](https://github.com/Icehunter/dune-admin) web panel as its own
AMP-managed application instead of baking it into the container image.

Letting AMP own the panel means AMP handles its **download, configuration,
start/stop, start-on-boot ordering and automatic restarts** — which fixes the
boot-timing and DB-reconnect problems the old embedded launcher had (dune-admin
used to start before the Dune server's PostgreSQL was ready and get stuck).

## Files

| File | Purpose |
|------|---------|
| `dune-admin.kvp` | Main application definition |
| `dune-adminconfig.json` | Settings shown in the AMP UI (mapped into `config.yaml`) |
| `dune-adminmetaconfig.json` | Maps settings to dune-admin's `config.yaml` |
| `dune-adminports.json` | Web UI port |
| `dune-adminupdates.json` | Downloads the dune-admin binary from GitHub releases |

## Prerequisites

- The **Podman** variant of this image (`Dockerfile.podman`), running AMP.
- A working, **containerized** Dune: Awakening server instance managed by AMP
  (e.g. `Arrakis01`) — dune-admin controls that instance.
- The Dune server's PostgreSQL reachable at `127.0.0.1:15432` (the default with
  host networking).

## Installing the template into AMP

Pick one method.

### Method A — Configuration Repository (recommended, auto-updates)

AMP loads templates from the **root** of a Git repository. Because this repo
keeps the files under `amp-templates/dune-admin/`, copy the five files to the
**root of a repository/branch you control**, then:

1. In AMP go to **Configuration → Instance Deployment**.
2. **Add** a **Configuration Repository**.
3. Enter it as `user/repo:branch` (e.g. `youruser/amp-templates:main`).
4. Refresh the application list; **Dune Admin** appears when creating an instance.

### Method B — Fully local (no GitHub)

Copy the five template files into a `LOCAL…-main` folder inside your ADS
instance's deployment templates directory, then refresh. Inside the container
(replace `ADS01` with your controller instance's name if different):

```bash
DEST=/home/amp/.ampdata/instances/ADS01/Plugins/ADSModule/DeploymentTemplates/LOCALduneadmin-main
mkdir -p "$DEST"
cp dune-admin.kvp dune-adminconfig.json dune-adminmetaconfig.json \
   dune-adminports.json dune-adminupdates.json "$DEST"/
chown -R amp:amp /home/amp/.ampdata/instances/ADS01/Plugins/ADSModule/DeploymentTemplates
```

Then in AMP, refresh the instance-deployment/application list.

## Creating and configuring the Dune Admin instance

1. Create a new instance and choose the **Dune Admin** application.
   - **Do not run it in a container** — it must run natively so it can reach
     the Dune server's PostgreSQL and drive it with `podman`/`ampinstmgr` as the
     `amp` user. The template declares `ContainerPolicy=NotSupported`, so AMP
     should keep it native; if your global default is "create in containers",
     turn that off for this instance.
2. Open the instance's **Configuration** and set:
   - **Server Control**: `AMP Instance Name` / `AMP Container Name` to match your
     Dune server (`Arrakis01` / `AMP_Arrakis01` by default), `Container Runtime`
     = Podman.
   - **Database**: usually the defaults (`127.0.0.1:15432`, `dune`/`dune`/`dune`).
   - **Web Interface**: set **Require Login = Yes** and provide a username +
     bcrypt password hash (generate one by running `./dune-admin --set-password`
     in the instance directory). dune-admin has full control of your server —
     don't expose it without a login.
3. **Update** the instance (downloads the dune-admin binary + `item-data.json`).
   Leave the `dune-admin Version` blank for the latest release, or pin a tag
   like `v0.44.2`.
4. **Start** it. AMP assigns the web port (default 18080); the panel is at
   `http://<host>:<port>/`.

Set the instance to **start on boot** and, if you use AMP's scheduler, order it
to start after the Dune server so PostgreSQL is ready first.

## How settings map

AMP writes the settings above into a `config.yaml` in the instance directory
(via the metaconfig auto-map). dune-admin is pointed at that directory with the
`DUNE_ADMIN_CONFIG_DIR` environment variable, and its port is set with
`LISTEN_ADDR` — both defined in `dune-admin.kvp`.

## Notes / troubleshooting

- This template is community/best-effort and may need small tweaks for your AMP
  version (built against the Generic module format used by AMP 2.6+). If the
  panel doesn't reach the **Ready** state, check the instance console/log.
- `dune-admin listening addr=…` in the log is what AMP watches for "Ready".
- If the app won't start because it's containerized, recreate the instance with
  containers disabled (see step 1).
- The panel needs the Dune server (and its PostgreSQL) up to connect; because
  AMP manages it now, just (re)start the Dune Admin instance after the Dune
  server is running.
