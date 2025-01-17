#!/bin/sh
#################################################################
#
#   BSD LICENSE
# 
#   Copyright(c) 2007-2021 Intel Corporation. All rights reserved.
#   All rights reserved.
# 
#   Redistribution and use in source and binary forms, with or without
#   modification, are permitted provided that the following conditions
#   are met:
# 
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in
#       the documentation and/or other materials provided with the
#       distribution.
#     * Neither the name of Intel Corporation nor the names of its
#       contributors may be used to endorse or promote products derived
#       from this software without specific prior written permission.
# 
#   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
#   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
#   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
#   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
#   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
#   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
#   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# 
#
#################################################################
#
#
# qat_init.sh Setup drivers for Intel QAT.
#

VFIO_DRIVER=${VFIO_DRIVER-vfio-pci}
QAT_USER_GROUP=${QAT_USER_GROUP-qat}

INTEL_VENDORID="0x8086"
DH895_DEVICE_PCI_ID="0x0435"
DH895_DEVICE_PCI_ID_VM="0x0443"
DH895_DEVICE_NAME="dh895xcc"
DH895_DRIVER_NAME="qat_dh895xcc"
C62X_DEVICE_PCI_ID="0x37c8"
C62X_DEVICE_PCI_ID_VM="0x37c9"
C62X_DEVICE_NAME="c6xx"
C62X_DRIVER_NAME="qat_c62x"
C3XX_DEVICE_PCI_ID="0x19e2"
C3XX_DEVICE_PCI_ID_VM="0x19e3"
C3XX_DEVICE_NAME="c3xxx"
C3XX_DRIVER_NAME="qat_c3xxx"
D15XX_DEVICE_PCI_ID="0x6f54"
D15XX_DEVICE_PCI_ID_VM="0x6f55"
D15XX_DEVICE_NAME="d15xx"
D15XX_DRIVER_NAME="qat_d15xx"
QAT_4XXX_DEVICE_PCI_ID="0x4940"
QAT_4XXX_DEVICE_PCI_ID_VM="0x4941"
QAT_4XXX_DEVICE_NAME="4xxx"
QAT_4XXX_DRIVER_NAME="qat_4xxx"
PF_NAMES="$QAT_4XXX_DEVICE_NAME"
VF_DEVICE_IDS="$QAT_4XXX_DEVICE_PCI_ID_VM"

unbind() {
    BSF=$1
    OLD_DRIVER=$2

    LOOP=0
    while [ $LOOP -lt  5 ]
    do
        echo -n 2> /dev/null $BSF > /sys/bus/pci/drivers/$OLD_DRIVER/unbind
        if [ $? -eq 0 ]; then
            break
        else
           LOOP=`expr $LOOP + 1`
            sleep 1
        fi
    done
}

override() {
    BSF=$1
    NEW_DRIVER=$2

    LOOP=0
    while [ $LOOP -lt  5 ]
    do
        echo -n 2> /dev/null  $NEW_DRIVER > /sys/bus/pci/devices/$BSF/driver_override
        if [ $? -eq 0 ]; then
                break
        else
           LOOP=`expr $LOOP + 1`
            sleep 1
        fi
    done
}

bind() {
    BSF=$1
    DRIVER=$2

    LOOP=0
    while [ $LOOP -lt  5 ]
    do
        echo -n 2> /dev/null $BSF > /sys/bus/pci/drivers/$DRIVER/bind
        if [ $? -eq 0 ]; then
            break
        else
           LOOP=`expr $LOOP + 1`
           echo -n 2> /dev/null $BSF > /sys/bus/pci/devices/$BSF/driver/unbind
            sleep 1
        fi
    done
}

