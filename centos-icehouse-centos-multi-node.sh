123456a@							 	Root password for the database MySQL
RABBIT_PASS 							Password of user guest of RabbitMQ
KEYSTONE_DBPASS 						Database password of Identity service
DEMO_PASS 								Password of user demo
ADMIN_PASS 								Password of user admin
GLANCE_DBPASS 							Database password for Image Service
GLANCE_PASS 							Password of Image Service user glance
NOVA_DBPASS 							Database password for Compute service
NOVA_PASS 								Password of Compute service user nova
DASH_DBPASS 							Database password for the dashboard
CINDER_DBPASS 							Database password for the Block Storage service
CINDER_PASS 							Password of Block Storage service user cinder
NEUTRON_DBPASS 							Database password for the Networking service
NEUTRON_PASS 							Password of Networking service user neutron
HEAT_DBPASS 							Database password for the Orchestration service
HEAT_PASS 								Password of Orchestration service user heat
CEILOMETER_DBPASS 						Database password for the Telemetry service
CEILOMETER_PASS 						Password of Telemetry service user ceilometer
TROVE_DBPASS 							Database password of Database service
TROVE_PASS 								Password of Database Service user trove

***** CONTROLLER && NETWORK && COMPUTE NODE *****
yum -y install ntp
vi /etc/ntp.conf
	server controller		# Comment all other servers on network && compute node

***** CONTROLLER NODE *****
yum -y install mysql mysql-server MySQL-python
vi /etc/my.cnf
	[mysqld]
		bind-address = 192.168.0.88
		default-storage-engine = innodb
		collation-server = utf8_general_ci
		init-connect = 'SET NAMES utf8'
		character-set-server = utf8
service mysqld start
chkconfig mysqld on

mysql_secure_installation	# Create password && Delete all anonymous users and data

***** NETWORK && COMPUTE NODE *****
yum -y install MySQL-python

***** CONTROLLER && NETWORK && COMPUTE NODE *****
yum -y install http://repos.fedorapeople.org/repos/openstack/openstack-icehouse/rdo-release-icehouse-3.noarch.rpm
yum -y install http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
yum -y install openstack-utils
yum -y install openstack-selinux
yum -y update
yum -y upgrade
reboot

***** CONTROLLER NODE *****
# QUEUE MESSAGE
yum -y install qpid-cpp-server
vi /etc/qpidd.conf
	auth=no				# sed -i 's/auth=yes/auth=no/g' /etc/qpidd.conf
service qpidd start
chkconfig qpidd on


********************************************************
********************************************************
### KEYSTONE SERVICE
********************************************************
********************************************************

***** CONTROLLER NODE *****
yum -y install openstack-keystone python-keystoneclient
openstack-config --set /etc/keystone/keystone.conf database connection mysql://keystone:KEYSTONE_DBPASS@controller/keystone
mysql -u root -p
	CREATE DATABASE keystone;
	GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'KEYSTONE_DBPASS';
	GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'KEYSTONE_DBPASS';
	exit;
su -s /bin/sh -c "keystone-manage db_sync" keystone			# create a Keystone database schema

ADMIN_TOKEN=$(openssl rand -hex 10)
echo $ADMIN_TOKEN
openstack-config --set /etc/keystone/keystone.conf DEFAULT admin_token $ADMIN_TOKEN

keystone-manage pki_setup --keystone-user keystone --keystone-group keystone
chown -R keystone:keystone /etc/keystone/ssl
chmod -R o-rwx /etc/keystone/ssl

service openstack-keystone start
chkconfig openstack-keystone on
(crontab -l 2>&1 | grep -q token_flush) || echo '@hourly /usr/bin/keystone-manage token_flush >/var/log/keystone/keystone-tokenflush.log 2>&1' >> /var/spool/cron/root

export OS_SERVICE_TOKEN=$ADMIN_TOKEN
export OS_SERVICE_ENDPOINT=http://controller:35357/v2.0

keystone user-create --name=admin --pass=ADMIN_PASS --email=ADMIN_EMAIL@controller.com
keystone role-create --name=admin
keystone tenant-create --name=admin --description="Admin Tenant"
keystone user-role-add --user=admin --role=admin --tenant=admin
keystone user-role-add --user=admin --role=_member_ --tenant=admin

