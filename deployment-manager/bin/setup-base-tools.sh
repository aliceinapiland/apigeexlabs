#!/usr/bin/env bash
source ~/env

task_id="setup-base-tools"
begin_task "${task_id}" "Installing base tools" 30

cd ~

echo "*************************************"
echo "*** (BEGIN) Installing base tools ***"
echo "*************************************"

apt-get install expect python2.7 -y
gcloud components install kubectl --quiet
snap install jq

end_task "${task_id}"
echo "***********************************"
echo "*** (END) Installing base tools ***"
echo "***********************************"