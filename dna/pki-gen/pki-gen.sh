#!/usr/bin/env bash

# Create CSR + private key for DNAC
# Optionally creates self-signed root CA and signs the CSR

# make sure we have openssl
if ! command -v openssl &> /dev/null; then
    echo "openssl is required"
    exit
fi

# fix date issue on Mac
if [[ "$OSTYPE" == "darwin"* ]]; then
  date() { gdate "$@"; }
  export -f date
fi

# get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# fetch info from config file
source "${SCRIPT_DIR}/pki-gen.config"

# should we create root CA?
while : ; do
  read -p 'Create self-signed root CA and sign the CSR? [y/n]: ' create_root

  case ${create_root} in
    [yY])
      create_root=true
      break
      ;;
    [nN])
      create_root=false
      break
      ;;
    *)
      echo "Invalid value: ${create_root}"
      ;;
  esac
done

# is it pre/post 2.1.1?
while : ; do
  read -p 'Is DNAC version 2.1.1 or later? [y/n]: ' dnac_version

  case ${dnac_version} in
    [yY])
      dnac_post_211=true
      break
      ;;
    [nN])
      dnac_post_211=false
      break
      ;;
    *)
      echo "Invalid value: ${dnac_version}"
      ;;
  esac
done

# create folders
CERT_PATH="${SCRIPT_DIR}/certs"
mkdir -p ${CERT_PATH}
cd "${CERT_PATH}"