keystone user-create --name=demo --pass=DEMO_PASS --email=DEMO_EMAIL@controller.com
keystone tenant-create --name=demo --description="Demo Tenant"
keystone user-role-add --user=demo --role=_member_ --tenant=demo

keystone tenant-create --name=service --description="Service Tenant"

keystone service-create --name=keystone --type=identity --description="OpenStack Identity"
keystone endpoint-create \
--service-id=$(keystone service-list | awk '/ identity / {print $2}') \			# OR --service-id=321ce2bc58fb402da5e660bb8a88438d \
--publicurl=http://controller:5000/v2.0 \
--internalurl=http://controller:5000/v2.0 \
--adminurl=http://controller:35357/v2.0

# Verify the KEYSTONE
unset OS_SERVICE_TOKEN OS_SERVICE_ENDPOINT

keystone --os-username=admin --os-password=ADMIN_PASS --os-auth-url=http://controller:35357/v2.0 token-get
keystone --os-username=admin --os-password=ADMIN_PASS --os-tenant-name=admin --os-auth-url=http://controller:35357/v2.0 token-get

touch admin-openrc.sh
vi admin-openrc.sh
	export OS_USERNAME=admin
	export OS_PASSWORD=ADMIN_PASS
	export OS_TENANT_NAME=admin
	export OS_AUTH_URL=http://controller:35357/v2.0
source admin-openrc.sh

keystone token-get
keystone user-list
keystone user-role-list --user admin --tenant admin


********************************************************
********************************************************
### GLANCE SERVICE
********************************************************
********************************************************

***** CONTROLLER *****
yum -y install openstack-glance python-glanceclient
openstack-config --set /etc/glance/glance-api.conf database connection mysql://glance:GLANCE_DBPASS@controller/glance
openstack-config --set /etc/glance/glance-registry.conf database connection mysql://glance:GLANCE_DBPASS@controller/glance

openstack-config --set /etc/glance/glance-api.conf DEFAULT rpc_backend qpid
openstack-config --set /etc/glance/glance-api.conf DEFAULT qpid_hostname controller

mysql -u root -p
	CREATE DATABASE glance;
	GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY 'GLANCE_DBPASS';
	GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY 'GLANCE_DBPASS';
	exit;
su -s /bin/sh -c "glance-manage db_sync" glance

keystone user-create --name=glance --pass=GLANCE_PASS --email=glance@controller.com
keystone user-role-add --user=glance --tenant=service --role=admin

openstack-config --set /etc/glance/glance-api.conf keystone_authtoken auth_uri http://controller:5000
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken auth_host controller
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken auth_port 35357
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken auth_protocol http
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken admin_tenant_name service
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken admin_user glance
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken admin_password GLANCE_PASS
openstack-config --set /etc/glance/glance-api.conf paste_deploy flavor keystone
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken auth_uri http://controller:5000
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken auth_host controller
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken auth_port 35357
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken auth_protocol http
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken admin_tenant_name service
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken admin_user glance
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken admin_password GLANCE_PASS
openstack-config --set /etc/glance/glance-registry.conf paste_deploy flavor keystone

keystone service-create --name=glance --type=image --description="OpenStack Image Service"
keystone endpoint-create \
--service-id=$(keystone service-list | awk '/ image / {print $2}') \			# OR --service-id=2e1ba914b5d84165b583b1373dd99fe4 \
--publicurl=http://controller:9292 \
--internalurl=http://controller:9292 \
--adminurl=http://controller:9292

service openstack-glance-api start
service openstack-glance-registry start
chkconfig openstack-glance-api on
chkconfig openstack-glance-registry on

# Verify GLANCE
mkdir images
cd images/
wget http://cdn.download.cirros-cloud.net/0.3.2/cirros-0.3.2-x86_64-disk.img

source /root/admin-openrc.sh
glance image-create --name "cirros-0.3.2-x86_64" --disk-format qcow2 --container-format bare --is-public True --progress < cirros-0.3.2-x86_64-disk.img

glance image-list


********************************************************
********************************************************
### COMPUTE SERVICE (NOVA)
********************************************************
********************************************************

