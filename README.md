# automount_part_data
mount a partition in format " EXT[2-3-4] " or " NTFS  automatically every time you start your computer .

This is a script that mounts an "EXT2/3/4" or "NTFS" format partition at each boot.
it modifies the /etc/fstab file and all the necessary commands to obtain a folder that is readable and writable by the current user, with the "LABEL" of his choice.

For example, if I choose the LABEL: ‘Data’, then in the end I can write, create folders, in short anything I want, in the following folder: /media/Data/iznobe-Data.
The script also creates the recycle bin or trash for the current user.

Command to download and execute this script : 

<code>sudo su -c "bash <(wget -qO- https://raw.githubusercontent.com/iznobe/automount_part_data/refs/heads/main/automount_part_data.sh)"</code>
