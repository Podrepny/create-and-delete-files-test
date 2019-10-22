#!/bin/bash
# Plenty file deletion performance test
# Some test can show - No such file or directory - it's ok
# set -x

VARSBEFORE=`compgen -v`

DISK_PATH="/dev/sdb1"
MOUNT_PATH="/test"
DISK_SIZE=$(fdisk -l ${DISK_PATH} | head -n 1 | tr -s ' ' | cut -d ' ' -f 5)
INODES_NUM=10000000
NUM_FILES=100
EXITCODE=0
VERBOSE=true
TEMPDIR=/tmp/empty
# DISCRETENESS=1000
declare -a ARRAYOFTEST
# ARRAYOFTEST=( test_rm1 test_rm2 test_find1 test_find2 test_rsync test_ls1 test_ls2 )
ARRAYOFTEST=( test_ls2 )
VARSIGNORED="VARSIGNORED\|PIPESTATUS\|VARSBEFORE\|VARSAFTER\|ARRAYOFTEST"

VARSAFTER=`compgen -v`

# Compose list variable for check. Exclude environment vars and array
VARSUSED=`comm -13 <(echo $VARSBEFORE | tr ' ' '\n' | grep -v "${VARSIGNORED}" | sort) <(echo $VARSAFTER | tr ' ' '\n' | grep -v "${VARSIGNORED}" | sort)`

function FN_VARS_CHECK() {
    # Check list of variables for empty values
    # EXITCODE=1 if at least one of variable is empty in the check list 
    # Print list of checked variables
    for i in $VARSUSED; do
        if [ -z `eval echo "\\${$i}"` ]; then
            echo -e "\e[31m\tERROR Parameter\e[33m ${i} \e[31mnot_defined = `eval echo "\\${$i}"`\e[0m" | cut -c 1-80
            EXITCODE=1
        else
            echo -e "\e[32m\tOK Parameter\e[36m ${i} \e[32mdefined = `eval echo "\\${$i}"`\e[0m" | cut -c 1-80
        fi
    done
}

