#!/bin/sh

set -o errexit
set -o pipefail
readonly VERSION='0.0.1'
readonly API_BASE_URI='https://api.fastly.com'

readonly API_TOKEN='your_api_token'

if [[ -z "${API_TOKEN}" ]]; then
    echo "Please set your API token first."
    exit 1
fi

usage () {
    echo "Usage: ./service-clone.sh [OPTIONS]"
    echo ""
    echo "List of available options"
    echo "  -s, --src SERVICE_ID    [required] source service ID"
    echo "  -d, --dst SERVICE_ID    [required] destinatuon service ID"
    echo "  -v, --version VERSION   (optional) source version number (default: the current active version)"
    echo "  --no-logging            (optional) exclude logging settings (default: include)"
    echo "  --no-acl                (optional) exclude acl (default: include)"
    echo "  --no-dictionary         (optional) exclude dictionry (default: include)"
    echo "  -h, --help              show help"
    echo ""
    echo "Need more help? Visit: https://github.com/smaeda-ks/fastly-service-clone"
}

case "$(uname -s)" in
    Darwin*)
        getopt=/usr/local/opt/gnu-getopt/bin/getopt
        ;;
    Linux|*)
        [ -x /bin/getopt ] && getopt=/bin/getopt || getopt=/usr/bin/getopt
        ;;
esac

arg_count=$#

options=$(${getopt} -n service-clone.sh -o s:d:v:h -l src:,dst:,version:,help,no-logging,no-acl,no-dictionary -- "$@")
eval set -- "${options}"

src_service=''
dst_service=''
version=''
dst_version=''
no_logging="false"
no_acl="false"
no_dictionary="false"
while true; do
    case "$1" in
        -s|--src) shift; src_service=$1 ;;
        -d|--dst) shift; dst_service=$1 ;;
        -v|--version) shift; version=$1 ;;
        -h|--help) usage; exit ;;
        --no-logging) no_logging="true" ;;
        --no-acl) no_acl="true" ;;
        --no-dictionary) no_dictionary="true" ;;
        --) shift; break ;;
    esac
    shift
done

options_check () {
    if [[ ${arg_count} -eq 0 ]]; then
        usage
        exit 0
    fi

    if [[ -z "${src_service}" ]]; then
        echo "please specify a source service ID"
        exit 1
    fi

    if [[ -z "${dst_service}" ]]; then
        echo "please specify a destination service ID"
        exit 1
    fi

    if [[ ! -x "$(command -v jq)" ]]; then
        echo "please install jq command"
        exit 1
    fi

    if [[ ! -x "$(command -v curl)" ]]; then
        echo "please install curl command"
        exit 1
    fi
}

