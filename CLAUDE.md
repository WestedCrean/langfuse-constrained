# Langfuse Self-Hosted Kubernetes Deployment

## Overview

This document describes a resource-constrained Langfuse deployment on Kubernetes using Helm, optimized for environments with limited RAM and CPU cores (5GB RAM, 3+ cores). This configuration is suitable for development, testing, and small-scale production workloads.

**Deployment Date**: 2026-01-28
**Langfuse Helm Chart Version**: 1.5.18
**Namespace**: langfuse-test

## Architecture

### Components

The deployment includes the following components:

1. **Langfuse Web** (1 replica)
   - Main web application and API
   - Resources: 512Mi-1Gi RAM, 500m-1 CPU
   - Health checks: /api/health endpoint
   - Port: 3000

2. **Langfuse Worker** (1 replica)
   - Background job processing
   - Resources: 512Mi-1Gi RAM, 500m-1 CPU
   - Handles async tasks and integrations

3. **PostgreSQL** (1 instance)
   - Primary database for application data
   - Resources: 256Mi-512Mi RAM, 250m-500m CPU
   - Storage: 5Gi persistent volume
   - Database: langfuse, User: langfuse

4. **Redis** (1 primary)
   - Caching and queue management
   - Resources: 256Mi-512Mi RAM, 250m-500m CPU
   - Storage: 2Gi persistent volume

5. **ClickHouse** (1 shard, 1 replica)
   - Analytics database for observability data
   - Resources: 512Mi-1Gi RAM, 500m-1 CPU
   - Storage: 10Gi persistent volume
   - Cluster mode: disabled (single instance)

6. **MinIO** (S3-compatible storage)
   - Object storage for exports and media
   - Resources: 256Mi-512Mi RAM, 250m-500m CPU
   - Storage: 10Gi persistent volume
   - Bucket: langfuse

7. **ZooKeeper** (3 replicas)
   - Coordination service for ClickHouse
   - Required for ClickHouse metadata management

### Resource Summary

**Total Resource Allocation:**
- Memory: ~5Gi (max limits)
- CPU: ~5 cores (max limits)
- Storage: ~45Gi persistent volumes

## Files

### Core Files

- **deploy.sh** - Deployment script that installs Langfuse via Helm
- **values.yaml** - Helm chart configuration with resource constraints and service settings
- **secrets.yaml** - Kubernetes secrets for all sensitive credentials (DO NOT commit to git)

### Configuration Files Description

#### deploy.sh
```bash
#!/bin/bash
echo "Deploying Langfuse using Helm..."
helm install langfuse langfuse/langfuse -n langfuse-test -f values.yaml
```

Simple deployment script that:
1. Uses the official Langfuse Helm repository
2. Deploys to the `langfuse-test` namespace
3. Applies custom values from `values.yaml`

#### values.yaml

Key configuration sections:

1. **Langfuse Core Configuration**
   ```yaml
   langfuse:
     salt:
       secretKeyRef: # Used to salt hashed API keys
     nextauth:
       secret:
         secretKeyRef: # JWT session secret
     encryptionKey:
       secretKeyRef: # Encrypts sensitive data (256-bit)
   ```

2. **Database Configurations**
   - PostgreSQL: Username/password via secrets, 5Gi storage
   - Redis: Password via secret, 2Gi storage
   - ClickHouse: Password via secret, 10Gi storage, cluster disabled
   - MinIO: Root user/password via secret, 10Gi storage

3. **Resource Constraints**
   - Each component has defined requests and limits
   - Prevents resource exhaustion in constrained environments

4. **Additional Environment Variables**
   - NEXTAUTH_URL: Set to http://localhost:3000 (update for production)
   - CLICKHOUSE_CLUSTER_ENABLED: "false" (single instance mode)

#### secrets.yaml

Contains all sensitive credentials:

- **langfuse-app-secret**: Application secrets (salt, nextauth-secret, encryption-key)
- **langfuse-postgres-secret**: Database credentials and connection string
- **langfuse-redis-secret**: Redis credentials and connection string
- **langfuse-clickhouse-secret**: ClickHouse password
- **langfuse-minio-secret**: MinIO root user and password

**IMPORTANT**: This file contains sensitive data and should:
- Never be committed to version control
- Be stored securely (e.g., encrypted vault, secret management system)
- Have restricted file permissions (chmod 600)

## Deployment Process

### Prerequisites

1. Kubernetes cluster (tested with Docker Desktop/K3s)
2. kubectl configured to access the cluster
3. Helm 3.x installed
4. Sufficient resources: 5GB RAM, 3+ CPU cores

