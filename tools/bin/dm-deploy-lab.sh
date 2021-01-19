#!/usr/bin/env bash


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"



export PARENT_PROJECT="$1";
export PARENT_PROJECT_SVC_ACCOUNT_PASS="$2";
export PARENT_PROJECT_DNS_ZONE="$3"
export PARENT_PROJECT_GITHUB_ORG="$4"
export PARENT_PROJECT_GITHUB_REPO="$5"
export PARENT_PROJECT_GITHUB_BRANCH="$6"
export PARENT_PROJECT_LAB_DIR_NAME="$7" ;

set -e

usage() {
  echo "Usage: "
  echo "  $0 \\"
  echo "    parentProject \\"
  echo "    parentProjectSvcAccountPass \\"
  echo "    parentProjectDNSZone \\"
  echo "    parentProjectGithubOrg \\"
  echo "    parentProjectGithubRepo \\"
  echo "    parentProjectGithubBranch \\"
  echo "    parentProjectLabDirName"
}

if [[ -z "$PARENT_PROJECT" ]] ; then
  echo "error: parentProject is required" && usage && exit 1;
fi

if [[ -z "$PARENT_PROJECT_SVC_ACCOUNT_PASS" ]] ; then
  echo "error: parentProjectSvcAccountPass is required" && usage && exit 1;
fi


if [[ -z "$PARENT_PROJECT_DNS_ZONE" ]] ; then
  echo "error: parentProjectDNSZone is required" && usage && exit 1;
fi

if [[ -z "$PARENT_PROJECT_GITHUB_ORG" ]] ; then
  echo "error: parentProjectGithubRepo is required" && usage && exit 1;
fi

if [[ -z "$PARENT_PROJECT_GITHUB_REPO" ]] ; then
  echo "error: parentProjectGithubRepo is required" && usage && exit 1;
fi

if [[ -z "$PARENT_PROJECT_GITHUB_BRANCH" ]] ; then
  echo "error: parentProjectGithubBranch is required" && usage && exit 1;
fi

if [[ -z "${PARENT_PROJECT_LAB_DIR_NAME}" ]] ; then
  echo "error: parentProjectLabDirName is required" && usage && exit 1;
fi



export DEPLOYMENT='qwiklabs'

export CHILD_PROJECT="$(gcloud config get-value project)"
export CHILD_PROJECT_REGION="$(gcloud compute project-info describe --project="${CHILD_PROJECT}" --format='value(commonInstanceMetadata.items.google-compute-default-region)')"
export CHILD_PROJECT_ZONE="$(gcloud compute project-info describe --project="${CHILD_PROJECT}" --format='value(commonInstanceMetadata.items.google-compute-default-zone)')"
export CHILD_PROJECT_USERNAME="${CHILD_PROJECT_USERNAME:-student}"
export CHILD_PROJECT_SVC_ACCOUNT_NAME="${CHILD_PROJECT_SVC_ACCOUNT_NAME:-lab-startup}"


export STARTUP_SCRIPT_URL="https://raw.githubusercontent.com/${PARENT_PROJECT_GITHUB_ORG}/${PARENT_PROJECT_GITHUB_REPO}/${PARENT_PROJECT_GITHUB_BRANCH}/deployment-manager/bin/bootstrap.sh?$(date +%s)"

if [ -z "${CHILD_PROJECT}" ] ; then
  echo "ERROR: Could not determine current GCP project. Set it using 'gcloud config set project your-gcp-project-name"
  exit 1
fi

if [ -z "${CHILD_PROJECT_REGION}" ] ; then
  echo "ERROR: Could not determine current GCP project default compute region."
  exit 1
fi

if [ -z "${CHILD_PROJECT_ZONE}" ] ; then
  echo "ERROR: Could not determine current GCP project default compute zone."
  exit 1
fi

if gcloud deployment-manager deployments describe qwiklabs &> /dev/null ; then
  echo "ERROR: Deployment named '${DEPLOYMENT}' already exists in project '${CHILD_PROJECT}'"
  echo "Run the following command to delete it:"
  echo "  gcloud deployment-manager deployments delete '${DEPLOYMENT}' --quiet"
  exit 1
fi

TMP_DIR=$(mktemp -d -t dm-XXXXXXXXXX)
pushd "${TMP_DIR}"


if gcloud iam service-accounts describe "${CHILD_PROJECT_SVC_ACCOUNT_NAME}@${CHILD_PROJECT}.iam.gserviceaccount.com" &> /dev/null ; then
  echo "WARNING: Service account ${CHILD_PROJECT_SVC_ACCOUNT_NAME} already exists, will delete it ..."
  gcloud iam service-accounts delete --quiet "${CHILD_PROJECT_SVC_ACCOUNT_NAME}@${CHILD_PROJECT}.iam.gserviceaccount.com"
fi

echo "*** Creating service account ${CHILD_PROJECT_SVC_ACCOUNT_NAME} ***"

gcloud iam service-accounts create "${CHILD_PROJECT_SVC_ACCOUNT_NAME}" \
    --description="Service account used for bootstrapping lab resources" \
    --display-name="${CHILD_PROJECT_SVC_ACCOUNT_NAME}"

gcloud projects add-iam-policy-binding "${CHILD_PROJECT}" \
    --member=serviceAccount:${CHILD_PROJECT_SVC_ACCOUNT_NAME}@${CHILD_PROJECT}.iam.gserviceaccount.com \
    --role=roles/owner

echo "*** Creating key for service account ${CHILD_PROJECT_SVC_ACCOUNT_NAME} ***"
gcloud iam service-accounts keys create svc.json \
    --iam-account=${CHILD_PROJECT_SVC_ACCOUNT_NAME}@${CHILD_PROJECT}.iam.gserviceaccount.com \
    --key-file-type=json

export CHILD_PROJECT_SVC_ACCOUNT_JSON="$(cat svc.json)"


echo "*** Copying deployment manager files ***"
cp -r "${DIR}/../../deployment-manager/dm/." .


echo "*** Rendering deployment properties in qwiklabs.yaml ***"
cat "${TMP_DIR}/qwiklabs.yaml" \
   | perl -pe 's#\$#§#g' \
   | perl -pe 's#\{\{([^}]+)\}\}#\${$1}#g' \
   | envsubst \
   | perl -pe 's#§#\$#g' > "${TMP_DIR}/qwiklabs.yaml.temp"
mv "${TMP_DIR}/qwiklabs.yaml.temp" "${TMP_DIR}/qwiklabs.yaml"

echo "*** Using the following rendered qwiklabs.yaml ***"
cat "${TMP_DIR}/qwiklabs.yaml"

echo "*** Creating deployment ***"
gcloud deployment-manager deployments create ${DEPLOYMENT} --config="qwiklabs.yaml" --quiet

echo "Done"