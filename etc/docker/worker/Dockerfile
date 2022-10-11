#
# This creates a Dreamwidth worker container.
#

FROM       194396987458.dkr.ecr.us-east-1.amazonaws.com/dreamwidth/base:latest
MAINTAINER Mark Smith "mark@dreamwidth.org"

# Configuration can go here.
ARG COMMIT=master

# Things that commands need, but shouldn't change.
ENV LJHOME /dw

# Install some packages we need in workers only.
RUN echo $COMMIT && \
    apt-get update && \
    apt-get install -y mysql-client && \
    curl https://raw.githubusercontent.com/dreamwidth/dw-free/master/doc/dependencies-system | \
        xargs apt-get -y install && \
    curl https://raw.githubusercontent.com/dreamwidth/dw-free/master/doc/dependencies-cpanm | \
        xargs cpanm -n -L /dw/extlib/ && \
    rm -rf /var/lib/apt/lists/*

# Actually check out the source code now.
RUN git -C $LJHOME fetch && \
    git -C $LJHOME checkout $COMMIT && \
    git -C $LJHOME pull --ff-only origin $COMMIT && \
    git -C $LJHOME/ext/dw-nonfree fetch && \
    git -C $LJHOME/ext/dw-nonfree checkout master && \
    git -C $LJHOME/ext/dw-nonfree pull --ff-only origin $COMMIT

# Copy in support scripts/configurations that are useful.
ADD scripts/ /opt/

# Setup script that runs to make sure we get configs in the right place and do any
# last minute configuration.
RUN bash /opt/setup.sh

# Kick off the startup script, which does some healthcheck and then starts
# Apache if things look good.
CMD bash /opt/startup-prod.sh
