#!/usr/bin/env bash
source ~/env

task_id="dm"
setup_logger "${task_id}"
setup_error_handler "${task_id}"

setup-bootstrap-tool.sh
setup-dns-metadata.sh
setup-student-home.sh
setup-gcp-logging.sh
setup-base-tools.sh
setup-cert.sh
setup-gs-bucket.sh
setup-lab-tools.sh

source ~/env
pushd ~/"${PARENT_PROJECT_GITHUB_REPO}/labs/${PARENT_PROJECT_LAB_DIR_NAME}"
./startup.sh