***** CONTROLLER NODE *****
yum -y install openstack-nova-api openstack-nova-cert openstack-nova-conductor openstack-nova-console openstack-nova-novncproxy openstack-nova-scheduler python-novaclient

openstack-config --set /etc/nova/nova.conf database connection mysql://nova:NOVA_DBPASS@controller/nova
openstack-config --set /etc/nova/nova.conf DEFAULT rpc_backend qpid
openstack-config --set /etc/nova/nova.conf DEFAULT qpid_hostname controller
openstack-config --set /etc/nova/nova.conf DEFAULT my_ip 192.168.0.88
openstack-config --set /etc/nova/nova.conf DEFAULT vncserver_listen 192.168.0.88
openstack-config --set /etc/nova/nova.conf DEFAULT vncserver_proxyclient_address 192.168.0.88

mysql -u root -p
	CREATE DATABASE nova;
	GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY 'NOVA_DBPASS';
	GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY 'NOVA_DBPASS';
	exit;
su -s /bin/sh -c "nova-manage db sync" nova

keystone user-create --name=nova --pass=NOVA_PASS --email=nova@controller.com
keystone user-role-add --user=nova --tenant=service --role=admin

openstack-config --set /etc/nova/nova.conf DEFAULT auth_strategy keystone
openstack-config --set /etc/nova/nova.conf keystone_authtoken auth_uri http://controller:5000
openstack-config --set /etc/nova/nova.conf keystone_authtoken auth_host controller
openstack-config --set /etc/nova/nova.conf keystone_authtoken auth_protocol http
openstack-config --set /etc/nova/nova.conf keystone_authtoken auth_port 35357
openstack-config --set /etc/nova/nova.conf keystone_authtoken admin_user nova
openstack-config --set /etc/nova/nova.conf keystone_authtoken admin_tenant_name service
openstack-config --set /etc/nova/nova.conf keystone_authtoken admin_password NOVA_PASS

keystone service-create --name=nova --type=compute --description="OpenStack Compute"
keystone endpoint-create \
--service-id=$(keystone service-list | awk '/ compute / {print $2}') \			# OR --service-id=69a048ccbd2f4da8b92590358076eb24 \
--publicurl=http://controller:8774/v2/%\(tenant_id\)s \
--internalurl=http://controller:8774/v2/%\(tenant_id\)s \
--adminurl=http://controller:8774/v2/%\(tenant_id\)s


service openstack-nova-api start				# người dùng phải đăng nhập để thực hiện các yêu cầu của mình
service openstack-nova-cert start				# 
service openstack-nova-consoleauth start		# validate tokens, wait for a reply from them until a timeout is reached
service openstack-nova-scheduler start			# lập lịch (chỉ định các VMs sẽ chạy trên 1 host vật lý nào đấy)
service openstack-nova-conductor start			# giúp nova-compute truy nhập vào db để ghi các trạng thái VM (chạy, xóa, khởi tạo,…) / database proxy call
service openstack-nova-novncproxy start			# use noVNC to provide vnc support through a web browser
chkconfig openstack-nova-api on
chkconfig openstack-nova-cert on
chkconfig openstack-nova-consoleauth on
chkconfig openstack-nova-scheduler on
chkconfig openstack-nova-conductor on
chkconfig openstack-nova-novncproxy on

# Verify COMPUTE
nova image-list

***** COMPUTE NODE *****
yum -y install openstack-nova-compute

openstack-config --set /etc/nova/nova.conf database connection mysql://nova:NOVA_DBPASS@controller/nova
openstack-config --set /etc/nova/nova.conf DEFAULT auth_strategy keystone
openstack-config --set /etc/nova/nova.conf keystone_authtoken auth_uri http://controller:5000
openstack-config --set /etc/nova/nova.conf keystone_authtoken auth_host controller
openstack-config --set /etc/nova/nova.conf keystone_authtoken auth_protocol http
openstack-config --set /etc/nova/nova.conf keystone_authtoken auth_port 35357
openstack-config --set /etc/nova/nova.conf keystone_authtoken admin_user nova
openstack-config --set /etc/nova/nova.conf keystone_authtoken admin_tenant_name service
openstack-config --set /etc/nova/nova.conf keystone_authtoken admin_password NOVA_PASS
openstack-config --set /etc/nova/nova.conf DEFAULT rpc_backend qpid
openstack-config --set /etc/nova/nova.conf DEFAULT qpid_hostname controller
openstack-config --set /etc/nova/nova.conf DEFAULT my_ip 192.168.0.90
openstack-config --set /etc/nova/nova.conf DEFAULT vnc_enabled True
openstack-config --set /etc/nova/nova.conf DEFAULT vncserver_listen 0.0.0.0
openstack-config --set /etc/nova/nova.conf DEFAULT vncserver_proxyclient_address 192.168.0.90
openstack-config --set /etc/nova/nova.conf DEFAULT novncproxy_base_url http://172.16.6.88:6080/vnc_auto.html
openstack-config --set /etc/nova/nova.conf DEFAULT glance_host controller

