#!/bin/bash
IP=$1
HPO_CONFIG=$2
SEARCHSPACE_JSON=$3
TRIAL=$4
ITERATIONS=$5
KAFKA_CONFIG=$6
PY_CMD="python3"
LOGFILE="${PWD}/hpo.log"
BENCHMARK_NAME="techempower"
BENCHMARK_LOGFILE="${PWD}/benchmark.log"
[ -z ${7:-} ] && OBJFUNC_VARIABLES='aggregatedEndToEndLatency99pct'
OBJFUNC_VARIABLES=${OBJFUNC_VARIABLES:=$7}

./benchmarks/kafka/scripts/perf/kafka-run.sh ${IP} ${ITERATIONS} $(realpath $KAFKA_CONFIG) $(realpath $HPO_CONFIG) 

RES_DIR=`ls -td -- ./benchmarks/kafka/result/*/ | head -n1 `
echo $RES_DIR
if [[ -f "${RES_DIR}/output.csv" ]]; then
  ## Copy the output.csv into current directory
  for i in ${RES_DIR}/*workload-Kafka.json;do
    j=`basename $i`
    cp ${RES_DIR}/$j ./benchmarks/kafka/result/${TRIAL}'-'${j}
  done
  cp -r ${RES_DIR}/output.csv .
  sed -i 's/[[:blank:]]//g' output.csv
  objfunc_result=`${PY_CMD} -c "import hpo_helpers.getobjfuncresult; hpo_helpers.getobjfuncresult.calcobj(\"${SEARCHSPACE_JSON}\", \"output.csv\", \"${OBJFUNC_VARIABLES}\")"`
  benchmark_status="success"
  if [[ $ITERATIONS -gt 1 ]]
  then
    i=`awk -v obj_var=$OBJFUNC_VARIABLES 'BEGIN{FS=","} {for (i=NF; i>=1;i--) if ($i == obj_var) {print i}}'  output.csv`
    benchmark_status=`tail -1 output.csv|awk -v var=$(($i+1)) 'BEGIN{FS=","} { if ($var<=100) {print "success"} else {print "failure"}}'`
  fi
  ${PY_CMD} -c "import hpo_helpers.utils; hpo_helpers.utils.hpoconfig2csv(\"hpo_config.json\",\"output.csv\",\"experiment-output.csv\",\"${TRIAL}\")"
  rm -rf output.csv
  if [[ ${benchmark_status} == "failure" ]]
  then
    objfunc_result=0
  fi

fi
echo "Objfunc_result=${objfunc_result}"
echo "Benchmark_status=${benchmark_status}"
