#!/usr/bin/env bash

# ==============================================================================
# Script: Generate SSL certificates for local development.
# 
# Description: 
#   A robust, cross-platform tool to generate locally-trusted SSL certificates.
#   It creates a private Certificate Authority (CA) and issues certificates
#   signed by it for local development environments.
#
# History:
#   2018 - kingkool68 <kingkool68@gmail.com> : Initial macOS version.
#   2026 - EmadAsefi <emad.asefi@gmail.com> : Refactored for Linux/macOS support, improved security,
#                 and added comprehensive interactive documentation.
# ==============================================================================

set -euo pipefail
umask 077

usage() {
    cat <<EOF
Usage: $(basename "$0") DOMAIN [--no-trust]
       $(basename "$0") --help

Generate a local CA and a server certificate for DOMAIN.

Before running:
  1. Add DOMAIN to the DNS entries in options.conf.
  2. Optionally edit certificate-authority-options.conf.
  3. Run this script from the project directory or by its full path.

Options:
  --no-trust   Generate certificates without installing the CA in the
               system trust store. No administrator access is needed.
  -h, --help   Show this help.

Passwords:
  OpenSSL asks for a passphrase when creating the CA key. This
  passphrase is required; remember it, because OpenSSL asks for it
  again when signing the certificates.
  When installing the CA, sudo may also ask for your system password.
  The sudo password and the CA passphrase are separate.

Examples:
  ./$(basename "$0") local.dev
  ./$(basename "$0") local.dev --no-trust

Output:
  your-certs/DOMAINCA.pem   Local CA certificate
  your-certs/DOMAIN.crt     Server certificate
  your-certs/DOMAIN.key     Server private key
EOF
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

run_as_root() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
esac

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    usage >&2
    exit 1
fi

name=$1
trust_ca=1

if [ "$#" -eq 2 ]; then
    if [ "$2" != "--no-trust" ]; then
        usage >&2
        exit 1
    fi
    trust_ca=0
fi

# Keep the name safe for both filenames and certificate configuration.
if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] ||
   [[ "$name" == *..* ]] ||
   [[ "$name" == *-.* ]] ||
   [[ "$name" == *.-* ]]; then
    echo "Error: DOMAIN must be a valid DNS name." >&2
    exit 1
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$script_dir"

if ! command_exists openssl; then
    echo "Error: OpenSSL is required." >&2
    exit 1
fi

for config in certificate-authority-options.conf options.conf; do
    if [ ! -f "$config" ]; then
        echo "Error: Missing $config in $script_dir" >&2
        exit 1
    fi
done

# Browsers check the Subject Alternative Name, not just the CN.
if ! awk -F= -v host="$name" '
    $1 ~ /^[[:space:]]*DNS\.[0-9]+[[:space:]]*$/ {
        value = $2
        sub(/#.*/, "", value)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        if (value == host) found = 1
    }
    END { exit !found }
' options.conf; then
    echo "Error: Add 'DNS.N = $name' to options.conf first." >&2
    exit 1
fi

mkdir -p tmp your-certs

ca_key="tmp/${name}CA.key"
ca_config="tmp/${name}CA.conf"
ca_cert="your-certs/${name}CA.pem"
server_key="your-certs/${name}.key"
server_csr="tmp/${name}.csr"
server_cert="your-certs/${name}.crt"
serial_file="tmp/${name}CA.srl"

# Remember the previous CA so macOS can remove only that certificate.
old_fingerprint=
if [ -f "$ca_cert" ]; then
    old_fingerprint=$(
        openssl x509 -in "$ca_cert" -noout -fingerprint -sha1 2>/dev/null |
        awk -F= '{ gsub(/:/, "", $2); print $2 }'
    ) || true
fi

cleanup() {
    rm -f "$ca_config" "$serial_file"

    # Restore ownership when the whole script was started with sudo.
    if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ] &&
       [ "$SUDO_USER" != "root" ]; then
        chown "$SUDO_USER" tmp your-certs \
            "$ca_key" "$ca_cert" "$server_key" \
            "$server_csr" "$server_cert" 2>/dev/null || true
    fi
}

trap cleanup EXIT

