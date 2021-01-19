#!/usr/bin/env bash
source ~/env

task_id="setup-lab-tools"
begin_task "${task_id}" "Installing lab tools" 30

cd ~

echo "********************************"
echo "*** (BEGIN) Installing tools ***"
echo "********************************"


echo "*** Installing xml tools ***"
apt-get install -y libxml2-utils xmlformat-perl

export NODE_VERSION=v12.18.0
echo "*** Installing Node.js ($NODE_VERSION) ***"
export NODE_DIR=node-${NODE_VERSION}-linux-x64
export NODE_TARBALL=${NODE_DIR}.tar.gz
echo "Downloading node.js tarball ..."
curl -s -O https://nodejs.org/dist/${NODE_VERSION}/${NODE_TARBALL}
tar -xzf ${NODE_TARBALL}
sudo mv ${NODE_DIR} /opt/${NODE_DIR}
chmod a+rwx -R /opt/${NODE_DIR}
export NODE_PATH=/opt/${NODE_DIR}/bin


echo "*** Installing Java 14 ***"
echo "Downloading jdk tarball ..."
curl -s -O https://download.java.net/java/GA/jdk14/076bab302c7b4508975440c56f6cc26a/36/GPL/openjdk-14_linux-x64_bin.tar.gz
tar -xzf openjdk-14_linux-x64_bin.tar.gz
chmod a+rwx -R jdk-14
sudo mv jdk-14 /opt
export JDK_PATH=/opt/jdk-14/bin


echo "*** Installing Maven 3 ***"
export MVN_VERSION=3.6.3
export MVN_DIR=apache-maven-${MVN_VERSION}
echo "Downloading maven tarball ..."
curl -s -O http://mirror.cc.columbia.edu/pub/software/apache/maven/maven-3/${MVN_VERSION}/binaries/${MVN_DIR}-bin.tar.gz
tar -xzf ${MVN_DIR}-bin.tar.gz
chmod a+rwx -R ${MVN_DIR}
sudo mv ${MVN_DIR} /opt/
export MVN_PATH=/opt/${MVN_DIR}/bin


cat << EOF >> ~/tools.env
export NODE_PATH='${NODE_PATH}'
export JDK_PATH='${JDK_PATH}'
export MVN_PATH='${MVN_PATH}'
export PATH="\${NODE_PATH}:\${JDK_PATH}:\${MVN_PATH}:\$PATH"
EOF

echo "source ~/tools.env" >> ~/env

end_task "${task_id}"
echo "********************************"
echo "*** (END) Installing tools ***"
echo "********************************"
