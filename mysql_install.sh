#!/bin/sh

#yuzhaoge
#yum  install libaio libaio-devel -y
#apt  install libaio-dev libaio1 -y


data_root_dir="data"

read  -p  "Please Input a mysql port:"  -t 30  mysql_port

mysqlTarFile="mysql-5.7.26-linux-glibc2.12-x86_64.tar.gz"

mysqld_version=$(echo ${mysqlTarFile} | awk  -F "-" '{print $2}')
base_dir="/usr/local/mysql/${mysqld_version}"

#create mysql group if not exists
egrep "^mysql" /etc/group >&  /dev/null
if [ $? -ne 0 ]
then
    groupadd mysql
fi

#create mysql user if not exists
egrep "^mysql" /etc/passwd >& /dev/null
if [ $? -ne 0 ]
then
    useradd -g mysql -s /sbin/nologin -M mysql
fi

if [ -d /${data_root_dir}/mysql/${mysql_port} ]
then
    echo "mysql data target /${data_root_dir}/mysql/${mysql_port} already exists, please consider to check it"
    exit 2
else
    mkdir -p /${data_root_dir}/mysql/${mysql_port}
    mkdir -p /${data_root_dir}/mysql/${mysql_port}/data
    mkdir -p /${data_root_dir}/mysql/${mysql_port}/logs
    mkdir -p /${data_root_dir}/mysql/${mysql_port}/tmp
    chown -R mysql:mysql /${data_root_dir}/mysql/${mysql_port}
fi


if [ ! -d ${base_dir} ]
then
    mkdir ${base_dir}  -p
    echo "untar and unzip mysql tar file........."
    tar zxvf ${mysqlTarFile} -C  ${base_dir} --strip-components 1
    chown -R mysql:mysql ${base_dir}
fi


cat > /${data_root_dir}/mysql/${mysql_port}/my.cnf << EOF
[mysqld]
user 	  = mysql
port      = ${mysql_port}
server_id = $(echo $RANDOM)${mysql_port} 
basedir   = ${base_dir}
datadir   = /${data_root_dir}/mysql/${mysql_port}/data
log_bin   = /${data_root_dir}/mysql/${mysql_port}/logs/mysql-bin
relay_log = /${data_root_dir}/mysql/${mysql_port}/logs/relay-log
tmpdir    = /${data_root_dir}/mysql/${mysql_port}/tmp
socket    = /${data_root_dir}/mysql/${mysql_port}/data/mysqld.sock
pid_file  = /${data_root_dir}/mysql/${mysql_port}/data/mysqld.pid
log_error = error.log
log-output  = TABLE,FILE

# BINLOG
binlog_error_action  = ABORT_SERVER
binlog_format        = row
binlog_rows_query_log_events = 1
log_slave_updates      = 1
max_binlog_size        = 250M
sync_binlog            = 1
expire_logs_days       = 14
master_info_repository = TABLE
relay_log_info_repository = TABLE
relay_log_recovery      = 1


# GTID #
gtid_mode = ON
enforce_gtid_consistency = 1

# ENGINE
default_storage_engine  = InnoDB
innodb_buffer_pool_size = 128M
innodb_data_file_path   = ibdata1:1G:autoextend
innodb_file_per_table   = 1
innodb_flush_log_at_trx_commit=1
innodb_flush_method    = O_DIRECT
innodb_io_capacity     = 1000
innodb_log_buffer_size = 64M
innodb_log_file_size   = 512M
innodb_log_files_in_group  = 2
innodb_max_dirty_pages_pct = 60
innodb_print_all_deadlocks =1
innodb_stats_on_metadata   = 0
innodb_strict_mode         = 1
innodb_max_undo_log_size   =4G
innodb_undo_log_truncate   =1
innodb_read_io_threads     = 8
innodb_write_io_threads    = 8
innodb_purge_threads       = 8
innodb_buffer_pool_load_at_startup  = 1
innodb_buffer_pool_dump_at_shutdown = 1
innodb_buffer_pool_dump_pct  =25
innodb_sort_buffer_size      = 8M
innodb_buffer_pool_instances = 8

