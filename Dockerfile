FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends procps psmisc ufw gawk && rm -rf /var/lib/apt/lists/*
RUN useradd -m -s /bin/bash agent
USER agent
WORKDIR /work
