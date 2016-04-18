#! /usr/bin/env bash

############################################################
#
# pxeinstall.sh
#
# Installing GNU/Linux to disk, upon PXE boot.
#
############################################################

############################################################
#
# get_config_name
#
# Parse kernel cmdline and get configfile name. 
#
############################################################

get_config_name() {
	sed -nre 's/(^config=|^.* config=)([^ ]+).*$/\2/; T; p' /proc/cmdline
}

############################################################
#
# umount_misk_fs
#
# Unmount filesystems: devfs, procfs, sysfs.
#
############################################################
umount_misk_fs() {
	local err_msg=
	local point=

	for point in dev sys proc; do
		egrep -q "/mnt/${point}" /proc/mounts
		if [ "$?" -eq 0 ]; then
			log "Unmount ${point}fs."
			err_msg=`umount -l /mnt/${point} 2>&1 1>/dev/null`
			if [ "$?" -ne 0 ]; then
				error "Failed unmount ${point}fs: ${err_msg}"
			fi
		fi
	done
}

############################################################
#
# umount_rootfs
#
# Unmount root filesystem.
#
############################################################
umount_rootfs() {
	local err_msg=
	local point=${root_dev}1

	egrep -q "${point}" /proc/mounts
	if [ "$?" -eq 0 ]; then
		err_msg=$(umount /dev/${point} 2>&1 1>/dev/null)
		if [ "$?" -ne 0 ]; then
			error "Disk /dev/${point} is mounted. Try unmount failed: ${err_msg}"
		fi
	fi
	
	return 0
}


############################################################
#
# mk_rootfs_part
#
# Cleaning disk and create MBR partition table.
# Creating partition for root filesystem.
#
############################################################
mk_rootfs_part() {
	local err_msg=

	log "Clean MBR."
	err_msg=$(dd if=/dev/zero of=/dev/${root_dev} bs=512 count=1 2>&1 1>/dev/null)
	if [ "$?" -ne 0 ]; then
		warning "Failed cleaned MBR: ${err_msg}"
	fi

	log "Remove GPT partition table."
	err_msg=$(echo -e "mklabel msdos\nYes\nquit\n" parted /dev/${root_dev} 2>&1 1>/dev/null)
	if [ "$?" -ne 0 ]; then
		warning "Failed remove GPT: ${err_msg}"
	fi

	log "Create DOS partition table and a new partition for ${root_dev}."
	err_msg=$(echo -e "o\nn\np\n1\n\n\nw" | fdisk /dev/${root_dev} 2>&1 1>/dev/null)
	if [ "$?" -ne 0 ]; then
		error "Can't create new partition: ${err_msg}"
	fi
}

############################################################
#
# mk_rootfs
#
# Formatting root partition in ext4 filesystem.
#
############################################################
mk_rootfs() {
	local err_msg=
	local root_part=/dev/${root_dev}1

	log "Create ext4 filesystem from ${root_part}."
	err_msg=$(mkfs.ext4 ${root_part} 2>&1 1>/dev/null)
	if [ "$?" -ne 0 ]; then 
		error "Can't create filesystem: ${err_msg}"
	fi
}

############################################################
#
# os_setup_pre
#
# Preparing root device. Mount.
#
############################################################
os_setup_pre() {
	local err_msg=
	local root_part=/dev/${root_dev}1

	log "Check mount dir."
	if [ ! -d "/mnt" ]; then
		log "Create /mnt" && mkdir /mnt
	fi
	log "Mount local disk."
	ERR_MSG=$(mount -t ext4 ${root_part} /mnt 2>&1 1>/dev/null)
	if [ "$?" -ne 0 ]; then
		error "Can't mount local filesystem: ${err_msg}"
	fi
}

############################################################
#
# change_root_password
#
# Password change to the one that in the config or default.
#
############################################################
change_root_password() {
	local err_msg=
	local password=${root_password:-"password"}

	log "Set root password."
	err_msg=$(chroot /mnt/ echo "root:"${password}"" | chpasswd 2>&1 1>/dev/null)
	if [ "$?" -ne 0 ]; then
		error "Failed set root password: ${err_msg}"
	fi
}

############################################################
#
# permit_ssh_root_login
#
# Allow root login via SSH.
#
############################################################
permit_ssh_root_login() {
	local err_msg=

	log "Permit ssh root login."
	err_msg=$(sed -i '/PermitRootLogin/d' /mnt/etc/ssh/sshd_config 2>&1 1>/dev/null)
	if [ "$?" -ne 0 ]; then
		warning "Failed permit ssh root login: ${err_msg}"
	fi
	err_msg=$(echo "PermitRootLogin yes" | tee -a /mnt/etc/ssh/sshd_config 2>&1)
	if [ "$?" -ne 0 ]; then
		warning "Failed permit ssh root login: ${err_msg}"
	fi
}

############################################################
#
# os_setup
#
# Copy and decompresing root filesystem archive.
#
############################################################
os_setup() {
	local err_msg=

	if [ -z ${archive} ]; then
		error "archive must be specified in config file."
	fi

	log "Copy and untar rootfs."
	err_msg=$(tar -xf /srv/images/$archive -C /mnt 2>&1 1>/dev/null)
	if [ "$?" -ne 0 ]; then
		error "Can't extract rootfs from ${archive}: ${err_msg}"
	fi

}

