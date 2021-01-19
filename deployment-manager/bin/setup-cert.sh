#!/usr/bin/env bash
source ~/env

task_id="setup-cert"
begin_task "${task_id}" "Setting up certificates" 180

echo "***********************************"
echo "*** (BEGIN) Getting certificate ***"
echo "***********************************"

cp ~/${PARENT_PROJECT_GITHUB_REPO}/misc/cert.pem /cert.pem
cp ~/${PARENT_PROJECT_GITHUB_REPO}/misc/privkey.pem /privkey.pem
cp /cert.pem /fullchain.pem


PARENT_PROJECT_DOMAIN=$(gcloud dns managed-zones describe "${PARENT_PROJECT_DNS_ZONE}" --format='value(dnsName)' --account "${PARENT_PROJECT_SVC_ACCOUNT}" --project "${PARENT_PROJECT}")

cat << EOF >> ~/certs.env
export CHILD_PROJECT_HOST_ALIAS="\${CHILD_PROJECT}.${PARENT_PROJECT_DOMAIN%.}"
export RUNTIME_HOST_ALIAS="api-\${CHILD_PROJECT_HOST_ALIAS}"
export DEV_PORTAL_HOST_ALIAS="developer-\${CHILD_PROJECT_HOST_ALIAS}"
export OAS_EDITOR_HOST_ALIAS="spec-editor-\${CHILD_PROJECT_HOST_ALIAS}"
export REST_SERVICE_HOST_ALIAS="rest-\${CHILD_PROJECT_HOST_ALIAS}"
export SOAP_SERVICE_HOST_ALIAS="soap-\${CHILD_PROJECT_HOST_ALIAS}"
export IDP_SERVICE_HOST_ALIAS="idp-\${CHILD_PROJECT_HOST_ALIAS}"

export RUNTIME_SSL_KEY="/privkey.pem"
export RUNTIME_SSL_CERT="/fullchain.pem"

export DEV_PORTAL_SSL_KEY="/privkey.pem"
export DEV_PORTAL_SSL_CERT="/cert.pem"
export DEV_PORTAL_SSL_CHAIN="/fullchain.pem"
EOF

echo "source ~/certs.env" >> ~/env

end_task "${task_id}"

echo "*********************************"
echo "*** (END) Getting certificate ***"
echo "*********************************"