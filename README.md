=========================================
Introduction
=========================================
This script is designed to leverage the existing VMWare vCenter alarms interface to forward alerts to Nagios.

=========================================
Pre-Install Requirements
========================================= 
 - NRDP Must be installed and configured on the Nagios server

=========================================
Upgrading
=========================================
There is no upgrade path for this plugin. The old plugin should be removed and the full install instructions for this version should be followed.
 
=========================================
Installation
=========================================
Extract the vmware_sender directory onto your vCenter servers. Ensure there are NO SPACES to the extracted path.
*NOTE*: As of the the time of writing, I've been unable to get vCenter to execute a Powershell script if there is a space in the path. If you have a workaround please contact me.

=========================================
Configuration
=========================================
Below is a list of valid commands for the vmware_sender.ini file and what they are for:
[main]  
strip_fqdn - 1 = Remove the fully qualified domain name from a hostname, 0 = Do not remove FQDN from a hostname.  
process_perfdata - 1 = Attempt to process performance data if possible, 0 = Do not process perfdata.  
hostname_case - lower = Convert the hostname to lowercase, upper = convert the hostname to uppercase, first-upper = convert the first letter of a hostname to uppercase, none = do not convert case.  

[logging]  
log_enable - 1 = Enable writing information to the log file, 0 = Do not write to log file.  
log_dir - The directory or full path to the directory that contains the vmware_sender log files.  
log_name - The logfile name.  
log_rotate - daily = Rotate log files daily, weekly = Rotate log files weekly, monthly = Rotate log files monthly 
log_backlogs - Number of backlogs to keep.  

[map_]  
nrdpurl - Nagios NRDP URL e.g. http://nagios/nrdp/  
nrdptoken - The NRDP token required for auth.  
hostname - The Nagios host to send the alarm information to.  
service - The Nagios service on the above host to send the alarm information to.  
state - The state to send to Nagios, this can be in either numeric (0,1,2,3), string(ok, warning, critical, unknown) or vmware(green, yellow, red) format.  
output - The information to display for the alarm in Nagios.  
checktype - 0 = Send alarm as passive, 1 = Send alarm as active.  

Any values assigned to variables under a map_ heading wrapped in dollar ($$) symbols will attempt to access an environment variable.

You can find more information on special VMWare alarm environment variables at: http://pubs.vmware.com/vsphere-4-esx-vcenter/index.jsp?topic=/com.vmware.vsphere.bsa.doc_40/vc_admin_guide/working_with_alarms/r_alarm_environment_variables.html  

=========================================
Usage
=========================================
Command line options:  
./vmware_sender.ps1 [-nrdpurl <Nagios NRDP Url> -nrdptoken <Nagios NRDP Token> -hostname <hostname> -service <service name> -state <nagios or vmware state> -output <Information> -activecheck <0/1>] | [-map <Map Name>] | [-help]  

VMWare execution usage:  
"cmd.exe" "/c echo.|powershell -NonInteractive -File C:\Path\To\vmware_sender\vmware_sender.ps1"  

With no command line options as shown above the script will automatically use map_default in the vmware_sender.ini for its configuration.  

The below example shows you how to define a custom map using map_vsc which is included by default:  
"cmd.exe" "/c echo.|powershell -NonInteractive -File C:\Path\To\vmware_sender\vmware_sender.ps1 -map vsc"  

If you define the hostname or any of the other nagios options via the commandline it will always take precedence anything specified in the INI files.  
Below is a list of all the available command line switches:  
-nrdpurl  
	The URL used to access the remote NRDP agent. i.e. http://nagiosip/nrdp/  
-nrdptoken  
	The authentication token used to access the remote NRDP agent.  
-hostname  
	The name of the host associated with the passive host/service check result.  
-service  
	The name of the service associated with this check result.  
-state  
	The state of the service. Valid values are: OK, Green, WARNING, Yellow, CRITICAL, Red, UNKNOWN  
-output  
	Text output to be sent as the passive check result.  
-activecheck  
    Used to specify active or passive check, 0 = active, 1 = passive. Defaults to passive.  
-help  
	Display this help text.  

=========================================
Patch notes
=========================================
v2.0  
 - Plugin ported to Powershell v2.0  
 - Improved logging, including better output and log rotation.  
 - More options for configuring the Nagios output and how the alarm maps back to Nagios.  
 - Significant improvements to the robustness of the script execution, no more failures to execute by vCenter.  
 - For those crazy enough to try to use it for gathering performance data it now attempts to learn about more kinds of metrics.  

v1.0  
 - First Relase.  