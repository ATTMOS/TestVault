# TestVault

Public storage for encrypted test assets to support CI and reproducible local setups.

## Overview

TestVault provides a secure way to store and distribute test data files using GPG encryption. Large encrypted files are managed with Git LFS, making them accessible to CI/CD pipelines and Docker containers.

## Features

- 🔐 **GPG Encryption** - AES256 symmetric encryption for test data
- ✅ **SHA-256 Verification** - Integrity checks before and after encryption
- 🐳 **Docker Ready** - Password file support for automated decryption
- 📦 **Git LFS** - Efficient storage for large encrypted files
- 📋 **Manifest Files** - JSON metadata for each dataset

## Repository Structure

```
TestVault/
├── scripts/
│   ├── encrypt.sh          # Encrypt tarballs with GPG
│   └── decrypt.sh          # Decrypt .gpg files
├── data/
│   └── amber/
│       └── tests/
│           └── v2025-11-01/
│               ├── test.tar.gz.gpg      # Encrypted data (Git LFS)
│               ├── test.tar.gz.gpg.sha256  # SHA-256 hash
│               └── manifest.json        # Dataset metadata
└── docker-example.md       # Docker integration guide
```

## Quick Start

### Encrypting Data

```bash
# Interactive (prompts for password)
./scripts/encrypt.sh backup.tar.gz

# Automated with password file
./scripts/encrypt.sh backup.tar.gz --password-file /path/to/password

# With hash verification
./scripts/encrypt.sh backup.tar.gz expected_sha256 --password-file /path/to/password
```

### Decrypting Data

```bash
# Interactive (prompts for password)
./scripts/decrypt.sh data/amber/tests/v2025-11-01/test.tar.gz.gpg

# Automated with password file
./scripts/decrypt.sh data/amber/tests/v2025-11-01/test.tar.gz.gpg \
  --password-file /path/to/password

# With hash verification
./scripts/decrypt.sh data/amber/tests/v2025-11-01/test.tar.gz.gpg \
  --password-file /path/to/password \
  --verify-hash
```

## Docker Integration

### Using Docker Secrets (Recommended)

```yaml
# docker-compose.yml
services:
  app:
    image: your-app:latest
    secrets:
      - gpg_password
    volumes:
      - ./scripts:/scripts
      - ./data:/data
    command: >
      sh -c "
        /scripts/decrypt.sh /data/amber/tests/v2025-11-01/test.tar.gz.gpg 
        --password-file /run/secrets/gpg_password 
        --verify-hash &&
        tar -xzf /data/amber/tests/v2025-11-01/test.tar.gz -C /app
      "

secrets:
  gpg_password:
    external: true
```

### Create Docker Secret

```bash
echo "your-secure-password" | docker secret create gpg_password -
```

See [docker-example.md](docker-example.md) for complete Docker and Kubernetes examples.

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Test with Encrypted Data

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          lfs: true
      
      - name: Install GPG
        run: sudo apt-get update && sudo apt-get install -y gnupg
      
      - name: Create password file
        run: echo "${{ secrets.GPG_PASSWORD }}" > /tmp/gpg_password
      
      - name: Decrypt test data
        run: |
          ./scripts/decrypt.sh data/amber/tests/v2025-11-01/test.tar.gz.gpg \
            --password-file /tmp/gpg_password \
            --verify-hash
      
      - name: Extract data
        run: tar -xzf data/amber/tests/v2025-11-01/test.tar.gz
      
      - name: Run tests
        run: ./run-tests.sh
      
      - name: Cleanup
        if: always()
        run: rm -f /tmp/gpg_password
```

## Git LFS Setup

This repository uses Git LFS for large encrypted files. To clone and work with this repository:

```bash
# Install Git LFS (if not already installed)
brew install git-lfs  # macOS
# or
sudo apt-get install git-lfs  # Ubuntu/Debian

# Clone the repository
git clone https://github.com/ATTMOS/TestVault.git
cd TestVault

# Pull LFS files
git lfs pull
```

### Adding New Encrypted Files

All `.gpg` files are automatically tracked by Git LFS:

```bash
# Encrypt your data
./scripts/encrypt.sh new-data.tar.gz --password-file password.txt

# Move to appropriate location
mkdir -p data/project/dataset/v2025-11-01
mv new-data.tar.gz.gpg new-data.tar.gz.gpg.sha256 data/project/dataset/v2025-11-01/

# Create manifest.json
# ... (see existing manifests for format)

# Commit and push
git add data/
git commit -m "Add new encrypted dataset"
git push
```

## Security Best Practices

### Password Management

- ✅ **Use Docker Secrets** or Kubernetes Secrets in production
- ✅ **Store passwords** in secure vaults (AWS Secrets Manager, HashiCorp Vault, etc.)
- ✅ **Set strict permissions** on password files (`chmod 400`)
- ❌ **Never commit** password files to the repository
- ❌ **Never use** environment variables for passwords in production

### Password File Permissions

```bash
# Create password file with restricted permissions
echo "your-password" > password.txt
chmod 400 password.txt
```

### Verifying Integrity

Always verify file integrity after decryption:

```bash
./scripts/decrypt.sh file.tar.gz.gpg \
  --password-file /run/secrets/gpg_password \
  --verify-hash
```

## Manifest File Format

Each encrypted dataset includes a `manifest.json` with metadata:

```json
{
  "version": "v2025-11-01",
  "created_at": "2025-11-01T00:00:00Z",
  "dataset": "amber/tests",
  "files": [
    {
      "name": "test.tar.gz.gpg",
      "type": "encrypted_archive",
      "encryption": {
        "algorithm": "GPG",
        "cipher": "AES256",
        "mode": "symmetric"
      },
      "original_file": "test.tar.gz",
      "sha256": "90276dad7773ae36a736611283b3ffef55741c1f0c1c69ac20d12fa003f1932f",
      "sha256_file": "test.tar.gz.gpg.sha256"
    }
  ],
  "decryption": {
    "command": "./scripts/decrypt.sh test.tar.gz.gpg --password-file /run/secrets/gpg_password --verify-hash",
    "password_location": "/run/secrets/gpg_password"
  }
}
```

## Requirements

- **GPG** - GNU Privacy Guard for encryption/decryption
- **Git LFS** - For cloning repositories with large files
- **shasum/sha256sum** - For hash verification (usually pre-installed)

### Installing Dependencies

```bash
# macOS
brew install gnupg git-lfs

# Ubuntu/Debian
sudo apt-get install gnupg git-lfs

# RHEL/CentOS
sudo yum install gnupg2 git-lfs
```

## Troubleshooting

### Git LFS Files Not Downloaded

```bash
git lfs pull
```

### Permission Denied on Password File

```bash
chmod 400 /path/to/password/file
```

### Hash Verification Failed

```bash
# Check if .sha256 file exists
ls -la data/path/to/file.tar.gz.gpg.sha256

# Manually verify
sha256sum data/path/to/file.tar.gz
cat data/path/to/file.tar.gz.gpg.sha256
```

### GPG Not Found in Docker

```dockerfile
RUN apt-get update && apt-get install -y gnupg
```

## Contributing

When adding new encrypted datasets:

1. Encrypt with the encryption script
2. Place files in appropriate `data/` subdirectory
3. Create a `manifest.json` with metadata
4. Git LFS will automatically track `.gpg` files
5. Commit and push

## License

See [LICENSE](LICENSE) for details.
