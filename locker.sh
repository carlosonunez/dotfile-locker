#!/usr/bin/env bash
set -euo pipefail
OVERWRITE="${OVERWRITE:-}"
GPG_IGNORE_CHANGED_KEY="${GPG_IGNORE_CHANGED_KEY:-}"

_error() {
  >&2 echo -e "\033[1;31mERROR:\033[m $1"
}

_info() {
  >&2 echo -e "\033[1;32mINFO:\033[m $1"
}

_this_dir() {
  realpath "$(dirname "$0")"
}

_archive_exists() {
  test -f "$(_archive_name_from_env "$1")"
}

_environment_dir() {
  echo "$(_this_dir)/$1"
}

_archive_name_from_env() {
  echo "$(_this_dir)/$1.tar.gz.enc"
}

_ensure_environment_or_fail() {
  local env
  env="$1"
  test -d "$(_environment_dir "$env")" && return 0

  _error "Environment doesn't exist: $env"
  exit 1
}

_ensure_not_environment_or_fail() {
  local env
  env="$1"
  test -d "$(_environment_dir "$env")" || return 0

  test -n "$OVERWRITE" && return 0
  _error "Environment exists (set OVERWRITE to ignore): $env"
  exit 1
}

_get_archive_gpg_key_fingerprint() {
  local archive
  archive="$(_archive_name_from_env "$1")"
  got_keyid=$(2>&1 gpg --pinentry-mode cancel --list-packets --with-colons "$archive" |
    grep ', ID' |
    sed -E 's/.*, ID/ID/' |
    awk '{print $2}' |
    tr -d ',')
  test -z "$got_keyid" && return
  _pgp_fp "$got_keyid"
}

_pgp_fp() {
  local want_item found_item
  want_item="$1"
  found_item=0
  while read -r line
  do
    if test "$found_item" == 1 && grep -Eq '^fpr:' <<< "$line"
    then
      echo "$line" | rev | cut -f2 -d ':' | rev
      return 0
    fi
    if grep -q "$want_item" <<< "$line"
    then
      found_item=1
      continue
    fi
  done < <(gpg --list-keys --with-colons)
  return 1
}

_ensure_args_provided_or_fail() {
  local env fp
  env="$1"
  fp="$2"
  for kvp in "${env};;Please provide an environment" \
    "${fp};;Please provide a fingerprint to encrypt this env with"
  do
    test -n "${kvp%%;;*}" && continue
    _error "${kvp##*;;}"
    exit 1
  done
}

_ensure_archive_exists_or_fail() {
  local env archive
  env="$1"
  _archive_exists "$env" && return 0

  _error "Archive does not exist for environment $env"
  exit 1
}

_ensure_archive_does_not_exist_or_fail() {
  local env archive
  env="$1"
  _archive_exists "$env" || return 0

  if test -z "$OVERWRITE"
  then
    _error "Archive exists: $env (set OVERWRITE to ignore)"
    exit 1
  fi
}

_ensure_archive_signed_with_desired_key_or_fail() {
  local env want_fp archive got_fp
  env="$1"
  want_fp="$2"
  _info "Verifying that $env was signed with PGP private key $want_fp; please wait"
  got_fp=$(_get_archive_gpg_key_fingerprint "$env")
  test -z "$got_fp" || { test -n "$got_fp" && test "$want_fp" == "$got_fp"; } && return 0

  _error "Archive for environment $env signed with PGP fingerprint $got_fp instead of $want_fp"
  exit 1
}

_ensure_archive_encrypted_or_fail() {
  test -n "$(_get_archive_gpg_key_fingerprint "$1")" && return 0

  _error "Archive for environment $1 is not encrypted!"
  exit 1
}

