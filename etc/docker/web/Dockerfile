#
# This creates a Dreamwidth webserver.
#

FROM  ghcr.io/dreamwidth/base:latest
LABEL org.opencontainers.image.authors="Mark Smith <mark@dreamwidth.org>"

# Configuration can go here.
ARG COMMIT=main

# Things that commands need, but shouldn't change.
ENV LJHOME /dw

# Install some packages we need in web only.
RUN echo $COMMIT && \
    apt-get update && \
    apt-get install -y mysql-client varnish && \
    curl https://raw.githubusercontent.com/dreamwidth/dreamwidth/main/doc/dependencies-system | \
        xargs apt-get -y install && \
    curl https://raw.githubusercontent.com/dreamwidth/dreamwidth/main/doc/dependencies-cpanm | \
        xargs cpanm -n -L /dw/extlib/ && \
    rm -rf /var/lib/apt/lists/*

# Actually check out the source code now.
RUN git -C $LJHOME fetch && \
    git -C $LJHOME checkout $COMMIT && \
    git -C $LJHOME pull --ff-only origin $COMMIT && \
    $LJHOME/bin/build-static.sh

# Copy in support scripts/configurations that are useful.
ADD scripts/ /opt/
ADD config/ /dw/ext/local

# Setup script that runs to make sure we get configs in the right place and do any
# last minute configuration.
RUN bash /opt/setup.sh

# We run on 80, TLS is handled by a proxy of some kind.
EXPOSE 80/tcp

# Varnish is here and is layered in front of Apache typically.
EXPOSE 6081/tcp

# Kick off the startup script, which does some healthcheck and then starts
# Apache if things look good.
CMD bash /opt/startup-prod.sh
