#!/bin/bash

# Script to encrypt a tarball file to .gpg with SHA-256 verification
# Usage: ./encrypt.sh <tarball_file> [sha256_hash]

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 <tarball_file> [sha256_hash] [options]"
    echo ""
    echo "Arguments:"
    echo "  tarball_file    Path to the tar/tar.gz/tar.bz2 file to encrypt"
    echo "  sha256_hash     (Optional) Expected SHA-256 hash for verification"
    echo ""
    echo "Options:"
    echo "  --password-file <file>    Path to file containing the encryption password"
    echo "                            (for automated/Docker use)"
    echo ""
    echo "If sha256_hash is not provided, the script will generate and display it."
    echo "If --password-file is not provided, GPG will prompt interactively for a passphrase."
    echo ""
    echo "Examples:"
    echo "  $0 backup.tar.gz"
    echo "  $0 backup.tar.gz a1b2c3d4..."
    echo "  $0 backup.tar.gz --password-file /run/secrets/gpg_password"
    echo "  $0 backup.tar.gz a1b2c3d4... --password-file /run/secrets/gpg_password"
    exit 1
}

# Function to print colored messages
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Check if gpg is installed
check_dependencies() {
    if ! command -v gpg &> /dev/null; then
        print_error "GPG is not installed. Please install it first."
        echo "  macOS: brew install gnupg"
        echo "  Linux: sudo apt-get install gnupg (Debian/Ubuntu) or sudo yum install gnupg (RHEL/CentOS)"
        exit 1
    fi
    
    if ! command -v shasum &> /dev/null && ! command -v sha256sum &> /dev/null; then
        print_error "Neither shasum nor sha256sum is available."
        exit 1
    fi
}

# Function to calculate SHA-256 hash
calculate_sha256() {
    local file="$1"
    if command -v shasum &> /dev/null; then
        shasum -a 256 "$file" | awk '{print $1}'
    elif command -v sha256sum &> /dev/null; then
        sha256sum "$file" | awk '{print $1}'
    fi
}

# Function to verify tarball integrity
verify_tarball() {
    local file="$1"
    print_info "Verifying tarball integrity..."
    
    case "$file" in
        *.tar.gz|*.tgz)
            if tar -tzf "$file" &> /dev/null; then
                print_success "Tarball integrity verified (gzip)"
                return 0
            else
                print_error "Tarball integrity check failed"
                return 1
            fi
            ;;
        *.tar.bz2|*.tbz2)
            if tar -tjf "$file" &> /dev/null; then
                print_success "Tarball integrity verified (bzip2)"
                return 0
            else
                print_error "Tarball integrity check failed"
                return 1
            fi
            ;;
        *.tar)
            if tar -tf "$file" &> /dev/null; then
                print_success "Tarball integrity verified (uncompressed)"
                return 0
            else
                print_error "Tarball integrity check failed"
                return 1
            fi
            ;;
        *)
            print_error "Unsupported file format. Supported formats: .tar, .tar.gz, .tgz, .tar.bz2, .tbz2"
            return 1
            ;;
    esac
}

