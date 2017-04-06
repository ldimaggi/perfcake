#set -x

## Needed ENV Variables
#export WORKSPACE=$PWD
#export ITERATIONS=100000
#export THREADS=30
#export USERS=300
#export SERVER_HOST=core-api-route-dsaas-e2e-testing.b6ff.rh-idev.openshiftapps.com
#export SERVER_PORT=80
#export PERFREPO_ENABLED=false
#export ZABBIX_HOST_PREFIX="PerfHost"

## Actuall test

export PERFCAKE_VERSION=8.0-SNAPSHOT
export PERFCAKE_HOME=$WORKSPACE/perfcake-$PERFCAKE_VERSION

if [[ "x$CYCLE" != "x" ]];
then
   export PERFORMANCE_RESULTS=$WORKSPACE/devtools-performance-results/$CYCLE;
else
   export PERFORMANCE_RESULTS=$WORKSPACE/devtools-performance-results;
fi

# Prepare clean environment
rm -rf $PERFORMANCE_RESULTS
mkdir -p $PERFORMANCE_RESULTS

export TOKEN_LIST=$PERFORMANCE_RESULTS/token.keys
export WORK_ITEM_IDS=$PERFORMANCE_RESULTS/workitem-id.list
export SOAK_SUMMARY=$PERFORMANCE_RESULTS/soak-summary.log
export ZABBIX_REPORT=$PERFORMANCE_RESULTS/zabbix-report.txt

# Get Perfcake, and our preconfigured Perfcake test config file
if [[ "x$CYCLE" < "x1" ]];
#if false;
then
   rm -rf PerfCake.git
   git clone -b devel  https://github.com/PerfCake/PerfCake PerfCake.git;
   cd PerfCake.git;
   git checkout f33795c8a3e2a4285e5b4a22cf4affcbb7785469;
   cd ..;
   echo "Building PerfCake..."
   mvn -f PerfCake.git/pom.xml clean install assembly:single -DskipTests 2>&1 > $PERFORMANCE_RESULTS/perfcake-build-maven.log

   rm -rf Plugins.git
   git clone https://github.com/PerfCake/Plugins Plugins.git;
   echo "Building PerfRepo Destination plugin..."
   mvn -f Plugins.git/perfrepo-destination/pom.xml clean install -DskipTests 2>&1 > $PERFORMANCE_RESULTS/perfrepo-destination-build-maven.log
   echo "Building HttpClientSender plugin..."
   mvn -f Plugins.git/httpclient-sender/pom.xml clean install -DskipTests 2>&1 > $PERFORMANCE_RESULTS/httpclient-sender-build-maven.log
fi

