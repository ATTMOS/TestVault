# Docker Integration Guide

This guide explains how to use the encryption/decryption scripts with Docker containers using Docker secrets for secure password management.

## Overview

TestVault's encryption/decryption scripts are designed to work seamlessly in containerized environments. This guide covers Docker Swarm secrets, Docker Compose, Kubernetes secrets, and CI/CD integration patterns.

## Docker Secrets Approach (Recommended for Production)

### 1. Create a Docker Secret

```bash
# Create a text file with your password
echo "your-secure-password" > gpg_password.txt

# Create Docker secret (Docker Swarm)
docker secret create gpg_password gpg_password.txt

# Clean up the password file
rm gpg_password.txt
```

### 2. Example Docker Compose with Secrets

```yaml
version: '3.8'

services:
  app:
    image: your-app:latest
    secrets:
      - gpg_password
    volumes:
      - ./data:/data:ro            # Mount data directory read-only
      - ./scripts:/scripts:ro      # Mount scripts read-only
    command: >
      sh -c "
        /scripts/decrypt.sh /data/amber/tests/v2025-11-01/test.tar.gz.gpg 
        --password-file /run/secrets/gpg_password 
        --verify-hash &&
        tar -xzf /data/amber/tests/v2025-11-01/test.tar.gz -C /app &&
        /app/start.sh
      "

secrets:
  gpg_password:
    external: true
```

**How it works:**
- The secret will be available at `/run/secrets/gpg_password` inside the container
- Files are mounted read-only for security
- Decryption happens with hash verification
- Extracted data goes to `/app`

## Volume Mount Approach (Development)

For development or simpler setups, you can mount the password file directly:

### Example Dockerfile

```dockerfile
FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && \
    apt-get install -y gnupg && \
    rm -rf /var/lib/apt/lists/*

# Copy scripts
COPY scripts/ /usr/local/bin/

# Make scripts executable
RUN chmod +x /usr/local/bin/*.sh

WORKDIR /app

# The password file will be mounted at runtime
CMD ["/usr/local/bin/decrypt.sh", "/data/backup.tar.gz.gpg", \
     "--password-file", "/secrets/gpg_password", "--verify-hash"]
```

### Running the Container

```bash
# Create password file (secure location)
echo "your-secure-password" > /secure/gpg_password
chmod 400 /secure/gpg_password

# Run container with mounted password
docker run -v /secure/gpg_password:/secrets/gpg_password:ro \
           -v $(pwd)/data:/data \
           your-image:latest
```

## Complete Docker Example with TestVault

### Full Dockerfile Example

```dockerfile
FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && \
    apt-get install -y gnupg git git-lfs && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Clone TestVault repository with LFS support
RUN git lfs install && \
    git clone https://github.com/ATTMOS/TestVault.git /testvault && \
    cd /testvault && \
    git lfs pull

# Copy your application
COPY . /app

# The entrypoint will decrypt data at runtime
ENTRYPOINT ["/testvault/scripts/decrypt.sh"]
CMD ["/testvault/data/amber/tests/v2025-11-01/test.tar.gz.gpg", \
     "--password-file", "/run/secrets/gpg_password", \
     "--verify-hash", \
     "--output", "/app/data/test.tar.gz"]
```

## Environment-Specific Setup

### Development

```bash
# Store password in a local file (add to .gitignore!)
echo "dev-password" > .gpg_password
chmod 400 .gpg_password

# Encrypt
./scripts/encrypt.sh backup.tar.gz --password-file .gpg_password

# Decrypt
./scripts/decrypt.sh backup.tar.gz.gpg --password-file .gpg_password --verify-hash
```

### Staging

```bash
# Use Docker Compose with file-based secret
echo "staging-password" > /secure/gpg_password
chmod 400 /secure/gpg_password

docker-compose -f docker-compose.staging.yml up
```

### Production (Kubernetes)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: gpg-password
type: Opaque
stringData:
  password: your-secure-password
---
apiVersion: v1
kind: Pod
metadata:
  name: data-processor
