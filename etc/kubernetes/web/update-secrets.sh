#!/bin/bash
#
# TODO: make this work for dev
#

kubectl create secret generic dw-config \
        --from-file=config.pl=secrets/config.pl \
        --from-file=config-local.pl=secrets/config-local.pl \
        --from-file=config-private.pl=secrets/config-private.pl \
        --from-file=log4perl.conf=secrets/log4perl.conf \
        --from-file=config-private-prod.pl=secrets/config-private-prod.pl \
        --dry-run -o yaml |
    kubectl apply -f -
