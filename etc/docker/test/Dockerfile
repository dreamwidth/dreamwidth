#
# Test container that does basically nothing, just used for testing out the
# build flow.
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
    apt-get install -y curl git tzdata rsync vim
