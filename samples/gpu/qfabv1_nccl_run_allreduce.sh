#!/bin/bash
set -e

# number of times to run the nccl test to stress the GPUs and RDMA network. This is different from -n iterations parameter of nccl allreduce which is set below using $iter
max=$1

# This assume, the hostfile  passed is already ordered based on their rackId
if [ -n "$2" ]; then
  hostfile=$2
else
  #hostfile="/home/opc/hostfile.tcp"
  #hostfile="/etc/opt/oci-hpc/hostfile.tcp"
  hostfile="/tmp/ordered_hostfile_system_name"
fi

ORDEREDMACHINEFILE="ordered_hostfile_system_name"
echo INPUTFILE
cat $hostfile

# will generate rack-aware ordered host file
python3 /home/opc/node_ordering_by_rack.py --input_file $hostfile > /dev/null
hostfile=$ORDEREDMACHINEFILE

echo ORDEREDMACHINEFILE
cat $ORDEREDMACHINEFILE


# The number of GPUs to use for the test.  Has to be multiplier of 8.  If not passed, all GPUs will be used. 
if [ -n "$3" ]; then
  np=$3
else
  np=$((`less $hostfile | wc -l` * 8 ))
fi

logfile="nccl_run_allreduce.sh.log"

for x in $(seq 1 1 $max)
do

  echo $x
  echo $x >> $logfile
  date >> $logfile

  hostfile=$hostfile; np=$np ; iter=20;

  if [ -f /usr/mpi/gcc/openmpi-4.1.0rc5/bin/mpivars.sh ]; then
    source /usr/mpi/gcc/openmpi-4.1.0rc5/bin/mpivars.sh
  else
    source /usr/mpi/gcc/openmpi-4.0.3rc4/bin/mpivars.sh
  fi

first_node=`head $hostfile -n 1`
shape=`ssh $first_node 'curl -sH "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/' | jq .shape`

if [ $shape == \"BM.GPU.B4.8\" ] || [ $shape == \"BM.GPU.A100-v2.8\" ]
then
  var_UCX_NET_DEVICES=mlx5_0:1
  var_NCCL_IB_HCA="=mlx5_5,mlx5_6,mlx5_7,mlx5_8,mlx5_1,mlx5_2,mlx5_3,mlx5_4,mlx5_14,mlx5_15,mlx5_16,mlx5_17,mlx5_9,mlx5_10,mlx5_11,mlx5_12"
elif [ $shape == \"BM.GPU4.8\" ]
then
  var_UCX_NET_DEVICES=mlx5_4:1
  var_NCCL_IB_HCA="=mlx5_0,mlx5_2,mlx5_6,mlx5_8,mlx5_10,mlx5_12,mlx5_14,mlx5_16"
fi

  # final version
  mpirun --mca pml ucx \
  --bind-to numa \
  -x NCCL_DEBUG=WARN \
  -x NCCL_IB_SL=0 \
  -x NCCL_IB_TC=41 \
  -x NCCL_IB_QPS_PER_CONNECTION=16 \
  -x UCX_TLS=ud,self,sm \
  -x UCX_NET_DEVICES=${var_UCX_NET_DEVICES} \
  -x HCOLL_ENABLE_MCAST_ALL=0 \
  -x coll_hcoll_enable=0 \
  -x NCCL_IB_GID_INDEX=3 \
  -x NCCL_ALGO=Ring \
  -x NCCL_IB_HCA="${var_NCCL_IB_HCA}" \
  --np $np --hostfile $hostfile  -N 8 /home/opc/nccl-tests/build/all_reduce_perf -b8  -e 4G -f 2 -n $iter >>  $logfile

  tail -n 32 $logfile


done


