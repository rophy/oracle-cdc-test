#!/usr/bin/tclsh
puts "HAMMERDB TPROC-C WORKLOAD RUN"
puts "=============================="

# Set database to Oracle
dbset db ora

# Connection settings
diset connection system_user system
diset connection system_password "OraclePwd123"
diset connection instance oracle:1521/FREEPDB1

# TPROC-C user settings
diset tpcc tpcc_user TPCC
diset tpcc tpcc_pass TPCCPWD

# Driver settings - timed test
diset tpcc ora_driver timed
diset tpcc total_iterations 1000
diset tpcc rampup 0
diset tpcc duration 1
diset tpcc allwarehouse false

# Virtual user settings
vuset logtotemp 1
vuset unique 1

puts "Configuration:"
print dict

# Load the TPROC-C driver script
loadscript

puts "\nStarting workload with 1 virtual user..."
puts "Rampup: 0 minutes, Duration: 1 minute"

# Set virtual users and run
vuset vu 1
vucreate
set jobid [vurun]
vudestroy

puts "\nTEST COMPLETE - Job ID: $jobid"
