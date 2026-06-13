#!/bin/bash
set -e

# Allow replication connections with password auth
echo "host replication lb-user 0.0.0.0/0 scram-sha-256" >> "$PGDATA/pg_hba.conf"
