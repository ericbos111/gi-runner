#!/bin/bash
set -e
trap "exit 1" ERR

echo "Setting environment"
if [[ $# -ne 0 && $1 != "repeat" ]]
then
	echo "To restart mirroring process use paramater 'repeat'"
	exit 1
fi

source scripts/init.globals.sh
source scripts/shared_functions.sh

get_pre_scripts_variables
if [ $# -eq 0 ]
then
	pre_scripts_init
	echo ""
fi
mkdir $GI_TEMP/cp4s_arch
read -sp "Insert your IBM Cloud Key: " ibm_account_key
if [ $# -eq 0 ]
then
	msg "Setup mirror image registry ..." true
	setup_local_registry
	msg "Download support tools ..." true
	cd $GI_TEMP
	declare -a ocp_files=("https://github.com/IBM/cloud-pak-cli/releases/latest/download/cloudctl-linux-amd64.tar.gz" "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest/openshift-client-linux.tar.gz")
	for file in ${ocp_files[@]}
	do
        	download_file $file
	done
	files_type="ICS"
	install_app_tools
	dnf -qy install skopeo
	check_exit_code $? "Cannot install skopeo package"
fi
b64auth=$( echo -n 'admin:guardium' | openssl base64 )
LOCAL_REGISTRY="$host_fqdn:5000"
echo "Mirroring GI ${cp4s_versions[0]}"
CASE_ARCHIVE=${cp4s_cases[0]}
CASE_INVENTORY_SETUP=ibmSecurityOperatorSetup
if [ $# -eq 0 ]
then
	cloudctl case save --case https://github.com/IBM/cloud-pak/raw/master/repo/case/${CASE_ARCHIVE} --outputdir $GI_TEMP/cp4s_arch/cp4s_offline
	check_exit_code $? "Cannot download GI case file"
	tar xvf $GI_TEMP/cp4s_arch/${CASE_ARCHIVE} -C $GI_TEMP/cp4s_arch/
	sed -i '/versionRegex/d' $GI_TEMP/cp4s_arch/ibm-cp-security/prereqs.yaml
	sites="cp.icr.io"
	for site in $sites
	do
		echo $site
	        cloudctl case launch --case $GI_TEMP/cp4s_arch/cp4s_offline/ibm-cp-security --action configure-creds-airgap --inventory $CASE_INVENTORY_SETUP --args "--registry $site --user cp --pass $ibm_account_key" --tolerance 1
		check_exit_code $? "Cannot configure credentials for site $site"
	done
	cloudctl case launch --case $GI_TEMP/cp4s_arch/cp4s_offline/ibm-cp-security --action configure-creds-airgap --inventory $CASE_INVENTORY_SETUP --args "--registry `hostname --long`:5000 --user admin --pass guardium" --tolerance 1
fi
cloudctl case launch --case $GI_TEMP/_arch/_offline/ibm-cp-security --action mirror-images --inventory $CASE_INVENTORY_SETUP --args "--registry `hostname --long`:5000 --inputDir $GI_TEMP/cp4s_offline" --tolerance 1
mirror_status=$?
echo "Mirroring status: $mirror_status"
if [ $mirror_status -ne 0 ]
then
	echo "Mirroring process failed, restart script with parameter repeat to finish"
	exit 1
fi
podman stop bastion-registry
cd $GI_TEMP
tar cf ${air_dir}/cp4s_registry-${cp4s_versions[0]}.tar cp4s_offline cloudctl-linux-amd64.tar.gz
cd /opt/registry
tar -rf ${air_dir}/cp4s_registry-${cp4s_versions[0]}.tar data
cd $GI_TEMP
rm -rf /opt/registry
podman rm bastion-registry
podman rmi --all
rm -rf $GI_TEMP
echo "CP4S ${cp4s_versions[0]} files prepared - copy $air_dir/cp4s_registry-${cp4s_versions[0]}.tar to air-gapped bastion machine"
