#!/usr/bin/env bash
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#

CHART_HOME=$(unset CDPATH && cd $(dirname "${BASH_SOURCE[0]}")/../.. && pwd)
cd ${CHART_HOME}

usage() {
    cat <<EOF
This script is used to bootstrap the pulsar namespace before deploying a helm chart. 
Options:
       -h,--help                        prints the usage message
       -n,--namespace                   the k8s namespace to install the pulsar helm chart
       -k,--release                     the pulsar helm release name
       -s,--symmetric                   generate symmetric secret key. If not provided, an asymmetric pair of keys are generated.
       --pulsar-superusers              the superusers of pulsar cluster. a comma separated list of super users.
       -c,--create-namespace            flag to create k8s namespace.
       --service-gcs-account-key-file   the path of GCS service account key file.
Usage:
    $0 --namespace pulsar --release pulsar-release
EOF
}


while [[ $# -gt 0 ]]
do
key="$1"

symmetric=false
create_namespace=false

case $key in
    -n|--namespace)
    namespace="$2"
    shift
    shift
    ;;
    -c|--create-namespace)
    create_namespace=true
    shift
    ;;
    -k|--release)
    release="$2"
    shift
    shift
    ;;
    --service-gcs-account-key-file)
    service_account_file="$2"
    shift
    shift
    ;;
    --pulsar-superusers)
    pulsar_superusers="$2"
    shift
    shift
    ;;
    -s|--symmetric)
    symmetric=true
    shift
    ;;
    -h|--help)
    usage
    exit 0
    ;;
    *)
    echo "unknown option: $key"
    usage
    exit 1
    ;;
esac
done

namespace=${namespace:-pulsar}
release=${release:-pulsar-dev}
service_gcs_account_file=${service_gcs_account_file:-"/pulsar/keys/gcs.json"}
pulsar_superusers=${pulsar_superusers:-"proxy-admin,broker-admin,admin,pulsar-manager-admin"}

function generate_service_account_credentials() {
    local secret_name="${release}-gcs-service-account-secret"
    kubectl create secret generic ${secret_name} -n ${namespace} \
        --from-file="gcs.json=${service_gcs_account_file}"
}

pulsar_superusers=${pulsar_superusers:-"proxy-admin,broker-admin,admin,pulsar-manager-admin"}

function do_create_namespace() {
    if [[ "${create_namespace}" == "true" ]]; then
        kubectl create namespace ${namespace}
    fi
}

do_create_namespace

echo "create the credentials for the service account key file (offload data to gcs)"
generate_service_account_credentials

extra_opts=""
if [[ "${symmetric}" == "true" ]]; then
  extra_opts="${extra_opts} -s"
fi

echo "generate the token keys for the pulsar cluster"
${CHART_HOME}/scripts/pulsar/generate_token_secret_key.sh -n ${namespace} -k ${release} ${extra_opts}

echo "generate the tokens for the super-users: ${pulsar_superusers}"

IFS=', ' read -r -a superusers <<< "$pulsar_superusers"
for user in "${superusers[@]}"
do
    echo "generate the token for $user"
    ${CHART_HOME}/scripts/pulsar/generate_token.sh -n ${namespace} -k ${release} -r ${user} ${extra_opts} 
done

echo "-------------------------------------"
echo
echo "The jwt token secret keys are generated under:"
if [[ "${symmetric}" == "true" ]]; then
    echo "    - '${release}-token-symmetric-key'"
else
    echo "    - '${release}-token-asymmetric-key'"
fi
echo

echo "The jwt tokens for superusers are generated and stored as below:"
for user in "${superusers[@]}"
do
    echo "    - '${user}':secret('${release}-token-${user}')"
done
echo

echo "The credentials of the administrator of Control Center (Grafana & Pulsar Manager)"
echo "is stored at secret '${release}-admin-secret"

echo "The credentials of the service account key file (offload data to gcs)"
echo "is stored at secret '${release}-service-account-secret"
echo