bind_driver() {
    BSF=$1
    DEVICE=$2
    NEW_DRIVER=$VFIO_DRIVER
    MODULE=$VFIO_DRIVER

    # Check if this device should be bound to qat VF driver
    LKCF_DEV=
    for DEV in $LKCF_LIST
    do
        if echo $BSF | grep -q -E $DEV; then
            LKCF_DEV=$DEV
            break
        fi
    done
    if [ $LKCF_DEV ]; then
        # Find the qat vf driver
        case "$DEVICE" in
        $DH895_DEVICE_PCI_ID_VM )
            NEW_DRIVER=${DH895_DEVICE_NAME}vf
            MODULE=${DH895_DRIVER_NAME}vf
            ;;
        $C62X_DEVICE_PCI_ID_VM )
            NEW_DRIVER=${C62X_DEVICE_NAME}vf
            MODULE=${C62X_DRIVER_NAME}vf
            ;;
        $C3XX_DEVICE_PCI_ID_VM )
            NEW_DRIVER=${C3XX_DEVICE_NAME}vf
            MODULE=${C3XX_DRIVER_NAME}vf
            ;;
        $D15XX_DEVICE_PCI_ID_VM )
            NEW_DRIVER=${D15XX_DEVICE_NAME}vf
            MODULE=${D15XX_DRIVER_NAME}vf
             ;;
        $QAT_4XXX_DEVICE_PCI_ID_VM )
            NEW_DRIVER=${QAT_4XXX_DEVICE_NAME}vf
            MODULE=${QAT_4XXX_DRIVER_NAME}vf
             ;;
        * )
             echo Unsupported PCI device $DEVICE
             ;;
        esac
    fi

    VF_DEV=/sys/bus/pci/devices/$BSF

    if [ ! -d /sys/bus/pci/drivers/$NEW_DRIVER ]; then
        modprobe $MODULE
    fi

    # What driver is currently bound to the device?
    if [ -e $VF_DEV/driver ]; then
         VF_DRIVER=`readlink $VF_DEV/driver | awk 'BEGIN {FS="/"} {print $NF}'`
    else
         VF_DRIVER=
    fi
    if [ x$VF_DRIVER != x$NEW_DRIVER ]; then
        if [ $VF_DRIVER ]; then
            # Unbind from existing driver
            unbind $BSF $VF_DRIVER
        fi

        # Bind to $NEW_DRIVER
        override $BSF $NEW_DRIVER
        bind $BSF $NEW_DRIVER

        # Change permissions on the device,
        # a delay is needed to allow the init caused
        # by the bind to complete before the permissions
        # can be changed
        GROUP=`readlink $VF_DEV/iommu_group | awk 'BEGIN {FS="/"} {print $NF}'`
        if [ -e /dev/vfio/$GROUP ]; then
            sleep 0.1
            chown :$QAT_USER_GROUP /dev/vfio/$GROUP
            chmod +060 /dev/vfio/$GROUP
        fi
    fi
}

enable_sriov() {
    PF_LIST=
    for NAME in $PF_NAMES
    do
        for PF in `ls -d /sys/bus/pci/drivers/$NAME/????:??:??.? 2> /dev/null`
        do
            PF_LIST="$PF_LIST $PF"
        done
    done

    if [ "$PF_LIST" ]; then
        for PF_DEV in $PF_LIST
        do
            # Enable sriov on the PF_DEV
            if [ -r $PF_DEV/sriov_totalvfs -a -w $PF_DEV/sriov_numvfs ]; then
                TOTALVFS=`cat $PF_DEV/sriov_totalvfs`
                NUMVFS=`cat $PF_DEV/sriov_numvfs`
                if [ $TOTALVFS -ne $NUMVFS ]; then
                    echo $TOTALVFS > $PF_DEV/sriov_numvfs
                fi
            fi

            for VF_LINK in `ls -d $PF_DEV/virtfn* 2> /dev/null`
            do
               BSF=`readlink $VF_LINK | awk 'BEGIN {FS="/"} {print $NF}'`
               DEVICE=`cat /sys/bus/pci/devices/$BSF/device`
               bind_driver $BSF $DEVICE &
            done
        done
    else
        # No PFs.  Find by pci device id.
        PCI_DEVICES=`ls -d /sys/bus/pci/devices/* | awk 'BEGIN{FS="/"} {print $NF}'`
        for BSF in $PCI_DEVICES
        do
          DEVICE=`cat /sys/bus/pci/devices/$BSF/device`
          if echo $VF_DEVICE_IDS | grep -q $DEVICE; then
              VENDOR=`cat /sys/bus/pci/devices/$BSF/vendor`
              if [ $VENDOR = $INTEL_VENDORID ]; then
                  bind_driver $BSF $DEVICE &
              fi
          fi
        done
    fi
}

enable_sriov
wait

exit 0
