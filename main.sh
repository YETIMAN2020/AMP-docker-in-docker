name: "Deploy Production"

# Fork-friendly publisher: builds the Podman-enabled image and pushes it to
# YOUR OWN Docker Hub account.
#
# SETUP (one time):
#   1. Create a Docker Hub access token: https://hub.docker.com/settings/security
#   2. In this repo: Settings > Secrets and variables > Actions > New repository secret
#        - DOCKERHUB_USERNAME = your Docker Hub username (e.g. yetiman2020)
#        - DOCKERHUB_TOKEN    = the access token you created
#
# It publishes:
#     <DOCKERHUB_USERNAME>/amp-docker-in-docker:podman
#     <DOCKERHUB_USERNAME>/amp-docker-in-docker:latest   (same image, for convenience)
#
# Triggers:
#   - Manually via the Actions tab ("Run workflow"), with a platform choice.
#   - Automatically when the image sources change on master.

on:
  workflow_dispatch:
    inputs:
      platforms:
        description: "Target platforms to build/push"
        required: true
        default: "linux/amd64"
        type: choice
        options:
          - "linux/amd64"
          - "linux/arm64"
          - "linux/amd64,linux/arm64"
  push:
    branches:
      - master
    paths:
      - Dockerfile
      - Dockerfile.podman
      - .dockerignore
      - entrypoint/**
      - .github/workflows/deploy-prod.yml

jobs:
  deploy:
    name: "Build & Push Podman Variant"
    runs-on: ubuntu-latest
    env:
      DOCKERHUB_USERNAME: ${{ secrets.DOCKERHUB_USERNAME }}
    steps:
      - name: "Verify Docker Hub secrets are set"
        run: |
          if [ -z "${DOCKERHUB_USERNAME}" ]; then
            echo "::error::DOCKERHUB_USERNAME / DOCKERHUB_TOKEN secrets are not set."
            echo "Add them in: Settings > Secrets and variables > Actions."
            exit 1
          fi

      - name: "Checkout Git Repo"
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: "Determine platforms"
        id: platforms
        run: echo "value=${{ inputs.platforms || 'linux/amd64' }}" >> "$GITHUB_OUTPUT"

      - name: "Set up QEMU"
        uses: docker/setup-qemu-action@v3

      - name: "Set up Docker Buildx"
        uses: docker/setup-buildx-action@v3

      - name: "Login to Docker Hub"
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: "Build and Push Podman Variant"
        uses: docker/build-push-action@v4
        with:
          context: .
          file: Dockerfile.podman
          platforms: ${{ steps.platforms.outputs.value }}
          push: true
          tags: |
            ${{ secrets.DOCKERHUB_USERNAME }}/amp-docker-in-docker:podman
            ${{ secrets.DOCKERHUB_USERNAME }}/amp-docker-in-docker:latest