### Initial Deployment Steps

1. **Add Langfuse Helm Repository**
   ```bash
   helm repo add langfuse https://langfuse.github.io/langfuse-k8s
   helm repo update
   ```

2. **Generate Secrets** (done automatically in secrets.yaml)
   ```bash
   # SALT (256-bit, base64)
   openssl rand -base64 32

   # NEXTAUTH_SECRET (256-bit, base64)
   openssl rand -base64 32

   # ENCRYPTION_KEY (256-bit, 64 hex chars)
   openssl rand -hex 32
   ```

3. **Create Namespace and Apply Secrets**
   ```bash
   kubectl apply -f secrets.yaml
   ```

   This creates:
   - langfuse-test namespace
   - All required secrets

4. **Deploy Langfuse**
   ```bash
   ./deploy.sh
   ```

   Or manually:
   ```bash
   helm install langfuse langfuse/langfuse -n langfuse-test -f values.yaml
   ```

5. **Wait for Pods to be Ready**
   ```bash
   kubectl get pods -n langfuse-test -w
   ```

   All pods should reach `1/1 Running` status within 2-5 minutes.

### Verification

1. **Check Pod Status**
   ```bash
   kubectl get pods -n langfuse-test
   ```

   Expected output: All pods showing `1/1 Running`

2. **Check Persistent Volumes**
   ```bash
   kubectl get pvc -n langfuse-test
   ```

   All PVCs should be `Bound`

3. **Check Services**
   ```bash
   kubectl get svc -n langfuse-test
   ```

4. **View Logs**
   ```bash
   # Web logs
   kubectl logs -n langfuse-test -l app=web --tail=100

   # Worker logs
   kubectl logs -n langfuse-test -l app=worker --tail=100
   ```

## Accessing Langfuse

### Port Forward (Development)

```bash
kubectl port-forward svc/langfuse-web -n langfuse-test 3000:3000
```

Then access Langfuse at: http://localhost:3000

### Ingress (Production)

For production deployments, configure an Ingress in values.yaml:

```yaml
ingress:
  enabled: true
  className: "nginx"  # or your ingress controller
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: langfuse.yourdomain.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: langfuse-tls
      hosts:
        - langfuse.yourdomain.com
```

Update `NEXTAUTH_URL` in values.yaml to match your domain.

## Troubleshooting

### Common Issues

#### 1. MinIO Pod - CreateContainerConfigError

**Error**: `couldn't find key root-user in Secret`

**Solution**: Ensure secrets.yaml includes both `root-user` and `root-password` keys:
```yaml
stringData:
  root-user: "minioadmin"
  root-password: "langfuse-minio-password"
```

#### 2. Worker Pod - CrashLoopBackOff with Redis WRONGPASS

**Error**: `WRONGPASS invalid username-password pair`

**Solutions**:
- Verify Redis secret has correct password
- Ensure values.yaml uses `redis` (not `valkey`) if using older chart versions
- Check Redis pod logs: `kubectl logs -n langfuse-test langfuse-redis-primary-0`

#### 3. PostgreSQL Authentication Failed

**Error**: Langfuse cannot connect to database

**Solutions**:
- Verify postgres-password in secret matches values.yaml configuration
- Check PostgreSQL logs: `kubectl logs -n langfuse-test langfuse-postgresql-0`
- Ensure connection string format: `postgresql://langfuse:PASSWORD@langfuse-postgresql:5432/langfuse`

#### 4. ClickHouse Issues

**Error**: ClickHouse migrations fail or cluster errors

**Solutions**:
- Ensure CLICKHOUSE_CLUSTER_ENABLED is "false" for single-node deployments
- Check ZooKeeper pods are running (required for ClickHouse)
- Verify ClickHouse has sufficient resources (needs CPU for queries)

#### 5. Pods Pending or Not Scheduled

**Error**: Pods stuck in `Pending` state

**Solutions**:
- Check cluster resources: `kubectl top nodes`
- Verify StorageClass exists: `kubectl get storageclass`
- Review pending pod: `kubectl describe pod <pod-name> -n langfuse-test`

### Debug Commands

```bash
# Get all resources in namespace
kubectl get all -n langfuse-test

# Describe pod for events/errors
kubectl describe pod <pod-name> -n langfuse-test

# Get pod logs (last 100 lines)
kubectl logs <pod-name> -n langfuse-test --tail=100

# Follow logs in real-time
kubectl logs <pod-name> -n langfuse-test -f

# Check secret contents (base64 encoded)
kubectl get secret <secret-name> -n langfuse-test -o yaml

# Execute command in pod
kubectl exec -it <pod-name> -n langfuse-test -- /bin/sh

# Check resource usage
kubectl top pods -n langfuse-test
kubectl top nodes
```

