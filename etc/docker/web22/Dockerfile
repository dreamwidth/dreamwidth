#
# This creates a Dreamwidth webserver.
#

FROM  ghcr.io/dreamwidth/base22:latest
LABEL org.opencontainers.image.authors="Mark Smith <mark@dreamwidth.org>"

# Configuration can go here.
ARG COMMIT=main

# Things that commands need, but shouldn't change.
ENV LJHOME /dw

# Refresh apt lists for the dependency install below (and bust the build cache
# when COMMIT changes).
RUN echo $COMMIT && \
    apt-get update


# Actually check out the source code now & install branch dependencies.
RUN git -C $LJHOME fetch && \
    git -C $LJHOME checkout $COMMIT && \
    git -C $LJHOME pull --ff-only origin $COMMIT && \
    cat $LJHOME/doc/dependencies-system | xargs apt-get -y install && \
    cat $LJHOME/doc/dependencies-cpanm | xargs cpanm -n -L /dw/extlib/ && \
    rm -rf /var/lib/apt/lists/*

RUN $LJHOME/bin/build-static.sh

# Copy in support scripts that are useful.
ADD scripts/ /opt/

EXPOSE 8080/tcp

# Kick off the startup script, which does some healthcheck and then starts
# Starman if things look good.
CMD bash /opt/startup-prod.sh
