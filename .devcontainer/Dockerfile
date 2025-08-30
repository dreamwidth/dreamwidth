# Dreamwidth Test Environment for GitHub Codespaces
# Optimized for running tests only (no database, Apache, etc.)

FROM ubuntu:24.04
LABEL org.opencontainers.image.authors="Mark Smith <mark@dreamwidth.org>"

# Set working directory
WORKDIR /workspaces/dreamwidth

# Environment setup
ENV LJHOME /workspaces/dreamwidth
ENV PERL5LIB /workspaces/dreamwidth/extlib/lib/perl5
ENV DEBIAN_FRONTEND noninteractive

# Install basic dependencies needed for Docker build process
RUN apt-get update && \
    apt-get install -y apt-transport-https curl git cpanminus tzdata rsync vim openssh-server locales && \
    bash -c 'echo "Etc/UTC" > /etc/timezone' && \
    dpkg-reconfigure -f noninteractive tzdata && \
    locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8

# Copy and install system dependencies automatically from dependencies-system file
COPY doc/dependencies-system /tmp/dependencies-system
RUN apt-get install -y $(cat /tmp/dependencies-system | grep -v '^#' | grep -v '^$' | tr '\n' ' ') && \
    rm /tmp/dependencies-system

# Install dependencies for local development full-stack
RUN apt-get install -y mysql-server mysql-client memcached htop

# Install cpm for faster CPAN module installation
RUN cpanm -nq App::cpm

# Copy dependency files to install Perl modules
COPY doc/dependencies-cpanm /tmp/dependencies-cpanm

# Install CPAN dependencies to system location (won't be overwritten by volume mount)
RUN cpm install -v --show-build-log-on-failure --no-color -L /opt/dreamwidth-extlib/ - < /tmp/dependencies-cpanm && \
    rm -rf /root/.perl-cpm && \
    rm -rf /root/.cpanm && \
    rm /tmp/dependencies-cpanm

# Default command
CMD ["bash"]