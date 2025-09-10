#!/usr/bin/env bash
set -euo pipefail

REPO_SSH="git@github.com:shaker402/setup_platform.git"
REPO_HTTPS="https://github.com/shaker402/setup_platform.git"
DEST_PARENT="/home/tenroot"
DEST_DIR="$DEST_PARENT/setup_platform"

# Check for git
if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is not installed. Install git and re-run."
  exit 1
fi

# Create parent directory if missing
if [ ! -d "$DEST_PARENT" ]; then
  echo "Creating parent directory: $DEST_PARENT"
  mkdir -p "$DEST_PARENT"
fi

# If destination already exists
if [ -d "$DEST_DIR" ]; then
  if [ -d "$DEST_DIR/.git" ]; then
    echo "Repository exists at $DEST_DIR — fetching latest..."
    git -C "$DEST_DIR" fetch --all --prune
    # try fast-forward first
    if git -C "$DEST_DIR" rev-parse --abbrev-ref @{u} >/dev/null 2>&1; then
      if ! git -C "$DEST_DIR" pull --ff-only; then
        git -C "$DEST_DIR" pull
      fi
    else
      echo "No upstream configured for current branch; performing a normal pull."
      git -C "$DEST_DIR" pull || true
    fi
    echo "Updated."
    exit 0
  else
    echo "Error: $DEST_DIR exists but is not a git repository. Aborting to avoid overwrite."
    exit 1
  fi
fi

# Helper: does an SSH key exist?
ssh_key_found=false
for key in id_ed25519 id_ed25519.pub id_rsa id_rsa.pub id_ecdsa id_ecdsa.pub; do
  if [ -f "$HOME/.ssh/$key" ]; then
    ssh_key_found=true
    break
  fi
done

# Try SSH clone if key present
if [ "$ssh_key_found" = true ]; then
  echo "SSH key found in $HOME/.ssh — attempting SSH clone..."
  if git clone "$REPO_SSH" "$DEST_DIR"; then
    echo "Cloned via SSH to $DEST_DIR"
    exit 0
  else
    echo "SSH clone failed. (Maybe your SSH key is not added to GitHub or ssh-agent isn't running)."
  fi
fi

# Fallback: HTTPS using GITHUB_TOKEN env var
if [ -n "${GITHUB_TOKEN-}" ]; then
  echo "Using GITHUB_TOKEN environment variable for HTTPS clone (token will be used only for this clone)."
  # Note: embedding token in URL may expose it to process listing/history — be careful.
  git clone "https://${GITHUB_TOKEN}@github.com/shaker402/setup_platform.git" "$DEST_DIR"
  echo "Cloned via HTTPS (token) to $DEST_DIR"
  exit 0
fi

# If we reach here, we can't clone
cat <<'EOF'

ERROR: couldn't clone automatically.

Reasons:
 - No usable SSH key found in ~/.ssh, or SSH clone failed.
 - GITHUB_TOKEN env var is not set for HTTPS fallback.

Choose one of the following fixes:

A) Preferred — Install an SSH key and add it to GitHub:
   1. Generate:    ssh-keygen -t ed25519 -C "your_email@example.com"
   2. Copy public key:    cat ~/.ssh/id_ed25519.pub
   3. Add that key to GitHub > Settings > SSH and GPG keys.
   4. Test: ssh -T git@github.com
   5. Then run: ./clone_setup_platform.sh

B) Use a Personal Access Token (PAT) with HTTPS (scopes: repo):
   1. Create a token on GitHub (Settings → Developer settings → Personal access tokens).
   2. Run the script with the token set:
      GITHUB_TOKEN=ghp_xxx ./clone_setup_platform.sh
   Note: Putting the token in the command exposes it briefly; consider using a credential helper.

C) Manually clone via existing SSH command (if you already added key on this machine):
   git clone git@github.com:shaker402/setup_platform.git /home/tenroot/setup_platform

EOF

exit 2
