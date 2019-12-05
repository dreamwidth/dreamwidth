#
# This creates a Dreamwidth webserver.
#

FROM       ubuntu:18.04
MAINTAINER Mark Smith "mark@dreamwidth.org"

# Configuration can go here.
ARG COMMIT=master

# Things that commands need, but shouldn't change.
ENV LJHOME /dw
ENV DEBIAN_FRONTEND noninteractive

# Set up base image with dependencies.
RUN apt-get update && \
    apt-get install -y apt-transport-https && \
    apt-get install -y curl git cpanminus tzdata rsync mysql-client && \
    bash -c 'echo "Etc/UTC" > /etc/timezone' && \
    dpkg-reconfigure -f noninteractive tzdata && \
    curl https://raw.githubusercontent.com/dreamwidth/dw-free/master/doc/dependencies-system | \
        xargs apt-get -y install && \
    curl https://raw.githubusercontent.com/dreamwidth/dw-free/master/doc/dependencies-cpanm | \
        xargs cpanm -n -L /dw/extlib/ && \
    rm -rf /root/.cpanm && \
    rm -rf /var/lib/apt/lists/*

# Check out the source code and prepare it.
RUN mv $LJHOME/extlib /dw-extlib && \
    rmdir $LJHOME && \
    git clone https://github.com/dreamwidth/dw-free.git $LJHOME && \
    mv /dw-extlib $LJHOME/extlib && \
    git -C $LJHOME checkout $COMMIT && \
    mkdir $LJHOME/ext/yuicompressor/ && \
    curl -s -L --output $LJHOME/ext/yuicompressor/yuicompressor.jar \
        https://github.com/yui/yuicompressor/releases/download/v2.4.8/yuicompressor-2.4.8.jar && \
    git clone https://github.com/dreamwidth/dw-nonfree.git $LJHOME/ext/dw-nonfree && \
    git -C $LJHOME/ext/dw-nonfree checkout master && \
    $LJHOME/bin/build-static.sh

# Copy in support scripts/configurations that are useful.
ADD scripts/ /opt/
ADD config/ /dw/ext/local

# Setup script that runs to make sure we get configs in the right place and do any
# last minute configuration.
RUN bash /opt/setup.sh

# We run on 80, TLS is handled by a proxy of some kind.
EXPOSE 80

# Kick off the startup script, which does some healthcheck and then starts
# Apache if things look good.
CMD bash /opt/startup-prod.sh
