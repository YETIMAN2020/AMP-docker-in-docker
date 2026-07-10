#!/bin/bash

check_data_volume() {
  # Starting with V24, we recommend that users mount /home/amp instead of /home/amp/.ampdata. 
  # This function allows existing users to simply change their mount point in the container, 
  # without needing to do any complicated remapping of their host data.
  echo "Checking data volume..."

  local AMP_HOME="/home/amp"
  local AMP_DATA_DIR="${AMP_HOME}/.ampdata"
  local AMP_DOCKERIZED_DIR="${AMP_DATA_DIR}/.amp-dockerized"
  local LEGACY_INSTANCES_JSON="${AMP_HOME}/instances.json"
  local LEGACY_INSTANCES_DIR="${AMP_HOME}/instances"

  if [ -f "${LEGACY_INSTANCES_JSON}" ] || [ -d "${LEGACY_INSTANCES_DIR}" ]; then
    echo "Updated data volume detected. Migration is required."
    # At this point we have detected that the contents of .ampdata are mapped to /home/amp, which is expected for V24 volume migration.
    # For example, the volume mount may have changed from:
    #     /mnt/user/appdata/amp:/home/amp/.ampdata 
    # to...
    #     /mnt/user/appdata/amp:/home/amp
    if [ -d "${AMP_DATA_DIR}" ]; then # This can happen if the new volume (/home/amp) was accidentally mounted on image v23 or earlier.
      if [ ! -z "$(ls -A "${AMP_DATA_DIR}")" ]; then # Something is very odd if .ampdata is not empty.
        echo "Error: Need to migrate data (${LEGACY_INSTANCES_DIR} and ${LEGACY_INSTANCES_JSON}), but ${AMP_DATA_DIR} is not empty. Please resolve this conflict manually. For help, visit https://github.com/MitchTalmadge/AMP-dockerized/discussions/247"
        exit 1
      fi
      echo "Empty .ampdata directory detected. Removing..."
      rmdir "${AMP_DATA_DIR}"
    fi
    
    echo "Beginning data migration..."
    mkdir -p "${AMP_DATA_DIR}"

    find "${AMP_HOME}" -mindepth 1 -maxdepth 1 \
      ! -name '.ampdata' \
      ! -name 'scripts' \
      -exec mv {} "${AMP_DATA_DIR}" \;

    # For future use, we will leave a fingerprint indicating that a migration took place
    mkdir -p "${AMP_DOCKERIZED_DIR}"
    touch "${AMP_DOCKERIZED_DIR}/.v24_volume_migrated"

    echo "Migration complete."
  fi

  echo "Data volume is ok!"
}

check_file_permissions() {
  echo "Checking file permissions..."
  chown -R ${APP_USER}:${APP_GROUP} /home/amp
}

configure_main_instance() {
  echo "Checking ADS instance existence..."
  if ! does_main_instance_exist; then
    echo "Creating ADS instance... (This can take a while)"
    run_amp_command "QuickStart \"${USERNAME}\" \"${PASSWORD}\" \"${IPBINDING}\" \"${PORT}\"" | consume_progress_bars
    if ! does_main_instance_exist; then
      handle_error "Failed to create ADS instance. Please check your configuration."
    fi
  fi

  local main_name
  main_name=$(get_main_instance_name)

  echo "Setting ADS instance to start on boot..."
  run_amp_command "ShowInstanceInfo ${main_name}" | grep "Start on Boot" | grep -q "No" && run_amp_command "SetStartBoot ${main_name} yes" || true
}

