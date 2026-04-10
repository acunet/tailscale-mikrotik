#!/bin/bash
# Copyright (c) 2024 Fluent Networks Pty Ltd & AUTHORS All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

set -m

up_args=()

# Enable IP forwarding
echo 'net.ipv4.ip_forward = 1' | tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' | tee -a /etc/sysctl.conf
sysctl -p /etc/sysctl.conf

# Prepare run dirs
if [ ! -d "/var/run/sshd" ]; then
  mkdir -p /var/run/sshd
fi

# Set root password when provided
if [[ -n "${PASSWORD}" ]]; then
  echo "root:${PASSWORD}" | chpasswd
fi

# Install local routes for advertised subnets when configured
if [[ -n "${ADVERTISE_ROUTES}" && -n "${CONTAINER_GATEWAY}" ]]; then
  IFS=',' read -ra SUBNETS <<< "${ADVERTISE_ROUTES}"
  for s in "${SUBNETS[@]}"; do
    [[ -z "${s}" ]] && continue
    ip route add "${s}" via "${CONTAINER_GATEWAY}"
  done
fi

# Perform an update if set
if [[ ! -z "${UPDATE_TAILSCALE+x}" ]]; then
  /usr/local/bin/tailscale update --yes
fi

# Set login server for tailscale
if [[ -z "${LOGIN_SERVER}" ]]; then
	LOGIN_SERVER=https://controlplane.tailscale.com
fi

up_args+=(--reset)
up_args+=(--login-server "${LOGIN_SERVER}")

if [[ -n "${ADVERTISE_ROUTES}" ]]; then
  up_args+=(--advertise-routes="${ADVERTISE_ROUTES}")
fi

if [[ -n "${AUTH_KEY}" ]]; then
  up_args+=(--authkey="${AUTH_KEY}")
fi

if [[ -n "${TAILSCALE_ARGS}" ]]; then
  # shellcheck disable=SC2206
  tailscale_extra_args=(${TAILSCALE_ARGS})
  up_args+=("${tailscale_extra_args[@]}")
fi

# Execute startup script if it exists
if [[ -n "${STARTUP_SCRIPT}" && -f "${STARTUP_SCRIPT}" ]]; then
       bash "${STARTUP_SCRIPT}" || exit $?
fi

# Start tailscaled and bring tailscale up
/usr/local/bin/tailscaled ${TAILSCALED_ARGS} &

if [[ -n "${AUTH_KEY}" ]]; then
  until /usr/local/bin/tailscale up "${up_args[@]}"
  do
      sleep 0.1
  done
  echo "Tailscale started with auth key"
else
  if /usr/local/bin/tailscale up "${up_args[@]}"; then
    echo "Tailscale started"
  else
    echo "No AUTH_KEY provided. Complete login interactively:"
    echo "  /usr/local/bin/tailscale login --login-server \"${LOGIN_SERVER}\""
    echo "Then verify with:"
    echo "  /usr/local/bin/tailscale status"
  fi
fi

# Check that a route exists for 100.64.0.0/10; if not, add
EXISTS=`ip route show 100.64.0.0/10 | wc -l`
if [ $EXISTS -eq 0 ]; then
  ip route add 100.64.0.0/10 dev tailscale0
fi

# Check that a route exists for fd7a:115c:a1e0::/48; if not, add
EXISTSV6=`ip -6 route show fd7a:115c:a1e0::/48 | wc -l`
if [ $EXISTSV6 -eq 0 ]; then
  ip -6 route add fd7a:115c:a1e0::/48 dev tailscale0
fi

# Execute running script if it exists
if [[ -n "${RUNNING_SCRIPT}" && -f "${RUNNING_SCRIPT}" ]]; then
       bash "${RUNNING_SCRIPT}" || exit $?
fi

# Start SSH
/usr/sbin/sshd -D

fg %1