## Maintenance

### Upgrading Langfuse

1. **Update Helm Repository**
   ```bash
   helm repo update
   ```

2. **Check Available Versions**
   ```bash
   helm search repo langfuse/langfuse --versions
   ```

3. **Upgrade Release**
   ```bash
   helm upgrade langfuse langfuse/langfuse -n langfuse-test -f values.yaml
   ```

4. **Rollback if Needed**
   ```bash
   helm rollback langfuse -n langfuse-test
   ```

### Backup Strategy

#### 1. PostgreSQL Backup

```bash
# Create backup
kubectl exec -n langfuse-test langfuse-postgresql-0 -- \
  pg_dump -U langfuse langfuse > langfuse-backup-$(date +%Y%m%d).sql

# Restore backup
kubectl exec -i -n langfuse-test langfuse-postgresql-0 -- \
  psql -U langfuse langfuse < langfuse-backup-20260128.sql
```

#### 2. ClickHouse Backup

```bash
# Backup ClickHouse data
kubectl exec -n langfuse-test langfuse-clickhouse-shard0-0 -- \
  clickhouse-backup create backup-$(date +%Y%m%d)
```

#### 3. Secrets Backup

```bash
# Export all secrets (store securely)
kubectl get secrets -n langfuse-test -o yaml > secrets-backup.yaml
```

#### 4. Persistent Volume Backup

Use your Kubernetes provider's snapshot functionality or backup tools like Velero.

### Scaling Considerations

This deployment is configured for resource-constrained environments. For production scaling:

1. **Increase Replicas**
   ```yaml
   replicaCount: 2  # For web
   worker:
     replicaCount: 2  # For worker
   ```

2. **Add More Resources**
   ```yaml
   resources:
     limits:
       memory: "4Gi"
       cpu: "2"
   ```

3. **Enable ClickHouse Clustering**
   ```yaml
   clickhouse:
     shards: 2
     replicaCount: 3
   ```

4. **Add Ingress & TLS**

5. **Enable Redis Sentinel/Cluster** for high availability

6. **Use External Managed Services** (RDS, ElastiCache, etc.)

## Security Best Practices

### 1. Secrets Management

- Store secrets.yaml in a secure vault (HashiCorp Vault, AWS Secrets Manager, etc.)
- Use Kubernetes External Secrets Operator to sync secrets
- Rotate secrets regularly (especially API keys and passwords)
- Never commit secrets.yaml to version control

### 2. Network Policies

Enable network policies in values.yaml for production:
```yaml
networkPolicy:
  enabled: true
```

### 3. RBAC

Create service accounts with minimal permissions:
```bash
kubectl create serviceaccount langfuse -n langfuse-test
# Add appropriate role bindings
```

### 4. TLS/SSL

- Use cert-manager for automatic certificate management
- Enable HTTPS for all external endpoints
- Configure NEXTAUTH_URL with https://

### 5. Image Security

- Use specific image tags instead of `latest`
- Scan images for vulnerabilities
- Use private container registry if needed

## Monitoring and Observability

### Health Checks

Langfuse includes built-in health endpoints:

- **Liveness Probe**: /api/health (checks if app is alive)
- **Readiness Probe**: /api/health (checks if app is ready to serve traffic)

Configuration in values.yaml:
```yaml
livenessProbe:
  httpGet:
    path: /api/health
    port: 3000
  initialDelaySeconds: 60
  periodSeconds: 30

readinessProbe:
  httpGet:
    path: /api/health
    port: 3000
  initialDelaySeconds: 30
  periodSeconds: 10
```

### Metrics

For production monitoring:

1. **Prometheus + Grafana**
   - Scrape Kubernetes metrics
   - Monitor pod resource usage
   - Alert on pod restarts, high memory/CPU

2. **Application Metrics**
   - Langfuse exports metrics (configure in environment variables)
   - Monitor queue depths, request latency, error rates

3. **Log Aggregation**
   - Use EFK stack (Elasticsearch, Fluentd, Kibana)
   - Or Loki + Grafana
   - Centralize logs from all pods

## Uninstalling

### Remove Langfuse Deployment

```bash
# Uninstall Helm release
helm uninstall langfuse -n langfuse-test

# Delete namespace (includes secrets and PVCs)
kubectl delete namespace langfuse-test
```

