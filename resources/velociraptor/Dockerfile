FROM ubuntu:22.04

# Define the VELOX_RELEASE https://github.com/Velocidex/velociraptor/releases
ARG VELOCIRAPTOR_VERSION=v0.74

LABEL description="Velociraptor server in a Docker container"
LABEL maintainer="@10RootOrg"
LABEL src.forked_from="https://github.com/weslambert/velociraptor-docker/tree/master"
LABEL version="Velociraptor $VELOCIRAPTOR_VERSION"

COPY ./entrypoint /entrypoint
RUN chmod +x /entrypoint
# Install necessary packages for downloading Velociraptor
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      rsync curl jq ca-certificates && \
    # Create dirs for Velociraptor binaries
    mkdir -p /opt/velociraptor/linux && \
    mkdir -p /opt/velociraptor/mac && \
    mkdir -p /opt/velociraptor/windows && \
    curl -o /tmp/velociraptor_rel.json -L -s https://api.github.com/repos/velocidex/velociraptor/releases/tags/${VELOCIRAPTOR_VERSION}  && \
    LINUX_BIN="$(jq -r '.assets[] | select(.name | test("linux-amd64$")) | .browser_download_url' /tmp/velociraptor_rel.json | sort -V | tail -n 1)" && \
    MAC_BIN="$(jq -r '.assets[] | select(.name | test("darwin-amd64$")) | .browser_download_url' /tmp/velociraptor_rel.json | sort -V | tail -n 1)" && \
    WINDOWS_EXE="$(jq -r '.assets[] | select(.name | test("windows-amd64.exe$")) | .browser_download_url' /tmp/velociraptor_rel.json | sort -V | tail -n 1)" && \
    WINDOWS_MSI="$(jq -r '.assets[] | select(.name | test("windows-amd64.msi$")) | .browser_download_url' /tmp/velociraptor_rel.json | sort -V | tail -n 1)" && \
    curl -s -L -o /opt/velociraptor/linux/velociraptor "$LINUX_BIN" && chmod +x /opt/velociraptor/linux/velociraptor && \
    curl -s -L -o /opt/velociraptor/mac/velociraptor_client "$MAC_BIN" && \
    curl -s -L -o /opt/velociraptor/windows/velociraptor_client.exe "$WINDOWS_EXE" && \
    curl -s -L -o /opt/velociraptor/windows/velociraptor_client.msi "$WINDOWS_MSI" && \
    # Cleanup
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -f /tmp/velociraptor_rel.json


# Set working directory
WORKDIR /velociraptor

# Default command
CMD ["/entrypoint"]
