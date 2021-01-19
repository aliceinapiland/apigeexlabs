#!/usr/bin/env bash
source ~/env

task_id="setup-student-home"
begin_task "${task_id}" "Setting up student account" 10

cd ~

echo "******************************************"
echo "*** (BEGIN) Setting up student account ***"
echo "******************************************"


if ! id "${CHILD_PROJECT_USERNAME}" &>/dev/null; then
  echo "*** Adding Student Account ${CHILD_PROJECT_USERNAME} ***"
  adduser --disabled-password --gecos "" "${CHILD_PROJECT_USERNAME}"
fi

echo "*** Creating home directory for ${CHILD_PROJECT_USERNAME} ***"
mkhomedir_helper ${CHILD_PROJECT_USERNAME}

export STUDENT_HOME="/home/${CHILD_PROJECT_USERNAME}"

cat << EOF >> "${STUDENT_HOME}/lab.env"
export PATH="/snap/bin:\$PATH"
export CHILD_PROJECT='${CHILD_PROJECT}'
export CHILD_PROJECT_ZONE='${CHILD_PROJECT_ZONE}'
export ENV="test"
export ACCESS_TOKEN=\$(gcloud auth print-access-token)
source "/google-cloud-sdk/path.bash.inc"
EOF

chown "${CHILD_PROJECT_USERNAME}:ubuntu" "${STUDENT_HOME}/lab.env"

export HOME="${STUDENT_HOME}"
sudo -u "${CHILD_PROJECT_USERNAME}" -E bash -c '
/google-cloud-sdk/install.sh --quiet --path-update true ;
source ~/lab.env ;
gcloud auth activate-service-account --key-file=<(echo ${CHILD_PROJECT_SVC_ACCOUNT_JSON})
'

cat << EOF >> ~/student.env
export STUDENT_HOME='${STUDENT_HOME}'
EOF
echo "source ~/student.env" >> ~/env


end_task "${task_id}"
echo "****************************************"
echo "*** (END) Setting up student account ***"
echo "****************************************"