get_src_version () {
    if [[ -z "${version}" ]]; then
        echo "[INFO] checking the current active version number for service ID: ${src_service} ..."
        version=$(curl -sS --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${src_service}/version/active" | jq '.number')
    fi
    echo "[INFO] source version is: ${version}"
}

global_dst_active_version=''
get_dst_active_version () {
    global_dst_active_version=$(curl -sS -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/version/active" | jq '.number')
}

check_dst_service () {
    echo "[INFO] checking destination service ID: ${dst_service} ..."
    local raw
    raw=$(curl -sS --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}")
}

check_src_service () {
    echo "[INFO] checking source service ID: ${src_service} ..."
    local raw
    raw=$(curl -sS --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${src_service}")
    local type=$(jq -r ".type" <<< ${raw})
    if [[ "${type}" != "vcl" ]]; then
        echo "[ERROR] wasm service is not supported ..."
        exit 1
    fi
}


global_get_objects=''
get_objects () {
    local readonly path=$1
    global_get_objects=$(curl -sS --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}${path}")
}

raw_conditions=''
get_conditions () {
    echo "[INFO] fetching condtions from the source service ..."
    get_objects "/service/${src_service}/version/${version}/condition"
    raw_conditions=${global_get_objects}
}

set_conditions () {
    echo "[INFO] copying condtions to the destination service ..."
    local count=$(jq 'length' <<< ${raw_conditions})
    for (( i=0; i<${count}; i++ ))
    do  
        local object=$(jq ".[${i}]" <<< ${raw_conditions})
        filter_objects "${object}"

        local post_body=${global_filter_objects}
        curl -sS -o /dev/null -X POST --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/version/${dst_version}/condition" -H "Content-Type: application/json" -d "${post_body}"
    done
}

raw_healthchecks=''
get_healthchecks () {
    echo "[INFO] fetching healthchecks from the source service ..."
    get_objects "/service/${src_service}/version/${version}/healthcheck"
    raw_healthchecks=${global_get_objects}
}

set_healthchecks () {
    echo "[INFO] copying healthchecks to the destination service ..."
    local count=$(jq 'length' <<< ${raw_healthchecks})
    for (( i=0; i<${count}; i++ ))
    do  
        local object=$(jq ".[${i}]" <<< ${raw_healthchecks})
        filter_objects "${object}"

        local post_body=${global_filter_objects}
        curl -sS -o /dev/null -X POST --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/version/${dst_version}/healthcheck" -H "Content-Type: application/json" -d "${post_body}"
    done
}

raw_cache_settings=''
get_cache_settings () {
    echo "[INFO] fetching cache_settings from the source service ..."
    get_objects "/service/${src_service}/version/${version}/cache_settings"
    raw_cache_settings=${global_get_objects}
}

set_cache_settings () {
    echo "[INFO] copying cache_settings to the destination service ..."
    local count=$(jq 'length' <<< ${raw_cache_settings})
    for (( i=0; i<${count}; i++ ))
    do  
        local object=$(jq ".[${i}]" <<< ${raw_cache_settings})
        filter_objects "${object}"

        local post_body=${global_filter_objects}
        curl -sS -o /dev/null -X POST --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/version/${dst_version}/cache_settings" -H "Content-Type: application/json" -d "${post_body}"
    done
}

raw_backends=''
get_backends () {
    echo "[INFO] fetching backends from the source service ..."
    get_objects "/service/${src_service}/version/${version}/backend"
    raw_backends=${global_get_objects}
}

set_backends () {
    echo "[INFO] copying backends to the destination service ..."
    local count=$(jq 'length' <<< ${raw_backends})
    for (( i=0; i<${count}; i++ ))
    do  
        local object=$(jq ".[${i}]" <<< ${raw_backends})
        filter_objects "${object}" backend

        local post_body=${global_filter_objects}
        curl -sS -o /dev/null -X POST --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/version/${dst_version}/backend" -H "Content-Type: application/json" -d "${post_body}"
    done
}

raw_directors=''    
get_directors () {
    echo "[INFO] fetching directors from the source service ..."
    get_objects "/service/${src_service}/version/${version}/director"
    raw_directors=${global_get_objects}
}

set_directors () {
    echo "[INFO] copying directors to the destination service ..."
    local count=$(jq 'length' <<< ${raw_directors})
    for (( i=0; i<${count}; i++ ))
    do  
        local object=$(jq ".[${i}]" <<< ${raw_directors})
        filter_objects "${object}" director

        local post_body=${global_filter_objects}
        curl -sS -o /dev/null -X POST --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/version/${dst_version}/director" -H "Content-Type: application/json" -d "${post_body}"

        # establishes a relationship between a backend and a director
        local director_name=$(jq -r ".[${i}] | .name" <<< ${raw_directors})
        director_name=$(urlencode "${director_name}")
        local backends=$(jq ".[${i}] | .backends" <<< ${raw_directors})
        local backends_count=$(jq 'length' <<< ${backends})
        for (( j=0; j<${backends_count}; j++ ))
        do
            local backend_name=$(jq -r ".[${j}]" <<< ${backends})
            backend_name=$(urlencode "${backend_name}")
            curl -sS -o /dev/null -X POST --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/version/${dst_version}/director/${director_name}/backend/${backend_name}"
        done
    done
}

raw_gzips=''
get_gzips () {
    echo "[INFO] fetching gzips from the source service ..."
    get_objects "/service/${src_service}/version/${version}/gzip"
    raw_gzips=${global_get_objects}
}

set_gzips () {
    echo "[INFO] copying gzips to the destination service ..."
    local count=$(jq 'length' <<< ${raw_gzips})
    for (( i=0; i<${count}; i++ ))
    do  
        local object=$(jq ".[${i}]" <<< ${raw_gzips})
        filter_objects "${object}"

        local post_body=${global_filter_objects}
        curl -sS -o /dev/null -X POST --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/version/${dst_version}/gzip" -H "Content-Type: application/json" -d "${post_body}"
    done
}

raw_headers=''
get_headers () {
    echo "[INFO] fetching headers from the source service ..."
    get_objects "/service/${src_service}/version/${version}/header"
    raw_headers=${global_get_objects}
}

set_headers () {
    echo "[INFO] copying headers to the destination service ..."
    local count=$(jq 'length' <<< ${raw_headers} )
    for (( i=0; i<${count}; i++ ))
    do  
        local object=$(jq ".[${i}]" <<< ${raw_headers} )
        filter_objects "${object}"

        local post_body=${global_filter_objects}
        curl -sS -o /dev/null -X POST --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/version/${dst_version}/header" -H "Content-Type: application/json" -d "${post_body}"
    done
}

raw_request_settings=''
get_request_settings () {
    echo "[INFO] fetching request_settings from the source service ..."
    get_objects "/service/${src_service}/version/${version}/request_settings"
    raw_request_settings=${global_get_objects}
}

set_request_settings () {
    echo "[INFO] copying request_settings to the destination service ..."
    local count=$(jq 'length' <<< ${raw_request_settings})
    for (( i=0; i<${count}; i++ ))
    do  
        local object=$(jq ".[${i}]" <<< ${raw_request_settings})
        filter_objects "${object}"

        local post_body=${global_filter_objects}
        curl -sS -o /dev/null -X POST --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/version/${dst_version}/request_settings" -H "Content-Type: application/json" -d "${post_body}"
    done
}

raw_response_objects=''
get_response_objects () {
    echo "[INFO] fetching response_objects from the source service ..."
    get_objects "/service/${src_service}/version/${version}/response_object"
    raw_response_objects=${global_get_objects}
}

set_response_objects () {
    echo "[INFO] copying response_objects to the destination service ..."
    local count=$(jq 'length' <<< ${raw_response_objects})
    for (( i=0; i<${count}; i++ ))
    do  
        local object=$(jq ".[${i}]" <<< ${raw_response_objects})
        filter_objects "${object}"

        local post_body=${global_filter_objects}
        curl -sS -o /dev/null -X POST --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/version/${dst_version}/response_object" -H "Content-Type: application/json" -d "${post_body}"
    done
}

raw_settings=''
get_settings () {
    echo "[INFO] fetching settings from the source service ..."
    get_objects "/service/${src_service}/version/${version}/settings"
    raw_settings=${global_get_objects}
}

set_settings () {
    echo "[INFO] copying settings to the destination service ..."
    local object=${raw_settings}
    filter_objects "${object}" settings

    local post_body=${global_filter_objects}
    curl -sS -o /dev/null -X PUT --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/version/${dst_version}/settings" -H "Content-Type: application/json" -d "${post_body}"
}

raw_vcls=''
get_vcls () {
    echo "[INFO] fetching vcls from the source service ..."
    get_objects "/service/${src_service}/version/${version}/vcl"
    raw_vcls=${global_get_objects}
}

set_vcls () {
    echo "[INFO] copying vcls to the destination service ..."
    local count=$(jq 'length' <<< ${raw_vcls})
    for (( i=0; i<${count}; i++ ))
    do  
        local object=$(jq ".[${i}]" <<< ${raw_vcls})
        filter_objects "${object}"

        local post_body=${global_filter_objects}
        curl -sS -o /dev/null -X POST --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/version/${dst_version}/vcl" -H "Content-Type: application/json" -d "${post_body}"
    done

    # the "main-ness" of the vcl does not get carried over during copy, so explicitly setting main
    if [[ count -ne 0 ]]; then
        local main_vcl_name=$(jq -r '.[] | select(.main == true) | .name' <<< ${raw_vcls})
        main_vcl_name=$(urlencode "${main_vcl_name}")
        curl -sS -o /dev/null -X PUT --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/version/${dst_version}/vcl/${main_vcl_name}/main"
    fi
}

raw_snippets=''
get_snippets () {
    echo "[INFO] fetching snippets from the source service ..."
    get_objects "/service/${src_service}/version/${version}/snippet"
    raw_snippets=${global_get_objects}
}

set_snippets () {
    echo "[INFO] copying snippets to the destination service ..."
    local count=$(jq 'length' <<< ${raw_snippets})
    for (( i=0; i<${count}; i++ ))
    do  
        local object=$(jq ".[${i}]" <<< ${raw_snippets})
        local dynamic=$(jq -r '.dynamic' <<< ${object})
        if [[ dynamic -eq 1 ]]; then
            local snippet_id=$(jq -r '.id' <<< ${object})
            get_objects "/service/${src_service}/snippet/${snippet_id}"
            local raw=${global_get_objects}
            filter_objects "${raw}" dynamic_snippet
            raw=${global_filter_objects}
            object=$(jq <<< ${object} | jq ". |= .+ ${raw}")
        fi
        filter_objects "${object}"

        local post_body=${global_filter_objects}
        curl -sS -o /dev/null -X POST --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/version/${dst_version}/snippet" -H "Content-Type: application/json" -d "${post_body}"
    done
}

raw_dictionaries=''
get_dictionaries () {
    echo "[INFO] fetching dictionaries from the source service ..."
    get_objects "/service/${src_service}/version/${version}/dictionary"
    raw_dictionaries=${global_get_objects}
}

set_dictionaries () {
    echo "[INFO] copying dictionaries to the destination service ..."
    local count=$(jq 'length' <<< ${raw_dictionaries})
    for (( i=0; i<${count}; i++ ))
    do  
        local object=$(jq ".[${i}]" <<< ${raw_dictionaries})
        local write_only=$(jq -r '.write_only' <<< ${object})

        filter_objects "${object}"
        local post_body=${global_filter_objects}
        local result=$(curl -sS -X POST --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/version/${dst_version}/dictionary" -H "Content-Type: application/json" -d "${post_body}")

        if [[ "${write_only}" == "true" ]]; then
            local dict_name=$(jq -r '.name' <<< ${object})
            echo "--> unable to retrive the contents of a write_only dictionary (name: \"${dict_name}\"), so creating an empty write_only dictionary instead ..."
            continue
        fi

        local dictionary_id=$(jq -r '.id' <<< ${object})
        get_objects "/service/${src_service}/dictionary/${dictionary_id}/items"
        local raw_items=${global_get_objects}
        local items_count=$(jq 'length' <<< ${raw_items})
        if [[ items_count -eq 0 ]]; then
            continue
        fi
        local json_items=''
        for (( j=0; j<${items_count}; j++ ))
        do
            local object=$(jq ".[${j}]" <<< ${raw_items})
            local item_key=$(jq '.item_key' <<< ${object})
            local item_value=$(jq '.item_value' <<< ${object})
            if [[ ${j} -ne 0 ]]; then
                json_items="${json_items},"
            fi
            json_items="${json_items}{\"op\": \"create\", \"item_key\": ${item_key}, \"item_value\": ${item_value}}"
        done

        local dst_dictionary_id=$(jq -r '.id' <<< ${result})
        post_body=$(jq <<< '{"items": []}' | jq ".items |= .+ [${json_items}]")
        curl -sS -o /dev/null -X PATCH --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/dictionary/${dst_dictionary_id}/items" -H "Content-Type: application/json" -d "${post_body}"
    done
}

raw_acls=''
get_acls () {
    echo "[INFO] fetching acls from the source service ..."
    get_objects "/service/${src_service}/version/${version}/acl"
    raw_acls=${global_get_objects}
}

set_acls () {
    echo "[INFO] copying acls to the destination service ..."
    local count=$(jq 'length' <<< ${raw_acls})
    for (( i=0; i<${count}; i++ ))
    do  
        local object=$(jq ".[${i}]" <<< ${raw_acls})
        filter_objects "${object}"

        local post_body=${global_filter_objects}
        local result=$(curl -sS -X POST --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/version/${dst_version}/acl" -H "Content-Type: application/json" -d "${post_body}")

        local acl_id=$(jq -r '.id' <<< ${object})
        get_objects "/service/${src_service}/acl/${acl_id}/entries"
        local raw_entries=${global_get_objects}
        local entries_count=$(jq 'length' <<< ${raw_entries})
        if [[ entries_count -eq 0 ]]; then
            continue
        fi
        local json_entries=''
        for (( j=0; j<${entries_count}; j++ ))
        do
            local object=$(jq ".[${j}]" <<< ${raw_entries})
            local ip=$(jq '.ip' <<< ${object})
            local subnet=$(jq '.subnet' <<< ${object})
            local negated=$(jq '.negated' <<< ${object})
            local comment=$(jq '.comment' <<< ${object})
            if [[ ${j} -ne 0 ]]; then
                json_entries="${json_entries},"
            fi
            json_entries="${json_entries}{\"op\": \"create\", \"ip\": ${ip}, \"subnet\": ${subnet}, \"negated\": ${negated}, \"comment\": ${comment}}"
        done

        local dst_acl_id=$(jq -r '.id' <<< ${result})
        post_body=$(jq <<< '{"entries": []}' | jq ".entries |= .+ [${json_entries}]")
        curl -sS -o /dev/null --fail -X PATCH -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/acl/${dst_acl_id}/entries" -H "Content-Type: application/json" -d "${post_body}"
    done
}

raw_loggigns=''
declare -a array_logging_types=("azureblob" "bigquery" "cloudfiles" "datadog" "digitalocean" "elasticsearch" "ftp" "pubsub" "gcs" "https" "heroku" "honeycomb" "kafka" "kinesis" "logshuttle" "logentries" "loggly" "newrelic" "openstack" "papertrail" "s3" "sftp" "scalyr" "splunk" "sumologic" "syslog")
copy_loggings () {
    echo "[INFO] copying loggings from the source service ..."
    local type
    for type in ${array_logging_types[@]}
    do
        printf "  type: %s ... " "${type}"
        get_objects "/service/${src_service}/version/${version}/logging/${type}"
        raw_loggigns=${global_get_objects}
        local count=$(jq 'length' <<< ${raw_loggigns})
        if [[ count -eq 0 ]]; then
            printf "skip\n"
            continue
        else
            printf "copying ...\n"
        fi

        for (( i=0; i<${count}; i++ ))
        do  
            local object=$(jq ".[${i}]" <<< ${raw_loggigns})
            filter_objects "${object}"

            local post_body=${global_filter_objects}
            curl -sS -o /dev/null -X POST --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/version/${dst_version}/logging/${type}" -H "Content-Type: application/json" -d "${post_body}"
        done
    done   
}

raw_domains=''
get_domains () {
    get_objects "/service/${dst_service}/version/${global_dst_active_version}/domain"
    raw_domains=${global_get_objects}
}

set_domains () {
    local count=$(jq 'length' <<< ${raw_domains})
    for (( i=0; i<${count}; i++ ))
    do  
        local object=$(jq ".[${i}]" <<< ${raw_domains})
        filter_objects "${object}"

        local post_body=${global_filter_objects}
        curl -sS -o /dev/null -X POST --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/version/${dst_version}/domain" -H "Content-Type: application/json" -d "${post_body}"
    done
}

urlencode() {
    old_lc_collate=$LC_COLLATE
    LC_COLLATE=C
    local length="${#1}"
    for (( i=0; i<length; i++ )); do
        local c="${1:$i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf '%s' "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done
    LC_COLLATE=$old_lc_collate
}

create_new_version () {
    echo "[INFO] creating a new version for service ID: ${dst_service} ..."
    dst_version=$(curl -sS -X POST --fail -H "fastly-key: ${API_TOKEN}" "${API_BASE_URI}/service/${dst_service}/version" | jq '.number')
    echo "[INFO] created a new version ${dst_version}"
}

global_filter_objects=''
filter_objects () {
    local readonly object=$1
    local readonly type=$2
    local filtered
    filtered=$(jq 'with_entries(select(.value != null and .value != "")) | del(.created_at, .updated_at, .deleted_at, .locked, .version, .id, .service_id)' <<< ${object})

    case ${type} in
        "backend") filtered=$(jq 'del(.ipv4, .ipv6, .hostname)' <<< ${filtered} ) ;;
        "director") filtered=$(jq 'del(.backends)' <<< ${filtered} ) ;;
        "settings") filtered=$(jq 'del(."general.default_pci")'<<< ${filtered} ) ;;
        "dynamic_snippet") filtered=$(jq 'del(.snippet_id)'<<< ${filtered} ) ;;
    esac

    global_filter_objects=${filtered}
}

main () {
    options_check
    get_src_version
    check_src_service
    check_dst_service
    create_new_version

    get_conditions
    set_conditions

    get_healthchecks
    set_healthchecks

    get_cache_settings
    set_cache_settings

    get_backends
    set_backends

    get_directors
    set_directors

    get_gzips
    set_gzips

    get_headers
    set_headers

    get_request_settings
    set_request_settings

    get_response_objects
    set_response_objects

    get_settings
    set_settings

    get_vcls
    set_vcls

    get_snippets
    set_snippets

    if [[ "${no_dictionary}" == "false" ]]; then
        get_dictionaries
        set_dictionaries
    fi

    if [[ "${no_acl}" == "false" ]]; then
        get_acls
        set_acls
    fi

    if [[ "${no_logging}" == "false" ]]; then
        copy_loggings
    fi

    # restore domains from the current active version (for destination service)
    get_dst_active_version
    if [[ "${global_dst_active_version}" != "null" ]]; then
        echo "[INFO] restoring domains ..."
        get_domains
        set_domains
    fi

    echo "\nCompleted! Go visit the destination service configuration page and activate the new version:"
    echo "https://manage.fastly.com/configure/services/${dst_service}/versions/${dst_version}/domains"
}

main

exit 0
