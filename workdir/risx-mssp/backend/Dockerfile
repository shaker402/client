# syntax=docker/dockerfile:1
FROM python:3.10-bookworm AS final
ENV NODE_VERSION=20

RUN apt-get update \
    && apt-get install -y curl gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_$NODE_VERSION.x | bash - \
    && apt-get install -y nodejs \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y docker-ce-cli p7zip-full sudo \
    && npm install -g yarn \
    && apt-get clean

# TODO: the number of the group docker should be exactly the same as for host !
RUN groupadd --gid 1000 node \
  && useradd --uid 1000 --gid node --shell /bin/bash --create-home node \
  && groupadd -g 123 docker \
  && usermod -aG docker node \
  && usermod -aG sudo node \
  && echo "node ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/node

# Set working directory
WORKDIR /risx-mssp-back

# Backend
# Copy package.json and package-lock.json
COPY /risx-mssp-back/package*.json ./
# Install dependencies
RUN npm ci
# Copy the rest of the application code
COPY --chown=1000:1000 /risx-mssp-back/ .

# PYTHON SCRIPTS
COPY --chown=1000:1000 /python-scripts /python-scripts
RUN pip install -r /python-scripts/requirements.txt

# Final steps
COPY /entrypoint.sh /entrypoint.sh
# Ensure entrypoint script is executable
RUN chmod +x /entrypoint.sh

# Use a non-root user
USER node
# Expose the application port
EXPOSE 5555

# Set environment variables
ENV FORCE_INIT=0
ENV INIT_CHECK_DIR=/init_check

# Define the entrypoint
ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
