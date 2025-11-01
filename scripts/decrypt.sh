#!/bin/bash

# Script to decrypt a .gpg encrypted file with SHA-256 verification
# Usage: ./decrypt.sh <encrypted_file> [options]

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 <encrypted_file> [options]"
    echo ""
    echo "Arguments:"
    echo "  encrypted_file    Path to the .gpg file to decrypt"
    echo ""
    echo "Options:"
    echo "  --password-file <file>    Path to file containing the decryption password"
    echo "                            (for automated/Docker use)"
    echo "  --output <file>           Output file path (default: removes .gpg extension)"
    echo "  --verify-hash             Verify SHA-256 hash after decryption (requires .sha256 file)"
    echo ""
    echo "If --password-file is not provided, GPG will prompt interactively for a passphrase."
    echo ""
    echo "Examples:"
    echo "  $0 backup.tar.gz.gpg"
    echo "  $0 backup.tar.gz.gpg --password-file /run/secrets/gpg_password"
    echo "  $0 backup.tar.gz.gpg --password-file /run/secrets/gpg_password --verify-hash"
    echo "  $0 backup.tar.gz.gpg --output /tmp/backup.tar.gz"
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

# Main script
main() {
    # Check arguments
    if [ $# -lt 1 ]; then
        print_error "Missing required argument: encrypted_file"
        echo ""
        usage
    fi

    ENCRYPTED_FILE="$1"
    PASSWORD_FILE=""
    OUTPUT_FILE=""
    VERIFY_HASH=false

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
            --output)
                if [ -z "$2" ]; then
                    print_error "Missing value for --output"
                    usage
                fi
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --verify-hash)
                VERIFY_HASH=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                usage
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
    fi

    # Check dependencies
    check_dependencies

    # Check if encrypted file exists
    if [ ! -f "$ENCRYPTED_FILE" ]; then
        print_error "File not found: $ENCRYPTED_FILE"
        exit 1
    fi

    # Determine output filename
    if [ -z "$OUTPUT_FILE" ]; then
        if [[ "$ENCRYPTED_FILE" == *.gpg ]]; then
            OUTPUT_FILE="${ENCRYPTED_FILE%.gpg}"
        else
            OUTPUT_FILE="${ENCRYPTED_FILE}.decrypted"
        fi
    fi

    print_info "Processing encrypted file: $ENCRYPTED_FILE"
    echo ""

    # Check if output file already exists
    if [ -f "$OUTPUT_FILE" ]; then
        print_info "Output file already exists: $OUTPUT_FILE"
        read -p "Do you want to overwrite it? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Decryption cancelled"
            exit 0
        fi
    fi

    # Decrypt the file
    print_info "Decrypting file to: $OUTPUT_FILE"
    
    if [ -n "$PASSWORD_FILE" ]; then
        # Use password file (for automation/Docker)
        print_info "Using password from file: $PASSWORD_FILE"
        if gpg --batch --yes --passphrase-file "$PASSWORD_FILE" --decrypt --output "$OUTPUT_FILE" "$ENCRYPTED_FILE"; then
            print_success "File decrypted successfully"
        else
            print_error "Decryption failed"
            exit 1
        fi
    else
        # Interactive mode (prompt for passphrase)
        print_info "You will be prompted to enter the passphrase"
        if gpg --decrypt --output "$OUTPUT_FILE" "$ENCRYPTED_FILE"; then
            print_success "File decrypted successfully"
        else
            print_error "Decryption failed"
            exit 1
        fi
    fi

    echo ""
    print_info "Decrypted file: $OUTPUT_FILE"

    # Verify hash if requested
    if [ "$VERIFY_HASH" = true ]; then
        HASH_FILE="${ENCRYPTED_FILE}.sha256"
        
        if [ ! -f "$HASH_FILE" ]; then
            print_error "Hash file not found: $HASH_FILE"
            print_info "Cannot verify integrity without hash file"
            exit 1
        fi

        print_info "Verifying SHA-256 hash..."
        EXPECTED_HASH=$(awk '{print $1}' "$HASH_FILE")
        CALCULATED_HASH=$(calculate_sha256 "$OUTPUT_FILE")

        if [ -z "$CALCULATED_HASH" ]; then
            print_error "Failed to calculate SHA-256 hash"
            exit 1
        fi

        echo "Expected SHA-256:   $EXPECTED_HASH"
        echo "Calculated SHA-256: $CALCULATED_HASH"
        echo ""

        if [ "$CALCULATED_HASH" = "$EXPECTED_HASH" ]; then
            print_success "SHA-256 hash verification passed - file integrity confirmed"
        else
            print_error "SHA-256 hash verification failed - file may be corrupted"
            exit 1
        fi
    else
        print_info "Tip: Use --verify-hash to verify file integrity after decryption"
    fi
}

# Run main function
main "$@"
