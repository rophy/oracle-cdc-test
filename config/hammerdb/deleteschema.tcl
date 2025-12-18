#!/usr/bin/tclsh
puts "HAMMERDB TPROC-C SCHEMA DELETE"
puts "==============================="

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

# TPROC-C user to delete
diset tpcc tpcc_user TPCC

puts "Deleting TPROC-C schema for user TPCC..."
deleteschema
wait_to_complete