rm -rf $PERFCAKE_HOME;
unzip -q PerfCake.git/perfcake/target/perfcake-$PERFCAKE_VERSION-bin.zip;
cp -rf Plugins.git/perfrepo-destination/target/perfrepo-*.jar $PERFCAKE_HOME/lib/plugins/;
cp -rf Plugins.git/perfrepo-destination/target/lib/*.jar $PERFCAKE_HOME/lib/plugins/;
cp -rf Plugins.git/httpclient-sender/target/httpclient-*.jar $PERFCAKE_HOME/lib/plugins/;
cp -rf Plugins.git/httpclient-sender/target/lib/*.jar $PERFCAKE_HOME/lib/plugins/;
cp devtools-core-crud-create.xml $PERFCAKE_HOME/resources/scenarios/;
cp devtools-core-crud-read.xml $PERFCAKE_HOME/resources/scenarios/;
cp devtools-core-crud-update.xml $PERFCAKE_HOME/resources/scenarios/;
cp devtools-core-crud-delete.xml $PERFCAKE_HOME/resources/scenarios/;

# Get the work items space ID
spaces_resp=`curl -silent -X GET --header 'Accept: application/json' 'http://'$SERVER_HOST':'$SERVER_PORT'/api/spaces'`
export WORK_ITEMS_SPACE=`echo $spaces_resp | grep self | sed -e 's,.*"self":"[^"]*/api/spaces/\([^"]*\)".*,\1,g'`

export WORK_ITEMS_BASE_URI="api/spaces/$WORK_ITEMS_SPACE/workitems"
export WORK_ITEMS_URI="http://$SERVER_HOST:$SERVER_PORT/$WORK_ITEMS_BASE_URI"

if [[ "x$CYCLE" != "x" ]];
then
   echo "==========================================" >> $SOAK_SUMMARY;
   echo "Cycle # $CYCLE:" >> $SOAK_SUMMARY;
fi
echo "Running $ITERATIONS iterations with $THREADS threads" >> $SOAK_SUMMARY

chmod +x ./_generate-auth-tokens.sh
chmod +x ./_get-workitem-count.sh

echo "$ZABBIX_HOST_PREFIX devtools.perf.core.commit $SOAK_TIMESTAMP $CORE_SERVER_COMMIT" >> $ZABBIX_REPORT

# Get a baseline of workitems in DB
echo "BEFORE:" >> $SOAK_SUMMARY
./_get-workitem-count.sh 2>>$SOAK_SUMMARY >> $SOAK_SUMMARY

export PERFREPO_TAGS="threads=$THREADS;iterations=$ITERATIONS;users=$USERS;jenkins=$BUILD_TAG"
if [[ "x$ADDITIONAL_PERFREPO_TAGS" != "x" ]];
then
   export PERFREPO_TAGS="$PERFREPO_TAGS;$ADDITIONAL_PERFREPO_TAGS";
fi
export PERFCAKE_PROPS="-Dthread.count=$THREADS -Diteration.count=$ITERATIONS -Dworkitems.space.id=$WORK_ITEMS_SPACE -Dworkitemid.list=file:$WORK_ITEM_IDS -Dauth.token.list=file:$TOKEN_LIST -Dserver.host=$SERVER_HOST -Dserver.port=$SERVER_PORT -Dperfrepo.tags=$PERFREPO_TAGS -Dperfrepo.enabled=$PERFREPO_ENABLED"

# (C)RUD
# Parse/extract the token for the test
bash -c ./_generate-auth-tokens.sh
# Execute PerfCake
$PERFCAKE_HOME/bin/perfcake.sh -s devtools-core-crud-create $PERFCAKE_PROPS
echo "PerfCake Exited with code $?"
cat $PERFCAKE_HOME/perfcake-validation.log | grep Response | sed -e 's,.*/'$WORK_ITEMS_BASE_URI'/\([^"/]*\)/.*".*,\1,g' > $WORK_ITEM_IDS
#cat $PERFCAKE_HOME/devtools-core-crud-create-average-throughput.csv
mv -vf $PERFCAKE_HOME/devtools-core-crud-create-*.csv $PERFORMANCE_RESULTS
./_zabbix-process-results.sh create >> $ZABBIX_REPORT
#mv $PERFCAKE_HOME/perfcake-validation.log $PERFORMANCE_RESULTS/perfcake-validation-create.log
rm -vf $PERFCAKE_HOME/perfcake-validation.log
mv $PERFCAKE_HOME/perfcake.log $PERFORMANCE_RESULTS/perfcake-create.log

echo "After CREATE:" >> $SOAK_SUMMARY
./_get-workitem-count.sh 2>>$SOAK_SUMMARY >> $SOAK_SUMMARY

# C(R)UD
# Parse/extract the token for the test
bash -c ./_generate-auth-tokens.sh
# Execute PerfCake
$PERFCAKE_HOME/bin/perfcake.sh -s devtools-core-crud-read $PERFCAKE_PROPS
echo "PerfCake Exited with code $?"
#cat $PERFCAKE_HOME/devtools-core-crud-read-average-throughput.csv
mv -vf $PERFCAKE_HOME/devtools-core-crud-read-*.csv $PERFORMANCE_RESULTS
./_zabbix-process-results.sh read >> $ZABBIX_REPORT
#mv $PERFCAKE_HOME/perfcake-validation.log $PERFORMANCE_RESULTS/perfcake-validation-read.log
rm -vf $PERFCAKE_HOME/perfcake-validation.log
mv $PERFCAKE_HOME/perfcake.log $PERFORMANCE_RESULTS/perfcake-read.log

echo "After READ:" >> $SOAK_SUMMARY
./_get-workitem-count.sh 2>>$SOAK_SUMMARY >> $SOAK_SUMMARY

# CR(U)D
#TODO: Coming soon...
# Parse/extract the token for the test
bash -c ./_generate-auth-tokens.sh
## Execute PerfCake
$PERFCAKE_HOME/bin/perfcake.sh -s devtools-core-crud-update $PERFCAKE_PROPS
echo "PerfCake Exited with code $?"
#cat $PERFCAKE_HOME/devtools-core-crud-update-average-throughput.csv
mv -vf $PERFCAKE_HOME/devtools-core-crud-update-*.csv $PERFORMANCE_RESULTS
./_zabbix-process-results.sh update >> $ZABBIX_REPORT
#mv $PERFCAKE_HOME/perfcake-validation.log $PERFORMANCE_RESULTS/perfcake-validation-update.log
rm -vf $PERFCAKE_HOME/perfcake-validation.log
mv $PERFCAKE_HOME/perfcake.log $PERFORMANCE_RESULTS/perfcake-update.log

echo "After UPDATE:" >> $SOAK_SUMMARY
./_get-workitem-count.sh 2>>$SOAK_SUMMARY >> $SOAK_SUMMARY

# CRU(D)
# Parse/extract the token for the test
bash -c ./_generate-auth-tokens.sh
# Execute PerfCake
$PERFCAKE_HOME/bin/perfcake.sh -s devtools-core-crud-delete $PERFCAKE_PROPS
echo "PerfCake Exited with code $?"
#cat $PERFCAKE_HOME/devtools-core-crud-delete-average-throughput.csv
mv -vf $PERFCAKE_HOME/devtools-core-crud-delete*.csv $PERFORMANCE_RESULTS
./_zabbix-process-results.sh delete >> $ZABBIX_REPORT
#mv $PERFCAKE_HOME/perfcake-validation.log $PERFORMANCE_RESULTS/perfcake-validation-delete.log
rm -vf $PERFCAKE_HOME/perfcake-validation.log
mv $PERFCAKE_HOME/perfcake.log $PERFORMANCE_RESULTS/perfcake-delete.log

echo "After DELETE (disabled):" >> $SOAK_SUMMARY
./_get-workitem-count.sh 2>>$SOAK_SUMMARY >> $SOAK_SUMMARY

echo "Soak test summary:"
cat $SOAK_SUMMARY
echo "Zabbix report"
cat $ZABBIX_REPORT

# Copy the PerfCake results to the jenkins' workspace to be able to archive
cp -rvf $PERFCAKE_HOME/perfcake-chart $PERFORMANCE_RESULTS
