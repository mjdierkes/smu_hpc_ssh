#!/bin/sh

set -e

# Function to print wrapped text
print_wrap() {
  clear
  echo "$1" | fold -s -w 80
}

# Function to wait for user input to proceed
proceed() {
  echo "Press enter to continue..."
  sed -n q </dev/tty
}

# Function to copy SSH keys to remote hosts
copy_keys() {
  n="$1" # Host Name
  u="$2" # User
  h="$3" # Host
  clear
  printf "\n\n%s\n\n" "$n"
  proceed
  cat ~/.ssh/smu_hpc_ssh/id_ecdsa_smu_hpc.pub | ssh "$u@$h" "mkdir -p ~/.ssh && \
  chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && \
  cat >> ~/.ssh/authorized_keys"
}

# Check if git is installed
if ! command -v git >/dev/null 2>&1; then
  echo "Please install git."
  case "$(uname -s)" in
    Darwin)
      echo "The recommended installation method is via Homebrew, which will also install git.\n\nSee https://brew.sh for installation instructions." | fold -s -w 80
      ;;
    Linux)
      echo "The recommended installation method is via your distribution's package manager." | fold -s -w 80
      ;;
    *)
      echo "Please install git using your system's package manager."
      ;;
  esac
  exit 1
fi

# Check if ssh, ssh-keygen, and ssh-add are installed
if ! command -v ssh >/dev/null 2>&1 || ! command -v ssh-keygen >/dev/null 2>&1 || ! command -v ssh-add >/dev/null 2>&1; then
  echo "Please install SSH (ssh, ssh-keygen, ssh-add)."
  case "$(uname -s)" in
    Linux)
      echo "The recommended installation method is via your distribution's package manager." | fold -s -w 80
      ;;
    *)
      echo "Please install SSH using your system's package manager."
      ;;
  esac
  exit 1
fi

# Introduction Message
print_wrap "\n\nThis script will guide you through setting up your SSH
configuration such that you can access M3 and the NVIDIA SuperPOD (MP) without
the need for the SMU VPN nor passwords. This is accomplished using SSH keys and
SMU's HPC bastion hosts.\n\nThe script makes only a single one-line edit to
\`~/.ssh/config\` with all other files contained in
\`~/.ssh/smu_hpc_ssh\`.\n\nFirst, we'll clone (git clone) the rest of the
configuration scripts to your computer.\n\nNote that if something goes wrong
during the setup process, you can simply restart this script to try again.\n\n"

proceed

# Ensure ~/.ssh directory exists with correct permissions
if [ -d ~/.ssh ]; then
  chmod 700 ~/.ssh
else
  mkdir ~/.ssh
  chmod 700 ~/.ssh
fi

# Ensure ~/.ssh/sockets directory exists
if [ ! -d ~/.ssh/sockets ]; then
  mkdir ~/.ssh/sockets
fi

# Ensure ~/.ssh/config file exists with correct permissions
if [ -e ~/.ssh/config ]; then
  chmod 600 ~/.ssh/config
else
  touch ~/.ssh/config
  chmod 600 ~/.ssh/config
fi

# Add Include directive to ~/.ssh/config if not present
config_include="Include ~/.ssh/smu_hpc_ssh/config"
if ! grep -qF "$config_include" ~/.ssh/config; then
  printf "%s\n%s" "$config_include" "$(cat ~/.ssh/config)" > ~/.ssh/config
fi

# Clone or update the smu_hpc_ssh repository
if [ -d ~/.ssh/smu_hpc_ssh ]; then
  git -C ~/.ssh/smu_hpc_ssh pull
else
  git clone https://github.com/SouthernMethodistUniversity/smu_hpc_ssh.git ~/.ssh/smu_hpc_ssh
fi

# Prompt user about SSH key generation
print_wrap "\n\nNext, we'll generate an SSH key for use with M3, MP, and the bastion
hosts.\n\nYou'll be prompted to create a passphrase to protect your SSH key. This
passphrase should not be your SMU password.\n\nNote that you will not see your
passphrase as you type.\n\n"

proceed

# Generate SSH key
unset DISPLAY
unset SSH_ASKPASS
ssh-keygen -q -t ecdsa -f ~/.ssh/smu_hpc_ssh/id_ecdsa_smu_hpc

# Configure SSH login
print_wrap "\n\nNext, we'll set up your SMU HPC SSH login configuration. You'll
be prompted for your SMU HPC username. This is not your SMU ID.\n\n"

proceed

# Prompt for SMU HPC username
printf "Please provide your SMU HPC username: "
read -r username < /dev/tty

# Create user_config file
cat > ~/.ssh/smu_hpc_ssh/user_config <<EOL
Host m3 mp hpc_bastion
  User $username
  IdentityFile ~/.ssh/smu_hpc_ssh/id_ecdsa_smu_hpc
EOL

# Determine OS type
OS_TYPE="$(uname -s)"

# Handle macOS-specific SSH configurations
if [ "$OS_TYPE" = "Darwin" ]; then
  # Check if ssh supports UseKeychain
  if ssh -V 2>&1 | grep -q "OpenSSH"; then
    # Attempt to add UseKeychain option
    ssh -V 2>&1 | grep -q "Apple" && MACOS_SSH=true || MACOS_SSH=false
  else
    MACOS_SSH=false
  fi

  if [ "$MACOS_SSH" = true ]; then
    # Add macOS-specific SSH options
    cat >> ~/.ssh/smu_hpc_ssh/user_config <<EOL
  UseKeychain yes
  AddKeysToAgent yes
EOL
  fi
fi

print_wrap "\n\nNext, we'll add your new SSH keys to the SSH agent so you
don't need to repeatedly enter the key's passphrase.\n\n"

proceed

# Start ssh-agent if not running
if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)"
fi

# Add SSH key to agent
if [ "$OS_TYPE" = "Darwin" ] && [ "$MACOS_SSH" = true ]; then
  ssh-add --apple-use-keychain ~/.ssh/smu_hpc_ssh/id_ecdsa_smu_hpc
else
  ssh-add ~/.ssh/smu_hpc_ssh/id_ecdsa_smu_hpc
fi

print_wrap "\n\nNext, we'll copy your new SSH keys to each bastion host and to
each cluster. You'll be prompted for your SMU password and go through Duo
authentication for each of the four systems.\n\n"

proceed

# Copy SSH keys to remote hosts
copy_keys "1. Bastion Host #1" "$username" "sjump7ap01.smu.edu"
copy_keys "2. Bastion Host #2" "$username" "sjump7ap02.smu.edu"
copy_keys "3. M3" "$username" "m3"
copy_keys "4. NVIDIA SuperPOD (MP)" "$username" "mp"

# Final Success Message
print_wrap "\n\nCongratulations! You have successfully set up your SSH configuration to be
able to access M3 and MP via SSH. You can now log into either system using
\`ssh m3\` and \`ssh mp\` without needing to use the SMU VPN.\n\n"

echo "SSH setup is complete."

exit 0
