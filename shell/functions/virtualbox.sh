#!/usr/bin/env bash
# VirtualBox management functions

function vbox_clone_volume() {
  local inputfile=$1
  local outputfile=$2
  local fileformat=VDI
  VBoxManage clonemedium disk "${inputfile}" "${outputfile}" --format ${fileformat}
}

function vbox_compress_volume() {
  local vm="$1"
  IFS=$'\n'
  local volpath
  volpath=$(VBoxManage showvminfo --machinereadable "$vm" | grep -E ".vdi" | awk -F'"' '{ print $4 }')
  VBoxManage modifyhd "$volpath" --compact
  unset IFS
}

function vbox_list() {
  vboxmanage list vms
}

function vbox_export() {
  local vm="$*"
  vboxmanage export "${vm}" -o "${vm}".ova
  echo -e "Exporting the file to ${PWD}/${vm}.ova\n"
}

function vbox_import() {
  local vm_file="$*"
  vboxmanage import "${vm_file}"
}

function vbox_bandwidth_control_list() {
  local vm="$1"
  VBoxManage bandwidthctl "$vm" list
}

function vbox_bandwidth_control_disable_shaping() {
  local vm="$1"
  VBoxManage modifyvm "$vm" --nicbandwidthgroup1 none
}

function vbox_bandwidth_control_remove_limit_group() {
  local vm="$1"
  VBoxManage bandwidthctl "$vm" remove Limit
}

function vbox_bandwidth_control_limit() {
  local vm="$1"
  local limit="$2"
  VBoxManage bandwidthctl "$vm" add Limit --type network --limit "$limit"
  VBoxManage modifyvm "$vm" --nicbandwidthgroup1 Limit
}

function vbox_all_compress_volume() {
  for list in $(vbox_list | cut -d' ' -f1 | tr -d '"'); do
    IFS=$'\n'
    vbox_compress_volume "$list"
    unset IFS
  done
}
