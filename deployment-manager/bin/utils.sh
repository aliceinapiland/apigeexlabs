function setup_logger() {
  exec 1> >(stdbuf -i0 -oL -eL sed -e 's/^/'"$1: "'/') 2>&1
}

function launch_prefixed() {
  prefix="$1"
  command="$2"
  "$command" 1> >(stdbuf -i0 -oL -eL sed -e 's/^/'"$1: "'/') 2>&1
}

# When doing a DNS lookup, check all the authoritative servers for the parent domain
# All of them must give a response before we return
# This logic is needed because we don't know which name server certbot is going to check
function short_dig_apigeelabs() {
  dns_record_type="$1"
  dns_record="$2"

  parent_project_domain=$(gcloud dns managed-zones describe "${PARENT_PROJECT_DNS_ZONE}" --format='value(dnsName)' --account "${PARENT_PROJECT_SVC_ACCOUNT}" --project "${PARENT_PROJECT}")

  dns_servers_count=$(dig +short NS "${parent_project_domain}"|wc -l)
  count=0
  dns_result=""

  for dns_server in $(dig +short NS "${parent_project_domain}") ; do
    dns_result=$(dig +short -t ${dns_record_type} ${dns_record} @${dns_server})
    if [[ ! -z "${dns_result}" ]] ; then
      let "count = count + 1"
    fi
  done

  if [[ "${dns_servers_count}" == "${count}" ]] ; then
    echo "${dns_result}"
  else
    echo ""
  fi
}

function assets_access_token() {

  #sometimes getting access token fails, so re-try until it succeeds
  while true ; do
    set +e
    access_token_value="$(gcloud auth print-access-token --account="${PARENT_PROJECT_SVC_ACCOUNT}" 2> /dev/null)"
    access_token_exit_code="$?"
    set -e
    if [[ "${access_token_exit_code}" == "0" ]] ; then
      echo "${access_token_value}"
      break;
    fi
  done
}

function add_apigeelabs_dns_entry() {
  resource_type="$1"
  resource_name="$2"
  resource_value="$3"
  resource_ttl="${4:-60}"

  curl -f -s -X POST  "https://www.googleapis.com/dns/v1/projects/${PARENT_PROJECT}/managedZones/${PARENT_PROJECT_DNS_ZONE}/changes" \
    -H "Authorization: Bearer $(assets_access_token)" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    -d "$(cat << DNSEOF
{
  "additions": [
    {
      "name": "${resource_name}",
      "type": "${resource_type}",
      "ttl": "${resource_ttl}",
      "rrdatas": [
        "${resource_value}"
      ]
    }
  ]
}
DNSEOF
)"
}

function wait_for_dns_record() {
  dns_record_type="$1"
  dns_host="$2"

  (
  setup_logger "poll"
  dns_server="${3:-@8.8.8.8}"
  dns_record=$(dig +short -t ${dns_record_type} ${dns_host} ${dns_server});
  attempts=0
  while [ -z "$dns_record" ] ; do
    (("attempts = attempts + 1"))
    echo "Waiting for ${dns_host} DNS ${dns_record_type} record (${attempts} attempt(s)) ...";
    dns_record=$(dig +short -t ${dns_record_type} ${dns_host} ${dns_server});
    [ -z "$dns_record" ] && sleep 10;
  done;
  echo "Got DNS \"${dns_record_type}\"  record \"${dns_record}\" for \"${dns_host}\" ..."
  )
}


function wait_for_apigeelabs_dns_record() {
  dns_record_type="$1"
  dns_host="$2"

  (
  setup_logger "poll"
  dns_record=$(short_dig_apigeelabs ${dns_record_type} ${dns_host});
  attempts=0
  while [ -z "$dns_record" ] ; do
    (("attempts = attempts + 1"))
    echo "Waiting for ${dns_host} DNS ${dns_record_type} record (${attempts} attempt(s)) ...";
    dns_record=$(short_dig_apigeelabs ${dns_record_type} ${dns_host});
    [ -z "$dns_record" ]  && sleep 10;
  done;
  echo "Got DNS \"${dns_record_type}\" record \"${dns_record}\" for \"${dns_host}\" ..."
  )
}