configure_release_stream() {
  echo "Setting release stream to ${AMP_RELEASE_STREAM}..."
  # Example Output from ShowInstancesList:
  # [Info] AMP Instance Manager v2.4.5.4 built 26/06/2023 18:20
  # [Info] Stream: Mainline / Release - built by CUBECODERS/buildbot on CCL-DEV
  # Instance ID        │ 295e9fc7-9987-4e4e-94a6-183cb04de459
  # Module             │ ADS
  # Instance Name      │ Main
  # Friendly Name      │ Main
  # URL                │ http://127.0.0.1:8080/
  # Running            │ No
  # Runs in Container  │ No
  # Runs as Shared     │ No
  # Start on Boot      │ Yes
  # AMP Version        │ 2.4.5.4
  # Release Stream     │ Mainline
  # Data Path          │ /home/amp/.ampdata/instances/Main
  run_amp_command "ShowInstancesList" | grep "Instance Name" | awk '{ print $4 }' | while read -r INSTANCE_NAME; do
    local RELEASE_STREAM=$(run_amp_command "ShowInstanceInfo \"${INSTANCE_NAME}\"" | grep "Release Stream" | awk '{ print $4 }')
    if [ "${RELEASE_STREAM}" != "${AMP_RELEASE_STREAM}" ]; then
      echo "Changing release stream of ${INSTANCE_NAME} from ${RELEASE_STREAM} to ${AMP_RELEASE_STREAM}..."
      run_amp_command "ChangeInstanceStream \"${INSTANCE_NAME}\" ${AMP_RELEASE_STREAM} True" | consume_progress_bars
      # Since we changed release streams we have to force an upgrade
      run_amp_command "UpgradeInstance \"${INSTANCE_NAME}\"" | consume_progress_bars
    fi
  done
}

configure_podman() {
  # Only relevant for the Podman-enabled image variant (built from Dockerfile.podman).
  # On the base image, Podman is not installed and this is a no-op.
  # AMP uses Podman to run "containerized" instances. Running Podman from inside
  # this Docker container needs a few fixes; we apply the runtime-only ones here
  # so they survive every container rebuild.
  if ! command -v podman >/dev/null 2>&1; then
    return 0
  fi

  echo "Configuring Podman..."

  # 0. Stale boot-ID cleanup. Podman records the host's boot ID in its transient
  #    runtime dir (runroot). Docker keeps the container's writable layer across
  #    restarts, so after a host reboot or container restart that runroot survives
  #    with the old boot ID and Podman fails with:
  #      "current system boot ID differs from cached boot ID"
  #    Clearing the transient runroot on startup fixes this. It does NOT touch the
  #    persistent image/container storage (graphroot lives under the AMP user's home).
  echo "Clearing stale Podman runtime directories..."
  rm -rf /tmp/storage-run-* /tmp/podman-run-* /tmp/containers-user-* 2>/dev/null || true

  # 1. Registry fix (also baked into the image): clean Podman installs don't know
  #    where to look for "short-name" images (e.g. cubecoders/ampbase:debian)
  #    without a default unqualified search registry. Applied idempotently here in
  #    case the file was removed or overridden by a mounted volume.
  local REGISTRIES_CONF="/etc/containers/registries.conf"
  if ! grep -qs '^[[:space:]]*unqualified-search-registries' "${REGISTRIES_CONF}"; then
    echo "Setting unqualified-search-registries in ${REGISTRIES_CONF}..."
    mkdir -p /etc/containers
    echo 'unqualified-search-registries = ["docker.io"]' >>"${REGISTRIES_CONF}"
  fi

  # 2. Rootless Podman (AMP runs Podman as the amp user) needs subuid/subgid
  #    ranges mapped for that user. The amp user is created at runtime with a
  #    user-provided UID/GID, so we ensure the ranges exist here.
  ensure_subid_range /etc/subuid "${APP_USER}"
  ensure_subid_range /etc/subgid "${APP_USER}"

  # 3. Shared mount fix: Podman needs "/" to be a shared mount so it can set up
  #    its own mount namespaces (otherwise you get: "/" is not a shared mount).
  #    This requires SYS_ADMIN, so run the container with --privileged OR
  #    --cap-add=SYS_ADMIN --security-opt seccomp=unconfined.
  if ! mount --make-rshared / 2>/dev/null; then
    echo "Warning: Could not make \"/\" a shared mount. AMP \"containerized\" (Podman) instances may fail to start."
    echo "         Run this container with --privileged, or --cap-add=SYS_ADMIN --security-opt seccomp=unconfined."
  fi

  echo "Podman configured!"
}