############################################################
#
# fix_root_device <file>
# 
# Change root device name in <file>.
#
############################################################
fix_root_device() {
	local err_msg=
	local root_part=/dev/${root_dev}1

	err_msg=$(chroot /mnt sed -i "s|/dev/[sv]d[a-z][0-9]|${root_part}|g" "$1" 2>&1 1>/dev/null)
	if [ "$?" -ne 0 ]; then
		warning "Failed fix root device for "$1": ${err_msg}"
	fi
}

############################################################
#
# copy_grub_cfg <path>
#
# Copying GRUB config to <path> or to /mnt/boot/grub/grub.cfg.
# Change root device to UUID from grub.cfg
#
############################################################
copy_grub_cfg() {
	local err_msg=
	local uuid=
	local grub_cfg=${grub_cfg:-""}
	local root_part=/dev/${root_dev}1
	local dest_grub_cfg=${1:-"/mnt/boot/grub/grub.cfg"}

	if [ -n "${grub_cfg}" ]; then
		log "Copy grub.cfg"
		err_msg=$(cp ${grub_cfg} ${dest_grub_cfg} 2>&1 1>/dev/null)
		if [ "$?" -ne 0 ]; then
			error "Failed copy grub.cfg."
		fi
		uuid=`blkid -s UUID -o value ${root_part}`
		log "Add UUID to grub.cfg."
		err_msg=$(sed -i "s|root=/dev/[sv]d[a-z][0-9]|root=UUID=${uuid}|" ${dest_grub_cfg} 2>&1 1>/dev/null)
		if [ "$?" -ne 0 ]; then
			warning "Failed add UUID to grub.cfg: ${err_msg}"
		fi
	fi
}

############################################################
#
# msvs_grub_cfg
#
# Copying GRUB config from MCBC Linux.
#
############################################################
msvs_grub_cfg() {
	local err_msg=

	if [ "yes" == "${mcvs_update_grub_cfg}" ]; then
		log "Update MCBC /etc/grub.conf"
		copy_grub_cfg "/mnt/etc/grub.conf"
		copy_grub_cfg "/mnt/boot/grub/grub.conf"
	fi
}

############################################################
#
# do_grub
#
# Install GRUB and update GRUB config.
#
############################################################
do_grub() {
	local err_msg=

	log "Install GRUB."
	err_msg=$(grub-install --no-floppy --root-directory=/mnt /dev/${root_dev} 2>&1 1>/dev/null)
	if [ "$?" -ne 0 ]; then
		error "Can't install GRUB: ${err_msg}"
	fi

	log "Mount devfs, sysfs, procfs."
	err_msg=$(mount -t proc none /mnt/proc && mount --bind /dev/ /mnt/dev/ && mount --bind /sys/ /mnt/sys/ 2>&1 1>/dev/null)
	if [ "$?" -ne 0 ]; then
		error "Failed mount devfs, sysfs, procfs: ${err_msg}"
	fi

	fix_root_device "/etc/fstab"

	log "Update GRUB."
	err_msg=$(chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg 2>&1 1>/dev/null)
	if [ $? -ne 0 ] ; then
		err_msg=$(chroot /mnt /bin/sh -c 'echo -e "find /boot/grub/grub.conf\nroot (hd0,0)\nsetup (hd0)\n" |grub' 2>&1 1>/dev/null)
	fi
	if [ "$?" -ne 0 ]; then
		warning "Failed update GRUB: ${err_msg}"
	fi
}

############################################################
#
# copy_initramfs
#
# Copying iniramfs image.
#
############################################################
copy_initramfs() {
	local err_msg=
	local initram=${initram:-""}

	if [ -n "${initram}" ]; then
		log "Install initrd.img."
		err_msg=$(cp -f ${initram} /mnt/boot/initrd.img 2>&1 1>/dev/null)
		if [ "$?" -ne 0 ]; then
			warning "Failed copy initrd.img: ${err_msg}"
		fi
	fi
}

os_setup_post() {
	local err_msg=

	log "Remove udev rules."
	err_msg=$(chroot /mnt/ rm -f /etc/udev/rules.d/* 2>&1 1>/dev/null)
	if [ "$?" -ne 0 ]; then
		error "Failed remove udev rules: ${err_msg}"
	fi
}

#set -e
cd $(dirname $0)

log_file=/var/log/pxeinstall.log
if [ -r "./logging.sh" ]; then
	. ./logging.sh
fi

path_to_configs=/etc/pxeinstall

config=$(get_config_name)
if [ "${config}" == "live" ]; then
	exit 0
fi

log "Starting PXE installation."
if [ -z ${config} ]; then
	error "No configuration file is specified."
fi
log "Configuration $config"
# read config
if [ -r ${path_to_configs}/${config} ]; then
	. ${path_to_configs}/${config}
else
	error "Can't read configuration file."
fi

log "Check local disks ${root_dev}."
sfdisk -l /dev/${root_dev} 1>/dev/null 2>&1
if [ "$?" -ne 0 ]; then
	error "Device to install (${root_dev}) not found."
fi

log "Check already mounted devfs, sysfs, procfs."
umount_misk_fs

log "Check already mounted rootfs."
umount_rootfs

mk_rootfs_part
mk_rootfs
os_setup_pre
os_setup
change_root_password
permit_ssh_root_login

msvs_grub_cfg
do_grub
copy_grub_cfg
copy_initramfs 
os_setup_post
umount_misk_fs
umount_rootfs

log "Congratulation! PXE installation was successful."
reboot
