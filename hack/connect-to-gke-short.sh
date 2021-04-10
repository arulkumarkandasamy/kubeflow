#!/usr/bin/env bash

kubeconfigs_dir="$HOME/.kubeconfigs"
mkdir -p "$kubeconfigs_dir"
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

gcloud beta compute ssh bastion-1 \
  --tunnel-through-iap \
  --zone=europe-west1 \
  --project=${project_id} \
  -- \
  -M \
  -S ${control_socket_path} \
  -fnNT -L 127.0.0.1:${unused_port}:${kubernetes_master_ip}:443
