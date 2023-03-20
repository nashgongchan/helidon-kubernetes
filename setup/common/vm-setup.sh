#!/bin/bash

export SETTINGS=$HOME/hk8sLabsSettings

if [ -f $SETTINGS ]
  then
    echo "Loading existing settings information"
    source $SETTINGS
  else 
    echo "No existing settings cannot continue"
    exit 10
fi

if [ -z $COMPARTMENT_OCID ]
then
  echo "Your COMPARTMENT_OCID has not been set, you need to run the compartment-setup.sh before you can run this script"
  exit 2
fi

# We've been given an COMPARTMENT_OCID, let's check if it's there, if so assume it's been configured already
COMPARTMENT_NAME=`oci iam compartment get  --compartment-id $COMPARTMENT_OCID | jq -j '.data.name'`

if [ -z $COMPARTMENT_NAME ]
then
  echo "The provided COMPARTMENT_OCID or $COMPARTMENT_OCID cant be located, please check you have set the correct value in $SETTINGS"
  exit 99
else
  echo "Operating in compartment $COMPARTMENT_NAME"
fi

# Define a timestamp function
TIMESTAMP=`date "+%Y%m%d-%H%M"`

# Define the names for the resources
VCN_NAME="vcn-helidon-kubernetes-$USER_INITIALS"
SUBNET_NAME="subnet-$TIMESTAMP"
INSTANCE_NAME="H-K8S-Lab-A-Helidon-$USER_INITIALS"

# Define the ingress rule parameters
cidr_block="0.0.0.0/0"
protocol="TCP"
destination_port_range="5800-5910"
description="VNC"

# Check if VCN already exists
if [[ $(oci network vcn list --compartment-id "$COMPARTMENT_OCID" --display-name "$VCN_NAME" --query 'data[*].id' --raw-output) ]]; then
  echo "VCN already exists."
else
  # Create VCN
  VCN_ID=$(oci network vcn create --cidr-block "10.0.0.0/16" --compartment-id "$COMPARTMENT_OCID" --display-name "$VCN_NAME" --wait-for-state AVAILABLE --region "$SETUP_REGION" --query 'data.id' --raw-output)
  echo "Created VCN with ID: $VCN_ID"
fi

# Check if subnet already exists
if [[ $(oci network subnet list --compartment-id "$COMPARTMENT_OCID" --display-name "$SUBNET_NAME" --query 'data[*].id' --raw-output) ]]; then
  echo "Subnet already exists."
else
  # Create subnet
  SUBNET_ID=$(oci network subnet create --compartment-id "$COMPARTMENT_OCID" --vcn-id $VCN_ID --display-name "$SUBNET_NAME" --cidr-block "10.0.0.0/24" --wait-for-state AVAILABLE --region "$SETUP_REGION" --query 'data.id' --raw-output)
  echo "Created subnet with ID: $SUBNET_ID"
fi

# Check if instance already exists
if [[ $(oci compute instance list --compartment-id "$COMPARTMENT_OCID" --display-name "$INSTANCE_NAME" --query 'data[*].id' --raw-output) ]]; then
  echo "Instance already exists."
else
  # Create instance
  INSTANCE_ID=$(oci compute instance launch --availability-domain "$(oci iam availability-domain list --query "data[0].name" --raw-output)" --compartment-id "$COMPARTMENT_OCID" --shape "VM.Standard.E3.Flex" --display-name "$INSTANCE_NAME" --subnet-id $SUBNET_ID --image-id "ocid1.image.oc1..aaaaaaaaq73xxgdkpzczyaypsirub75xp75nzogtu5ti5o7ikc6pw2idjmuq" --wait-for-state RUNNING --region "$SETUP_REGION" --query 'data.id' --raw-output)
  echo "Created instance with ID: $INSTANCE_ID"
fi

# Find the security list in the compartment
security_list=$(oci network security-list list --compartment-id "$COMPARTMENT_OCID" "data[*].id | [0]" --raw-output)

if [ -z "$security_list" ]; then
  echo "Security list not found"
  exit 1
fi

# Add the ingress rule to the security list
# oci network security-list update --security-list-id $security_list --ingress-security-rules "[{\"protocol\": \"$protocol\", \"source\": \"$cidr_block\", \"source-type\": \"CIDR_BLOCK\", \"tcp-options\": {\"destination-port-range\": {\"max\": $destination_port_range, \"min\": $destination_port_range}}, \"description\": \"$description\"}]"
oci network security-list update --security-list-id $security_list --ingress-security-rules "[{\"protocol\": \"$protocol\", \"source\": \"$cidr_block\", \"source-type\": \"CIDR_BLOCK\", \"tcp-options\": {\"destination-port-range\": \"$destination_port_range\"}, \"description\": \"$description\"}]"