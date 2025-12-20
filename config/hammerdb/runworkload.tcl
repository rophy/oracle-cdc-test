#!/usr/bin/tclsh
puts "HAMMERDB TPROC-C WORKLOAD RUN"
puts "=============================="

wsstart

# Set database to Oracle
dbset db ora

# Connection settings
diset connection system_user system
diset connection system_password "OraclePwd123"
diset connection instance oracle:1521/FREEPDB1

# TPROC-C user settings
diset tpcc tpcc_user TPCC
diset tpcc tpcc_pass TPCCPWD

# Driver settings
diset tpcc ora_driver timed
diset tpcc rampup 2
diset tpcc duration 5
diset tpcc allwarehouse false

# Log to output directory for capture
vuset logtotemp 0
vuset unique 1
vuset logdir /output

puts "Configuration:"
print dict

# Load the TPROC-C driver script
loadscript

puts "\nStarting workload with 8 virtual users..."
puts "Rampup: 2 minutes"
puts "Duration: 5 minutes"

# Set virtual users and run
vuset vu 8
vucreate
vurun

# Wait for test duration plus rampup plus buffer
set total_seconds [expr { (2 + 5 + 2) * 60 }]
puts "Waiting ${total_seconds} seconds for test completion..."
runtimer $total_seconds

vudestroy
after 5000

puts "\nTEST COMPLETE"
puts "Check /output/hammerdb*.log for detailed results"
