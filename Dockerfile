FROM python:3.12-slim

# ---------------------------------------------------------------------------
# System deps
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates gnupg apt-transport-https && \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Docker CLI + Compose plugin (talks to host Docker via mounted socket)
# ---------------------------------------------------------------------------
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list && \
    apt-get update && apt-get install -y --no-install-recommends \
    docker-ce-cli docker-compose-plugin && \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# .NET 10 SDK (builder/tester need dotnet CLI for .NET target projects)
# Uses the dotnet-install script since .NET 10 may not be in the Debian repo yet.
# Requires ICU libraries for globalization support on slim images.
# ---------------------------------------------------------------------------
ENV DOTNET_ROOT=/usr/share/dotnet
ENV PATH="$DOTNET_ROOT:$PATH"
RUN apt-get update && apt-get install -y --no-install-recommends libicu-dev && \
    rm -rf /var/lib/apt/lists/* && \
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh && \
    chmod +x /tmp/dotnet-install.sh && \
    /tmp/dotnet-install.sh --channel 10.0 --install-dir "$DOTNET_ROOT" && \
    rm /tmp/dotnet-install.sh && \
    dotnet --version

# ---------------------------------------------------------------------------
# Node.js 22 LTS (builder/tester need node/npm for JS/TS target projects)
# ---------------------------------------------------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# GitHub CLI
# ---------------------------------------------------------------------------
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && apt-get install -y gh && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Copilot CLI: standalone binary via official install script
# ---------------------------------------------------------------------------
RUN curl -fsSL https://gh.io/copilot-install | bash

# ---------------------------------------------------------------------------
# Git: default branch = main
# ---------------------------------------------------------------------------
RUN git config --global init.defaultBranch main

# ---------------------------------------------------------------------------
# Install buildteam
# ---------------------------------------------------------------------------
COPY . /opt/buildteam
RUN pip install --no-cache-dir /opt/buildteam

# Entrypoint handles auth + dockerd startup then delegates to buildteam
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
