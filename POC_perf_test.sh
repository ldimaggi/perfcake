set -x

## Needed ENV variables
export WORKSPACE=$PWD #This should be provided by Jenkins
export ITERATIONS=100000
export THREADS=30
export USERS=300
export SERVER_HOST=localhost
export SERVER_PORT=1234
export DURATION=43200
export ADDITIONAL_PERFREPO_TAGS=soak;12h;centos-ci
export PERFREPO_ENABLED=true

# Setup required packages
yum -y install java-1.8.0-oracle-devel java-1.8.0-oracle
yum -y install docker*
yum -y install wget
yum -y install git
yum -y install curl
yum -y install make
yum -y install chkconfig
yum -y install unzip
yum -y install maven

# Install Java - ref: https://tecadmin.net/install-java-8-on-centos-rhel-and-fedora/

cd /opt/
wget --no-cookies --no-check-certificate --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie" "http://download.oracle.com/otn-pub/java/jdk/8u121-b13/e9e7ea248e2c4826b92b3f075a80e441/jdk-8u121-linux-x64.tar.gz"
tar xzf jdk-8u121-linux-x64.tar.gz

cd /opt/jdk1.8.0_121/
alternatives --install /usr/bin/java java /opt/jdk1.8.0_121/bin/java 2
alternatives --install /usr/bin/jar jar /opt/jdk1.8.0_121/bin/jar 2
alternatives --install /usr/bin/javac javac /opt/jdk1.8.0_121/bin/javac 2
alternatives --set jar /opt/jdk1.8.0_121/bin/jar
alternatives --set javac /opt/jdk1.8.0_121/bin/javac
alternatives --set javac /opt/jdk1.8.0_121/bin/java

export JAVA_HOME=/opt/jdk1.8.0_121
export JRE_HOME=/opt/jdk1.8.0_121/jre
export PATH=$PATH:/opt/jdk1.8.0_121/bin:/opt/jdk1.8.0_121/jre/bin
export MAVEN_OPTS="-Dmaven.repo.local=$WORKSPACE/local-maven-repo"

cd $WORKSPACE

# Start up the docker daemon
systemctl start docker
sleep 10
systemctl status docker

chmod +x devtools-performance-core-crud-soak.sh
./devtools-performance-core-crud-soak.sh
