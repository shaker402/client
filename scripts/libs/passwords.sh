#!/bin/bash

set -e

function _list_passwords_from_compose() {
    local workdir=$1

    if [ -e "${workdir}/docker-compose.yml" -o "${workdir}/docker-compose.yaml" ]
    then
      local name=$(ls ${workdir}/docker-compose.y* | grep -E 'ya?ml$' | head -n 1)
      # Env secrets
      echo $(cat ${name} | sed -n 's#.*\(env\..*\.secret\).*#\1#p' | sort | uniq)
      # Build-time secrets
      echo $(cat ${name} | sed -En 's#.*:\s*(.*\.passwd).*#\1#p' | sort | uniq)
    fi
}

function _list_password_files_with_passwords() {
    local workdir=$1

    echo $(find $workdir -type f -not -empty -and -name 'env.*.secret' | xargs -I % basename %)
    echo $(find $workdir -type f -not -empty -and -name '*.passwd' | xargs -I % basename %)
}

function check_password_generator() {
    if [ "${PASSWORD_GENERATOR}123" = "123" ]
    then
      # Recommended: `apg -n 1 -m 16 -x 20 -MSNCL`
      export PASSWORD_GENERATOR="LC_ALL=C tr -dc 'A-Za-z0-9-_!' </dev/urandom | head -c 16"
    fi
}

function setup_shell() {
    # We can not rely on ${SHELL} variable
    export SH=${SH:-/bin/bash}
}

function generate_passwords_if_required() {
    local workdir=$1

    printf "Start generating passwords...\n"
    if [ "${GENERATE_PASSWORDS}234${GENERATE_ALL_PASSWORDS}" != 234 ]
    then
      declare -a required=($(_list_passwords_from_compose $workdir))
      if [ "${GENERATE_PASSWORDS}345" != "345" ]
      then
        declare -a existing=($(_list_password_files_with_passwords $workdir))
        # Two matching names means we have the same thing defined in docker-compose.yaml and env secrets
        declare -a defined=($(printf "%s\n%s\n" ${required[@]} ${existing[@]} | sort | uniq -c | sort -rn | grep -E '\s*2' | awk '{print $2}'))
        # Filter out extra env secrets that are not required
        declare -a undefined=($(printf "%s\n%s\n" ${required[@]} ${defined[@]} | sort | uniq -c | sort -rn | grep -E '\s*1' | awk '{print $2}'))
        for var in ${undefined[@]}
        do
          echo $(sh -c "${PASSWORD_GENERATOR}") > ${workdir}/${var}
        done
      else
        for var in ${required[@]}
        do
          echo $(sh -c "${PASSWORD_GENERATOR}") > ${workdir}/${var}
        done
      fi
    fi
}

setup_shell
check_password_generator