egrep -c '(vmx|svm)' /proc/cpuinfo			# Check the kvm support

service libvirtd start
service messagebus start
chkconfig libvirtd on
chkconfig messagebus on
service openstack-nova-compute start
chkconfig openstack-nova-compute on


********************************************************
********************************************************
### NETWORK SERVICE (NEUTRON)
********************************************************
********************************************************

***** CONTROLLER NODE *****
mysql -u root -p
	CREATE DATABASE neutron;
	GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY 'NEUTRON_DBPASS';
	GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY 'NEUTRON_DBPASS';
	exit;

keystone user-create --name neutron --pass NEUTRON_PASS --email neutron@controller.com
keystone user-role-add --user neutron --tenant service --role admin
keystone service-create --name neutron --type network --description "OpenStack Networking"
keystone endpoint-create \
--service-id=$(keystone service-list | awk '/ network / {print $2}') \			# OR --service-id=4e5bb698867e48e99d7db33f4cd0abae \
--publicurl=http://controller:9696 \
--adminurl=http://controller:9696 \
--internalurl=http://controller:9696

# Network Components
yum -y install openstack-neutron openstack-neutron-ml2 python-neutronclient

openstack-config --set /etc/neutron/neutron.conf database connection mysql://neutron:NEUTRON_DBPASS@controller/neutron
openstack-config --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_uri http://controller:5000
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_host controller
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_protocol http
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_port 35357
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken admin_tenant_name service
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken admin_user neutron
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken admin_password NEUTRON_PASS
openstack-config --set /etc/neutron/neutron.conf DEFAULT rpc_backend neutron.openstack.common.rpc.impl_qpid
openstack-config --set /etc/neutron/neutron.conf DEFAULT qpid_hostname controller
openstack-config --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_status_changes True
openstack-config --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_data_changes True
openstack-config --set /etc/neutron/neutron.conf DEFAULT nova_url http://controller:8774/v2
openstack-config --set /etc/neutron/neutron.conf DEFAULT nova_admin_username nova
openstack-config --set /etc/neutron/neutron.conf DEFAULT nova_admin_tenant_id $(keystone tenant-list | awk '/ service / { print $2 }')
openstack-config --set /etc/neutron/neutron.conf DEFAULT nova_admin_password NOVA_PASS
openstack-config --set /etc/neutron/neutron.conf DEFAULT nova_admin_auth_url http://controller:35357/v2.0
openstack-config --set /etc/neutron/neutron.conf DEFAULT core_plugin ml2
openstack-config --set /etc/neutron/neutron.conf DEFAULT service_plugins router

vi /etc/neutron/neutron.conf
	[DEFAULT]
		verbose = True
	[service_providers]
		# Comment all lines

# Configure the Modular Layer 2 (ML2) plugin
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers gre
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types gre
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers openvswitch
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_gre tunnel_id_ranges 1:1000
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_security_group True

# Configure Compute to use Networking
openstack-config --set /etc/nova/nova.conf DEFAULT network_api_class nova.network.neutronv2.api.API
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_url http://controller:9696
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_auth_strategy keystone
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_admin_tenant_name service
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_admin_username neutron
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_admin_password NEUTRON_PASS
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_admin_auth_url http://controller:35357/v2.0
openstack-config --set /etc/nova/nova.conf DEFAULT linuxnet_interface_driver nova.network.linux_net.LinuxOVSInterfaceDriver
openstack-config --set /etc/nova/nova.conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
openstack-config --set /etc/nova/nova.conf DEFAULT security_group_api neutron

ln -s plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini

