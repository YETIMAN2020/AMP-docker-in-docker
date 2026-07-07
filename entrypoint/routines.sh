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

  # Launch in the background once the Dune container is up. dune-admin tolerates
  # the DB not being ready yet and will keep retrying, but we wait for the
  # container so the amp provider has something to talk to.
  (
    local waited=0
    until su -l "${APP_USER}" -c "podman ps --format '{{.Names}}'" 2>/dev/null | grep -q "^${container}$"; do
      sleep 5
      waited=$((waited + 5))
      if [ "${waited}" -ge 300 ]; then
        echo "dune-admin: timed out waiting for container ${container}; starting anyway."
        break
      fi
    done
    cd /opt/dune-admin
    HOME=/home/amp "${DA_BIN}" >>"${cfg_dir}/dune-admin.log" 2>&1
  ) &

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