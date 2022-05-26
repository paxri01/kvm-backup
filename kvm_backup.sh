#!/bin/bash

set -e

# Sync method is either 'virt' or 'qemu'.
SYNC_METHOD='qemu'
DOMAIN=${1:-'one-1792'}
DATE=$(date +%Y%m%d)
BACKUP_DIR='/var/lib/libvirt/backup'
XML_DUMP="${BACKUP_DIR}/${DOMAIN}-${DATE}.xml"
RSYNC_USER='libvirt'
RSYNC_TARGET='remote01.domain.local:/var/lib/libvirt/backup'

if [[ ! -d ${BACKUP_DIR} ]]; then
  mkdir -p ${BACKUP_DIR}
fi

logger "Starting KVM backup of $DOMAIN."
echo "Starting KVM backup of $DOMAIN."

# Collect all block devices of the domain
virsh domblklist "$DOMAIN" | tail -n +3 | grep -v '\-$' >> .vm_blk_list

# Collect disk devices on domain
while read -r DEVICE; do
  case "$DEVICE" in
    "vd"*) SOURCE+=("$(awk '{ print $2 }' <<< "$DEVICE")")
           TARGET+=("$(awk '{ print $1 }' <<< "$DEVICE")")
      ;;
    "sd"*) SOURCE+=("$(awk '{ print $2 }' <<< "$DEVICE")")
           TARGET+=("$(awk '{ print $1 }' <<< "$DEVICE")")
      ;;
  esac
done < .vm_blk_list
rm .vm_blk_list

# Collect vm configuration
virsh dumpxml --security-info $DOMAIN > "$XML_DUMP"
sudo -u ${RSYNC_USER} rsync -Shv "$XML_DUMP" "${RSYNC_TARGET}/"

if [[ $SYNC_METHOD == 'virt' ]]; then
  virsh undefine --keep-nvram $DOMAIN
fi

i=0
# Parse list of image files to copy
while (( i < ${#SOURCE[*]} )); do
  _OUT_FILE="${BACKUP_DIR}/${DOMAIN}-${TARGET[$i]}-${DATE}.qcow2"
  logger "Creating $_OUT_FILE ..."
  echo "Creating $_OUT_FILE ..."
  if [[ $SYNC_METHOD == 'virt' ]]; then
    virsh blockcopy $DOMAIN "${TARGET[$i]}" "$_OUT_FILE" --wait --finish
  else
    qemu-img convert -f qcow2 "${SOURCE[$i]}" -O qcow2 "${_OUT_FILE}" -U
  fi

  sudo -u ${RSYNC_USER} rsync -Shv "$_OUT_FILE" "${RSYNC_TARGET}/"
  logger "Finished backup of ${SOURCE[$i]}."
  echo "Finished backup of ${SOURCE[$i]}."
  ((i++))

done

# Don't do this for OpenNebula VMs, allow ON to define.
if [[ $SYNC_METHOD == 'virt' ]]; then
  virsh define "$XML_DUMP"
fi

logger "Domain $DOMAIN backup completed."
echo "Domain $DOMAIN backup completed."
