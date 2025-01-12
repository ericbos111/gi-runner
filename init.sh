#!/bin/bash

trap display_error EXIT
export MPID=$$

#author: zibi - zszmigiero@gmail.com

#import global variables
. ./scripts/init.globals.sh
#load functions
. ./scripts/functions.sh
#MAIN PART
echo "#gi-runner configuration file" > $file
msg "This script must be executed from gi-runner home directory" 8
msg "Checking OS release" 7
save_variable KUBECONFIG "$GI_HOME/ocp/auth/kubeconfig"
check_linux_distribution_and_release
msg "Deployment decisions with/without Internet Access" 7
get_network_installation_type
msg "Deployment deicisons about the software and its releases to install" 7
get_software_selection
get_software_architecture
mkdir -p $GI_TEMP
[[ "$use_air_gap" == 'Y' ]] && prepare_offline_bastion
msg "Installing tools for init.sh" 7
[[ "$use_air_gap" == 'N' ]] && { dnf -qy install jq;[[ $? -ne 0 ]] && display_error "Cannot install jq"; }
get_ocp_domain
get_network_architecture
[[ $one_subnet == 'N' ]] && get_subnets
get_bastion_info
msg "Collecting data about bootstrap node (IP and MAC addres, name)" 7
get_nodes_info 1 "boot"
msg "Collecting Control Plane nodes data (IP and MAC addres, name), values must be inserted as comma separated list without spaces" 7
get_nodes_info 3 "mst"
get_worker_nodes
get_set_services
get_hardware_info
get_service_assignment
get_cluster_storage_info
get_inter_cluster_info
get_credentials
get_certificates
[[ "$gi_install" == 'Y' ]] && get_gi_options
#[[ "$gi_install" == 'Y' ]] && save_variable GI_ICS_OPERANDS "Y,N,N,N,N,N"
[[ "$ics_install" == 'Y' || "$gi_install" == 'Y' ]] && get_ics_options
[[ "$cp4s_install" == 'Y' ]] && get_cp4s_options
[[ "$install_ldap" == 'Y' ]] && get_ldap_options
[[ "$use_air_gap" == 'N' && "$use_proxy" == 'P' ]] && configure_os_for_proxy || unset_proxy_settings
[[ "$use_air_gap" == 'N' ]] && software_installation_on_online
create_cluster_ssh_key
#ln /usr/bin/python3 /usr/bin/python
msg "All information to deploy environment collected" 6
if LAST_KERNEL=$(rpm -q --last kernel | awk 'NR==1{sub(/kernel-/,""); print $1}'); CURRENT_KERNEL=$(uname -r); if [ $LAST_KERNEL != $CURRENT_KERNEL ]; then true; else false; fi;
then
	msg "System reboot required because new kernel has been installed" 6
	msg "Execute these commands after relogin to bastion:" 6
	msg "- go to gi-runner home directory: \"cd $GI_HOME\"" 6
	msg "- import variables: \". $file\"" 6
        msg "- start first playbook: \"ansible-playbook playbooks/install_all.yaml\"" 6
	read -p "Press enter to continue to reboot system"
	shutdown -r now
else
	msg "Execute commands below to continue:" 6
	[[ $use_proxy == 'P' ]] &&  msg "- import PROXY settings: \". /etc/profile\"" 6
	msg "- import variables: \". $file\"" 6
	msg "- start playbook: \"ansible-playbook playbooks/install_all.yaml\"" 6
fi
trap - EXIT
