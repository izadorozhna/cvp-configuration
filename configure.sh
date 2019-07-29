#!/bin/bash
 
variables=(
OS_USERNAME
OS_PASSWORD
OS_TENANT_NAME
OS_AUTH_URL
)

check_variables () {
  for i in $(seq 0 $(( ${#variables[@]} - 1 )) ); do
    if [ -z "${!variables[$i]}" ]; then
      echo "Variable \"${variables[$i]}\" is not defined"
      exit 1
    fi
  done
  ip=$(echo ${OS_AUTH_URL} | sed -e 's/[^/]*\/\/\([^@]*@\)\?\([^:/]*\).*/\2/')
  export no_proxy=$ip
}

rally_configuration () {
  if [ "$PROXY" != "offline" ]; then
     if [ -n "${PROXY}" ]; then
       export http_proxy=$PROXY
       export https_proxy=$PROXY
     fi
     pip install --force-reinstall python-glanceclient==2.11
     apt-get update; apt-get install -y iputils-ping curl wget
     unset http_proxy
     unset https_proxy
  fi

  sub_name=`date "+%H_%M_%S"`

  # remove dashes from rally user passwords to fit into 32 char limit
  sed -i 's/uuid4())/uuid4()).replace("-","")/g' /usr/local/lib/python2.7/dist-packages/rally/plugins/openstack/scenarios/keystone/utils.py
  sed -i 's/uuid4())/uuid4()).replace("-","")/g' /usr/local/lib/python2.7/dist-packages/rally/plugins/openstack/context/keystone/users.py

  rally deployment create --fromenv --name=tempest_$sub_name
  rally deployment config

  # Check whether file exists by path for Rally Performance scenario, or download it
  if [ "$PROXY" != "offline" ]; then
     if [ -n "${PROXY}" ]; then
       export http_proxy=$PROXY
       export https_proxy=$PROXY
     fi
     apt-get update; apt-get install -y iputils-ping curl wget
     wget http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img -O /home/rally/cvp-configuration/cirros-0.4.0-x86_64-disk.img
     unset http_proxy
     unset https_proxy
  fi

  # Get fixed net id and set it in rally_scenarios.json, rally_dry_run_scenarios.json
  shared_count=`neutron net-list -c name -c shared | grep True | grep "fixed-net" | wc -l`
  if [ $shared_count -eq 0 ]; then
    echo "Let's create shared fixed net"
    neutron net-create --shared fixed-net
    FIXED_NET_ID=$(neutron net-list -c id -c name -c shared | grep "fixed-net" | grep True | awk '{print $2}' | tail -n 1)
    neutron subnet-create --name fixed-subnet --gateway 192.168.0.1 --allocation-pool start=192.168.0.2,end=192.168.0.254 --ip-version 4 $FIXED_NET_ID 192.168.0.0/24
  fi
  fixed_count=`neutron net-list | grep "fixed-net" | wc -l`
  if [ $fixed_count -gt 1 ]; then
    echo "TOO MANY NETWORKS WITH fixed-net NAME! This may affect tests. Please review your network list."
  fi
  FIXED_NET=$(neutron net-list --shared True -c name -c router:external | grep False | awk '{print $2}' | tail -n 1)
  FIXED_NET_ID=$(neutron net-show $FIXED_NET -c id | grep id | awk '{print $4}')
  echo "Fixed net is: $FIXED_NET"

  EXT_NET_ID=$(neutron net-list --router:external True | grep ext | awk '{print $2}' | tail -n 1)
  EXT_NET_NAME=$(neutron net-show $EXT_NET_ID -c name | grep name | awk '{print $4}')
  echo "External net ID is: $EXT_NET_ID"
  echo "External net name is: $EXT_NET_NAME"

  current_path=$(pwd)
  sed -i 's/${FIXED_NET_ID}/'$FIXED_NET_ID'/g' $current_path/cvp-configuration/rally/*
  sed -i 's/${EXT_NET_ID}/'$EXT_NET_ID'/g' $current_path/cvp-configuration/rally/*
  sed -i 's/${EXT_NET_NAME}/'$EXT_NET_NAME'/g' $current_path/cvp-configuration/rally/*
}

tempest_configuration () {
  sub_name=`date "+%H_%M_%S"`
  tempest_version='mcp/pike'
  if [ "$PROXY" == "offline" ]; then
    rally verify create-verifier --name tempest_verifier_$sub_name --type tempest --source $TEMPEST_REPO --system-wide --version $tempest_version
    rally verify add-verifier-ext --source /var/lib/heat-tempest-plugin
    rally verify add-verifier-ext --source /var/lib/neutron-lbaas
  else
    if [ -n "${PROXY}" ]; then
      export https_proxy=$PROXY
      export http_proxy=$PROXY
    fi
    apt-get update; apt-get install -y iputils-ping curl wget
    rally verify create-verifier --name tempest_verifier_$sub_name --type tempest --source $TEMPEST_REPO --version $tempest_version
    current_path=$(pwd)
    # Install Heat plugin
    git clone http://gerrit.mcp.mirantis.com/packaging/sources/heat-tempest-plugin -b mcp/pike $current_path/heat-tempest-plugin
    rally verify add-verifier-ext --version mcp/queens --source $current_path/heat-tempest-plugin
    # Install LBaaS plugin
    rally verify add-verifier-ext --version stable/pike --source https://github.com/openstack/neutron-lbaas

    pip install --force-reinstall python-cinderclient==3.2.0

    unset https_proxy
    unset http_proxy
  fi
  # supress tempest.conf display in console
  #rally verify configure-verifier --show
}

quick_configuration () {
current_path=$(pwd)
# Remove this if you use local gerrit cvp-configuration repo
if [ "$PROXY" == "offline" ]; then
  current_path=/var/lib
fi
#image
glance image-list | grep "\btestvm\b" 2>&1 >/dev/null || {
    if [ -n "${PROXY}" ] && [ "$PROXY" != "offline" ]; then
      export http_proxy=$PROXY
      export https_proxy=$PROXY
    fi
    ls $current_path/cvp-configuration/cirros-0.4.0-x86_64-disk.img || wget http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img -O $current_path/cvp-configuration/cirros-0.4.0-x86_64-disk.img
    unset http_proxy
    unset https_proxy
    echo "MD5 should be 443b7623e27ecf03dc9e01ee93f67afe"
    md5sum $current_path/cvp-configuration/cirros-0.4.0-x86_64-disk.img
    glance image-create --name=testvm --visibility=public --container-format=bare --disk-format=qcow2 < $current_path/cvp-configuration/cirros-0.4.0-x86_64-disk.img
}
IMAGE_REF2=$(glance image-list | grep 'testvm' | awk '{print $2}')

#flavor for rally
nova flavor-list | grep m1.tiny 2>&1 >/dev/null || {
    echo "Let's create m1.tiny flavor"
    nova flavor-create --is-public true m1.tiny auto 512 1 1
}
nova flavor-list | grep m1.micro 2>&1 >/dev/null || {
    echo "Let's create m1.micro flavor"
    nova flavor-create --is-public true m1.micro auto 1024 2 1
}
FLAVOR_REF=$(nova flavor-list | grep m1.tiny | awk '{print $2}')
FLAVOR_REF_ALT=$(nova flavor-list | grep m1.micro | awk '{print $2}')

#shared fixed network
shared_count=`neutron net-list -c name -c shared | grep True | grep "fixed-net" | wc -l`
if [ $shared_count -eq 0 ]; then
  echo "Let's create shared fixed net"
  neutron net-create --shared fixed-net
  FIXED_NET_ID=$(neutron net-list -c id -c name -c shared | grep "fixed-net" | grep True | awk '{print $2}' | tail -n 1)
  neutron subnet-create --name fixed-subnet --gateway 192.168.0.1 --allocation-pool start=192.168.0.2,end=192.168.0.254 --ip-version 4 $FIXED_NET_ID 192.168.0.0/24
fi
fixed_count=`neutron net-list | grep "fixed-net" | wc -l`
if [ $fixed_count -gt 1 ]; then
echo "TOO MANY NETWORKS WITH fixed-net NAME! This may affect tests. Please review your network list."
fi
FIXED_NET=$(neutron net-list -c name -c shared | grep "fixed-net" | grep True | awk '{print $2}' | tail -n 1)
FIXED_NET_ID=$(neutron net-show $FIXED_NET -c id | grep id | awk '{print $4}')
echo "Fixed net name is: $FIXED_NET"
echo "Fixed net ID is: $FIXED_NET_ID"
FIXED_SUBNET_ID=$(neutron net-show $FIXED_NET -c subnets | grep subnets | awk '{print $4}')
FIXED_SUBNET_NAME=$(neutron subnet-show -c name $FIXED_SUBNET_ID | grep name | awk '{print $4}')
echo "Fixed subnet is: $FIXED_SUBNET_ID, name: $FIXED_SUBNET_NAME"


#Updating of tempest_full.conf file is skipped/deprecated
sed -i 's/${IMAGE_REF2}/'$IMAGE_REF2'/g' $current_path/cvp-configuration/tempest/tempest_ext.conf
sed -i 's/${FLAVOR_REF}/'$FLAVOR_REF'/g' $current_path/cvp-configuration/tempest/tempest_ext.conf
sed -i 's/${FLAVOR_REF_ALT}/'$FLAVOR_REF_ALT'/g' $current_path/cvp-configuration/tempest/tempest_ext.conf
sed -i 's/${FIXED_NET}/'$FIXED_NET'/g' $current_path/cvp-configuration/tempest/tempest_ext.conf
sed -i 's/${FIXED_SUBNET_NAME}/'$FIXED_SUBNET_NAME'/g' $current_path/cvp-configuration/tempest/tempest_ext.conf
sed -i 's/${OS_USERNAME}/'$OS_USERNAME'/g' $current_path/cvp-configuration/tempest/tempest_ext.conf
sed -i 's/${OS_TENANT_NAME}/'$OS_TENANT_NAME'/g' $current_path/cvp-configuration/tempest/tempest_ext.conf
sed -i 's/${OS_REGION_NAME}/'$OS_REGION_NAME'/g' $current_path/cvp-configuration/tempest/tempest_ext.conf
sed -i 's|${OS_AUTH_URL}|'"${OS_AUTH_URL}"'|g' $current_path/cvp-configuration/tempest/tempest_ext.conf
sed -i 's|${OS_PASSWORD}|'"${OS_PASSWORD}"'|g' $current_path/cvp-configuration/tempest/tempest_ext.conf
sed -i 's/publicURL/'$TEMPEST_ENDPOINT_TYPE'/g' $current_path/cvp-configuration/tempest/tempest_ext.conf
#supress tempest.conf display in console
#cat $current_path/cvp-configuration/tempest/tempest_ext.conf
cp $current_path/cvp-configuration/tempest/boot_config_none_env.yaml /home/rally/boot_config_none_env.yaml
cp $current_path/cvp-configuration/cleanup.sh /home/rally/cleanup.sh
cp $current_path/cvp-configuration/rally/default.yaml.template /home/rally/default.yaml.template
chmod 755 /home/rally/cleanup.sh
}

if [ "$1" == "reconfigure" ]; then
  echo "This is reconfiguration"
  rally verify configure-verifier --reconfigure
  rally verify configure-verifier --extend $current_path/cvp-configuration/tempest/tempest_ext.conf
  rally verify configure-verifier --show
  exit 0
fi

check_variables
rally_configuration
if [ -n "${TEMPEST_REPO}" ]; then
    tempest_configuration
    quick_configuration
    # Since OS Pike is used:
    cat $current_path/cvp-configuration/tempest/skip-list-pike.yaml >> $current_path/cvp-configuration/tempest/skip-list.yaml
    # Since OpenContrail is used:
    cat $current_path/cvp-configuration/tempest/skip-list-oc4.yaml >> $current_path/cvp-configuration/tempest/skip-list.yaml
    # Since Heat plugin is used:
    cat $current_path/cvp-configuration/tempest/skip-list-heat.yaml >> $current_path/cvp-configuration/tempest/skip-list.yaml
    # Since Ceph is used:
    cat $current_path/cvp-configuration/tempest/skip-list-ceph.yaml >> $current_path/cvp-configuration/tempest/skip-list.yaml
    # Since LBaaS is used with Contrail:
    cat $current_path/cvp-configuration/tempest/skip-list-lbaas.yaml >> $current_path/cvp-configuration/tempest/skip-list.yaml

    rally verify configure-verifier --extend $current_path/cvp-configuration/tempest/tempest_ext.conf
    rally verify configure-verifier --show

    # If Barbican tempest plugin is installed, and for Heat API tests
    mkdir -p /etc/tempest
    rally verify configure-verifier --show | grep -v "rally.api" > /etc/tempest/tempest.conf
fi
set -e

echo "Configuration is done!"
