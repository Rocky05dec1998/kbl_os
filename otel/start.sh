#!/bin/bash
export OTEL_RESOURCE_ATTRIBUTES="server.ip=$(hostname -I | awk '{print $1}')"
docker compose up -d
