#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
"$PROJECT_DIR/tools/verify-coverage.sh"
cd "$PROJECT_DIR/tests"
alr -n build
./bin/flyology_object_storage_tests
./bin/s3_server_application_corpus
for run in 1 2 3
do
  ./bin/s3_http_socket_corpus
  ./bin/s3_transfer_many_corpus
done
