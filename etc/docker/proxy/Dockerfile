#
# This creates a Dreamwidth proxy container.
#

FROM       ubuntu:18.04
MAINTAINER Mark Smith "mark@dreamwidth.org"

# Configuration can go here.
ARG COMMIT=master

# Things that commands need, but shouldn't change.
ENV LJHOME /dw
ENV DEBIAN_FRONTEND noninteractive

# Ubuntu level setup for the basics
RUN apt-get update && \
    apt-get install -y apt-transport-https && \
    apt-get install -y curl git cpanminus tzdata rsync vim golang-go && \
    bash -c 'echo "Etc/UTC" > /etc/timezone' && \
    dpkg-reconfigure -f noninteractive tzdata && \
    rm -rf /var/lib/apt/lists/*

# Actually check out the source code now.
RUN git clone https://github.com/dreamwidth/dw-free.git $LJHOME && \
    git -C $LJHOME checkout $COMMIT && \
    git -C $LJHOME pull --ff-only origin $COMMIT && \
    cd $LJHOME/src/proxy && \
    go build

# Copy in support scripts/configurations that are useful.
ADD scripts/ /opt/

# Setup script that runs to make sure we get configs in the right place and do any
# last minute configuration.
RUN bash /opt/setup.sh

# We run our proxy on this port
EXPOSE 6250/tcp

# Kick off the startup script, which does things
CMD bash /opt/startup-prod.sh
