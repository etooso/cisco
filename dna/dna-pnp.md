# Plug and Play (PnP)

Some PnP notes:

1. Switch must be in Bundle mode not in Install mode.
2. The username/password credentials in the Template must match the CLI credentials configured in DNAC.
3. AAA for local login must be included in the Template, otherwise the sync will fail with credentials error.
4. If Template include enable/configure terminal, it will fail. No need for that in the template.
5. Sync took approximately 30 minutes.
6. We got error when we added the switch to the fabric, though the switch was successfuly added as CP/BN/E node.

## Device cleanup before PnP

**Manually enter commands**

```
conf t
crypto key zeroize
no crypto pki cert pool
end
delete nvram:*
delete flash:pnp*
write erase
delete flash:nvram*
```

**Script for the lazy**

```
! copy the following in "conf t" mode

alias exec prep4pnp event manager run prep4pnp
!
event manager applet prep4pnp
event none sync yes
action a1010 syslog msg "Start: ‘prep4pnp’  EEM applet."
action a1020 puts "Preparing device to be discovered by device automation - This script will reboot the device."
action b1010 cli command "enable"
action c1010 puts "Erasing startup-config."
action c1020 cli command "wr er" pattern "confirm"
!
action c1030 cli command "y"
action d1010 puts "Clearing crypto keys."
action d1020 cli command "config t"
action d1030 cli command "crypto key zeroize" pattern "yes/no"
action d1040 cli command "y"
action e1010 puts "Clearing crypto PKI stuff."
action e1020 cli command "no crypto pki cert pool" pattern "yes/no"
action e1030 cli command "y"
action e1040 cli command "exit"
action f1010 puts "Deleting vlan.dat file."
action f1020 cli command "delete /force vlan.dat"
action g1010 puts "Deleting certificate files in NVRAM."
action g1020 cli command "delete /force nvram:*.cer"
action h0001 puts "Deleting PnP files"
action h0010 cli command "delete /force flash:pnp*"
action h0020 cli command "delete /force nvram:pnp*"
action z1010 puts "Device is prepared for being discovered by device automation.  Rebooting."
action z1020 syslog msg "Stop: 'prep4pnp' EEM applet."
action z1030 reload
!

! then write “prep4pnp” on the CLI and the script will run, clear all and reboot the switch
```
