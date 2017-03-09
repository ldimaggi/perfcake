set -x

# Get a baseline of workitems in DB
curl -silent -X GET --header 'Accept: application/json' 'http://api-perf.dev.rdu2c.fabric8.io/api/workitems' |  sed s/.*totalCount/\\n\\n\\n"totalCount of workitems in DB"/g | sed s/\"//g | sed s/}//g | grep totalCount >/tmp/before

# Setup required packages
# yum -y install java-1.8.0-oracle-devel java-1.8.0-oracle
yum -y install docker*
yum -y install wget
yum -y install git
yum -y install curl
yum -y install make
yum -y install chkconfig
yum -y install unzip

# Install Java - ref: https://tecadmin.net/install-java-8-on-centos-rhel-and-fedora/

export startDir=$PWD
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

cd $startDir

# Start up the docker daemon
systemctl start docker
sleep 10
systemctl status docker

# Get Perfcake, and our preconfigured Perfcake test config file
wget https://www.perfcake.org/download/perfcake-7.4-bin.zip
unzip perfcake-7.4-bin.zip
export PERFCAKE_HOME=$PWD/perfcake-7.4
git clone https://github.com/ldimaggi/perfcake.git
cp perfcake/input.xml perfcake-7.4/resources/scenarios/
cp perfcake/create.xml perfcake-7.4/resources/scenarios/
cp perfcake/read.xml perfcake-7.4/resources/scenarios/

# Build the core server that will provide our test client with tokens

# Download the core 
git clone https://github.com/almighty/almighty-core.git
cd almighty-core

# Run the DB docker image (detached) that the core requires
docker run --name db -d -p 5432 -e POSTGRESQL_ADMIN_PASSWORD=mysecretpassword centos/postgresql-95-centos7

# Cleanup and then build the docker core image
make docker-rm
sleep 10
make docker-start 
sleep 10
make docker-build
sleep 10
make docker-image-deploy
sleep 10

# Run the docker core image (detached)
docker run -p 1234:8080 --name core -d -e ALMIGHTY_DEVELOPER_MODE_ENABLED=1 -e ALMIGHTY_POSTGRES_HOST=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' db 2>/dev/null) almighty-core-deploy
sleep 10

# Run the test
export ITERATIONS=10000
export THREADS=10
export TOKEN_LIST=$PERFCAKE_HOME/token.keys
export WORK_ITEM_IDS=$PERFCAKE_HOME/workitem-id.list
# Parse/extract the token for the test
for i in $(seq 1 $THREADS);
do
   auth_resp=$(curl --silent -X GET --header 'Accept: application/json' 'http://0000:1234/api/login/generate')
   token=$(echo $auth_resp | cut -d ":" -f 3 | sed -e 's/","expires_in//g' | sed -e 's/"//g');
   echo $token >> $TOKEN_LIST;
done

# Run the test - single token == single user */
export WORK_ITEM_IDS=$PERFCAKE_HOME/workitem-id.list
export PERFCAKE_PROPS="-Dthread.count=$THREADS -Diteration.count=$ITERATIONS -Dworkitemid.list=file:$WORK_ITEM_IDS -Dauth.token.list=file:$TOKEN_LIST"

# (C)RUD
$PERFCAKE_HOME/bin/perfcake.sh -s create $PERFCAKE_PROPS
cat $PERFCAKE_HOME/perfcake-validation.log | grep Response | sed -e 's,.*"links":{"self":"http://api-perf.dev.rdu2c.fabric8.io/api/workitems/\([^"]*\)".*,\1,g' > $WORK_ITEM_IDS
#cat $WORK_ITEM_IDS
cat $PERFCAKE_HOME/create-average-throughput.csv
mv $PERFCAKE_HOME/perfcake-validation.log $PERFCAKE_HOME/perfcake-validation-create.log
#cat $PERFCAKE_HOME/perfcake-validation-create.log
mv $PERFCAKE_HOME/perfcake.log $PERFCAKE_HOME/perfcake-create.log
#cat $PERFCAKE_HOME/perfcake-create.log

# C(R)UD
$PERFCAKE_HOME/bin/perfcake.sh -s read $PERFCAKE_PROPS
cat $PERFCAKE_HOME/read-average-throughput.csv
mv $PERFCAKE_HOME/perfcake-validation.log $PERFCAKE_HOME/perfcake-validation-read.log
#cat $PERFCAKE_HOME/perfcake-validation-read.log
mv $PERFCAKE_HOME/perfcake.log $PERFCAKE_HOME/perfcake-read.log
#cat $PERFCAKE_HOME/perfcake-read.log

# CR(U)D
# TODO: Coming soon...

# CRU(D)
# TODO: Coming soon...

# Copy the PerfCake results to the jenkins' workspace to be able to archive
export PERFORMANCE_RESULTS=$WORKSPACE/devtools-performance-results
mkdir -p $PERFORMANCE_RESULTS
cp -rvf $PERFCAKE_HOME/perfcake-chart $PERFORMANCE_RESULTS

# Query for the workitems
curl -X GET --header 'Accept: application/json' 'http://api-perf.dev.rdu2c.fabric8.io/api/workitems'

# Cleanup any left over docker containers
docker stop core; 
docker rm core
docker stop db; 
docker rm db

export docker_containers="almighty-core-local-build silly_leakey boring_panini jolly_rosalind amazing_mccarthy evil_shirley pedantic_dubinsky pedantic_engelbart backstabbing_meninsky reverent_wescoff gigantic_kilby grave_feynman silly_brattain mad_mccarthy mad_bardeen goofy_williams"

for c in $docker_containers; do docker stop $c; done
for c in $docker_containers; do docker rm $c; done

# Query for the workitems
curl -X GET --header 'Accept: application/json' 'http://api-perf.dev.rdu2c.fabric8.io/api/workitems' |  sed s/.*totalCount/\\n\\n\\n"totalCount of workitems in DB"/g | sed s/\"//g | sed s/}//g

curl -silent -X GET --header 'Accept: application/json' 'http://api-perf.dev.rdu2c.fabric8.io/api/workitems' |  sed s/.*totalCount/\\n\\n\\n"totalCount of workitems in DB"/g | sed s/\"//g | sed s/}//g | grep totalCount >/tmp/after

cat /tmp/before /tmp/after




