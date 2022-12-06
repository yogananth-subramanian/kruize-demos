#!/bin/bash
PY_CMD="python3"
LOGFILE="${PWD}/hpo.log"
ITERATIONS=1
SEARCHSPACE_JSON="hpo_helpers/kafka_search_space.json"
KAFKA_CONFIG="hpo_helpers/kafka.json"
URL="http://localhost:8085"
exp_json=$(cat ${SEARCHSPACE_JSON})
ename=$(${PY_CMD} -c "import hpo_helpers.utils; hpo_helpers.utils.getexperimentname(\"${SEARCHSPACE_JSON}\")")
ttrials=$(${PY_CMD} -c "import hpo_helpers.utils; hpo_helpers.utils.gettrials(\"${SEARCHSPACE_JSON}\")")

function check_err() {
        err=$?
        if [ ${err} -ne 0 ]; then
                echo "$*"
                exit 1
        fi
}

curl -LfSs -H 'Content-Type: application/json' ${URL}/experiment_trials -d '{ "operation": "EXP_TRIAL_GENERATE_NEW",  "search_space": '"${exp_json}"'}'
check_err "Error: Creating the new experiment failed. Restart HPO."

function get_date() {
        date "+%Y-%m-%d %H:%M:%S"
}

function time_diff() {
        ssec=`date --utc --date "$1" +%s`
        esec=`date --utc --date "$2" +%s`
        diffsec=$(($esec-$ssec))
        echo $diffsec
}
start_time=$(get_date)
for (( i=0 ; i<${ttrials} ; i++ ))
do
  sleep 10
  HPO_CONFIG=$(curl -LfSs -H 'Accept: application/json' "${URL}"'/experiment_trials?experiment_name='"${ename}"'&trial_number='"${i}")
  check_err "Error: Issue generating the configuration from HPO."
  echo ${HPO_CONFIG}
  echo "${HPO_CONFIG}" > hpo_config.json  
  BENCHMARK_OUTPUT=$(./hpo_helpers/kafkarunbenchmark.sh "hpo_config.json" "${SEARCHSPACE_JSON}" "$i" "${ITERATIONS}" "${KAFKA_CONFIG}")
  echo ${BENCHMARK_OUTPUT}
  obj_result=$(echo ${BENCHMARK_OUTPUT} | cut -d "=" -f2 | cut -d " " -f1)
  trial_state=$(echo ${BENCHMARK_OUTPUT} | cut -d "=" -f3 | cut -d " " -f1)
  echo ${obj_result} 
  echo ${trial_state} 
  echo "#######################################"
  echo "Send the benchmark results for trial ${i}"
  curl  -LfSs -H 'Content-Type: application/json' ${URL}/experiment_trials -d '{"experiment_name" : "'"${ename}"'", "trial_number": '"${i}"', "trial_result": "'"${trial_state}"'", "result_value_type": "double", "result_value": '"${obj_result}"', "operation" : "EXP_TRIAL_RESULT"}'
  check_err "ERROR: Sending the results to HPO failed."
  sleep 5
  if (( i < ${ttrial} - 1 )); then
    echo "#######################################"
    echo
    echo "Generate subsequent trial of ${i}"
    curl  -LfSs -H 'Content-Type: application/json' ${URL}/experiment_trials -d '{"experiment_name" : "'"${ename}"'", "operation" : "EXP_TRIAL_GENERATE_SUBSEQUENT"}'
    check_err "ERROR: Generating the subsequent trial failed."
    echo
  fi
done
end_time=$(get_date)
elapsed_time=$(time_diff "${start_time}" "${end_time}")
echo "Success! HPO demo setup took ${elapsed_time} seconds"
