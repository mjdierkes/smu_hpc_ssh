#!/bin/sh

set -e

if ! type git &> /dev/null; then
  echo "Please install git."
  case `uname -s` in
    Darwin)
      echo "The recommended installation method is via Homebrew, which will
      also isntall git.\n\nSee https://brew.sh for installation instructions."\
      | fold -s -w 80
      ;;
    Linux)
      echo "The recommended installation method is via your distribution's
      package manager." | fold -s -w 80
      ;;
  esac
  exit
fi

if ! type ssh &> /dev/null || ! type ssh-keygen &> /dev/null ||\
  ! type ssh-add &> /dev/null; then
  echo "Please install SSH."
  case `uname -s` in
    Linux)
      echo "The recommended installation method is via your distribution's
      package manager." | fold -s -w 80
      ;;
  esac
  exit
fi

print_wrap() {
  clear
  echo $1 | fold -s -w 80
}

proceed() {
  echo "Press enter to continue..."
  sed -n q </dev/tty
}

copy_keys() {
  n=$1 # Host Name
  u=$2 # User
  h=$3 # Host
  clear
  printf "\n\n%s\n\n" "$n"
  proceed
  cat ~/.ssh/smu_hpc_ssh/id_ecdsa_smu_hpc.pub | ssh $u@$h "mkdir -p ~/.ssh &&\
  chmod 0700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 0700\
  ~/.ssh/authorized_keys && cat >> ~/.ssh/authorized_keys"
}

print_wrap "\n\nThis script will guide you through setting up your SSH
configuration such that you can access M3 and the NVIDIA SuperPOD (MP) without
need of the SMU VPN nor passwords. This is accomplished using SSH keys and
SMU's HPC bastion hosts.\n\nThe script makes only single one-line edit to
\`~/.ssh/config\` with all other files contained in
\`~/.ssh/smu_hpc_ssh\`.\n\nFirst we'll copy (git clone) the rest of the
configuration scripts to your computer.\n\nNote that if something goes wrong
during the setup process you can simply restart this script to try again.\n\n"

proceed

test -d ~/.ssh && chmod u+rwx ~/.ssh || mkdir ~/.ssh
test ! -d ~/.ssh/sockets && mkdir ~/.ssh/sockets
test -e ~/.ssh/config && chmod u+rw ~/.ssh/config || touch ~/.ssh/config

config_include="Include ~/.ssh/smu_hpc_ssh/config"
if ! { grep -v '^#' | grep -q "$config_include" ~/.ssh/config; } then
  printf "%s\n%s" "$config_include" "`cat ~/.ssh/config`" > ~/.ssh/config
fi

test -d ~/.ssh/smu_hpc_ssh && git -C ~/.ssh/smu_hpc_ssh pull ||\
 git clone https://github.com/SouthernMethodistUniversity/smu_hpc_ssh.git\
 ~/.ssh/smu_hpc_ssh

print_wrap "\n\nNext we'll make an SSH key for use with M3, MP, and the bastion
hosts.\n\nYou'll be prompted to make a password to protect your SSH key. This
password should not be your SMU password.\n\nNote that you will not see you
password as your type.\n\n"

proceed

if test -f ~/.ssh/smu_hpc_ssh/id_ecdsa_smu_hpc
  echo "The ssh key ~/.ssh/smu_hpc_ssh/id_ecdsa_smu_hpc already exists"
  echo "Continuing will permanently delete the current ssh key"
  echo "Continue? (y/N)"
  read answer
  if [ "$answer" != "${answer#[Yy]}" ] ;then 
    rm ~/.ssh/smu_hpc_ssh/id_ecdsa_smu_hpc
  else
    exit 1
  fi
fi

unset DISPLAY
unset SSH_ASKPASS
ssh-keygen -q -t ecdsa -f ~/.ssh/smu_hpc_ssh/id_ecdsa_smu_hpc

print_wrap "\n\nNext we'll setup your SMU HPC SSH login configuration. You'll
be prompted for your SMU HPC username. This is not your SMU ID.\n\n"

proceed

printf "Please provide your SMU HPC username: "
read -r username < /dev/tty

printf "Host m3 mp hpc_bastion\n\
  User $username\n\
  IdentityFile ~/.ssh/smu_hpc_ssh/id_ecdsa_smu_hpc\n"\
 > ~/.ssh/smu_hpc_ssh/user_config

print_wrap "\n\nNext we'll add your new SSH keys to the SSH keychain so you
don't need to repeatedly enter the key's password.\n\n"

proceed

if [ `uname -s` = "Darwin" ]; then
  printf "  UseKeychain yes\n  AddKeysToAgent no\n"\
    >> ~/.ssh/smu_hpc_ssh/user_config
  ssh-add --apple-use-keychain ~/.ssh/smu_hpc_ssh/id_ecdsa_smu_hpc
else
  printf "  AddKeysToAgent yes\n" >> ~/.ssh/smu_hpc_ssh/user_config
  eval "`ssh-agent -s`"
  ssh-add -k ~/.ssh/smu_hpc_ssh/id_ecdsa_smu_hpc
fi

print_wrap "\n\nNext we'll copy your new SSH keys to each bastion host and to
each cluster. You'll be prompted for your SMU password and go through Duo
authentication for each of the four systems.\n\n"

proceed

copy_keys "1. Bastion Host #1" $username "sjump7ap01.smu.edu"
copy_keys "2. Bastion Host #2" $username "sjump7ap02.smu.edu"
copy_keys "3. M3" $username "m3"
copy_keys "4. NVIDIA SuperPOD (MP)" $username "mp"

print_wrap "\n\nCongradulations! You successfully setup your SSH config to be
able to access M3 and MP via SSH. You can now log into either system using
\`ssh m3\` and \`ssh mp\` without needing to use the SMU VPN.\n\n"

