#!/usr/bin/env bash
source ~/env

task_id="setup-dns-metadata"
setup_logger "${task_id}"
setup_error_handler "${task_id}"

cd ~

echo "**********************************"
echo "*** (BEGIN) Setup DNS Metadata ***"
echo "**********************************"

export PARENT_PROJECT_DOMAIN=$(gcloud dns managed-zones describe "${PARENT_PROJECT_DNS_ZONE}" --format='value(dnsName)' --account "${PARENT_PROJECT_SVC_ACCOUNT}" --project "${PARENT_PROJECT}")

add_apigeelabs_dns_entry "TXT" "_created_at-${CHILD_PROJECT}.${PARENT_PROJECT_DOMAIN}"  "$(date +%s)"

echo "********************************"
echo "*** (END) Setup DNS Metadata ***"
echo "********************************"