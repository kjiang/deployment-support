#!/bin/bash

set -e -x

if [ $(id -u) != 0 ]; then
    echo "Must run as root"
    exit 1
fi

apt-get -y install openssh-server vim-nox

# Add 2nd network interface
cat >> /etc/network/interfaces <<EOF
auto eth1
iface eth1 inet manual
    up ifconfig $IFACE 0.0.0.0 up
    up ifconfig $IFACE promisc
EOF

# http://docs.puppetlabs.com/guides/puppetlabs_package_repositories.html#for-debian-and-ubuntu
# http://docs.puppetlabs.com/guides/installation.html#debian-and-ubuntu
wget http://apt.puppetlabs.com/puppetlabs-release-precise.deb
sudo dpkg -i puppetlabs-release-precise.deb
sudo apt-get -y update
sudo apt-get -y install puppet-common

echo "bsn ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/bsn
chmod 440 /etc/sudoers.d/bsn

# Add cinder-volumes
apt-get -y install lvm2
LOOPDEV=/dev/loop2
FILE=/root/cinder-volumes
dd if=/dev/zero of=$FILE bs=1 count=0 seek=10G
dd if=/dev/zero of=$FILE bs=512 count=1 conv=notrunc
losetup $LOOPDEV $FILE
# fdisk returns 1 even when done
printf "n\np\n1\n\n\nt\n8e\nw\n" | fdisk $LOOPDEV || :
pvcreate $LOOPDEV
vgcreate cinder-volumes $LOOPDEV

# Add Havana repo for Ubuntu 12.04.3.
apt-get -y install python-software-properties
add-apt-repository cloud-archive:havana
apt-get -y update

puppet module install puppetlabs/openstack
cd /etc/puppet/modules
mv openstack openstack.old
apt-get -y install git
git clone -b stable/havana git://github.com/stackforge/puppet-openstack.git openstack
cp -p openstack/tests/site.pp /etc/puppet/manifests/

# Change IPs
sed -e "s|^\$fixed_network_range *=.*$|\$fixed_network_range = \'10.203.100.0/24\'|" \
    -e "s|^\$floating_network_range *=.*$|\$floating_network_range = \'10.192.23.64/28\'|" \
    -e "s|^\$controller_node_address *=.*$|\$controller_node_address = \'10.192.23.9\'|" \
    -i /etc/puppet/manifests/site.pp

# Add mysql password
sed -i "/# shared variables #/a \$mysql_root_password     = 'mysql_root_password'" /etc/puppet/manifests/site.pp
sed -i "/openstack::all/a mysql_root_password     => \$mysql_root_password," /etc/puppet/manifests/site.pp

# Comment out line 186
sed -i -e 's/neutron_metadata_proxy_shared_secret/# neutron_metadata_proxy_shared_secret/' /etc/puppet/modules/openstack/manifests/nova/controller.pp

puppet apply /etc/puppet/manifests/site.pp --certname openstack_all
source /root/openrc
nova-manage service list