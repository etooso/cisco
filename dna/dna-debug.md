# Debug for Cisco DNAC and SDA

Useful information for debugging and troubleshooting DNAC and SDA.

## Catch-all

Configuration to log all commands sent to a device (tested on 9300 and 3850). Handy to verify all commands DNA is sending and which one is failing.

```
conf t
event manager applet catchall
event cli pattern ".*" sync no skip no
action 1 syslog msg "$_cli_msg"
end


! to remove it
conf t
no event manager applet catchall
```

## maglev commands

Miscellaneous maglev commands for troubleshooting. These commands are taken from TAC webex, troubleshooting guides, presentations, etc.

Please use at your own risk!

```
### Checks status of all applications
magctl appstack status

### Checks hardware status of server, handy to fetch the Serial Number if no access to CIMC
sudo lshw

### Log location
/var/log/

### Example, the maglev config wizard log (for failed installations)  
/var/log/maglev_config_wizard.log

### For HA environments, check cluster status
magctl node status

### For HA, check distribution of applications
maglev service nodescale progress

### For HA, check docker status  
systemctl status docker

### HA status
maglev service nodescale status
maglev service nodescale history
maglev cluster node display

### Caution!! For HA, trigger the re-distribution of services
maglev service nodescale refresh

### Caution!! For HA, removed a failed node from cluster
### "node ip" is the cluster ip, can be found with "magctl node status"
maglev node remove < node_ip >

### Caution!! For HA, graceful removal of node
maglev node drain < node_ip >
maglev node remove < node_ip >

### Misc commands related to upgrading
maglev catalog settings display
maglev system_updater update_info
maglev package status
maglev catalog package display network visibility | grep

### CAUTION! to remove a package for a failed installation, for example
maglev package undeploy network visibility

### To "pull" the package again from the catalog on a specific version
maglev catalog package pull network visibility:2.1.1.60067

### To deploy the package again
maglev package deploy <>

###  Misc   
maglev catalog package pull <name> --force
maglev package upgrade <name> --force
maglev catalog release_channel display

### Logs
magctl service logs -r -f <service name>

### GUI user
magctl user display admin
magctl user password update admin TNT0

### Trigger maglev updater Wizard
sudo maglev-config update

### Misc network status
netstat -rn
etcdctl get /maglev/config/cluster/cluster_network
ip a s <enterprise>

### Cluster health
etcdctl cluster-health

### Show Cluster addresses, services subnet, cluster subnet
maglev cluster network display

### Show interface info
ethtool enp94s0f0

### Install logs
more /var/log/maglev_config_wizard_last_run.log
more /var/log/maglev_config_wizard.log

### Service status where "inventory" is the service
magctl service status inventory

### Which catalog is loaded
maglev catalog package display
```

## SQL-queries

Most of DNAC related info is stored in the PostgreSQL database. Runs inside a docker container.

ALL changes done to DB should be done with guidance from TAC. However, sometimes it's useful to be able to do simple select queries and/or fixes that is known/has been done before.

To open a shell to PostgreSQL-docker, do the following;

```
# find the relevant container + launch psql from within that
docker exec -it $(docker ps | awk '/postgres_postgres-[0-2]+_fusion/ {print $1}') psql -U apic_em_user -d campus -h localhost

# can also be done in separate, manual steps
$ docker ps | grep postgres

d7b24a9026e6        maglev-registry.maglev-system.svc.cluster.local:5000/postgres                                       "/home/postgres/.ssh…"   3 weeks ago         Up 3 weeks                              k8s_postgres_postgres-0_fusion_18089030-96c3-11ea-8524-40a6b7097190_1
b02aed9fe0f4        maglev-registry.maglev-system.svc.cluster.local:5000/postgres-sidecar                               "/bin/sh -c '. /opt/…"   3 weeks ago         Up 3 weeks                              k8s_sidecar_postgres-0_fusion_18089030-96c3-11ea-8524-40a6b7097190_1
faef01dd4db1        maglev-registry.maglev-system.svc.cluster.local:5000/postgres-proxy                                 "/usr/local/bin/entr…"   3 weeks ago         Up 3 weeks                              k8s_proxy_postgres-0_fusion_18089030-96c3-11ea-8524-40a6b7097190_1
ebe95c495fd3        maglev-registry.maglev-system.svc.cluster.local:5000/postgres                                       "/home/postgres/.ssh…"   3 weeks ago         Up 3 weeks                              k8s_postgres_postgres-0_app-hosting_953fd1fe-97ed-11ea-8524-40a6b7097190_1
c11387d68feb        maglev-registry.maglev-system.svc.cluster.local:5000/postgres-sidecar                               "/bin/sh -c '. /opt/…"   3 weeks ago         Up 3 weeks                              k8s_sidecar_postgres-0_app-hosting_953fd1fe-97ed-11ea-8524-40a6b7097190_1
ca6d7f87092e        maglev-registry.maglev-system.svc.cluster.local:5000/postgres-proxy                                 "/usr/local/bin/entr…"   3 weeks ago         Up 3 weeks                              k8s_proxy_postgres-0_app-hosting_953fd1fe-97ed-11ea-8524-40a6b7097190_1
fb9fe24e684c        maglev-registry.maglev-system.svc.cluster.local:5000/pause-amd64:3.1                                "/pause"                 3 weeks ago         Up 3 weeks                              k8s_POD_postgres-0_fusion_18089030-96c3-11ea-8524-40a6b7097190_1
d44ab29d1106        maglev-registry.maglev-system.svc.cluster.local:5000/pause-amd64:3.1                                "/pause"                 3 weeks ago         Up 3 weeks                              k8s_POD_postgres-0_app-hosting_953fd1fe-97ed-11ea-8524-40a6b7097190_1

# you want "postgres_postgres-[0-2]_fusion" from the list
$ docker exec -it d7b24a9026e6 bash

# then enter the database
root@postgres-0:/# psql -U apic_em_user -d campus
```


