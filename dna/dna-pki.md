# Certificate, PKI & CSR for Cisco DNAC

It's recommended to use a "well known CA" to issue the certificate to DNAC. Pre DNAC 2.1.1, we require SAN IP entries to be added for the cluster IPs (per-node cluster and enterprise IP, in addition to VIPs), which are often in the form of RFC1918 IP addresses. As of DNAC 2.1.1 this is no long a requirement.

The "well known" is somewhat confusing. Public CAs has since around 2015 not been allowed to issue certificates with SAN IP entries containing RFC1918 IP addresses, so pre DNAC 2.1.1 the only way was to use self-signed certificates (either ad-hoc, or issued by organization PKI). Cisco TAC clarified that "organization PKI CA" is what they mean with "well known CA".

The easiest is to create a CSR using OpenSSL, issue the certificate from the organizational internal PKI, and then upload it to the DNAC. If no organizational internal PKI is available, a self-signed root CA can be utilized.

1. Download the contents of the "pki-gen" folder
2. Edit "pki-gen.config", and run "pki-gen.sh" (openssl is required)
3. It will generate CSR and/or root/intermediate CA based on input
4. If you chose to only generate CSR, get this signed by CA of your choice (internal or whatnot). Make sure it has 2+ years validity (DNAC complains if it's less than 723 days), and the required keyUsage fields (it has to match the CSR)
5. Upload the root CA certificate to DNAC Trustpool (System Settings -> Settings -> Trustpool)
6. Upload certificate chain to DNAC in format of your choosing, including the key. Make sure it contains all certificates (root + intermediate + issued). If PEM, the chain order needs to be; 1) issued cert, 2) intermediate cert, 3) root cert.

If this is done on an exisiting setup (i.e. after ISE has been set up, and devices has been provisioned), the following must now be done;

1. Edit ISE-settings (System Settings -> Settings -> Authentication and Policy Servers), choose the ISE-server(s) added
2. Enter the ISE-password again, and hit "Apply"
3. Verify that new root CA has been added to trusted certificates on ISE (Administration -> System -> Certificates -> Trusted certificates)
4. Make sure ISE-status remains green (System Settings -> System 360 -> bottom left)

If you have to change the certificate after adding devices, we need to manually change it on all the devices using a template.

1. Download the CA cert in PEM format from http://dnac-fqdn-or-ip/ca/pem
2. Navigate to "Tools > Template editor"
3. Create a "New Project > Template"
4. Use the following for the contents of the template:

```
#INTERACTIVE
no crypto pki trustpoint DNAC-CA<IQ>yes/no<R>yes
#ENDS_INTERACTIVE
#set($multiCommandTag = "MLTCMD")
crypto pki trustpoint DNAC-CA
enrollment mode ra
enrollment terminal
usage ssl-client
revocation-check crl none
exit
<$multiCommandTag>
crypto pki authenticate DNAC-CA
-----BEGIN CERTIFICATE-----
<<< copy the PEM certificate contents/DNAC-CA downloaded from http://dnac-fqdn-or-ip/ca/pem >>>
-----END CERTIFICATE-----
quit
yes
</$multiCommandTag>
```

5. Save and commit the template.
6. Either add the template to existing network profile, or create a new profile; "Design > Network Profiles > Create a new profile".
7. Make sure that the profile is assigned to the sites in the hierarchy where you want to apply it.
8. Re-provision the devices, this will apply the template.
9. Once all devices have been reprovisioned, you can un-assign the template and/or network profile to avoid that the template gets applied on each subsequent provisioning.
