#!/bin/bash
#
# TODO: make this work for dev
#

kubectl create secret generic dw-config \
        --from-file=config.pl=config.pl \
        --from-file=config-local.pl=config-local.pl \
        --from-file=config-private.pl=config-private.pl \
        --from-file=log4perl.conf=log4perl.conf \
        --from-file=config-private-prod.pl=config-private-prod.pl \
        --dry-run -o yaml |
    kubectl apply -f -