### Useful queries

**Failed device won't clear (cosmetic bug)**

If a device has previously failed to provision, but is now fixed, it still might show as failed, even if it's no longer failing. This is a cosmetic bug (don't know the bug ID), but it's apparently Soon Fixed™.

```
# to find if there are any such failures on a device with a given IP
select id, instanceuuid, servicetype, deviceid, namespace, cfsversion, status, error_detail
from deviceconfigstatus where islatest=true and status = 'Failed' and deviceid in 
(select instanceuuid from networkdevice where managementipaddress='<IP of device>');

# then update this error, so that GUI reflects true status
update deviceconfigstatus set islatest=false where islatest=true and status = 'Failed' and deviceid in
(select instanceuuid from networkdevice where managementipaddress='10.199.255.130');
```

**IP SLA duplicates (CSCvt54665 / CSCvs68227)**

Sometimes there are duplicates in the IPSLA table. Different root causes leads to duplicate entries.

```
# group IPSLA tests in orderly manner
select sourcedeviceid, sourceipaddress, destinationipaddress, virtualnetworkid
from reachabilitysession
order by sourcedeviceid, virtualnetworkid, sourceipaddress, destinationipaddress;

# find potential duplicate entries
select id from customerfacingservice where id in (
 select deviceinfo_id from deviceinfo where networkdeviceid
 NOT IN (
  select instanceuuid from networkdevice
 )
);

# find VN name if you have "virtualnetworkid"
select * from customerfacingservice where instanceuuid='<virtualnetworkid>';
```

**All network devices**

```
select * from networkdevice;
select * from deviceinfo;
```

**Check NETCONF reason for provision failure**

Sometimes you get provision failures, where the GUI just gives you a gibberish error message. This happened when trying to provision RF-profiles with invalid channels for the country the WLC is set to. The GUI just failed, but did not inform of the true error. The query below would show latest configuration status (including NETCONF content), and the NETCONF error code/text.

```
select * from deviceconfigstatus where deviceid in (
 select instanceuuid from networkdevice where managementipaddress='<Device IP address>'
) and islatest=true;

# a bit shorter/easy to read version
select instanceuuid, error_message, error_detail
from deviceconfigstatus where deviceid in (
 select instanceuuid from networkdevice where managementipaddress='<Device IP address>'
) and islatest=true;
```

**Version information**

Current + original version information.

```
# SQL query
select * from commonresourceversion;

# CLI commands
cat /etc/maglev/release-info.yaml
etcdctl ls /maglev/system_updates/cluster_update_jobs/version
```
**Devices stuck with internal error in inventory**
Find UUID

docker exec -it $(docker ps | awk '/postgres_postgres-[0-2]+_fusion/ {print $1}') psql -U apic_em_user -d campus -h localhost
 select instanceuuid from managedelementinterface where managementaddress='10.2.136.x';
Control-D

Get token
curl -X "POST" -u admin https://DNAIP/api/system/v1/auth/token 

Device cleanup
curl -X PUT -H "X-AUTH-TOKEN:INSERT TOKEN" -H "content-type: application/json" -d 'Fill inn UUID' https://DNAIP/api/v1/network-device/sync-with-cleanup?forceSync=true --insecure

The device will resync

Do a manual resync

If this does not help, remove and add the device from DNA
