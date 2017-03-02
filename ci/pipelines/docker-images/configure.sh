#!/bin/bash

exec fly -t production set-pipeline \
  -p bosh:test-docker-image \
  -c ./pipeline.yml \
  --load-vars-from <(lpass show --note "bosh:docker-images concourse secrets")
