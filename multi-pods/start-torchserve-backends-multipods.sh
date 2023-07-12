#!/bin/bash
configFile=""
backend_core_list=""
SGX_ENABLED="false"

usage() {
    echo "Usage: $0 [-c <configfile>] [-b <core# for each backend worker>] [-f <core# for frontend worker>] [-x]"

    echo "The following example command will launch 2 backend workers (as specified in /ppml/serve-benchmark_config)."
    echo "The first backend worker will be pinned to core 0 while the second backend worker will be pinned to core 1."
    echo "The frontend worker will be pinned to core 5"
    echo "Example: $0 -c /ppml/serve-benchmark_config -t '0,1' -f 5"
    echo "To launch within SGX environment using gramine"
    echo "Example: $0 -c /ppml/serve-benchmark_config -t '0,1' -f 5 -x"
    exit 0
}

while getopts ":b:c:i:x" opt
do
    case $opt in
        b)
            backend_core_list=$OPTARG
            ;;
        c)
            configFile=$OPTARG
            ;;
        i)
            backends_IP=$OPTARG
            ;;
        x)
            SGX_ENABLED="true"
            ;;
        *)
            echo "Error: unknown positional arguments"
            usage
            ;;
    esac
done

# Check backend_core_list has values
if [ -z "${backend_core_list}" ]; then
    echo "Error: please specify backend core lists"
    usage
fi

# Check config file exists
if [ ! -f "${configFile}" ]; then
    echo "Error: cannot find config file"
    usage
fi

## Only applicable for continous core list currently
if [[ $backend_core_list =~ "-" ]]; then
	start=`echo $backend_core_list | cut -d '-' -f 1`
	end=`echo $backend_core_list | cut -d '-' -f 2`
	total_cores=$[end-start+1]
else
	declare -a cores=($(echo "$backend_core_list" | tr "," " "))
	start=0
	total_cores=${#cores[@]}
fi

# In case we change the path name in future
cd /ppml || exit

port=9000
sgx_flag=""

if [[ $SGX_ENABLED == "true" ]]; then
    ./init.sh
    sgx_flag=" -x "
fi


# Consider the situation where we have multiple models, and each load serveral workers.
while read -r line
do
    if [[ $line =~ "minWorkers" ]]; then
        line=${line#*\"minWorkers\": }
        num=${line%%,*}
        line=${line#*,}

        if [ $[total_cores%num] != "0" ]; then
            echo "Error: worker number cannot be divided by the length of core list"
            exit 1
        fi

        cores_per_worker=$[total_cores/num]

        for ((i=0;i<num;i++,port++))
        do
                left=$[start+cores_per_worker*i]
#		echo $i
#		echo $left
                coreset=$left-$[left+cores_per_worker-1]
                echo $coreset
        (
        	bash /ppml/benchmark-kit/multi-pods/start-torchserve-backend-k8s.sh -p $port -c "$coreset" -b $backends_IP $sgx_flag

        )&
        done
    fi
done < "$configFile"