# Main script
main() {
    # Check arguments
    if [ $# -lt 1 ]; then
        print_error "Missing required argument: tarball_file"
        echo ""
        usage
    fi

    TARBALL_FILE="$1"
    EXPECTED_HASH=""
    PASSWORD_FILE=""

    # Parse arguments
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --password-file)
                if [ -z "$2" ]; then
                    print_error "Missing value for --password-file"
                    usage
                fi
                PASSWORD_FILE="$2"
                shift 2
                ;;
            -*)
                print_error "Unknown option: $1"
                usage
                ;;
            *)
                if [ -z "$EXPECTED_HASH" ]; then
                    EXPECTED_HASH="$1"
                else
                    print_error "Too many arguments"
                    usage
                fi
                shift
                ;;
        esac
    done

    # Validate password file if provided
    if [ -n "$PASSWORD_FILE" ]; then
        if [ ! -f "$PASSWORD_FILE" ]; then
            print_error "Password file not found: $PASSWORD_FILE"
            exit 1
        fi
        if [ ! -r "$PASSWORD_FILE" ]; then
            print_error "Password file is not readable: $PASSWORD_FILE"
            exit 1
        fi
        # Check file permissions (warn if too permissive)
        if [ "$(uname)" = "Darwin" ]; then
            # macOS
            PERMS=$(stat -f "%Lp" "$PASSWORD_FILE")
        else
            # Linux
            PERMS=$(stat -c "%a" "$PASSWORD_FILE")
        fi
        if [ "$PERMS" != "400" ] && [ "$PERMS" != "600" ]; then
            print_info "Warning: Password file permissions are $PERMS (recommend 400 or 600)"
        fi
    fi

    # Check dependencies
    check_dependencies

    # Check if file exists
    if [ ! -f "$TARBALL_FILE" ]; then
        print_error "File not found: $TARBALL_FILE"
        exit 1
    fi

    print_info "Processing file: $TARBALL_FILE"
    echo ""

    # Verify tarball integrity
    if ! verify_tarball "$TARBALL_FILE"; then
        exit 1
    fi
    echo ""

    # Calculate SHA-256 hash
    print_info "Calculating SHA-256 hash..."
    CALCULATED_HASH=$(calculate_sha256 "$TARBALL_FILE")
    
    if [ -z "$CALCULATED_HASH" ]; then
        print_error "Failed to calculate SHA-256 hash"
        exit 1
    fi
    
    echo "SHA-256: $CALCULATED_HASH"
    echo ""

    # Verify hash if provided
    if [ -n "$EXPECTED_HASH" ]; then
        print_info "Verifying SHA-256 hash..."
        if [ "$CALCULATED_HASH" = "$EXPECTED_HASH" ]; then
            print_success "SHA-256 hash verification passed"
        else
            print_error "SHA-256 hash verification failed"
            echo "  Expected: $EXPECTED_HASH"
            echo "  Calculated: $CALCULATED_HASH"
            exit 1
        fi
        echo ""
    fi

    # Generate output filename
    OUTPUT_FILE="${TARBALL_FILE}.gpg"

    # Check if output file already exists
    if [ -f "$OUTPUT_FILE" ]; then
        print_info "Output file already exists: $OUTPUT_FILE"
        read -p "Do you want to overwrite it? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Encryption cancelled"
            exit 0
        fi
    fi

    # Encrypt the file
    print_info "Encrypting file to: $OUTPUT_FILE"
    
    if [ -n "$PASSWORD_FILE" ]; then
        # Use password file (for automation/Docker)
        print_info "Using password from file: $PASSWORD_FILE"
        if gpg --batch --yes --passphrase-file "$PASSWORD_FILE" --symmetric --cipher-algo AES256 --output "$OUTPUT_FILE" "$TARBALL_FILE"; then
            print_success "File encrypted successfully"
        else
            print_error "Encryption failed"
            exit 1
        fi
    else
        # Interactive mode (prompt for passphrase)
        print_info "You will be prompted to enter a passphrase"
        if gpg --symmetric --cipher-algo AES256 --output "$OUTPUT_FILE" "$TARBALL_FILE"; then
            print_success "File encrypted successfully"
        else
            print_error "Encryption failed"
            exit 1
        fi
    fi
    
    echo ""
    print_info "Encrypted file: $OUTPUT_FILE"
    print_info "Original SHA-256: $CALCULATED_HASH"
    
    # Save hash to a file
    HASH_FILE="${OUTPUT_FILE}.sha256"
    echo "$CALCULATED_HASH  $TARBALL_FILE" > "$HASH_FILE"
    print_success "SHA-256 hash saved to: $HASH_FILE"
}

# Run main function
main "$@"