# encrypt: Encrypts an environment given an email address with a PGP private key on this system.
encrypt() {
  _delete_existing_archive() {
    archive="$(_archive_name_from_env "$env")"
    _archive_exists "$env" || return 0
    _info "Deleting: $archive"
    rm -f "$archive"
  }

  _archive_environment() {
    _info "Backing up and encrypting env: $env"
    tar -cvzf - "$env" | gpg --encrypt -r "$fp" > "$(_archive_name_from_env "$env")"
  }

  local env fp
  env="$1"
  fp="$2"
  _ensure_args_provided_or_fail "$env" "$fp"
  _ensure_environment_or_fail "$env"
  _ensure_archive_does_not_exist_or_fail "$env"
  _ensure_archive_signed_with_desired_key_or_fail "$env" "$fp"
  _delete_existing_archive
  _archive_environment
}

# ensure_encrypted: Checks that an environment archive file is encrypted against the key associated
# with a provided PGP fingerprint.
ensure_encrypted() {
  local env fp
  env="$1"
  fp="$2"
  _ensure_args_provided_or_fail "$env" "$fp"
  _ensure_archive_encrypted_or_fail "$env"
  _ensure_archive_signed_with_desired_key_or_fail "$env" "$fp"
}

# decrypt: decrypts an environment given an email address with a PGP private key on this system.
decrypt() {
  _delete_existing_env() {
    env_dir="$(_environment_dir "$env")"
    _info "Deleting: $env_dir"
    rm -rf "$env_dir"
  }

  _unarchive_environment() {
    _info "Decrypting and restoring env: $env; please wait"
    gpg --pinentry-mode=cancel --decrypt -r "$fp" "$(_archive_name_from_env "$env")" |
      tar -xvzf -
  }

  local env fp
  env="$1"
  fp="$2"
  _ensure_args_provided_or_fail "$env" "$fp"
  _ensure_not_environment_or_fail "$env"
  _ensure_archive_exists_or_fail "$env"
  _ensure_archive_signed_with_desired_key_or_fail "$env" "$fp"
  _delete_existing_env
  _unarchive_environment
}

usage() {
  cat <<-EOF
$(basename "$0") [ENVIRONMENT_NAME]
Encrypts or decrypts a work config.

OPTIONS

  -h, --help                                Shows this help.
  -e, --encrypt ENVIRONMENT_NAME            The name of an environment folder to encrypt.
  -d, --decrypt ENVIRONMENT_NAME            The name of an environment folder to decrypt.
      --ensure-encrypted ENVIRONMENT_NAME   Ensure environment file is encrypted if found.
      --email EMAIL_ADDRESS                 Red Hat email with a PGP key installed on this system.

ENVIRONMENT VARIABLES

  OVERWRITE=''                              Overwrites an existing encrypted environment zip.
                                            (Default: not set)
  GPG_IGNORE_CHANGED_KEY=''                 Continues encryption even if existing env archive
                                            was encrypted with a different key
                                            (Default: not set)
EOF
}

if grep -Eiq -- '-h|--help' <<< "$@"
then
  usage
  exit 0
fi

op=""
email=""
while test "$#" -gt 0
do
  case "$1" in
    -e|--encrypt)
      shift
      op="encrypt"
      if test -z "$1" || grep -Eiq '^-' <<< "$1"
      then
        usage
        _error "Please specify ENVIRONMENT_NAME after --${op}."
        exit 1
      fi
      env="$1"
      shift
      ;;
    -d|--decrypt)
      shift
      op="decrypt"
      if test -z "$1" || grep -Eiq '^-' <<< "$1"
      then
        usage
        _error "Please specify ENVIRONMENT_NAME after --${op}."
        exit 1
      fi
      env="$1"
      shift
      ;;
    --ensure-encrypted)
      shift
      op="ensure_encrypted"
      if test -z "$1" || grep -Eiq '^-' <<< "$1"
      then
        usage
        _error "Please specify ENVIRONMENT_NAME after --${op}."
        exit 1
      fi
      env="$1"
      shift
      ;;
    --email)
      shift
      email="$1"
      shift
      ;;
    *)
      usage
      _error "Not a valid option: $1"
      exit 1
  esac
done

if test -z "$email"
then
  usage
  _error "--email must be defined."
  exit 1
fi

if ! fp="$(_pgp_fp "$email")"
then
  _error "No PGP key found on system that belongs to [$email]"
  exit 1
fi

$op "$env" "$fp"