service openstack-nova-api restart
service openstack-nova-scheduler restart
service openstack-nova-conductor restart

service neutron-server start
chkconfig neutron-server on


***** NETWORK NODE *****
# enable certain kernel networking functions
vi /etc/sysctl.conf
	net.ipv4.ip_forward=1
	net.ipv4.conf.all.rp_filter=0				#Reverse Path Filtering
	net.ipv4.conf.default.rp_filter=0
sysctl -p

yum -y install openstack-neutron openstack-neutron-ml2 openstack-neutron-openvswitch

openstack-config --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_uri http://controller:5000
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_host controller
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_protocol http
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_port 35357
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken admin_tenant_name service
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken admin_user neutron
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken admin_password NEUTRON_PASS
openstack-config --set /etc/neutron/neutron.conf DEFAULT rpc_backend neutron.openstack.common.rpc.impl_qpid
openstack-config --set /etc/neutron/neutron.conf DEFAULT qpid_hostname controller
openstack-config --set /etc/neutron/neutron.conf DEFAULT core_plugin ml2
openstack-config --set /etc/neutron/neutron.conf DEFAULT service_plugins router

vi /etc/neutron/neutron.conf
	[DEFAULT]
		verbose = True
	[service_providers]
		# Comment all lines

# Configure the Layer-3 (L3) agent		
openstack-config --set /etc/neutron/l3_agent.ini DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
openstack-config --set /etc/neutron/l3_agent.ini DEFAULT use_namespaces True
vi /etc/neutron/l3_agent.ini
	verbose = True

# Configure the DHCP agent
openstack-config --set /etc/neutron/dhcp_agent.ini DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
openstack-config --set /etc/neutron/dhcp_agent.ini DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
openstack-config --set /etc/neutron/dhcp_agent.ini DEFAULT use_namespaces True
vi /etc/neutron/dhcp_agent.ini
	verbose = True

# Configure the Metadata agent
openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT auth_url http://controller:5000/v2.0
openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT auth_region regionOne
openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT admin_tenant_name service
openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT admin_user neutron
openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT admin_password NEUTRON_PASS
openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT nova_metadata_ip controller
openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT metadata_proxy_shared_secret METADATA_SECRET
vi /etc/neutron/metadata_agent.ini
	verbose = True

***** CONTROLLER NODE *****
openstack-config --set /etc/nova/nova.conf DEFAULT service_neutron_metadata_proxy true
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_metadata_proxy_shared_secret METADATA_SECRET
service openstack-nova-api restart

***** NETWORK NODE *****
# Configure the Modular Layer 2 (ML2) plugin
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers gre
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types gre
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers openvswitch
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_gre tunnel_id_ranges 1:1000
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs local_ip 192.168.2.89
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs tunnel_type gre
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs enable_tunneling True
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_security_group True

# Configure the Open vSwitch (OVS) service
service openvswitch start
chkconfig openvswitch on

ovs-vsctl add-br br-int			# add the integration bridge
ovs-vsctl add-br br-ex			# add the external bridge
ovs-vsctl add-port br-ex eth0	# add a port to the external bridge that connects to the physical external network interface

ethtool -K eth0 gro off			# 

ln -s plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
cp /etc/init.d/neutron-openvswitch-agent /etc/init.d/neutron-openvswitch-agent.orig
sed -i 's,plugins/openvswitch/ovs_neutron_plugin.ini,plugin.ini,g' /etc/init.d/neutron-openvswitch-agent

service neutron-openvswitch-agent start
service neutron-l3-agent start
service neutron-dhcp-agent start
service neutron-metadata-agent start
chkconfig neutron-openvswitch-agent on
chkconfig neutron-l3-agent on
chkconfig neutron-dhcp-agent on
chkconfig neutron-metadata-agent on


***** COMPUTE NODE *****
vi /etc/sysctl.conf
	net.ipv4.conf.all.rp_filter=0
	net.ipv4.conf.default.rp_filter=0
sysctl -p

yum -y install openstack-neutron-ml2 openstack-neutron-openvswitch