function get_service_ip() {
  service_name=$1
  service_ip=$(kubectl get service ${service_name} -o json | jq ".status.loadBalancer.ingress[0].ip" -r)
  echo "${service_ip}"
}

function wait_for_service_ip() {
  service_name=$1
  (
  setup_logger "poll"
  service_ip="null"
  attempts=0
  while [ -z "$service_ip" ] || [ "$service_ip" == "null" ]; do
    (("attempts = attempts + 1"))
    echo "Waiting for ${service_name} IP address (${attempts} attempts(s)) ...";
    service_ip=$(kubectl get service "${service_name}" -o json | jq ".status.loadBalancer.ingress[0].ip" -r);
    [ -z "$service_ip" ] || [ "$service_ip" == "null" ] && sleep 10;
  done;
  echo "Got IP Address \"${service_ip}\" for \"${service_name}\" ...";
  )
}


function wait_for_service_and_add_to_dns() {
  service_name="$1"
  service_host="$2"
  wait_for_service_ip "$service_name"
  service_ip=$(get_service_ip "$service_name")
  echo "Adding $service_name address ($service_ip) to DNS"
  add_apigeelabs_dns_entry "A" "${service_host}" "${service_ip}"
  echo "*** $service_name ready: ${service_host} ***"
}


function get_repo_dir() {
  repo_dir="$(basename "${1}" .git)"
  echo "${repo_dir}"
}

function checkout_branch() {
  git_branch_desired="$1"
  git_branch_fallback="$2"

  git_branch="${git_branch_desired}"
  if [[ "$(git ls-remote origin "${git_branch}" | wc -l)" == "0" ]] ; then
    echo "WARNING: '${git_branch}' branch does not exist. Falling back to '${git_branch_fallback}' branch"
    git_branch="${git_branch_fallback}"
  fi

  git checkout "${git_branch}"
}

function clone_github_repo_and_checkout_branch(){
  github_org="$1"
  github_repo="$2"
  github_branch="$3"
  github_depth="${4:-1}"
  github_branch_fallback="${5:-main}"
  git_repo_dir="$(get_repo_dir ${github_repo})"

  echo "*** Cloning ${git_repo_dir} (${github_branch} branch) ***"
  set +e
  git clone --single-branch --branch "${github_branch}" -q --depth "${github_depth}" "https://github.com/${github_org}/${github_repo}.git"
  git_clone_exit_code="$?"
  set -e
  if [[ "${git_clone_exit_code}" == "0" ]] ; then
    return 0
  fi

  echo "WARNING: Could not clone ${git_repo_dir} (${github_branch}), falling back to '${github_branch_fallback}'"
  github_branch="${github_branch_fallback}"
  echo "*** Cloning ${git_repo_dir} (${github_branch} branch) ***"
  set +e
  git clone --single-branch --branch "${github_branch}" -q --depth "${github_depth}" "${github_repo}"
  git_clone_exit_code="$?"
  set -e
  if [[ "${git_clone_exit_code}" != "0" ]] ; then
    echo "ERROR: Could not clone ${git_repo_dir} (${github_branch})"
    return 1
  fi
}



function project_access_token() {
  # looks like there is a big in gcloud where sometimes this command fails, so re-try until it succeeds
  while true ; do
    access_token_value="$(gcloud auth print-access-token --account="${CHILD_PROJECT_SVC_ACCOUNT}" 2> /dev/null)"
    access_token_exit_code="$?"
    if [[ "${access_token_exit_code}" == "0" ]] ; then
      echo "${access_token_value}"
      break;
    fi
  done
}



