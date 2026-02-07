# Dreamwidth Test Environment for GitHub Codespaces
# Optimized for running tests only (no database, Apache, etc.)

FROM ubuntu:22.04
LABEL org.opencontainers.image.authors="Mark Smith <mark@dreamwidth.org>"

# Set working directory
WORKDIR /workspaces/dreamwidth

# Environment setup
ENV LJHOME /workspaces/dreamwidth
ENV PERL5LIB /opt/dreamwidth-extlib/lib/perl5
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

# Install Node.js 20 LTS (for sass and esbuild)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g sass esbuild

# Install cpm for faster CPAN module installation
RUN cpanm -nq App::cpm

# Copy dependency files to install Perl modules
COPY doc/dependencies-cpanm /tmp/dependencies-cpanm

# Install CPAN dependencies to system location (won't be overwritten by volume mount)
RUN cpm install -v --show-build-log-on-failure --no-color --resolver metadb -L /opt/dreamwidth-extlib/ - < /tmp/dependencies-cpanm && \
    rm -rf /root/.perl-cpm && \
    rm -rf /root/.cpanm && \
    rm /tmp/dependencies-cpanm

# Copy full source tree for pre-baking schema and static assets
# Placed late in the Dockerfile to avoid busting cache for package/CPAN layers.
# At runtime, a bind mount overlays /workspaces/dreamwidth, so anything written
# here is only used during the build and then in /opt/dreamwidth-static/.
COPY . /workspaces/dreamwidth/

# Set up config symlink needed by update-db.pl and build-static.sh
RUN mkdir -p $LJHOME/ext/local && \
    ln -ns $LJHOME/.devcontainer/config/etc/dw-etc $LJHOME/ext/local/etc

# Pre-populate database schema and build static assets into the image.
# Start MySQL, run all schema migrations, build statics, copy to a safe
# location outside the workspace (which gets overlaid at runtime), then
# clean up MySQL.
RUN service mysql start && \
    mysql -u root -e "\
        CREATE DATABASE IF NOT EXISTS dw_global CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; \
        CREATE DATABASE IF NOT EXISTS dw_cluster01 CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; \
        CREATE DATABASE IF NOT EXISTS dw_schwartz CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; \
        CREATE USER IF NOT EXISTS 'dw'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY 'dw'; \
        CREATE USER IF NOT EXISTS 'dw'@'localhost' IDENTIFIED WITH mysql_native_password BY 'dw'; \
        GRANT ALL PRIVILEGES ON dw_global.* TO 'dw'@'127.0.0.1'; \
        GRANT ALL PRIVILEGES ON dw_cluster01.* TO 'dw'@'127.0.0.1'; \
        GRANT ALL PRIVILEGES ON dw_schwartz.* TO 'dw'@'127.0.0.1'; \
        GRANT ALL PRIVILEGES ON dw_global.* TO 'dw'@'localhost'; \
        GRANT ALL PRIVILEGES ON dw_cluster01.* TO 'dw'@'localhost'; \
        GRANT ALL PRIVILEGES ON dw_schwartz.* TO 'dw'@'localhost'; \
        FLUSH PRIVILEGES;" && \
    mysql -u root dw_schwartz < $LJHOME/doc/schwartz-schema.sql && \
    bin/upgrading/update-db.pl -r && \
    bin/upgrading/update-db.pl -r --cluster=all && \
    bin/upgrading/update-db.pl -r -p && \
    bin/upgrading/texttool.pl load && \
    t/bin/initialize-db && \
    bin/build-static.sh && \
    mkdir -p /opt/dreamwidth-static && \
    cp -a build/static/* /opt/dreamwidth-static/ && \
    service mysql stop

# Default command
CMD ["bash"]