#
# This creates a Dreamwidth base setup, which has all of the dependencies
# installed. Mostly a speedup hack so we can deploy code changes w/o having
# to rebuild dependencies.
#

FROM       ubuntu:18.04
MAINTAINER Mark Smith "mark@dreamwidth.org"

# Configuration can go here.
ARG COMMIT=master

# Things that commands need, but shouldn't change.
ENV LJHOME /dw
ENV DEBIAN_FRONTEND noninteractive

# All this to bootstrap our initialization process so that we can use
RUN apt-get update && \
    apt-get install -y apt-transport-https && \
    apt-get install -y curl git cpanminus tzdata rsync && \
    bash -c 'echo "Etc/UTC" > /etc/timezone' && \
    dpkg-reconfigure -f noninteractive tzdata && \
    curl https://raw.githubusercontent.com/dreamwidth/dw-free/master/doc/dependencies-system | \
        xargs apt-get -y install && \
    curl https://raw.githubusercontent.com/dreamwidth/dw-free/master/doc/dependencies-cpanm | \
        xargs cpanm -n -L /dw/extlib/ && \
    rm -rf /root/.cpanm && \
    rm -rf /var/lib/apt/lists/*

# Actually check out the source code now.
RUN mv $LJHOME/extlib /dw-extlib && \
    rmdir $LJHOME && \
    git clone https://github.com/dreamwidth/dw-free.git $LJHOME && \
    mv /dw-extlib $LJHOME/extlib && \
    git -C $LJHOME checkout $COMMIT && \
    mkdir $LJHOME/ext/yuicompressor/ && \
    curl -s -L --output $LJHOME/ext/yuicompressor/yuicompressor.jar \
        https://github.com/yui/yuicompressor/releases/download/v2.4.8/yuicompressor-2.4.8.jar && \
    git clone https://github.com/dreamwidth/dw-nonfree.git $LJHOME/ext/dw-nonfree && \
    git -C $LJHOME/ext/dw-nonfree checkout master
