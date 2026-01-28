#!/bin/bash

echo "Deploying Langfuse using Helm..."

helm install langfuse langfuse/langfuse -n langfuse-test -f values.yaml