#WRITE SET
binlog_transaction_dependency_tracking = WRITESET
transaction_write_set_extraction       = XXHASH64

# CACHE
key_buffer_size     = 32M
tmp_table_size      = 32M
max_heap_table_size = 32M
table_open_cache    = 1024
query_cache_type    = 0
query_cache_size    = 0
max_connections     = 2000
thread_cache_size   = 1024
open_files_limit    = 65535
binlog_cache_size   = 1M
join_buffer_size    = 8M
sort_buffer_size    = 8M

# SEMISYNC #
plugin_load = "rpl_semi_sync_master=semisync_master.so;rpl_semi_sync_slave=semisync_slave.so"

# SLOW LOG AND GENERAL LOG
slow_query_log        = 1
slow_query_log_file   = slow.log
long_query_time       = 1
log_slow_admin_statements = 1
log_slow_slave_statements = 1
general_log            = 0
general_log_file       = /data/mysql/3307/data/general.log

# MISC
log_timestamps         = SYSTEM

lower_case_table_names = 1
max_allowed_packet     = 64M
skip_external_locking  = 1
skip_name_resolve      = 1
skip_slave_start        = 1
disabled_storage_engines = ARCHIVE,BLACKHOLE,EXAMPLE,FEDERATED,MEMORY,MERGE,NDB
character_set_server    = utf8mb4
secure_file_priv        = ""
explicit_defaults_for_timestamp = 1
performance-schema-instrument ='wait/lock/memory/metadata/sql/mdl=ON'


# MTS
slave-parallel-type         = LOGICAL_CLOCK
slave_parallel_workers      = 16
slave_preserve_commit_order = 1

EOF

chown mysql:mysql /${data_root_dir}/mysql/${mysql_port}/my.cnf

## initialize mysql data
echo 
echo "initializing mysql data........."
${base_dir}/bin/mysqld --defaults-file=/${data_root_dir}/mysql/${mysql_port}/my.cnf --initialize-insecure
if [ "$?" -ne 0 ]
then
  echo "mysql data initialize failed, please check mysql-error log for detail"
  exit 2
else
  echo "mysql datadir initialize success"
fi


#backup
mv /etc/systemd/system/mysqld_${mysql_port}.service /tmp/mysqld_${mysql_port}.service.bak.$(date +%FT%H:%M:%S) > /dev/null 2>&1

cat > /etc/systemd/system/mysqld_${mysql_port}.service << EOF
# Copyright (c) 2015, Oracle and/or its affiliates. All rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
#
# systemd service file for MySQL forking server
#

[Unit]
Description=MySQL Server
After=network.target
After=syslog.target

[Install]
WantedBy=multi-user.target

[Service]
User=mysql

Restart=on-failure

Type=forking

PIDFile=/${data_root_dir}/mysql/${mysql_port}/data/mysqld.pid

TimeoutStartSec=0
TimeoutStopSec=30

# Set cgroups which systemd support
TasksMax=infinity

# Start main service
ExecStart=${base_dir}/bin/mysqld --defaults-file=/${data_root_dir}/mysql/${mysql_port}/my.cnf --daemonize --port=${mysql_port}

PrivateTmp=false

LimitNOFILE = 65535
LimitNPROC = 65535

EOF

systemctl daemon-reload
if [ $? -ne 0 ]
then
   echo "systemctl daemon reload failed please check it manaually"
else 
   echo "systemctl daemon reload success"
fi 
$(which mysql > /dev/null 2>&1)
if [ $? -ne 0 ]
then
    echo 
    #echo "export PATH=\$PATH:${base_dir}/bin" >> /etc/profile 
fi

echo "all finshed, Use systemctl start/stop/status/disable/enable mysqld_${mysql_port}.service to manage mysqld process......"