function wait_for_apigee_config_api_ready() {
  org="$1"
  (
  setup_logger "poll"
  status_code=""
  attempts=0
  while [ -z "$status_code" ] || [ "$status_code" != "200" ]; do
    (("attempts = attempts + 1"))
    echo "Waiting for Apigee config API to be ready (${attempts} attempts(s)) ..." && sleep 10;
    status_code=$(curl -k -s -o /dev/null \
                      -w "%{http_code}" \
                      --max-time 5 \
                      -H "Authorization: Bearer $(project_access_token)" \
                      -X GET "https://apigee.googleapis.com/v1/organizations/${org}/apiproducts" | head -1)
  done;
  echo "Got HTTP \"${status_code}\" from Apigee config API ..." && sleep 10;
  )
}

function wait_for_devportal_apidocs_api_ready() {
  dev_portal_host_alias="$1"
  (
  setup_logger "poll"
  status_code=""
  attempts=0
  while [ -z "$status_code" ] || [ "$status_code" != "200" ]; do
    (("attempts = attempts + 1"))
    echo "Waiting for Dev Portal API-Docs API to be ready (${attempts} attempts(s)) ..." && sleep 10;
    status_code=$(curl -k -s -o /dev/null \
                      -w "%{http_code}" \
                      --max-time "5" \
                      -X GET "https://${dev_portal_host_alias}/jsonapi/apidoc/apidoc" | head -1)
  done;
  echo "Got HTTP \"${status_code}\" from the Portal API-Docs API ..." && sleep 10;
  )
}

function error_handler() {
  program="$0"
  line_num="$1"
  exit_code="$2"
  task_id="$3"
  if [[ "${exit_code}" == "0" ]] ; then
    exit ${exit_code}
  fi

  echo "${program}: line ${line_num}: exit status of last command: ${exit_code}"
  fail_task "${task_id}"
  exit ${exit_code}
}

export -f error_handler
function setup_error_handler() {
  set -e
  TASK_ID="$1"
  trap 'error_handler ${LINENO} $? '"$TASK_ID" EXIT
}



function begin_task() {
  task_id="$1"
  task_name="$2"
  task_eta="$3"
  setup_logger "${task_id}"
  setup_error_handler "${task_id}"

  if command -v lab-bootstrap &> /dev/null  ; then
    lab-bootstrap begin "${task_id}" "${task_name}" "${task_eta}"
  fi
}

function end_task() {
  task_id="$1"

  if command -v lab-bootstrap &> /dev/null  ; then
    lab-bootstrap end "${task_id}"
  fi
}

function fail_task() {
  task_id="$1"

  if command -v lab-bootstrap &> /dev/null  ; then
    lab-bootstrap fail "${task_id}"
  fi
}




function install_google_cloud_sdk() {
  version="${1}"; shift
  snap remove google-cloud-sdk
  tarball="google-cloud-sdk-${version}-linux-x86_64.tar.gz"
  curl -s  -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/${tarball}
  tar --overwrite -xzf "${tarball}" -C /
  chmod a+rwx -R /google-cloud-sdk
  pushd /google-cloud-sdk
  ./install.sh --quiet --path-update true
  source /google-cloud-sdk/path.bash.inc
  popd
}

function activate_service_account() {
  service_account_json="$1"
  # sometimes service account activation fails, so retry
  while true ; do
    set +e
    gcloud auth activate-service-account --key-file=<(echo "${service_account_json}")
    exit_code="$?"
    set -e
    if [[ "${exit_code}" == "0" ]] ; then
      break;
    fi
  done
}

function checkout_branch() {
  git_branch_desired="$1"
  git_branch_fallback="$2"

  git_branch="${git_branch_desired}"
  if [[ "$(git ls-remote origin "${git_branch}" | wc -l)" == "0" ]] ; then
    echo "WARNING: '${git_branch}' branch does not exist. Falling back to '${git_branch_fallback}' branch"
    git_branch="${git_branch_fallback}"
  fi

  git checkout "${git_branch}"
}