spec:
  containers:
  - name: app
    image: your-app:latest
    command:
      - /scripts/decrypt.sh
      - /data/backup.tar.gz.gpg
      - --password-file
      - /secrets/password
      - --verify-hash
    volumeMounts:
    - name: secrets
      mountPath: /secrets
      readOnly: true
    - name: data
      mountPath: /data
  volumes:
  - name: secrets
    secret:
      secretName: gpg-password
      items:
      - key: password
        path: password
        mode: 0400
  - name: data
    persistentVolumeClaim:
      claimName: data-pvc
```

## Security Best Practices

### 1. Password File Permissions

Always set strict permissions on password files:

```bash
chmod 400 password_file  # Read-only for owner
```

### 2. Never Commit Passwords

Add to `.gitignore`:

```
*.password
*_password
.gpg_password
gpg_password.txt
```

### 3. Rotate Passwords Regularly

```bash
# Re-encrypt with new password
./scripts/decrypt.sh backup.tar.gz.gpg --password-file old_password
./scripts/encrypt.sh backup.tar.gz --password-file new_password
```

### 4. Use Docker Secrets in Production

- Never use environment variables for passwords
- Never mount password files from the host in production
- Use Docker secrets (Swarm) or Kubernetes secrets

### 5. Verify Hash After Decryption

Always use `--verify-hash` to ensure file integrity:

```bash
./scripts/decrypt.sh backup.tar.gz.gpg \
  --password-file /run/secrets/gpg_password \
  --verify-hash
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Build and Test with Encrypted Data

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
        with:
          lfs: true  # Enable Git LFS
      
      - name: Install dependencies
        run: sudo apt-get update && sudo apt-get install -y gnupg
      
      - name: Create password file
        run: |
          echo "${{ secrets.GPG_PASSWORD }}" > /tmp/gpg_password
          chmod 400 /tmp/gpg_password
      
      - name: Decrypt test data
        run: |
          ./scripts/decrypt.sh data/amber/tests/v2025-11-01/test.tar.gz.gpg \
            --password-file /tmp/gpg_password \
            --verify-hash \
            --output /tmp/test.tar.gz
      
      - name: Extract and run tests
        run: |
          tar -xzf /tmp/test.tar.gz -C /tmp
          # Run your tests here
      
      - name: Cleanup sensitive files
        if: always()
        run: rm -f /tmp/gpg_password /tmp/test.tar.gz
```

### GitLab CI

```yaml
test:
  image: ubuntu:22.04
  before_script:
    - apt-get update && apt-get install -y gnupg git git-lfs
    - git lfs pull
    - echo "$GPG_PASSWORD" > /tmp/gpg_password
    - chmod 400 /tmp/gpg_password
  script:
    - ./scripts/decrypt.sh data/amber/tests/v2025-11-01/test.tar.gz.gpg 
        --password-file /tmp/gpg_password 
        --verify-hash
    - tar -xzf data/amber/tests/v2025-11-01/test.tar.gz
    - ./run-tests.sh
  after_script:
    - rm -f /tmp/gpg_password
  variables:
    GIT_LFS_SKIP_SMUDGE: "0"
```

## Complete Workflow Example

### Step 1: Prepare and Encrypt Data

```bash
# Create tarball from your test data
tar -czf test-data.tar.gz /path/to/test/data

# Encrypt with password file
./scripts/encrypt.sh test-data.tar.gz --password-file /secrets/gpg_password

# Organize encrypted files
mkdir -p data/project/dataset/v2025-11-01
mv test-data.tar.gz.gpg test-data.tar.gz.gpg.sha256 data/project/dataset/v2025-11-01/

# Create manifest
cat > data/project/dataset/v2025-11-01/manifest.json << 'EOF'
{
  "version": "v2025-11-01",
  "created_at": "2025-11-01T00:00:00Z",
  "dataset": "project/dataset",
  "files": [{
    "name": "test-data.tar.gz.gpg",
    "type": "encrypted_archive",
    "encryption": {"algorithm": "GPG", "cipher": "AES256"},
    "original_file": "test-data.tar.gz",
    "sha256": "YOUR_SHA256_HERE"
  }]
}
EOF
```

### Step 2: Commit to Repository

```bash
# Add files (Git LFS will handle .gpg automatically)
git add data/
git commit -m "Add encrypted test dataset v2025-11-01"
git push