# create root CA if-need-be
if $create_root ; then
  # set password to use for CAs
  while : ; do
    read -sp 'Enter CA password: ' ca_password
    echo
    read -sp 'Verify CA password: ' ca_password_verify

    if [ "$ca_password" == "$ca_password_verify" ]; then
      break
    else
      echo "Passwords do not match. Try again."
    fi
  done

  ROOT_CA="root-ca"
  INTERMEDIATE_CA="intermediate-ca"
  mkdir -p ${CERT_PATH}/${ROOT_CA}/{certreqs,certs,newcerts,private}
  mkdir -p ${CERT_PATH}/${INTERMEDIATE_CA}/{certreqs,certs,newcerts,private}

  # create root CA
  echo -e "#\n# Creating root CA structure\n#"
  cd "${CERT_PATH}/${ROOT_CA}"
  chmod 700 private
  touch root-ca.index
  openssl rand -hex 16 > root-ca.serial

  # print config file
  echo -e "#\n# Creating root CA config\n#"
  sed -e "s|VAR_COUNTRY|${country_name}|g" \
    -e "s|VAR_STATE|${state_name}|g" \
    -e "s|VAR_ORG_NAME|${organization_name}|g" \
    -e "s|VAR_ORG_UNIT|${ou_name}|g" \
    -e "s|VAR_ORG_URL|${org_url}|g" \
    -e "s|VAR_ORG_EMAIL|${org_email}|g" \
    "${SCRIPT_DIR}/root-ca.conf" > root-ca.cnf

  # use config file for future openssl commands
  export OPENSSL_CONF=./root-ca.cnf

  # create new key
  echo -e "#\n# Creating new key for root CA\n#"
  openssl req -new -out root-ca.req.pem -passout pass:${ca_password}
  chmod 400 private/root-ca.key.pem

  # generate root CSR
  echo -e "#\n# Creating root CA CSR\n#"
  openssl req -new \
    -key private/root-ca.key.pem \
    -out root-ca.req.pem \
    -passin pass:${ca_password}

  # show the CSR
  echo -e "#\n# Showing the root CA CSR\n#"
  openssl req -verify -in root-ca.req.pem \
    -noout -text \
    -reqopt no_version,no_pubkey,no_sigdump \
    -nameopt multiline

  # selfsign the CSR
  echo -e "#\n# Selfsign the root CA CSR\n#"
  openssl rand -hex 16 > root-ca.serial
  openssl ca -selfsign -batch \
    -in root-ca.req.pem \
    -out root-ca.cert.pem \
    -extensions root-ca_ext \
    -startdate `date +%y%m%d000000Z -u -d -1day` \
    -enddate `date +%y%m%d000000Z -u -d +10years+1day` \
    -passin pass:${ca_password}

  # show the CA
  echo -e "#\n# Showing the root CA\n#"
  openssl x509 -in ./root-ca.cert.pem \
    -noout -text \
    -certopt no_version,no_pubkey,no_sigdump \
    -nameopt multiline

  # verify
  echo -e "#\n# Verifying the root CA\n#"
  openssl verify -verbose -CAfile root-ca.cert.pem \
      root-ca.cert.pem

  # create intermediate CA
  echo -e "#\n# Creating intermediate CA structure\n#"
  cd "${CERT_PATH}/${INTERMEDIATE_CA}"

  # print config file
  echo -e "#\n# Creating intermediate CA config\n#"
  sed -e "s|VAR_COUNTRY|${country_name}|g" \
    -e "s|VAR_STATE|${state_name}|g" \
    -e "s|VAR_ORG_NAME|${organization_name}|g" \
    -e "s|VAR_ORG_UNIT|${ou_name}|g" \
    -e "s|VAR_ORG_URL|${org_url}|g" \
    -e "s|VAR_ORG_EMAIL|${org_email}|g" \
    "${SCRIPT_DIR}/intermediate-ca.conf" > intermed-ca.cnf

  # use config file for future openssl commands
  export OPENSSL_CONF=./intermed-ca.cnf

  # create files
  chmod 700 private
  touch intermed-ca.index
  openssl rand -hex 16 > intermed-ca.serial

  # create new key
  echo -e "#\n# Creating new key for intermediate CA\n#"
  openssl req -new -out intermed-ca.req.pem -passout pass:${ca_password}
  chmod 400 private/intermed-ca.key.pem

  # generate intermediate CSR
  echo -e "#\n# Creating intermediate CA CSR\n#"
  openssl req -new \
    -key private/intermed-ca.key.pem \
    -out intermed-ca.req.pem \
    -passin pass:${ca_password}

  # show the CSR
  echo -e "#\n# Showing the intermediate CA CSR\n#"
  openssl req -verify -in intermed-ca.req.pem \
    -noout -text \
    -reqopt no_version,no_pubkey,no_sigdump \
    -nameopt multiline

  # copy the CSR to root-ca
  echo -e "#\n# Copying the intermediate CA CSR to root CA certreqs\n#"
  cp intermed-ca.req.pem "${CERT_PATH}/${ROOT_CA}/certreqs/"

  # sign the CSR
  echo -e "#\n# Sign the intermediate CSR with the root CA\n#"
  cd "${CERT_PATH}/${ROOT_CA}"
  export OPENSSL_CONF=./root-ca.cnf

  openssl rand -hex 16 > root-ca.serial
  openssl ca -batch \
    -in certreqs/intermed-ca.req.pem \
    -out certs/intermed-ca.cert.pem \
    -extensions intermed-ca_ext \
    -startdate `date +%y%m%d000000Z -u -d -1day` \
    -enddate `date +%y%m%d000000Z -u -d +5years+1day` \
    -passin pass:${ca_password}

  # check the signed cert
  echo -e "#\n# Showing the intermediate CA\n#"
  openssl x509 -in certs/intermed-ca.cert.pem \
    -noout -text \
    -certopt no_version,no_pubkey,no_sigdump \
    -nameopt multiline

  # verify intermediate CA
  echo -e "#\n# Verifying the intermediate CA\n#"
  openssl verify -verbose -CAfile root-ca.cert.pem \
    certs/intermed-ca.cert.pem

  # copy the intermediate CA
  echo -e "#\n# Copying the intermediate CA\n#"
  cp certs/intermed-ca.cert.pem "${CERT_PATH}/${INTERMEDIATE_CA}/"

  # create the CSR for the issued cert
  cd "${CERT_PATH}/${INTERMEDIATE_CA}"
  export OPENSSL_CONF=./intermed-ca.cnf

  # print config file
  echo -e "#\n# Creating issued CSR config\n#"
  sed -e "s|VAR_COUNTRY|${country_name}|g" \
    -e "s|VAR_STATE|${state_name}|g" \
    -e "s|VAR_ORG_NAME|${organization_name}|g" \
    -e "s|VAR_ORG_UNIT|${ou_name}|g" \
    -e "s|VAR_CN|${common_name}|g" \
    "${SCRIPT_DIR}/issued-cert.conf" > certreqs/dnac.conf

  if $dnac_post_211 ; then
    sed -i -e "s|VAR_KEYUSAGE|${key_usage_post211}|g" certreqs/dnac.conf
    printf "%s\n" "${alt_names_post211[@]}" >> certreqs/dnac.conf
  else
    sed -i -e "s|VAR_KEYUSAGE|${key_usage_pre211}|g" certreqs/dnac.conf
    printf "%s\n" "${alt_names_pre211[@]}" >> certreqs/dnac.conf
  fi

  echo -e "#\n# Creating CSR for issued cert\n#"
  openssl req -new -config certreqs/dnac.conf \
    -keyout private/dnac.key \
    -out certreqs/dnac.csr

  echo -e "#\n# Verifying CSR\n#"
  openssl req -text -noout -verify -in certreqs/dnac.csr

  echo -e "#\n# Signing CSR for issued cert\n#"
  openssl rand -hex 16 > intermed-ca.serial
  openssl ca -batch \
    -in certreqs/dnac.csr \
    -out certs/dnac.pem \
    -passin pass:${ca_password}

  echo -e "#\n# Showing the issued cert\n#"
  openssl x509 -in certs/dnac.pem \
    -noout -text \
    -certopt no_version,no_pubkey,no_sigdump \
    -nameopt multiline

  echo -e "#\n# Verifying the issued cert\n#"
  openssl verify -verbose \
    -CAfile "${CERT_PATH}/${ROOT_CA}/root-ca.cert.pem" \
    -untrusted intermed-ca.cert.pem \
    certs/dnac.pem

  # print relevant stuff
  cd ${CERT_PATH}
  echo -e "#\n# ##### Root CA #####\n#"
  cat ${ROOT_CA}/root-ca.cert.pem

  # print all certs/keys
  echo -e "\n#####\n##### Intermediate CA \n#####"
  cat ${INTERMEDIATE_CA}/intermed-ca.cert.pem

  echo -e "\n#####\n##### Issued cert \n#####"
  cat ${INTERMEDIATE_CA}/certs/dnac.pem

  echo -e "\n#####\n##### Issued cert key \n#####"
  cat ${INTERMEDIATE_CA}/private/dnac.key

  # create chain
  echo -e "#\n# Creating chain\n#"
  cat ${ROOT_CA}/root-ca.cert.pem > dnac-root.pem
  cat ${INTERMEDIATE_CA}/certs/dnac.pem > dnac-chain.pem
  cat ${INTERMEDIATE_CA}/intermed-ca.cert.pem >> dnac-chain.pem
  cat ${ROOT_CA}/root-ca.cert.pem >> dnac-chain.pem
  cat ${INTERMEDIATE_CA}/private/dnac.key > dnac.key

