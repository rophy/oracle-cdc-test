#!/usr/bin/tclsh
puts "HAMMERDB TPROC-C SCHEMA BUILD"
puts "=============================="

global complete
proc wait_to_complete {} {
  global complete
  set complete [vucomplete]
  if {!$complete} {
    after 5000 wait_to_complete
  } else {
    exit
  }
}

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
diset tpcc count_ware 10
diset tpcc num_vu 4

puts "Configuration:"
print dict

puts "\nBuilding schema with 10 warehouses..."
buildschema
wait_to_complete
