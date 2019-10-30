#!/bin/bash
set -e

KEY=/etc/ssl/private/tides.key
CERT=/etc/ssl/certs/tides.pem
if [ -f /run/secrets/key ]; then
    ln -s /run/secrets/key $KEY
    ln -s /run/secrets/cert $CERT
else
    ln -s /etc/ssl/private/ssl-cert-snakeoil.key $KEY
    ln -s /etc/ssl/certs/ssl-cert-snakeoil.pem $CERT
fi

exec "$@"