# Git LFS will upload the large .gpg file
```

### Step 3: Use in Docker Container

### Step 4: Container Startup Script

```bash
#!/bin/bash
# entrypoint.sh - Container startup script
set -e

echo "Decrypting test data..."
/testvault/scripts/decrypt.sh \
  /testvault/data/amber/tests/v2025-11-01/test.tar.gz.gpg \
  --password-file /run/secrets/gpg_password \
  --verify-hash \
  --output /tmp/test.tar.gz

echo "Extracting test data..."
tar -xzf /tmp/test.tar.gz -C /app/data

echo "Starting application..."
exec /app/start.sh
```

## Real-World Examples

### Example 1: ML Model Training with Encrypted Datasets

```dockerfile
FROM python:3.11-slim

# Install dependencies
RUN apt-get update && \
    apt-get install -y gnupg git git-lfs && \
    rm -rf /var/lib/apt/lists/*

# Clone TestVault
RUN git clone https://github.com/ATTMOS/TestVault.git /testvault && \
    cd /testvault && git lfs pull

# Install Python packages
COPY requirements.txt .
RUN pip install -r requirements.txt

WORKDIR /app
COPY . /app

# Decrypt and extract training data at runtime
CMD ["/bin/bash", "-c", "\
  /testvault/scripts/decrypt.sh \
    /testvault/data/amber/tests/v2025-11-01/test.tar.gz.gpg \
    --password-file /run/secrets/gpg_password \
    --verify-hash && \
  tar -xzf /testvault/data/amber/tests/v2025-11-01/test.tar.gz -C /app/training_data && \
  python train.py"]
```

### Example 2: Automated Testing Pipeline

```yaml
# docker-compose.test.yml
version: '3.8'

services:
  test-runner:
    build: .
    secrets:
      - gpg_password
    volumes:
      - ./TestVault:/testvault:ro
      - test-results:/results
    environment:
      - TEST_DATA_PATH=/app/test-data
    command: >
      sh -c "
        /testvault/scripts/decrypt.sh 
          /testvault/data/amber/tests/v2025-11-01/test.tar.gz.gpg 
          --password-file /run/secrets/gpg_password 
          --verify-hash &&
        tar -xzf /testvault/data/amber/tests/v2025-11-01/test.tar.gz -C /app/test-data &&
        pytest tests/ --junit-xml=/results/junit.xml
      "

volumes:
  test-results:

secrets:
  gpg_password:
    file: ./.secrets/gpg_password
```

## Best Practices Summary

### ✅ Do's

1. **Use Docker secrets** in Swarm or Kubernetes secrets in K8s
2. **Mount volumes read-only** when possible (`ro` flag)
3. **Verify hashes** after decryption with `--verify-hash`
4. **Install Git LFS** in containers that clone TestVault
5. **Clean up** decrypted files after use
6. **Set proper permissions** on password files (400 or 600)
7. **Use multi-stage builds** to keep images small

### ❌ Don'ts

1. **Don't use environment variables** for passwords
2. **Don't commit** password files to repositories
3. **Don't skip** hash verification in production
4. **Don't expose** password files in logs or error messages
5. **Don't use** world-readable permissions on secrets

## Troubleshooting

### Git LFS Files Not Available in Container

```dockerfile
# Ensure Git LFS is installed and files are pulled
RUN apt-get update && apt-get install -y git-lfs && \
    git lfs install && \
    git clone https://github.com/ATTMOS/TestVault.git /testvault && \
    cd /testvault && git lfs pull
```

### Permission Denied on Password File

```bash
# Fix permissions on host
chmod 400 /path/to/password_file

# In Dockerfile, ensure proper ownership
RUN chown appuser:appuser /secrets/password && chmod 400 /secrets/password
```

### GPG Not Found in Container

```dockerfile
# Add to Dockerfile (Debian/Ubuntu)
RUN apt-get update && apt-get install -y gnupg

# Alpine Linux
RUN apk add --no-cache gnupg
```

### Hash Verification Failed

```bash
# Check if .sha256 file exists alongside .gpg file
ls -la data/amber/tests/v2025-11-01/test.tar.gz.gpg.sha256

# Manual verification
sha256sum data/amber/tests/v2025-11-01/test.tar.gz
cat data/amber/tests/v2025-11-01/test.tar.gz.gpg.sha256

# Ensure Git LFS pulled the actual file, not just the pointer
git lfs pull
```

### Container Can't Access Secrets

```bash
# Verify secret exists (Docker Swarm)
docker secret ls

# Check secret is mounted in container
docker exec <container> ls -la /run/secrets/

# Verify secret content (be careful in production!)
docker exec <container> cat /run/secrets/gpg_password
```

### Decryption Hangs or Fails

```bash
# Ensure using --batch mode with password file
gpg --batch --yes --passphrase-file /run/secrets/gpg_password ...

# Check GPG agent isn't waiting for input
export GPG_TTY=$(tty)

# In containers, ensure scripts use non-interactive mode
```

## Script Usage Summary

## Performance Considerations

### Optimizing Large File Decryption

```dockerfile
# Use multi-stage build to decrypt at build time (if password is build-time secret)
FROM ubuntu:22.04 AS decryptor
RUN apt-get update && apt-get install -y gnupg git git-lfs
RUN git clone https://github.com/ATTMOS/TestVault.git /testvault && \
    cd /testvault && git lfs pull
ARG GPG_PASSWORD
RUN echo "$GPG_PASSWORD" > /tmp/pass && \
    /testvault/scripts/decrypt.sh \
      /testvault/data/amber/tests/v2025-11-01/test.tar.gz.gpg \
      --password-file /tmp/pass \
      --verify-hash && \
    rm /tmp/pass

FROM ubuntu:22.04
COPY --from=decryptor /testvault/data/amber/tests/v2025-11-01/test.tar.gz /data/
RUN tar -xzf /data/test.tar.gz -C /app/data && rm /data/test.tar.gz
COPY . /app
CMD ["/app/start.sh"]
```

### Caching Decrypted Data

```yaml
# docker-compose.yml with cached volumes
services:
  app:
    image: your-app:latest
    volumes:
      - decrypted-data:/app/data  # Reused across container restarts
    command: >
      sh -c "
        if [ ! -f /app/data/.decrypted ]; then
          /testvault/scripts/decrypt.sh ... &&
          tar -xzf ... -C /app/data &&
          touch /app/data/.decrypted
        fi &&
        /app/start.sh
      "

volumes:
  decrypted-data:
```

## Quick Reference

### Script Options

**encrypt.sh**
```bash
./scripts/encrypt.sh <tarball> [sha256_hash] [--password-file <file>]
```

**decrypt.sh**
```bash
./scripts/decrypt.sh <encrypted_file> [options]
  --password-file <file>    Password file path
  --output <file>           Output file path
  --verify-hash            Verify SHA-256 after decryption
```

### Common Docker Commands

```bash
# Create secret from file
docker secret create gpg_password /path/to/password

# Create secret from stdin
echo "password" | docker secret create gpg_password -

# List secrets
docker secret ls

# Inspect secret (doesn't show value)
docker secret inspect gpg_password

# Remove secret
docker secret rm gpg_password

# Run with secret
docker run --secret gpg_password your-image:latest
```

### Kubernetes Quick Commands

```bash
# Create secret
kubectl create secret generic gpg-password --from-literal=password=yourpassword

# Create from file
kubectl create secret generic gpg-password --from-file=password=/path/to/password

# Get secrets
kubectl get secrets

# Describe secret
kubectl describe secret gpg-password

# Delete secret
kubectl delete secret gpg-password
```

## Additional Resources

- [Docker Secrets Documentation](https://docs.docker.com/engine/swarm/secrets/)
- [Kubernetes Secrets Documentation](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Git LFS Documentation](https://git-lfs.github.com/)
- [GPG Documentation](https://gnupg.org/documentation/)
- [TestVault README](../README.md)

## Support

For issues or questions:
- Open an issue on [GitHub](https://github.com/ATTMOS/TestVault/issues)
- Check existing issues for solutions
- Review the main [README.md](../README.md) for general usage
