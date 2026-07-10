#!/bin/bash
# Example `docker run` for the Podman-enabled image variant.
#
# Use this if you want AMP to run "containerized" instances (which use Podman)
# from inside this container. Podman and the required fixes are baked into the
# image (amp-docker-in-docker:podman), so you do NOT need to reinstall
# Podman or re-apply the registry fix every time the container is recreated.
#
# Podman needs permission to create user namespaces. Either run the container
# privileged (--privileged) OR grant SYS_ADMIN + an unconfined seccomp profile
# as shown below.
#
# Build the Podman variant first:
#     docker build -f Dockerfile.podman -t amp-docker-in-docker:podman .

docker run -d \
  --name amp \
  --restart unless-stopped \
  --network bridge \
  --mac-address 02:42:AC:XX:XX:XX \ # See README for MAC address info
  --cap-add SYS_ADMIN \             # Required for Podman (or use --privileged instead)
  --security-opt seccomp=unconfined \
  --device /dev/fuse \              # For the fuse-overlayfs storage driver
  -p 8080:8080 \                  # AMP Web UI
  # Uncomment the ports below as needed for whatever game servers you'll be running.
  # -p 34197:34197/udp \          # Factorio
  # -p 27015:27015/udp \          # GMod, TF2, and other Source engine games
  # -p 19132:19132/udp \          # Minecraft Bedrock Edition
  # -p 25565:25565 \              # Minecraft Java Edition
  # -p 21025:21025 \              # Starbound
  # -p 5678-5680:5678-5680/udp \  # Valheim
  -v $(pwd)/ampdata:/home/amp/ \
  -e UID=120 \
  -e GID=124 \
  -e TZ=Etc/UTC \
  amp-docker-in-docker:podman
