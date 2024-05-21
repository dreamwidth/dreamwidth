#
# This creates a Dreamwidth development container. This uses entirely
# local source files and runs a webserver that is exposed for your
# development testing pleasure.
#

FROM  ubuntu:22.04
LABEL org.opencontainers.image.authors="Mark Smith <mark@dreamwidth.org>"

# Configuration can go here.
ARG COMMIT=main

# Things that commands need, but shouldn't change.
ENV HOME /dw
ENV LJHOME /dw
ENV PERL5LIB /dw/extlib/lib/perl5
ENV DEBIAN_FRONTEND noninteractive

# Clean up anything from base in a weird state
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/*

    # Install system dependencies
RUN apt-get update && \
    apt-get install -y apt-transport-https && \
    apt-get install -y curl git tzdata rsync vim && \
    bash -c 'echo "Etc/UTC" > /etc/timezone' && \
    dpkg-reconfigure -f noninteractive tzdata

# Install system dependencies
RUN apt-get update && \
    apt-get install -y cpanminus

# Install some basic packages we need
RUN apt-get update && \
    apt-get install -y ruby-rubygems ruby-dev build-essential bison openssl \
       libreadline6-dev curl git-core zlib1g zlib1g-dev libssl-dev libyaml-dev \
       libxml2-dev autoconf libc6-dev ncurses-dev automake libtool && \
    gem install compass

# Copy in dependency lists and scripts to reduce the need to rebuild
ADD doc/ /opt/doc

# Install base system dependencies, then clean up
RUN cat /opt/doc/dependencies-system | \
        xargs apt-get -y install && \
    rm -rf /var/lib/apt/lists/* && \
    cpanm -nq App::cpm

# Dev server needs databases and stuff
RUN apt-get update && \
    apt-get -y install mysql-server && \
    rm -rf /var/lib/apt/lists/*

# Split CPAN dependencies into a second step, since they change more
# frequently than system dependencies
RUN cat /opt/doc/dependencies-cpanm | \
        cpm install -v --show-build-log-on-failure --no-color -L /dw/extlib/ - && \
    rm -rf /root/.perl-cpm && \
    rm -rf /root/.cpanm

# Copy in our repository and scripts so we can use it for everything else
ADD . /dw/
ADD etc/docker/dev/config/ /dw/ext/local
ADD etc/docker/dev/scripts/ /opt

# last update in case some Perl dependency changed
RUN cat /opt/doc/dependencies-cpanm | \
        cpm install -v --show-build-log-on-failure --no-color -L /dw/extlib/ - && \
    rm -rf /root/.perl-cpm && \
    rm -rf /root/.cpanm

# Setup script that runs to make sure we get configs in the right place and do any
# last minute configuration.
RUN bash /opt/setup.sh

# Kick off the startup script, which does some healthcheck and then starts
# Apache if things look good.
CMD bash /opt/startup.sh
