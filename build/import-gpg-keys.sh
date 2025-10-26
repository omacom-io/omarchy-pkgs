#!/bin/bash
# Import GPG keys for package verification and signing

echo "==> Importing GPG keys..."

# Check if signing is enabled
if [[ "$SKIP_SIGNING" == true ]]; then
  echo "  -> Skipping signing key import (--skip-signing enabled)"
else
  # Import signing key (required for signing)
  echo "  -> Importing signing key..."
  # Import with batch mode and no tty for automated signing
  echo "$GPG_PRIVATE_KEY" | gpg --batch --import || {
    echo "  -> ERROR: Failed to import signing key"
    exit 1
  }

  # Configure GPG for automated signing with passphrase
  echo "allow-loopback-pinentry" >>~/.gnupg/gpg-agent.conf
  echo "pinentry-mode loopback" >>~/.gnupg/gpg.conf
  gpg-connect-agent reloadagent /bye 2>/dev/null || true

  # Extract key ID and configure
  KEY_ID=$(gpg --list-secret-keys --keyid-format LONG | grep "sec" | head -1 | awk '{print $2}' | cut -d'/' -f2)
  if [[ -n "$KEY_ID" ]]; then
    # Trust the key using fingerprint
    FINGERPRINT=$(gpg --list-secret-keys --with-colons | grep "^fpr" | head -1 | cut -d':' -f10)
    echo "$FINGERPRINT:6:" | gpg --import-ownertrust
    # Set as default key in makepkg.conf
    echo "GPGKEY=\"$KEY_ID\"" >>~/.makepkg.conf
    echo "  -> Signing key configured: $KEY_ID"

    # Test signing with the key and passphrase
    echo "  -> Testing GPG signing capability..."
    echo "test" | gpg --batch --yes --pinentry-mode loopback --passphrase "$GPG_PASSPHRASE" --sign --local-user "$KEY_ID" >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      echo "  -> ERROR: Failed to sign with the provided passphrase"
      echo "  -> Please check your passphrase and try again"
      exit 1
    fi
    echo "  -> GPG signing test successful"

    # Import public signing key into pacman's keyring for local package verification
    echo "  -> Adding signing key to pacman keyring..."
    sudo pacman-key --init || exit 1
    gpg --armor --export "$KEY_ID" > /tmp/signing-key.asc || exit 1
    sudo pacman-key --add /tmp/signing-key.asc || exit 1
    rm -f /tmp/signing-key.asc
    sudo pacman-key --lsign-key "$KEY_ID" || exit 1
  else
    echo "  -> ERROR: Could not extract key ID"
    exit 1
  fi
fi

# Read the gpg-keys.txt file for verification keys
if [[ -f /build/gpg-keys.txt ]]; then
  echo "  -> Importing verification keys..."
  while IFS= read -r line || [ -n "$line" ]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^#.*$ ]] && continue
    [[ -z "$line" ]] && continue

    # Check if it's a URL (contains ://)
    if [[ "$line" == *"://"* ]]; then
      echo "    - Importing key from $line"
      curl -sS "$line" | gpg --import - || {
        echo "      Warning: Failed to import key from $line"
      }
    else
      # It's a key ID - use receive-keys
      echo "    - Receiving key $line"
      gpg --receive-keys "$line" || {
        echo "      Warning: Failed to receive key $line"
      }
    fi
  done </build/gpg-keys.txt
  echo "  -> Verification key import complete"
else
  echo "  -> No gpg-keys.txt file found, skipping verification key import"
fi

echo "  -> GPG setup complete"
