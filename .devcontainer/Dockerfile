# Dreamwidth Test Environment for GitHub Codespaces
# Optimized for running tests only (no database, Apache, etc.)

FROM ubuntu:24.04
LABEL org.opencontainers.image.authors="Mark Smith <mark@dreamwidth.org>"

# Environment setup
ENV LJHOME /workspaces/dreamwidth
ENV PERL5LIB /workspaces/dreamwidth/extlib/lib/perl5
ENV DEBIAN_FRONTEND noninteractive

# Install basic dependencies needed for Docker build process
RUN apt-get update && \
    apt-get install -y apt-transport-https curl git cpanminus tzdata rsync vim openssh-server && \
    bash -c 'echo "Etc/UTC" > /etc/timezone' && \
    dpkg-reconfigure -f noninteractive tzdata

# Copy and install system dependencies automatically from dependencies-system file
COPY doc/dependencies-system /tmp/dependencies-system
RUN apt-get install -y $(cat /tmp/dependencies-system | grep -v '^#' | grep -v '^$' | tr '\n' ' ') && \
    rm /tmp/dependencies-system && \
    rm -rf /var/lib/apt/lists/*

# Install cpm for faster CPAN module installation
RUN cpanm -nq App::cpm

# Copy dependency files to install Perl modules
COPY doc/dependencies-cpanm /tmp/dependencies-cpanm

# Install CPAN dependencies to system location (won't be overwritten by volume mount)
RUN cpm install -v --show-build-log-on-failure --no-color -L /opt/dreamwidth-extlib/ - < /tmp/dependencies-cpanm && \
    rm -rf /root/.perl-cpm && \
    rm -rf /root/.cpanm && \
    rm /tmp/dependencies-cpanm

# Set working directory
WORKDIR /workspaces/dreamwidth

# Copy SSH setup script
COPY .devcontainer/setup-ssh.sh /usr/local/bin/setup-ssh.sh
RUN chmod +x /usr/local/bin/setup-ssh.sh

# Configure SSH
RUN mkdir /var/run/sshd && \
    echo 'root:dreamwidth' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd && \
    mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh

# Expose SSH port
EXPOSE 22

# Default command
CMD ["bash"]