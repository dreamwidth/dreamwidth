#
# This creates a Dreamwidth base setup, which has all of the dependencies
# installed. Mostly a speedup hack so we can deploy code changes w/o having
# to rebuild dependencies.
#

FROM  ubuntu:18.04
LABEL org.opencontainers.image.authors="Mark Smith <mark@dreamwidth.org>"

# Configuration can go here.
ARG COMMIT=main

# Things that commands need, but shouldn't change.
ENV LJHOME /dw
ENV DEBIAN_FRONTEND noninteractive

# Ubuntu level setup for the basics
RUN apt-get update && \
    apt-get install -y apt-transport-https && \
    apt-get install -y curl git cpanminus tzdata rsync vim && \
    bash -c 'echo "Etc/UTC" > /etc/timezone' && \
    dpkg-reconfigure -f noninteractive tzdata && \
    curl https://raw.githubusercontent.com/dreamwidth/dreamwidth/main/doc/dependencies-system | \
        xargs apt-get -y install && \
    rm -rf /var/lib/apt/lists/* && \
    cpanm -nq App::cpm

# Split CPAN dependencies into a second step, since they change more
# frequently than system dependencies
RUN curl https://raw.githubusercontent.com/dreamwidth/dreamwidth/main/doc/dependencies-cpanm | \
        cpm install -v --no-color -L /dw/extlib/ - && \
    rm -rf /root/.perl-cpm && \
    rm -rf /root/.cpanm

# Actually check out the source code now. Also build static, so that later when
# we do individual deploys, the static build is faster.
RUN mv $LJHOME/extlib /dw-extlib && \
    rmdir $LJHOME && \
    git clone https://github.com/dreamwidth/dreamwidth.git $LJHOME && \
    mv /dw-extlib $LJHOME/extlib && \
    git -C $LJHOME checkout $COMMIT && \
    git -C $LJHOME pull --ff-only origin $COMMIT && \
    mkdir $LJHOME/ext/yuicompressor/ && \
    curl -s -L --output $LJHOME/ext/yuicompressor/yuicompressor.jar \
        https://github.com/yui/yuicompressor/releases/download/v2.4.8/yuicompressor-2.4.8.jar && \
    $LJHOME/bin/build-static.sh