else
  # print config file
  echo -e "#\n# Creating issued CSR config\n#"
  sed -e "s|VAR_COUNTRY|${country_name}|g" \
    -e "s|VAR_STATE|${state_name}|g" \
    -e "s|VAR_ORG_NAME|${organization_name}|g" \
    -e "s|VAR_ORG_UNIT|${ou_name}|g" \
    -e "s|VAR_CN|${common_name}|g" \
    "${SCRIPT_DIR}/issued-cert.conf" > dnac.conf

  if $dnac_post_211 ; then
    sed -i -e "s|VAR_KEYUSAGE|${key_usage_post211}|g" dnac.conf
    printf "%s\n" "${alt_names_post211[@]}" >> dnac.conf
  else
    sed -i -e "s|VAR_KEYUSAGE|${key_usage_pre211}|g" dnac.conf
    printf "%s\n" "${alt_names_pre211[@]}" >> dnac.conf
  fi

  echo -e "#\n# Creating CSR for issued cert\n#"
  openssl req -new -config dnac.conf \
    -keyout dnac.key \
    -out dnac.csr

  echo -e "#\n# Verifying CSR\n#"
  openssl req -text -noout -verify -in dnac.csr

  # echo CSR
  echo -e "\n#####\n##### Cert key \n#####"
  cat dnac.key

  echo -e "\n#####\n##### CSR \n#####"
  cat dnac.csr

fi