**WARNING**: This will delete all data. Ensure you have backups before proceeding.

### Selective Cleanup

```bash
# Keep PVCs but remove deployment
helm uninstall langfuse -n langfuse-test

# Delete specific resources
kubectl delete deployment langfuse-web -n langfuse-test
kubectl delete secret langfuse-app-secret -n langfuse-test
```

## Production Readiness Checklist

Before deploying to production:

- [ ] Use specific Langfuse image tag (not `latest`)
- [ ] Generate strong, unique secrets (never use example values)
- [ ] Configure NEXTAUTH_URL with production domain
- [ ] Enable and configure Ingress with TLS
- [ ] Set up database backups (automated, tested)
- [ ] Configure resource limits based on actual workload
- [ ] Enable network policies
- [ ] Set up monitoring and alerting
- [ ] Configure log aggregation
- [ ] Document incident response procedures
- [ ] Test disaster recovery process
- [ ] Review and implement security best practices
- [ ] Scale replicas for high availability
- [ ] Use external managed services for databases (optional)
- [ ] Enable pod disruption budgets
- [ ] Configure horizontal pod autoscaling (if needed)

## Known Limitations

1. **Single Replica Components**
   - PostgreSQL, Redis, ClickHouse run as single instances
   - No automatic failover
   - Suitable for dev/test, not production HA requirements

2. **Resource Constraints**
   - Configured for 5GB RAM / 3 CPU cores
   - May experience performance issues under heavy load
   - Not suitable for large-scale production workloads

3. **No High Availability**
   - No redundancy for critical components
   - Single point of failure for each service

4. **Limited Storage**
   - 45Gi total storage may fill up quickly
   - Monitor disk usage regularly
   - Implement data retention policies

5. **Local Storage**
   - Uses default StorageClass
   - May not have backup/snapshot capabilities
   - Consider using cloud provider storage classes

## Support and Documentation

### Official Langfuse Documentation

- Website: https://langfuse.com
- Docs: https://langfuse.com/docs
- Self-Hosting Guide: https://langfuse.com/self-hosting
- Kubernetes/Helm: https://langfuse.com/self-hosting/deployment/kubernetes-helm

### Helm Chart Repository

- GitHub: https://github.com/langfuse/langfuse-k8s
- Chart README: https://github.com/langfuse/langfuse-k8s/blob/main/README.md

### Community Support

- GitHub Discussions: https://github.com/orgs/langfuse/discussions
- GitHub Issues: https://github.com/langfuse/langfuse/issues
- Discord: https://langfuse.com/discord

## Changelog

### 2026-01-28 - Initial Deployment

- Deployed Langfuse v1.5.18 via Helm
- Configured resource-constrained setup (5GB RAM, 3 cores)
- Created secrets management with generated credentials
- Configured all required services:
  - PostgreSQL 1 instance (5Gi storage)
  - Redis 1 primary (2Gi storage)
  - ClickHouse 1 shard (10Gi storage, cluster mode disabled)
  - MinIO S3-compatible storage (10Gi storage)
  - ZooKeeper 3 replicas for ClickHouse coordination
- Resolved deployment issues:
  - Fixed MinIO secret configuration (added root-user key)
  - Fixed Redis authentication (changed valkey to redis)
  - Fixed PostgreSQL secret references
- Verified successful deployment with all pods running
- Created comprehensive documentation

## Additional Notes

### Environment Variables

The Helm chart automatically configures most environment variables based on the deployed services. Manual configuration via `additionalEnv` in values.yaml is only needed for:

- NEXTAUTH_URL (set to your domain)
- LANGFUSE_LOG_LEVEL (debug, info, warn, error)
- Custom feature flags or integrations

### Database Migrations

Langfuse automatically runs database migrations on startup. The web and worker pods may restart once or twice during initial deployment while migrations complete. This is expected behavior.

### First-Time Setup

After deployment:

1. Access Langfuse UI (via port-forward or ingress)
2. Create your first admin account
3. Create an organization
4. Create a project
5. Generate API keys for your application

### ClickHouse Single-Node Mode

This deployment uses ClickHouse in single-node mode (cluster disabled) for resource efficiency. This is sufficient for development and small production workloads. For larger deployments, enable clustering:

```yaml
clickhouse:
  shards: 2
  replicaCount: 3
  # Then enable cluster mode in additionalEnv:
  - name: CLICKHOUSE_CLUSTER_ENABLED
    value: "true"
```

---

**Document Maintained By**: Claude (AI Assistant)
**Last Updated**: 2026-01-28
**Version**: 1.0
