#!/usr/bin/tclsh
puts "HAMMERDB TPROC-C SCHEMA BUILD"
puts "=============================="

# Set database to Oracle
dbset db ora

# Connection settings
diset connection system_user system
diset connection system_password "OraclePwd123"
diset connection instance oracle:1521/FREEPDB1

# TPROC-C schema settings
diset tpcc tpcc_user TPCC
diset tpcc tpcc_pass TPCCPWD
diset tpcc tpcc_def_tab TBLS1
diset tpcc count_ware 1
diset tpcc num_vu 1

puts "Configuration:"
print dict

puts "\nBuilding schema with 1 warehouse..."
buildschema
