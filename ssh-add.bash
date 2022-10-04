#!/bin/bash
# Import all arguments into the current ssh-agent as SSH keys

for PASSWORD_STORE_SSH_ASKPASS_HELPER_RECORD in "$@" ; do
    first_line=$(pass show "$PASSWORD_STORE_SSH_ASKPASS_HELPER_RECORD" | sed --quiet '/^[^$]/{p;q}') || exit $?
    if [[ "$first_line" =~ ^-----BEGIN.* ]] ; then
        ssh-add <(pass show "$PASSWORD_STORE_SSH_ASKPASS_HELPER_RECORD")
    else
        echo "First line does not start with '-----BEGIN', this is unsupported at the moment." >&2
        # FIXME: Treat the first line as the key's passphrase?
        exit 2
    fi
done
