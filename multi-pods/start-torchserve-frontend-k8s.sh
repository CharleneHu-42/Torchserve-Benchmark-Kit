#!/bin/bash
configFile=""
backends_IP=""
#SGX_ENABLED=$SGX_ENABLED
SGX_ENABLED="false"
ATTESTATION=$ATTESTATION
while getopts ":c:i:f:XA" opt
do
    case $opt in
        c)
            configFile=$OPTARG
            ;;
        i)
            backends_IP=$OPTARG
            ;;
        f)
            core=$OPTARG
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
    taskset -c "$core" /opt/jdk11/bin/java \
            -DBackends_IP=$backends_IP \
            -Dmodel_server_home=/usr/local/lib/python3.9/dist-packages \
            -cp .:/ppml/torchserve/* \
            -Xmx1g \
            -Xms1g \
            -Xss1024K \
            -XX:MetaspaceSize=64m \
            -XX:MaxMetaspaceSize=128m \
            -XX:MaxDirectMemorySize=128m \
            org.pytorch.serve.ModelServer \
            --python /usr/bin/python3 \
            -f "$configFile" \
            -ncs
else
    export sgx_command="/opt/jdk11/bin/java \
            -DBackends_IP=$backends_IP \
            -Dmodel_server_home=/usr/local/lib/python3.9/dist-packages \
            -cp .:/ppml/torchserve/* \
            -Xmx1g \
            -Xms1g \
            -Xss1024K \
            -XX:MetaspaceSize=64m \
            -XX:MaxMetaspaceSize=128m \
            -XX:MaxDirectMemorySize=128m \
            org.pytorch.serve.ModelServer \
            --python /usr/bin/python3 \
            -f $configFile \
            -ncs"
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
    gramine-sgx bash 2>&1 | tee frontend-sgx.log
    rm /ppml/temp_command_file || true
fi

