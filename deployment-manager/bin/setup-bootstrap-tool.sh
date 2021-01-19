#!/usr/bin/env bash
source ~/env

task_id="setup-bootstrap-tool"
setup_logger "${task_id}"
setup_error_handler "${task_id}"

cd ~

echo "*********************************************"
echo "*** (BEGIN) Setting up lab-bootstrap tool ***"
echo "*********************************************"

cp "${BASEDIR}/lab-bootstrap" /usr/bin/
chmod a+rx /usr/bin/lab-bootstrap

echo "*******************************************"
echo "*** (END) Setting up lab-bootstrap tool ***"
echo "*******************************************"