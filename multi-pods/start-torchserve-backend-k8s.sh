#!/bin/bash
set -x
port=9000
#SGX_ENABLED=$SGX_ENABLED
SGX_ENABLED="false"
ATTESTATION=$ATTESTATION
while getopts ":p:c:b:XA" opt
do
    case $opt in
        p)
            port=$OPTARG
            ;;
        c)
            core=$OPTARG
            ;;
        b)
            backends_IP=$OPTARG
            ;;
        X)
            SGX_ENABLED="true"
            ;;
        A)
            ATTESTATION="true"
            ;;
        *)
            echo "Unknown argument passed in: $opt"
            exit 1
            ;;
    esac
done

cd /ppml || exit

if [[ $SGX_ENABLED == "false" ]]; then
    if [ "$ATTESTATION" = "true" ]; then
        rm /ppml/temp_command_file || true
        bash attestation.sh
        bash temp_command_file
    fi
    if [[ `hostname` =~ tdx  ]]; then
	    numa_node=0
#	    taskset -c "$core" /usr/bin/python3 /usr/local/lib/python3.9/dist-packages/ts/model_service_worker.py --sock-type tcp --port $port --host $backends_IP --metrics-config /ppml/metrics.yaml
    else
	    core_start=`echo $core | cut -f 1 -d "-"`
	    cores_per_socket=`lscpu | grep "Core(s) per socket" | awk '{print $NF}'`
	    if [[ $core_start -lt $cores_per_socket ]]; then
		    numa_node=0
	    else
		    numa_node=1
	    fi
#	    numactl -C "$core" -m $numa_node /usr/bin/python3 /usr/local/lib/python3.9/dist-packages/ts/model_service_worker.py --sock-type tcp --port $port --host $backends_IP --metrics-config /ppml/metrics.yaml
    fi
    numactl -C "$core" -m $numa_node /usr/bin/python3 /usr/local/lib/python3.9/dist-packages/ts/model_service_worker.py --sock-type tcp --port $port --host $backends_IP --metrics-config /ppml/metrics.yaml

else
    export sgx_command="/usr/bin/python3 /usr/local/lib/python3.9/dist-packages/ts/model_service_worker.py --sock-type tcp --port $port --host $backends_IP --metrics-config /ppml/metrics.yaml"
    if [ "$ATTESTATION" = "true" ]; then
          # Also consider ENCRYPTEDFSD condition
          rm /ppml/temp_command_file || true
          bash attestation.sh
          if [ "$ENCRYPTED_FSD" == "true" ]; then
            echo "[INFO] Distributed encrypted file system is enabled"
            bash encrypted-fsd.sh
          fi
          echo $sgx_command >>temp_command_file
          export sgx_command="bash temp_command_file"
    else
          # ATTESTATION is false
          if [ "$ENCRYPTED_FSD" == "true" ]; then
            # ATTESTATION false, encrypted-fsd true
            rm /ppml/temp_command_file || true
            echo "[INFO] Distributed encrypted file system is enabled"
            bash encrypted-fsd.sh
            echo $sgx_command >>temp_command_file
            export sgx_command="bash temp_command_file"
          fi
    fi
    gramine-sgx bash 2>&1 | tee backend-sgx.log
    rm /ppml/temp_command_file || true
fi