# Remove only files belonging to this domain.
rm -f "$ca_key" "$ca_config" "$ca_cert" \
      "$server_key" "$server_csr" "$server_cert" "$serial_file"

# Build a temporary CA config. Leave the original config untouched.
awk -v cn="$name" '
    /^\[req_distinguished_name\][[:space:]]*$/ {
        in_dn = 1
        seen_dn = 1
        print
        next
    }

    /^\[[^]]+\][[:space:]]*$/ && in_dn {
        if (!wrote_cn) print "CN = " cn
        in_dn = 0
    }

    in_dn && /^[[:space:]]*CN[[:space:]]*=/ {
        if (!wrote_cn) {
            print "CN = " cn
            wrote_cn = 1
        }
        next
    }

    { print }

    END {
        if (in_dn && !wrote_cn) print "CN = " cn
        if (!seen_dn) exit 1
    }
' certificate-authority-options.conf > "$ca_config"

cat >> "$ca_config" <<'EOF'

[local_development_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
EOF

echo "Generating certificates for $name..."
echo "OpenSSL will now ask you to create a CA passphrase."
echo "This is NOT your system password. Enter it again when prompted."

openssl genrsa -des3 -out "$ca_key" 2048

openssl req -x509 -new \
    -config "$ca_config" \
    -extensions local_development_ca \
    -key "$ca_key" \
    -sha256 -days 825 \
    -out "$ca_cert"

openssl genrsa -out "$server_key" 2048

openssl req -new \
    -config "$ca_config" \
    -key "$server_key" \
    -out "$server_csr"

echo "Enter the same CA passphrase once more to sign the server certificate."

openssl x509 -req \
    -in "$server_csr" \
    -CA "$ca_cert" \
    -CAkey "$ca_key" \
    -CAserial "$serial_file" \
    -CAcreateserial \
    -out "$server_cert" \
    -days 825 -sha256 \
    -extfile options.conf

openssl verify -CAfile "$ca_cert" "$server_cert"

if [ "$trust_ca" -eq 1 ]; then
    trust_method=manual

    case "$(uname -s)" in
        Darwin)
            if command_exists security; then
                trust_method=macos
            fi
            ;;
        Linux)
            if command_exists update-ca-certificates &&
               [ -d /usr/local/share/ca-certificates ]; then
                trust_method=debian
            elif command_exists update-ca-trust; then
                trust_method=redhat
            fi
            ;;
    esac

    if [ "$trust_method" != manual ] && [ "$EUID" -ne 0 ]; then
        if ! command_exists sudo; then
            echo "Error: sudo is needed to install the CA certificate." >&2
            echo "Certificates were generated; use --no-trust to skip installation." >&2
            exit 1
        fi

        echo "Installing the CA requires administrator access."
        echo "If sudo asks for a password, enter your SYSTEM password."
        sudo -v
    fi

    case "$trust_method" in
        macos)
            # Remove only the previous CA generated for this domain.
            if [ -n "$old_fingerprint" ]; then
                run_as_root security delete-certificate \
                    -Z "$old_fingerprint" \
                    /Library/Keychains/System.keychain \
                    >/dev/null 2>&1 || true
            fi

            run_as_root security add-trusted-cert \
                -d -r trustRoot \
                -k /Library/Keychains/System.keychain \
                "$ca_cert"
            echo "CA installed in the macOS System Keychain."
            ;;
        debian)
            run_as_root install -m 644 "$ca_cert" \
                "/usr/local/share/ca-certificates/local-dev-${name}.crt"
            run_as_root update-ca-certificates
            echo "CA installed in the Linux system trust store."
            ;;
        redhat)
            run_as_root install -m 644 "$ca_cert" \
                "/etc/pki/ca-trust/source/anchors/local-dev-${name}.crt"
            run_as_root update-ca-trust extract
            echo "CA installed in the Linux system trust store."
            ;;
        manual)
            echo "No supported system trust command was found."
            echo "Import $ca_cert into your system or browser trust store manually."
            ;;
    esac
else
    echo "System trust installation skipped (--no-trust)."
fi

echo "Done. Certificate and private key are in your-certs/."
