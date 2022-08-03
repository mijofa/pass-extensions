#!/bin/bash

# The main logic of grabbing the passwords actually needs to be done in an "askpass" command that SSH calls out to.
export SSH_ASKPASS="${BASH_SOURCE[0]%.bash}.askpass-helper"
export SSH_ASKPASS_REQUIRE=force  # NOTE: If there's any extra password prompts, they will appear in a GUI
# Need to somehow get the pass file sent through to the askpass helper,
# and ssh won't allow arguments in the askpass variable (it uses exec()).
# Thankfully it allows environment variables through though, so set one.
export PASSWORD_STORE_SSH_ASKPASS_HELPER_RECORD="$1"

# This helper is what we use when the password file is just an SSH key
ssh_agent_helper="${BASH_SOURCE[0]%/*}/ssh-agent.bash"

# Pass can verify extension file's GPG signatures before sourcing them, so verify the helpers this calls out to as well.
verify_file "$SSH_ASKPASS"
verify_file "$ssh_agent_helper"

# All other arguments should go straight to SSH itself
shift

# Find a line that starts with 'url: ssh://' as openssh actually supports those URIs,
# and 'url:' lines seem to be fairly standard in password-store GUIs and such.
sshurl_meta="$(pass show "$PASSWORD_STORE_SSH_ASKPASS_HELPER_RECORD" | grep --ignore-case --color=never --only-matching --perl-regexp '^url:\s+\Kssh://.*$')"
if [[ -n "$sshurl_meta" ]] ; then
    ssh_dest="$sshurl_meta"
else
    # We couldn't find a URL in the record itself, so we'll assume the filename matches the hostname
    ssh_dest="${PASSWORD_STORE_SSH_ASKPASS_HELPER_RECORD##*/}"
fi
if [[ ! "$ssh_dest" =~ '@' ]] ; then
    # There's no username in the url, so let's take it from the login: line
    # NOTE: This takes the last login line to allow for a difference with the browser plugin taking the first login line.
    #       Although you really should just put the username in the 'url: ssh://' line in that case
    ssh_user="$(pass show "$PASSWORD_STORE_SSH_ASKPASS_HELPER_RECORD" | grep --ignore-case --color=never --only-matching --perl-regexp '^login:\s+\K.*$' | tail -n1)"
fi

ssh_options=($(pass show "$PASSWORD_STORE_SSH_ASKPASS_HELPER_RECORD" | sed --quiet 's/^ssh_option:\s\+\(.*\)$/-o"\1"/p'))

# FIXME: Does *NOT* support spaces in $ssh_user, probably has issues with other special characters too
ssh_cmd=('ssh' ${ssh_user:+-l} ${ssh_user} ${ssh_options[@]} "$ssh_dest" "$@")

first_line=$(pass show "$PASSWORD_STORE_SSH_ASKPASS_HELPER_RECORD" | sed --quiet '/^[^$]/{p;q}') || exit $?
if [[ "$first_line" =~ ^-----BEGIN.* ]] ; then
    # Entire file is an ssh key, create a temporary SSH agent and use it
    # FIXME: What if the there's an SSH key in the file *and* a password at the top?
    "$ssh_agent_helper" "$PASSWORD_STORE_SSH_ASKPASS_HELPER_RECORD" "${ssh_cmd[@]}"
#elif [[ "$first_line" =~ ^otpauth:// ]] ; then
#    # First line is an OTP URI, we actually don't need to do anything special here as it's handled in the askpass helper
else
    # First line is a password or OTP URI, use it

   "${ssh_cmd[@]}"
fi
