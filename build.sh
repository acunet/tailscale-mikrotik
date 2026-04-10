#!/usr/bin/env sh
# Copyright (c) 2024 Fluent Networks Pty Ltd & AUTHORS All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.
#
# Updates tailscale respository and runs `docker build` with flags configured for 
# docker distribution. 
# 
############################################################################
#
# WARNING: Tailscale is not yet officially supported in Docker,
# Kubernetes, etc.
#
# It might work, but we don't regularly test it, and it's not as polished as
# our currently supported platforms. This is provided for people who know
# how Tailscale works and what they're doing.
#
# Our tracking bug for officially support container use cases is:
#    https://github.com/tailscale/tailscale/issues/504
#
# Also, see the various bugs tagged "containers":
#    https://github.com/tailscale/tailscale/labels/containers
#
############################################################################
#
# Set PLATFORM as required for your router model. See:
# https://mikrotik.com/products/matrix
#
PLATFORM="linux/arm64"
TAILSCALE_VERSION=v1.96.4
VERSION=0.1.40
BUILDER="${BUILDER:-arm64-builder}"

set -eu

rm -f tailscale.tar

case "$TAILSCALE_VERSION" in
  v*) TS_GIT_REF="$TAILSCALE_VERSION" ;;
  *) TS_GIT_REF="v$TAILSCALE_VERSION" ;;
esac

if [ ! -d ./tailscale/.git ]
then
    git -c advice.detachedHead=false clone https://github.com/tailscale/tailscale.git --branch "$TS_GIT_REF"
fi

if docker buildx inspect "$BUILDER" >/dev/null 2>&1
then
    docker buildx use "$BUILDER"
else
    docker buildx create --name "$BUILDER" --driver docker-container --use
fi
docker buildx inspect --bootstrap >/dev/null

TS_USE_TOOLCHAIN="Y"
cd tailscale && eval $(./build_dist.sh shellvars) && cd ..

docker buildx build \
  --no-cache \
  --build-arg TAILSCALE_VERSION="$TAILSCALE_VERSION" \
  --build-arg VERSION_LONG="$VERSION_LONG" \
  --build-arg VERSION_SHORT="$VERSION_SHORT" \
  --build-arg VERSION_GIT_HASH="$VERSION_GIT_HASH" \
  --platform "$PLATFORM" \
  --builder "$BUILDER" \
  --load -t "ghcr.io/acunet/tailscale-mikrotik:$VERSION" .

skopeo copy "docker-daemon:ghcr.io/acunet/tailscale-mikrotik:$VERSION" docker-archive:tailscale.tar
