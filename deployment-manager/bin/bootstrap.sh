#!/usr/bin/env bash
cd ~

# Helper functions for bootstrapping
function get_metadata_property() {
  attribute_name="$1";
  default_value="$2"
  ! attribute_value=$(curl -f -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/${attribute_name}" -H "Metadata-Flavor: Google")
  if [[ -z "${attribute_value}" ]] ; then
    echo "${default_value}"
    return
  fi
  echo "${attribute_value}"
}

echo "*** Setting up parent project config ***"
export PARENT_PROJECT=$(get_metadata_property 'parentProject' "")
export PARENT_PROJECT_GITHUB_ORG=$(get_metadata_property 'parentProjectGithubOrg' "")
export PARENT_PROJECT_GITHUB_REPO=$(get_metadata_property 'parentProjectGithubRepo' "")
export PARENT_PROJECT_GITHUB_BRANCH=$(get_metadata_property 'parentProjectGithubBranch' "")
export PARENT_PROJECT_DNS_ZONE=$(get_metadata_property 'parentProjectDNSZone' "")
export PARENT_PROJECT_SVC_ACCOUNT_PASS=$(get_metadata_property 'parentProjectSvcAccountPass' "")
export PARENT_PROJECT_SVC_ACCOUNT_JSON=$(openssl aes-256-cbc -d -salt -pbkdf2 -pass "pass:${PARENT_PROJECT_SVC_ACCOUNT_PASS}" -in <(curl -o - -s "https://raw.githubusercontent.com/${PARENT_PROJECT_GITHUB_ORG}/${PARENT_PROJECT_GITHUB_REPO}/${PARENT_PROJECT_GITHUB_BRANCH}/misc/svc.json.enc?$(date +%s)"))
export PARENT_PROJECT_LAB_DIR_NAME=$(get_metadata_property 'parentProjectLabDirName' "")

echo "*** Setting up child project config ***"
export CHILD_PROJECT=$(get_metadata_property 'childProject' "")
export CHILD_PROJECT_SVC_ACCOUNT_JSON=$(get_metadata_property 'childProjectSvcAccountJSON' "")
export CHILD_PROJECT_USERNAME=$(get_metadata_property 'childProjectUsername' "student")
export CHILD_PROJECT_ZONE=$(get_metadata_property 'childProjectZone' "us-west1-b")
export CHILD_PROJECT_REGION=$(get_metadata_property 'childProjectRegion' "us-west1")

echo "*** Setting up other config ***"
export ENV=$(get_metadata_property 'env' "test")
export GOOGLE_CLOUD_SDK_VERSION=$(get_metadata_property 'googleCloudSDKVersion' "322.0.0")
export HOME=/root

# Additional helper functions
source <(curl -o - -s "https://raw.githubusercontent.com/${PARENT_PROJECT_GITHUB_ORG}/${PARENT_PROJECT_GITHUB_REPO}/${PARENT_PROJECT_GITHUB_BRANCH}/deployment-manager/bin/utils.sh?$(date +%s)")

echo "*** Updating apt package list ***"
apt-get update

echo "*** Installing Google Cloud SDK (${GOOGLE_CLOUD_SDK_VERSION}) ***"
install_google_cloud_sdk "${GOOGLE_CLOUD_SDK_VERSION}"

echo "*** Activating parent project service account ***"
activate_service_account "${PARENT_PROJECT_SVC_ACCOUNT_JSON}"
export PARENT_PROJECT_SVC_ACCOUNT=$(gcloud config list account --format "value(core.account)")

echo "*** Activating child project service account ***"
activate_service_account "${CHILD_PROJECT_SVC_ACCOUNT_JSON}"
export CHILD_PROJECT_SVC_ACCOUNT=$(gcloud config list account --format "value(core.account)")

echo "*** Cloning deployment manager (${PARENT_PROJECT_GITHUB_BRANCH} branch) ***"
rm -rf "${PARENT_PROJECT_GITHUB_REPO}"

clone_github_repo_and_checkout_branch "${PARENT_PROJECT_GITHUB_ORG}" "${PARENT_PROJECT_GITHUB_REPO}" "${PARENT_PROJECT_GITHUB_BRANCH}"

echo "*** Creting main environment file ***"
cat << EOF > ~/env
BASEDIR="\$( cd "\$( dirname "\$0" )" && pwd )"
export PATH="${HOME}/${PARENT_PROJECT_GITHUB_REPO}/deployment-manager/bin:/snap/bin:\$PATH"
export HOME='${HOME}'
export CHILD_PROJECT='${CHILD_PROJECT}'
export CHILD_PROJECT_ZONE='${CHILD_PROJECT_ZONE}'
export CHILD_PROJECT_REGION='${CHILD_PROJECT_REGION}'
export CHILD_PROJECT_USERNAME='${CHILD_PROJECT_USERNAME}'
export CHILD_PROJECT_SVC_ACCOUNT='${CHILD_PROJECT_SVC_ACCOUNT}'
export CHILD_PROJECT_SVC_ACCOUNT_JSON='${CHILD_PROJECT_SVC_ACCOUNT_JSON}'

export PARENT_PROJECT='${PARENT_PROJECT}'
export PARENT_PROJECT_SVC_ACCOUNT='${PARENT_PROJECT_SVC_ACCOUNT}'
export PARENT_PROJECT_GITHUB_ORG='${PARENT_PROJECT_GITHUB_ORG}'
export PARENT_PROJECT_GITHUB_REPO='${PARENT_PROJECT_GITHUB_REPO}'
export PARENT_PROJECT_GITHUB_BRANCH='${PARENT_PROJECT_GITHUB_BRANCH}'
export PARENT_PROJECT_DNS_ZONE='${PARENT_PROJECT_DNS_ZONE}'
export PARENT_PROJECT_LAB_DIR_NAME='${PARENT_PROJECT_LAB_DIR_NAME}'

source "/google-cloud-sdk/path.bash.inc"
source "\$(which utils.sh)"
EOF

echo "*** Handing off deployment to dm.sh ***"
source ~/env
dm.sh