configure_timezone() {
  echo "Configuring timezone..."
  ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ >/etc/timezone
  dpkg-reconfigure --frontend noninteractive tzdata
}

ensure_subid_range() {
  # Ensures a subordinate UID/GID range exists for the given user in the given
  # file (/etc/subuid or /etc/subgid), which rootless Podman requires.
  # Usage: ensure_subid_range <file> <user>
  local file="$1"
  local user="$2"

  if [ -z "${user}" ]; then
    return 0
  fi

  mkdir -p "$(dirname "${file}")"
  touch "${file}"
  if ! grep -q "^${user}:" "${file}"; then
    echo "Adding subordinate ID range for ${user} to ${file}..."
    echo "${user}:100000:65536" >>"${file}"
  fi
}

create_amp_user() {
  echo "Creating AMP group..."
  if [ ! "$(getent group ${GID})" ]; then
    # Create group
    addgroup \
    --gid ${GID} \
    amp
  fi
  APP_GROUP=$(getent group ${GID} | awk -F ":" '{ print $1 }')
  echo "Group Created: ${APP_GROUP} (${GID})"

  echo "Creating AMP user..."
  if [ ! "$(getent passwd ${UID})" ]; then
    # Create user
    adduser \
      --uid ${UID} \
      --shell /bin/bash \
      --no-create-home \
      --disabled-password \
      --gecos "" \
      --ingroup ${APP_GROUP} \
      amp
  fi
  APP_USER=$(getent passwd ${UID} | awk -F ":" '{ print $1 }')
  echo "User Created: ${APP_USER} (${UID})"
}

handle_error() {
  # Prints a nice error message and exits.
  # Usage: handle_error "Error message"
  local error_message="$1"
  echo "Sorry! An error occurred during startup and AMP needs to shut down."
  if [ ! -z "${error_message}" ]; then
    echo "Error message: ${error_message}"
  fi
  echo "Please direct any questions or concerns to https://github.com/MitchTalmadge/AMP-dockerized/issues"
  exit 1
}

monitor_amp() {
  # Periodically process pending tasks (e.g. upgrade, reboots, ...)
  while true; do
    run_amp_command_silently "ProcessPendingTasks"
    sleep 60 # Check for pending tasks every 60 seconds to reduce CPU usage
  done
}

run_startup_script() {
  # Users may provide their own startup script for installing dependencies, etc.
  STARTUP_SCRIPT="/home/amp/scripts/startup.sh"
  if [ -f ${STARTUP_SCRIPT} ]; then
    echo "Running startup script..."
    chmod +x ${STARTUP_SCRIPT}
    /bin/bash ${STARTUP_SCRIPT}
  fi
}

shutdown() {
  echo "Shutting down... (Signal ${1})"
  if [ -n "${AMP_STARTED}" ] && [ "${AMP_STARTED}" -eq 1 ] && [ "${1}" != "KILL" ]; then
    stop_amp
  fi
  exit 0
}

start_amp() {
  echo "Starting AMP..."
  run_amp_command "StartBoot"
  export AMP_STARTED=1
  echo "AMP Started!"
}

# --- dune-admin supervision helpers -----------------------------------------
# dune-admin (as of the bundled release) only establishes its PostgreSQL
# connection on the working *startup* path. If that first connect fails (Postgres
# not ready yet, the Dune stack still booting) the process is left with no DB
# handle, and the in-UI "Reconnect" button rebuilds the DSN from now-empty
# internal fields -- producing errors like:
#   failed to connect to `user=password= database=sslmode=disable`:
#   FATAL: role "password=" does not exist (SQLSTATE 28000)
# The only reliable recovery is a full process restart (which reuses the working
# startup path). These helpers supervise dune-admin and restart it automatically
# whenever its database connection is down while PostgreSQL is actually up, so
# the panel self-heals instead of stranding the operator on the broken button.

