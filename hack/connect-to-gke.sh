#!/usr/bin/env bash

set -eu

if [ -n "${NEURON_DEBUG:-}" ]; then
  set -x
fi

while [ "${1-}" != "" ]; do
  case ${1-} in
  -p | --project_id) shift && project_id=$1 ;;
  -c | --cluster_name) shift && cluster_name=$1 ;;
  -l | --location) shift && location=$1 ;;
  -b | --bastion_name) shift && bastion_name=$1 ;;
  -t | --tunnel_params) shift && tunnel_params=$1 ;;
  -x | --close) shift && close=true ;;
  *) echo "🚫  Wrong flags specified, exiting..." && exit 1 ;;
  esac
  shift
done || true

close=${close:-false}
kubeconfigs_dir="$HOME/.kubeconfigs"
mkdir -p "$kubeconfigs_dir"

echo -e "ℹ️  Getting variables for connection to \033[1m$cluster_name\033[0m." >&2

function handle_variable_ambiguity() {
  local variable_name="${1}"
  local value="${!variable_name}" # indirect parameter expansion
  local how_many
  how_many="$(echo $value | wc -w)"

  if [[ $how_many -gt 1 ]]; then
    local first_value
    first_value=$(echo $value | tr ' ' '\n' | head -n 1)
    local values
    values=$(echo $value | tr '\n' ' ')

    echo "🧐 Found more than one value for '${variable_name}', you can specify one with the --${variable_name} flag."
    echo "🧐 Found values: $values" >&2
    echo "🧐 Using the first available value: $first_value" >&2
    eval "$variable_name='$first_value'" # crazy eval to override variable
  fi

  if [[ $how_many -lt 1 ]]; then
    echo "🧐 No value for '${variable_name}' found." >&2
    echo "🧐 If you provided the value with --${variable_name}, it does was not found." >&2
    echo "🧐 Skipping GKE tunnel creation." >&2
    exit 0
  fi
}

handle_variable_ambiguity project_id

cluster_name="${cluster_name:-$(
  gcloud container clusters list \
    --project $project_id \
    --format='value(name)'
)}"
handle_variable_ambiguity cluster_name

kubeconfig_path="$kubeconfigs_dir/${project_id}_${cluster_name}.yaml"
# Cut to 87 characters long to fit max OSX unix socket length (104) and to account for 16 char hash suffix added by ssh
control_socket_path=$(echo "$kubeconfigs_dir/.s_${project_id}_${cluster_name}" | cut -c -86)
if [ -S "$control_socket_path" ]; then
  is_running=true
  old_host="$(ps aux | grep $control_socket_path | grep -m 1 -o -E [0-9A-Za-z_\.]+@[0-9A-Za-z_\.]+)" || is_running=false
  if [[ $is_running == true ]]; then
    if [[ $close == true ]]; then
      echo -e "ℹ️  Closing connection to GKE cluster \033[1m$cluster_name\033[0m." >&2
      ssh -S ${control_socket_path} -O exit $old_host 2>&1 || true
      # TODO close connection
      exit 0
    fi
    check_output=$(ssh -S ${control_socket_path} -O check $old_host 2>&1)
    echo "$check_output" | grep "Master running" || is_running=false
    echo -e "ℹ️  Connection to GKE cluster \033[1m$cluster_name\033[0m is live." >&2
    exit 0
  else
    echo -e "ℹ️  Recreating connection to GKE cluster \033[1m$cluster_name\033[0m." >&2
    rm $control_socket_path
  fi
fi

tunnel_params="${tunnel_params:-}"

bastion_name="${bastion_name:-bastion}"
bastion_name=$(
  gcloud compute instances list \
    --project $project_id \
    --filter=name:$bastion_name* \
    --format='value(name)'
)
# handle bastion-vault etc.
named_bastion="$(echo $bastion_name| tr ' ' '\n' |grep $cluster_name || echo '' )"
if [[ "${named_bastion}" ]]; then 
  bastion_name="${named_bastion}";
fi;
handle_variable_ambiguity bastion_name

bastion_zone="$(
  gcloud compute instances list \
    --project $project_id \
    --filter=name:$bastion_name \
    --format='value(zone)'
)"

location="${location:-$(
  gcloud container clusters list \
    --project $project_id \
    --filter=name=$cluster_name \
    --format='value(zone)'
)}"
handle_variable_ambiguity location

zone="$(
  gcloud compute zones list \
    --project $project_id \
    --filter="name=$location" \
    --format="value(name)" |
    grep -x $location || true
)"

cluster_location_flag="--zone"
[[ -z "$zone" ]] && cluster_location_flag="--region"
cluster_location="${zone:-$location}"

echo -e "ℹ️  Connecting to \033[1m$cluster_name\033[0m." >&2

kubeconfig_original_path=$(mktemp -t kubeconfig_original.XXXXXX)
export KUBECONFIG=$kubeconfig_original_path

gcloud container clusters get-credentials ${cluster_name} \
  ${cluster_location_flag}=${cluster_location} \
  --project ${project_id}

kubernetes_master_ip="$(cat $kubeconfig_original_path |
  yq "
    .clusters[]
    | select(.name == \"gke_${project_id}_${cluster_location}_${cluster_name}\").cluster.server" \
    --raw-output |
  sed 's#https://##')"
echo $kubernetes_master_ip
unused_port=$(ruby -e 'require "socket"; puts Addrinfo.tcp("", 0).bind {|s| s.local_address.ip_port }')

gcloud beta compute ssh ${bastion_name} \
  --tunnel-through-iap \
  --zone=${bastion_zone} \
  --project=${project_id} \
  -- \
  -M \
  -S ${control_socket_path} \
  -fnNT -L 127.0.0.1:${unused_port}:${kubernetes_master_ip}:443 $tunnel_params

gke_name=".name == \"gke_${project_id}_${cluster_location}_${cluster_name}\""
cat $kubeconfig_original_path |
  yq ".clusters = ([.clusters[] | select($gke_name).cluster.server = \"https://localhost:${unused_port}\"])" |
  yq ".clusters = ([.clusters[] | select($gke_name).cluster.\"insecure-skip-tls-verify\" = true])" |
  yq "del(.clusters[0].cluster.\"certificate-authority-data\")" |
  ruby -e "require 'json'; require 'yaml'; puts YAML.dump(JSON.parse(ARGF.read))" \
    >$kubeconfig_path

echo -e "ℹ️  Connection to GKE cluster \033[1m$cluster_name\033[0m is live." >&2

echo "️ℹ️  To connect to kubernetes in $cluster_name $cluster_location in $project_id use following:"
echo "export KUBECONFIG=$kubeconfig_path"
echo "" # spacing
