#!/bin/bash
#
# a simple script to dump and rotate Perfect World backups
#
# Copyright (c) 2016 Harris Marfel (hrace009)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

## set default variables
backup_root=			                                  # root directory for all backups
v=true					                                    # verbose output
keep=1					                                    # number of old backups to keep
hash=sha256				                                  # crypto hash to use for checksums
costumfilename=                                     # backup file name
target_backup=                                      # backup target
pwlogs_folder=                                      # pw logs folder
weblogs_folder=                                     # website logs folder
gdrive_folder=                                      # google drive folder ID

# set mysqldump options
dumpopts='--single-transaction --flush-logs --flush-privileges'

## don't edit below this line

# get our options
while getopts qk:h: opt; do
  case $opt in
  q)
      v=false
      ;;
  k)
      keep=$OPTARG 
      ;;
  h)
      hash=$OPTARG 
      ;;
  esac
done
shift $((OPTIND - 1))

# set a righteous mask
umask 0027

# create backup path
stamp=`date +%Y-%m-%d.%H%M%S`
backup_dir=${backup_root}/${stamp}
mkdir -p ${backup_dir}
$v && printf 'Keeping %s backups.\n' $keep
$v && printf 'Backup location: %s\n' $backup_dir

## set some functions

# get a list of databases to backup (strip out garbage and internal databases)
_get_db_list () {
  mysqlshow | \
    sed -r '/Databases|information_schema|performance_schema/d' | \
    awk '{ print $2 }'
}

# get a list of backups in the backup directory, ignore files and links
# make this a pattern match later
_get_backups () {
  (cd $backup_root && find ./* -maxdepth 1 -type d -exec basename {} \;)
}

# create checksums
_checksum () {
  sum=`openssl $hash $1 | cut -d' ' -f2`
  printf '%s %s\n' $sum `basename $1`
}

# dump database
_dump_db () {
   #nice -n 19 mysqldump $dumpopts $1 | nice -n 19 gzip
	nice -n 19 mysqldump $1 | nice -n 19 gzip
}

# backup spesific folder
_backuppwdata () {
	printf 'Backing up Perfect World data...\n'
	cd $target_backup
	nice -n 19 tar -zcpf $backup_dir/$costumfilename.tar.gz $target_backup
	printf ' done.\n'
}

# clear logs folder
_clearpwlogs () {
	printf 'Clear Perfect World Logs...\n'
	find $pwlogs_folder -type f -print | while read i
	do
 		cat /dev/null > "$i"
	done
}

# clear website logs folder
_clearweblogs () {
	printf 'Clear Web Logs...\n'
	find $weblogs_folder -type f -print | while read i
	do
 		cat /dev/null > "$i"
	done
}

# get the database list and remove garbage
db_list=`_get_db_list`

# run the backup
for db in $db_list; do
   $v && printf 'Backing up "%s" database...' $db
   _dump_db $db > ${backup_dir}/${db}.sql.gz
   _checksum ${backup_dir}/${db}.sql.gz >> ${backup_dir}/${hash^^}SUMS
   $v &&printf ' done.\n'
done

sync; echo 3 > /proc/sys/vm/drop_caches
sleep 5
_backuppwdata
sleep 5
_clearpwlogs
sleep 5
_clearweblogs
sleep 5
_checksum ${backup_dir}/${costumfilename}.tar.gz >> ${backup_dir}/${hash^^}SUMS

# create a link to current backup
(cd $backup_root && rm -f latest && ln -s ${stamp} latest)

# find out how many backup directories are in the root
dirnum=`_get_backups | wc -l`
diff=$(expr $dirnum - $keep)

# figure out if we need to delete any old backups
if [ "$diff" -gt "0" ]; then
  $v && printf 'Removing %s old backup(s):\n' $diff
  for d in `_get_backups | sort | head -n $diff`; do
    $v && printf '  %s\n' $d
    rm -rf ${backup_root}/${d}
  done
else
  $v && printf 'No old backups to remove (found %s).\n' $dirnum
fi

# chmod folder and files
find $backup_root -type d -exec chmod 755 {} \;
find $backup_root -type f -exec chmod 644 {} \;
sleep 10
sync; echo 3 > /proc/sys/vm/drop_caches

# send backup to google drive
/usr/local/bin/gdrive sync upload --keep-remote $backup_root $gdrive_folder
sync; echo 3 > /proc/sys/vm/drop_caches
