#!/bin/sh

GOOGLE_PROJECT="rk0n-experimental"
GOOGLE_REGION="us-central1"

readonly STATE_KEY_FILE="./up-state.key"
readonly TF_NO_VAR_FILE="env fmt get graph init output providers show taint untaint version workspace state"
readonly TF="/bin/terraform"

function confirm() {
	while true; do
		read -p "$1 (y/n)? " choice
		case "$choice" in
		y | Y) return 0 ;;
		n | N) return 1 ;;
		*) echo "invalid" ;;
		esac
	done
}

function usage_err() {
	echo "$1"
	echo
	echo "$usage"
	exit 1
}

function err() {
	echo >&2 "ERROR: $@"
	exit 1
}

function tf() {
	local google_project=$1 && shift
	local google_region=$1 && shift
	local tf_cluster_id=$1 && shift
	local tf_cmd=$1 && shift
	local tf_args=$@

	local tf_module_main="main.tf"
	local google_project_tfvars="tfvars/project/${google_project}.tfvars"
	local cluster_tfvars="tfvars/cluster/${tf_cluster_id}.tfvars"

	if [[ ! -f $tf_module_main ]]; then
		usage_err "Invalid Terraform module: $tf_module_main does not exist."
	fi

	if [[ ! -f $google_project_tfvars ]]; then
		usage_err "Unsupported GCP project: $google_project_tfvars does not exist."
	fi

	# Setting GOOGLE_ENCRYPTION_KEY enables encrypted Terraform state.
	# https://www.terraform.io/docs/backends/types/gcs.html#configuration-variables
	export GOOGLE_ENCRYPTION_KEY=$(cat ${STATE_KEY_FILE})
	[[ -z "$GOOGLE_ENCRYPTION_KEY" ]] && err "Unable to decrypt state encryption key $STATE_KEY_FILE"

	local autoload_tfvars="true"
	if echo ${TF_NO_VAR_FILE} | grep -q "$tf_cmd"; then
		autoload_tfvars="false"
	fi

	local tf_run="$TF $tf_cmd"
	if [[ "$autoload_tfvars" == "true" ]]; then
		tf_run="$tf_run -var-file=${google_project_tfvars}"
		if [[ -f "$cluster_tfvars" ]]; then
			tf_run="$tf_run -var-file=${cluster_tfvars}"
		fi
	fi
	tf_run="$tf_run $tf_args"

	$TF init -input=false >/dev/null || err "'terraform init' failed - try removing .terraform"
	if ! $TF workspace select $tf_cluster_id >/dev/null; then
		if ! confirm "Workspace $tf_cluster_id does not exist, create it"; then
			exit 1
		fi
		$TF workspace new $tf_cluster_id
	fi
	eval $tf_run
}

read -r -d '' usage <<EOD
A wrapper for running Up flavoured Terraform commands.

This wrapper invokes Terraform in an opinionated fashion. It manages one GKE
cluster per Terraform workspace, automatically loading tfvars and configuring
encrypted Google Cloud Storage remote state.

Usage:

  ./tf [flags] CLUSTER TF_CMD [TF_ARGS]

  Args:
    CLUSTER             Cluster ID. (i.e. Terraform workspace)
    TF_CMD              Terraform command to run. (i.e. plan, apply, ...)
    TF_ARGS (Optional)  Arguments to the Terraform command.

  Flags:
    -p PROJECT  GCP project. (Default: ${GOOGLE_PROJECT})
    -r REGION   GCP region. (Default: ${GOOGLE_REGION})
EOD

set -e

while getopts ":p:r:h" o; do
	case "${o}" in
	p)
		GOOGLE_PROJECT="$OPTARG"
		;;
	r)
		GOOGLE_REGION="$OPTARG"
		;;
	h)
		echo "$usage"
		exit 0
		;;
	*)
		usage_err "Unknown or invalid option."
		;;
	esac
done
shift $((OPTIND - 1))

readonly TF_CLUSTER_ID=$1
[[ -z "$TF_CLUSTER_ID" ]] && usage_err "Missing Up Cluster ID."
shift

readonly TF_CMD=$1
[[ -z "$TF_CMD" ]] && usage_err "Missing Terraform command."
shift

readonly TF_ARGS=$@

tf $GOOGLE_PROJECT $GOOGLE_REGION $TF_CLUSTER_ID $TF_CMD $TF_ARGS
