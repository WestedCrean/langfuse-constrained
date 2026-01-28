#!/bin/bash

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="langfuse-test"
RELEASE_NAME="langfuse"
HELM_REPO="https://langfuse.github.io/langfuse-k8s"
PORT=3000

# Parse arguments
PORT_FORWARD=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --port-forward)
      PORT_FORWARD=true
      shift
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      echo "Usage: $0 [--port-forward]"
      exit 1
      ;;
  esac
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Langfuse Kubernetes Deployment Script${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl not found. Please install kubectl first.${NC}"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo -e "${RED}helm not found. Please install helm first.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ kubectl and helm found${NC}\n"

# Check if deployment already exists
if helm list -n $NAMESPACE 2>/dev/null | grep -q $RELEASE_NAME; then
    echo -e "${YELLOW}Langfuse is already deployed in namespace '$NAMESPACE'${NC}"
    read -p "Do you want to upgrade the existing deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Skipping deployment...${NC}"
        if [ "$PORT_FORWARD" = true ]; then
            echo -e "\n${YELLOW}Setting up port forwarding...${NC}"
            kubectl port-forward svc/langfuse-web -n $NAMESPACE $PORT:$PORT
        fi
        exit 0
    fi
    DEPLOY_CMD="upgrade"
else
    DEPLOY_CMD="install"
fi

# Add Helm repository
echo -e "${YELLOW}Adding Langfuse Helm repository...${NC}"
helm repo add langfuse $HELM_REPO 2>/dev/null || helm repo add langfuse $HELM_REPO --force-update
helm repo update
echo -e "${GREEN}✓ Helm repository added${NC}\n"

# Apply secrets
echo -e "${YELLOW}Applying secrets...${NC}"
if [ -f "secrets.yaml" ]; then
    kubectl apply -f secrets.yaml
    echo -e "${GREEN}✓ Secrets applied${NC}\n"
else
    echo -e "${RED}secrets.yaml not found in current directory!${NC}"
    exit 1
fi

# Deploy Langfuse
echo -e "${YELLOW}${DEPLOY_CMD^}ing Langfuse via Helm...${NC}"
if [ -f "values.yaml" ]; then
    helm $DEPLOY_CMD $RELEASE_NAME langfuse/langfuse -n $NAMESPACE -f values.yaml
    echo -e "${GREEN}✓ Langfuse ${DEPLOY_CMD}ed${NC}\n"
else
    echo -e "${RED}values.yaml not found in current directory!${NC}"
    exit 1
fi

# Wait for pods to be ready
echo -e "${YELLOW}Waiting for pods to be ready...${NC}"
echo -e "${BLUE}This may take 2-5 minutes...${NC}\n"

kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=langfuse -n $NAMESPACE --timeout=300s 2>/dev/null || true

# Check pod status
echo -e "\n${YELLOW}Current pod status:${NC}"
kubectl get pods -n $NAMESPACE

# Count running pods
TOTAL_PODS=$(kubectl get pods -n $NAMESPACE --no-headers | wc -l)
RUNNING_PODS=$(kubectl get pods -n $NAMESPACE --no-headers | grep "Running" | wc -l)

echo -e "\n${BLUE}Pods running: $RUNNING_PODS/$TOTAL_PODS${NC}"

if [ "$RUNNING_PODS" -eq "$TOTAL_PODS" ]; then
    echo -e "${GREEN}✓ All pods are running!${NC}\n"
else
    echo -e "${YELLOW}⚠ Some pods are still starting. Check status with:${NC}"
    echo -e "  kubectl get pods -n $NAMESPACE -w\n"
fi

# Check services
echo -e "${YELLOW}Services:${NC}"
kubectl get svc -n $NAMESPACE

# Success message
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}Access Langfuse:${NC}"
echo -e "  1. Port-forward: ${YELLOW}kubectl port-forward svc/langfuse-web -n $NAMESPACE $PORT:$PORT${NC}"
echo -e "  2. Then visit: ${YELLOW}http://localhost:$PORT${NC}\n"

echo -e "${BLUE}Useful commands:${NC}"
echo -e "  • View pods:        ${YELLOW}kubectl get pods -n $NAMESPACE${NC}"
echo -e "  • View logs (web):  ${YELLOW}kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=web --tail=100${NC}"
echo -e "  • Delete deployment:${YELLOW}helm uninstall $RELEASE_NAME -n $NAMESPACE${NC}\n"

# Port forward if requested
if [ "$PORT_FORWARD" = true ]; then
    echo -e "${GREEN}Setting up port forwarding...${NC}"
    echo -e "${BLUE}Press Ctrl+C to stop${NC}\n"
    kubectl port-forward svc/langfuse-web -n $NAMESPACE $PORT:$PORT
fi