function FN_ARRAY_CHECK() {
    # Check array for empty values
    # EXITCODE=1 if at least one of variable is empty in the check list 
    if [ ${#ARRAYOFTEST[*]} = 0 ]; then
        echo -e "\e[31m\n\tArray of test is empty\e[0m\n"
        EXITCODE=1
    else
        echo -e "\e[32m\n\tArray of test contains items\e[36m ${#ARRAYOFTEST[*]} \e[0m\n"
    fi
}

function FN_DECORATE {
    # Print "-" character 40 times
    # echo -e "\n"
    for i in {1..40}; do
        echo -n "-"
    done
    echo -e "\n"
}

function FN_CREATE_FILES {
    if [ ${VERBOSE} = true ]; then
        echo -e "\e[32m\tCreating\e[36m ${NUM_FILES} \e[32mfiles in\e[36m ${MOUNT_PATH}\e[0m"
        for (( i=1; i <= ${NUM_FILES}; i++ )); do
            touch ${MOUNT_PATH}/$i.file
            if [[ $((i % 1000)) = 0 ]]; then
                progress=$(echo "scale=3; ${i}/${NUM_FILES}*100" | bc)
                echo -ne "\e[?25l\r${progress}% complete (files $i of ${NUM_FILES})"
                # echo -ne "\e[?25l\e[s\e[2K${progress}% complete (files $i of ${NUM_FILES})\e[u"
                # echo -ne "\e[?25l\e[s\e[2K$i of ${NUM_FILES}\e[u"
            fi
        done
        echo -e "\n\e[36m\t${NUM_FILES} \e[32mfiles have been created\e[0m"
        df -i ${MOUNT_PATH}
    else
        for (( i=1; i <= ${NUM_FILES}; i++ )); do
            touch ${MOUNT_PATH}/$i.file
        done
    fi
    echo -e "\e[?25h"
    sh -c 'sync && echo 2 > /proc/sys/vm/drop_caches'
}

function FN_MOUNT_DISK {
    if $(mountpoint -q ${MOUNT_PATH}); then
        echo -e "\e[31m\tDevice\e[36m ${DISK_PATH} \e[31malready mounted\e[0m"
        echo -e "\e[32m\tUn mount a\e[36m ${DISK_PATH} \e[0m"
        umount ${MOUNT_PATH}
    fi
    FN_MKDIR
    FN_WIPE_DISK
    FN_CREATE_FS_EXT4
    echo -e "\e[32m\tMount disk\e[36m ${DISK_PATH} \e[32mto\e[36m ${MOUNT_PATH}\e[0m"
    mount ${DISK_PATH} ${MOUNT_PATH}
}

function FN_CREATE_FS_EXT4 {
    if [ ${VERBOSE} = true ]; then
        echo -e "\e[32m\tCreating filesystem\e[36m ext4 \e[32mwith\e[36m ${INODES_NUM} \e[32minodes\e[0m"
        mkfs -q -t ext4 -N ${INODES_NUM} ${DISK_PATH}
    else
        mkfs -q -t ext4 -N ${INODES_NUM} ${DISK_PATH}
    fi
}

function FN_WIPE_DISK {
    if [ ${VERBOSE} = true ]; then
        echo -e "\e[31m\tWipe\e[36m ${DISK_PATH} \e[32mwith zeros... \e[0m"
        dd if=/dev/zero of=${DISK_PATH} bs=$((1024*1024)) count=$((${DISK_SIZE}/$((1024*1024)))) status=progress
        echo -e "\e[32m\tWipe completed\e[0m"
    else
        dd if=/dev/zero of=${DISK_PATH} bs=$((1024*1024)) count=$((${DISK_SIZE}/$((1024*1024)))) &>/dev/null
    fi
}

function FN_MKDIR {
    if [ -d ${MOUNT_PATH}/ ]; then
        if [ ${VERBOSE} = true ]; then
            echo -e "\e[32m\tDelete directory\e[36m $MOUNT_PATH \e[0m"
        fi
        rm -rf $MOUNT_PATH/
    fi
    if [ ${VERBOSE} = true ]; then
        echo -e "\e[32m\tCreate directory\e[36m ${MOUNT_PATH}\e[0m"
    fi
    mkdir -p ${MOUNT_PATH}
}

# Function for tests
function test_rm1 {
    rm -rf ${MOUNT_PATH}/
}

function test_rm2 {
    rm -rf ${MOUNT_PATH}/*
}

function test_find1 {
    find ${MOUNT_PATH}/ -type f -exec rm -v {} \;
}

function test_find2 {
    find ${MOUNT_PATH}/ -type f -delete
}

function test_xarg {
    cd ${MOUNT_PATH}/
    ls -f . | xargs -n 100 rm
}

function test_rsync {
    mkdir -p ${TEMPDIR}/
    rsync -a --delete ${TEMPDIR}/ ${MOUNT_PATH}/
    rm -rf ${TEMPDIR}
}

function test_ls1 {
    ls ${MOUNT_PATH} | wc -l
}

function test_ls2 {
    ls -f ${MOUNT_PATH} | wc -l
}


echo -e "\n\n\n\tVariable check:"
FN_DECORATE
# Only show check results
FN_VARS_CHECK | column -t
# Run and return EXITCODE
FN_VARS_CHECK &>/dev/null
FN_ARRAY_CHECK

# If FN_VARS_CHECK or FN_ARRAY_CHECK generate $EXITCODE = 1, exit 1
if [ $EXITCODE = 1 ]; then
    echo -e "\nError\nVariable is empty\n"
    exit 1
fi

# ----------------------------------------
# Run tests
for array in ${!ARRAYOFTEST[@]}; do
    FN_DECORATE
    echo -e "\e[30;42m\n\t Test $((${array}+1)) of ${#ARRAYOFTEST[*]} - Function: ${ARRAYOFTEST[${array}]} \e[0m\n"
    FN_MOUNT_DISK
    FN_CREATE_FILES
    sh -c 'sync && echo 2 > /proc/sys/vm/drop_caches'
    echo -e "\e[33m\tExecution time for function:\e[36m ${ARRAYOFTEST[${array}]} \e[0m"
    time eval ${ARRAYOFTEST[${array}]} &>/dev/null
    echo -e "\n\e[33m\tAfter execution dir\e[36m ${MOUNT_PATH} \e[33mcontain:\e[0m\n"
    df -i ${MOUNT_PATH}
    echo -e "\n\n"
done
FN_DECORATE
echo -e "\e[32m\n\tAll tests complete\e[0m\n\n"

exit 0