# dune_admin_tcp_up HOST PORT -- returns 0 if a TCP connection succeeds. Uses
# bash /dev/tcp because the image ships no ss/netstat/pg client.
dune_admin_tcp_up() {
  local host="$1" port="$2"
  (exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null || return 1
  exec 3>&- 2>/dev/null || true
  return 0
}

# dune_admin_db_state PORT -- echoes the DB connection state dune-admin reports
# on its own status endpoint: "connected", "disconnected", or "unknown". The
# /api/v1/status heartbeat is unauthenticated when dashboard auth is disabled
# (the default for this image); when auth is enabled it needs a session, so this
# returns "unknown" and the caller falls back to a Postgres-recovery heuristic.
dune_admin_db_state() {
  local port="$1" body
  body="$(wget -q -T 5 -O - "http://127.0.0.1:${port}/api/v1/status" 2>/dev/null)" || {
    echo "unknown"
    return 0
  }
  case "${body}" in
    *'"db_connected":true'*) echo "connected" ;;
    *'"db_connected":false'*) echo "disconnected" ;;
    *) echo "unknown" ;;
  esac
}

# dune_admin_launch DA_BIN CFG_DIR DB_HOST DB_PORT CONTAINER -- waits (bounded)
# for the Dune container and PostgreSQL to be reachable, launches dune-admin in
# the background, and echoes its PID. `exec` makes the backgrounded subshell
# become dune-admin itself so $! is the real process PID.
dune_admin_launch() {
  local da_bin="$1" cfg_dir="$2" db_host="$3" db_port="$4" container="$5"
  local waited=0
  # 1. Wait for the Dune Podman container to be up (needed by the amp provider).
  until su -l "${APP_USER}" -c "podman ps --format '{{.Names}}'" 2>/dev/null | grep -q "^${container}$"; do
    sleep 5
    waited=$((waited + 5))
    if [ "${waited}" -ge 600 ]; then
      echo "dune-admin: timed out waiting for container ${container}; starting anyway." >&2
      break
    fi
  done
  # 2. Wait for PostgreSQL to actually accept TCP connections.
  waited=0
  until dune_admin_tcp_up "${db_host}" "${db_port}"; do
    sleep 5
    waited=$((waited + 5))
    if [ "${waited}" -ge 600 ]; then
      echo "dune-admin: timed out waiting for database ${db_host}:${db_port}; starting anyway." >&2
      break
    fi
  done
  ( cd /opt/dune-admin && exec env HOME=/home/amp "${da_bin}" >>"${cfg_dir}/dune-admin.log" 2>&1 ) &
  echo "$!"
}