openstack-config --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_uri http://controller:5000
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_host controller
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_protocol http
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_port 35357
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken admin_tenant_name service
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken admin_user neutron
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken admin_password NEUTRON_PASS
openstack-config --set /etc/neutron/neutron.conf DEFAULT rpc_backend neutron.openstack.common.rpc.impl_qpid
openstack-config --set /etc/neutron/neutron.conf DEFAULT qpid_hostname controller
openstack-config --set /etc/neutron/neutron.conf DEFAULT core_plugin ml2
openstack-config --set /etc/neutron/neutron.conf DEFAULT service_plugins router

vi /etc/neutron/neutron.conf
	[DEFAULT]
		verbose = True
	[service_providers]
		# Comment all lines
	
# Configure Modular Layer 2 (ML2) plugin
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers gre
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types gre
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers openvswitch
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_gre tunnel_id_ranges 1:1000
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs local_ip 192.168.2.90
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs tunnel_type gre
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs enable_tunneling True
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_security_group True

# Configure Open vSwitch service
service openvswitch start
chkconfig openvswitch on

ovs-vsctl add-br br-int			# add the integration bridge

# Configure COMPUTE to use Networking
openstack-config --set /etc/nova/nova.conf DEFAULT network_api_class nova.network.neutronv2.api.API
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_url http://controller:9696
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_auth_strategy keystone
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_admin_tenant_name service
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_admin_username neutron
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_admin_password NEUTRON_PASS
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_admin_auth_url http://controller:35357/v2.0
openstack-config --set /etc/nova/nova.conf DEFAULT linuxnet_interface_driver nova.network.linux_net.LinuxOVSInterfaceDriver
openstack-config --set /etc/nova/nova.conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
openstack-config --set /etc/nova/nova.conf DEFAULT security_group_api neutron

ln -s plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
cp /etc/init.d/neutron-openvswitch-agent /etc/init.d/neutron-openvswitch-agent.orig
sed -i 's,plugins/openvswitch/ovs_neutron_plugin.ini,plugin.ini,g' /etc/init.d/neutron-openvswitch-agent

service openstack-nova-compute restart
service neutron-openvswitch-agent start
chkconfig neutron-openvswitch-agent on


***** CONTROLLER NODE *****
# Create initial networks
# External network
source admin-openrc.sh
neutron net-create ext-net --shared --router:external=True			# Create the external network --connect to the physical network
neutron subnet-create ext-net --name ext-subnet \					# Create a subnet on the external network
--allocation-pool start=172.16.6.100,end=172.16.6.120 \
--disable-dhcp --gateway 172.16.6.254 172.16.6.0/24

# Tenant network
touch demo-openrc.sh
vi demo-openrc.sh
	export OS_USERNAME=demo
	export OS_PASSWORD=DEMO_PASS
	export OS_TENANT_NAME=demo
	export OS_AUTH_URL=http://controller:35357/v2.0
source demo-openrc.sh
neutron net-create demo-net											# Create the tenant network
neutron subnet-create demo-net --name demo-subnet \					# Create a subnet on the tenant network
--gateway 192.168.10.1 192.168.10.0/24 \
--dns_nameservers list=true 8.8.8.8 208.67.222.222

# Create a router on the tenant network and attach the external and tenant networks to it
neutron router-create demo-router
neutron router-interface-add demo-router demo-subnet				# Attach the router to the demo tenant subnet
neutron router-gateway-set demo-router ext-net						# Attach the router to the external network by setting it as the gateway

# Verify


********************************************************
********************************************************
### DASHBOARD
********************************************************
********************************************************

***** CONTROLLER NODE *****
yum -y install memcached python-memcached mod_wsgi openstack-dashboard
vi /etc/openstack-dashboard/local_settings		# match the address & port in /etc/sysconfig/memcached
	CACHES['default']['LOCATION']
		CACHES = {
		'default': {
		'BACKEND' : 'django.core.cache.backends.memcached.MemcachedCache',
		'LOCATION' : '127.0.0.1:11211'
		}
		}
	ALLOWED_HOSTS = ['localhost', 'my-desktop','*']
	TIME_ZONE = 'Etc/GMT-8'
	OPENSTACK_HOST = "controller"

setsebool -P httpd_can_network_connect on			# Ensure that the SELinux policy of the system is configured to allow network connections to the HTTP server

service httpd start
service memcached start
chkconfig httpd on
chkconfig memcached on

#http://controller/dashboard






