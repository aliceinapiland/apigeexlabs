#!/usr/bin/env bash
source ~/env

task_id="setup-gcp-logging"
begin_task "${task_id}" "Setting up GCP logging agent" 30


cd ~

echo "********************************************"
echo "*** (BEGIN) Installing GCP Logging Agent ***"
echo "********************************************"

GOOGLE_APPLICATION_CREDENTIALS="/etc/google/auth/application_default_credentials.json"
mkdir -p $(dirname ${GOOGLE_APPLICATION_CREDENTIALS})
echo "${CHILD_PROJECT_SVC_ACCOUNT_JSON}" > $GOOGLE_APPLICATION_CREDENTIALS
chown root:root "$GOOGLE_APPLICATION_CREDENTIALS"
chmod 0400 "$GOOGLE_APPLICATION_CREDENTIALS"

curl -sSO https://dl.google.com/cloudagents/add-logging-agent-repo.sh
bash add-logging-agent-repo.sh
apt-get update -y
apt-get install -y google-fluentd google-fluentd-catch-all-config-structured
service google-fluentd start

end_task "${task_id}"
echo "******************************************"
echo "*** (END) Installing GCP Logging Agent ***"
echo "******************************************"