# dune_admin_supervise DA_BIN CFG_DIR DB_HOST DB_PORT PORT CONTAINER -- runs the
# launch-then-monitor loop forever (meant to run in the background).
dune_admin_supervise() {
  # This is a long-running background loop; disable errexit (inherited from
  # main.sh) so a single transient non-zero command can never kill the monitor.
  set +e
  local da_bin="$1" cfg_dir="$2" db_host="$3" db_port="$4" port="$5" container="$6"
  local check_interval=30 fail_threshold=3 grace=25
  local pid state fails=0 pg_was_down=0

  pid="$(dune_admin_launch "${da_bin}" "${cfg_dir}" "${db_host}" "${db_port}" "${container}")"
  echo "dune-admin: launched (pid ${pid}); supervising DB connection."
  sleep "${grace}"

  while true; do
    sleep "${check_interval}"

    # Process gone? Relaunch it.
    if ! kill -0 "${pid}" 2>/dev/null; then
      echo "dune-admin: process ${pid} exited; relaunching."
      pid="$(dune_admin_launch "${da_bin}" "${cfg_dir}" "${db_host}" "${db_port}" "${container}")"
      echo "dune-admin: relaunched (pid ${pid})."
      fails=0
      pg_was_down=0
      sleep "${grace}"
      continue
    fi

    # Nothing to heal while PostgreSQL itself is unreachable -- wait for it.
    if ! dune_admin_tcp_up "${db_host}" "${db_port}"; then
      pg_was_down=1
      fails=0
      continue
    fi

    # PostgreSQL is up: confirm dune-admin is actually connected to it.
    state="$(dune_admin_db_state "${port}")"
    if [ "${state}" = "connected" ]; then
      fails=0
      pg_was_down=0
      continue
    fi

    # Restart when either the status endpoint says the DB is disconnected, or we
    # can't read it (auth on) but just saw PostgreSQL recover from being down --
    # both mean dune-admin's DB handle is stale and only a restart recovers it.
    if [ "${state}" = "disconnected" ] || { [ "${state}" = "unknown" ] && [ "${pg_was_down}" = "1" ]; }; then
      fails=$((fails + 1))
      echo "dune-admin: database unavailable while PostgreSQL is up (${fails}/${fail_threshold}, status=${state})."
      if [ "${fails}" -ge "${fail_threshold}" ]; then
        echo "dune-admin: restarting to re-establish the database connection."
        kill "${pid}" 2>/dev/null || true
        sleep 3
        kill -9 "${pid}" 2>/dev/null || true
        pkill -f "${da_bin}" 2>/dev/null || true
        sleep 1
        pid="$(dune_admin_launch "${da_bin}" "${cfg_dir}" "${db_host}" "${db_port}" "${container}")"
        echo "dune-admin: restarted (pid ${pid})."
        fails=0
        pg_was_down=0
        sleep "${grace}"
      fi
    else
      # Unknown state with no observed Postgres outage -- assume healthy.
      fails=0
    fi
  done
}

