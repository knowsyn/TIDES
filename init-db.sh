#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username postgres <<-EOSQL
    CREATE USER tides PASSWORD '$(< $WWW_PASSWORD_FILE)';
EOSQL