start_dune_admin() {
  # Optional: launch dune-admin (https://github.com/Icehunter/dune-admin), a web
  # admin panel for a Dune Awakening private server managed by AMP.
  # Only runs in the Podman image variant (where dune-admin + podman are present)
  # and only when DUNE_ADMIN_ENABLED=true. No-op otherwise, so the base image and
  # non-Dune users are unaffected.
  if [ "${DUNE_ADMIN_ENABLED}" != "true" ]; then
    return 0
  fi

  local DA_BIN="/opt/dune-admin/dune-admin"
  if [ ! -x "${DA_BIN}" ]; then
    echo "DUNE_ADMIN_ENABLED=true but dune-admin is not installed in this image."
    echo "dune-admin is only bundled in the Podman image variant (Dockerfile.podman). Skipping."
    return 0
  fi

  echo "Starting dune-admin..."

  local instance="${DUNE_ADMIN_INSTANCE:-Arrakis01}"
  local container="${DUNE_ADMIN_CONTAINER:-AMP_${instance}}"
  local port="${DUNE_ADMIN_PORT:-18080}"
  local cfg_dir="/home/amp/.dune-admin"

  mkdir -p "${cfg_dir}"

  # dune-admin reads ~/.dune-admin/config.yaml. We launch it as root (so its
  # "amp" provider can `sudo -u ${APP_USER}` to run ampinstmgr/podman), with
  # HOME=/home/amp so all its state (config, auth db, audit log, market cache)
  # persists in the mounted volume across container rebuilds.
  {
    echo "control: amp"
    echo "db_host: ${DUNE_ADMIN_DB_HOST:-127.0.0.1}"
    echo "db_port: ${DUNE_ADMIN_DB_PORT:-15432}"
    echo "db_user: ${DUNE_ADMIN_DB_USER:-dune}"
    echo "db_pass: ${DUNE_ADMIN_DB_PASS:-dune}"
    echo "db_name: ${DUNE_ADMIN_DB_NAME:-dune}"
    echo "db_schema: ${DUNE_ADMIN_DB_SCHEMA:-dune}"
    echo "amp_instance: ${instance}"
    echo "amp_container: ${container}"
    echo "amp_user: ${APP_USER}"
    echo "amp_use_container: true"
    echo "amp_container_runtime: podman"
    echo "amp_data_root: /AMP/duneawakening"
    echo "broker_exec_prefix: \"sudo -i -u ${APP_USER} podman exec ${container}\""
    echo "market_bot_cache_db: ${cfg_dir}/market-bot-cache.db"
    echo "market_bot_item_data: /opt/dune-admin/item-data.json"
    echo "listen_addr: :${port}"
  } >"${cfg_dir}/config.yaml"

  # AMP Web API login (only needed for the Server Settings tab under AMP).
  if [ -n "${DUNE_ADMIN_API_USER}" ]; then
    {
      echo "amp_api_user: ${DUNE_ADMIN_API_USER}"
      echo "amp_api_pass: ${DUNE_ADMIN_API_PASS}"
      echo "amp_api_port: ${DUNE_ADMIN_API_PORT:-8086}"
    } >>"${cfg_dir}/config.yaml"
  fi

  # Optional dashboard auth. Strongly recommended: dune-admin has full control of
  # the game server. Provide a bcrypt hash (dune-admin --set-password prints one).
  if [ -n "${DUNE_ADMIN_AUTH_USER}" ] && [ -n "${DUNE_ADMIN_AUTH_PASSWORD_HASH}" ]; then
    {
      echo "auth_enabled: true"
      echo "auth_local_username: ${DUNE_ADMIN_AUTH_USER}"
      echo "auth_local_password_hash: \"${DUNE_ADMIN_AUTH_PASSWORD_HASH}\""
    } >>"${cfg_dir}/config.yaml"
  else
    echo "Warning: dune-admin auth is disabled. Anyone who can reach port ${port} has full control of your server."
    echo "         Set DUNE_ADMIN_AUTH_USER and DUNE_ADMIN_AUTH_PASSWORD_HASH to enable a login."
  fi

  chown -R ${APP_USER}:${APP_GROUP} "${cfg_dir}" 2>/dev/null || true

  # dune-admin resolves ~/.dune-admin from the running user's home directory.
  # We run it as root (so its "amp" provider can sudo to the AMP user), and
  # root's home is /root -- not /home/amp. Point root's config dir at the
  # persistent volume location so dune-admin actually finds our config.yaml
  # (and keeps its own state -- auth db, audit log, market cache -- on the volume).
  ln -sfn "${cfg_dir}" /root/.dune-admin

  # Launch under a supervisor. dune-admin only establishes its DB connection on
  # the working startup path -- if that first attempt fails (Postgres not ready,
  # the Dune stack still booting) the process is left disconnected, and the in-UI
  # "Reconnect" button then fails with a malformed DSN (role "password=" does not
  # exist). The supervisor waits for the Dune container + PostgreSQL before each
  # launch and restarts dune-admin automatically whenever its DB connection is
  # down while PostgreSQL is up, so the panel self-heals instead of stranding the
  # operator on the broken button.
  local db_host="${DUNE_ADMIN_DB_HOST:-127.0.0.1}"
  local db_port="${DUNE_ADMIN_DB_PORT:-15432}"
  dune_admin_supervise "${DA_BIN}" "${cfg_dir}" "${db_host}" "${db_port}" "${port}" "${container}" &

  echo "dune-admin started on port ${port} (logs: ${cfg_dir}/dune-admin.log)"
}

stop_amp() {
  echo "Stopping AMP..."
  run_amp_command "StopAll"
  echo "AMP Stopped."
}

upgrade_instances() {
  echo "Upgrading instances..."
  run_amp_command "UpgradeAll" | consume_progress_bars
}