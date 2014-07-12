RADAR - Robust multi-Area Distribution Active Routing
=======

What RADAR Does
-----------

In a highly distributed, dynamic, environment where everyone has a mobile computer; determining which specific distribution point/server should be set for a defined network segment can be a daunting task. Add in the fact that some subnets can span multiple buildings, and that subnets can be expanded, reduced, or deleted altogether, and managing this becomes impossible. We want to have the client machine actively monitor the network connection, and notify the JSS which distribution server it should be connecting to based on availability and responsiveness.

In short, *RADAR* allows the client machine to determine the distribution point with the lowest latency and write it back for this computer object in the JSS. The next time a policy requires a package download, it will download from the closest server. Hopefully, this will also be able to do the same for JAMF Distribution Servers (JDS) in the near future when the following feature request is implemented.
https://jamfnation.jamfsoftware.com/featureRequest.html?id=2320

*RADAR* works by spawning a subprocess for each distribution point managed by the JSS. This subprocess first determines if a valid service port is available on a given server, then issues a series of pings for that server and records the average time. These times are then sorted and the quickest one is assumed to be the closest. Note: The assumption is made that the server with the lowest latency also has the highest bandwidth to your client machine. If that is not a reasonably accurate assumption for your infrastructure, it may be best to have network segments with defined distribution points/servers.

Because a subprocess is spawned for each distribution point, rather than working through them sequentially, results can be gathered fairly quickly for even a large number of servers. Actively checking to see if a server is available means that there is a rudimentary, client driven, failover when servers become unavailable. It would still be a good idea to specify failover distribution points in the JSS.

Explanation of Variables
=======
Note on variables with `true` settings. Only the exact, case-sensitive, string `true` is checked for. As long as that variable is not defined elsewhere/globally, setting it to anything other than `true`, or not defining it at all, is equivalent to a value of `false`.

* `WRITE_TO_SYSTEM_LOG` Set to `true` in order for *RADAR* output to be written to system.log.
* `LOGGING_TAG` The tag used by *logger* for system.log entries.


* `JSS_RADAR_API_USER` The Casper API username.
* `JSS_RADAR_API_PASS` The Casper API password.
    + The API username and password need to have read access to the distribution points/servers and read and write access to *computer* objects. For security, it is best to use a special purpose service account that only has these privilages.


* `BLACKLIST_DIST_POINT_ID` An array which defines the ID numbers of distribution points which should never be set for a client machine.
* `BLACKLIST_DIST_SERVER_ID` An array which defines the ID numbers of distribution servers which should never be set for a client machine.
* Uncommment the `BLACKLIST_DIST_POINT/SERVER_ID+=('1')` line(s) to define servers. As many lines as needed can be added.


* `VALIDATE_SHARE_PORT` Set to `true` in order to validate that the default service port on the distribution point is reachable. Otherwise, don't perform any connection testing other than making sure the server is pingable.


* `JSS_IS_PUBLIC` Define as the string `true` in order to specify that your JSS is available on the public internet for API access, not limited access, and that you'd like *RADAR* to run while a machine is on the public internet.


* `INTERNET_URL` A public URL to test if a machine has access to the internet.
* `INTERNET_PORT` An port available on the previously defined server for testing connectivity.


* `CORP_URL` A private URL, only available on your corporate intranet, to test if a machine has access to internal resources.
* `CORP_PORT` An port available on the previously defined server for testing connectivity.


* `VALIDATE_SETTING`  Define as the string `true` in order to specify that, after *RADAR* has attempted to set the server, you'd like it to validate that the server setting was successfully changed. Adds some processing time and, if some network segments have defined distribution points/servers, can generate errors. Can be useful in troubleshooting.


Common Implementation Scenarios
=======

JSS 8.x - Script Stored in the JSS
-----------

Storing the *RADAR* script in the JSS is the most secure method, as you do not have to store the API credentials on your client machines. With JSS 8, there is no built-in method to detect network changes so you need to define a custom trigger. This could be done by installing a LaunchDaemon with a custom jamf trigger, and using a WatchPath for a file which changes on network change. Create a policy with the radar.sh script included, the API username/password defined as the first and second parameters, that uses this custom trigger and it should run this script on any network change.

Example LaunchDaemon:
*/Library/LaunchDaemons/com.company.radartrigger.plist*

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.company.radartrigger</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/sbin/jamf</string>
		<string>policy</string>
		<string>-trigger</string>
		<string>radar</string>
	</array>
	<key>WatchPaths</key>
	<array>
		<string>/private/var/run/resolv.conf</string>
	</array>
</dict>
</plist>
```

JSS 9.x - Script Stored in the JSS
-----------

Storing the *RADAR* script in the JSS is the most secure method, as you do not have to store the API username/password on your client machines. With JSS 9, there is a built-in process which monitors network changes. Create a policy with the radar.sh script, the API username/password defined on the first and second parameters, and have it take action when the `Network State Change` event happens.

Script Stored on Client Machine
-----------

Storing the *RADAR* script on the client machine does expose some additional risk as you will need to also store the API credentials, which have read and write access to computer objects, on the client machine. You can store the password in a file located in a root-only accessible location to mitigate some risk, but that location will still be readable by local administrators and by anyone who has physical access to the machine and can access the decrypted contents of the drive.

However, it does reduce the amount of load on the JSS; which may be not insignificant depending on the number of machines and frequency of network changes. Each network event then won't have to activate a policy and write a policy log locally as well as send it back to the JSS. You could do this by including a LaunchDaemon on the machine to run your script, or integrating it with your existing local client management framework (if you have one deployed).

Example LaunchDaemon:
*/Library/LaunchDaemons/com.company.radar.plist*

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.company.radar</string>
	<key>ProgramArguments</key>
	<array>
		<string>/path/to/radar.sh</string>
	</array>
	<key>WatchPaths</key>
	<array>
		<string>/private/var/run/resolv.conf</string>
	</array>
</dict>
</plist>
```

Limited Access JSS on Public Internet
-----------

If you only have a limited access JSS available on the public internet, *RADAR* will not be able to be used for client machines on the internet. You will need to define network segments for IP ranges which are not on your intranet, and define a default distribution point or JDS for those subnets.

Even if the JSS API is available on the public internet, you can define `JSS_IS_PUBLIC` as `false` to restrict running *RADAR* only when on your corporate intranet. This is useful if you have a number of distribution points on your intranet, but only a limited number on the public internet, and would rather use defined network segments or an external method for geographic traffic routing.

RADAR Only Used for Specific Network Segments
-----------

If you only want *RADAR* to have control on specific network segments, you likely want to make sure that a policy was run recently. Running a policy updates the computer's IP address in the JSS which ensures that the JSS knows which network segment the client machine is currently connected to. Otherwise, the computer could be on a segment controlled by *RADAR* but have that setting not apply because the JSS thinks it's on a different segment.

In this case, you may want to define `WAIT_FOR_JSS_POLICY` as `true`. This is not necessary if *RADAR* is being run by a policy, only if the script is stored locally on the machine.

If the "specific network segment" is intranet versus internet, it might be easier to just  define `JSS_IS_PUBLIC` as `false`.

JSS API Access Available on Public Internet; RADAR Used For All Network Segments
-----------

In the case that no network segments have defined default distribution points/servers, and the JSS API is available on all networks, define `WAIT_FOR_JSS_POLICY` as `false` and define `JSS_IS_PUBLIC` to be `true`. *RADAR* will attempt to set a distribution point whenever the machine is on the internet and the script is run. This ensures that a machine is always pointed at the closest distribution point.

JDS Workaround
=======
There is a workaround you can do in order to get RADAR to also work with JAMF Distribution Servers. It is experimental, and not supported by JAMF or guaranteed to continue working with updates to the Casper Suite. Also, I do not know how often this configuration file is overwritten or modified by the JDS installer or when doing configuration changes. It's probably best to verify that the modifications remain after an upgrade or configuration change to a JDS.

A JDS is basically just an auto-replicating distribution point, with a slightly different layout. As an added benefit, by doing this workaround, you also gain the ability to specify failover distribution points for your JDS servers. However, this may confuse things if you use a hybrid infrastructure with both classic distribution points and JDS servers when you attempt to replicate packages. In this case, I suggest using something in the display name to easily distinguish the type of server at a glance.

1. Create a new File Share Distribution point for each JDS, this is in addition to the JDS already defined.
2. On the *General* tab, specify whatever display name you wish, the correct server name for this JDS, and a failover distribution point.
3. Fill in all the required fields on the *File Sharing* tab with invalid information, you will never be connecting to the JDS to manually replicate.
4. On the *http/https* tab make sure you enabled http downloads, use ssl, and use port 443. For the context enter `JDS`. Authentication type: `None`.
5. On your JDS, you need to edit your apache config to add an alias. The alias directive must be within the `<VirtualHost>` container. I usually put it right at the bottom of the file, immediately before the closing `</VirtualHost>` tag. The file location and alias directive depends on your installed operating system. I believe the following are correct, but please test and let me know if corrections need to be made.
    * **RHEL/CentOS** File: */etc/httpd/conf.d/ssl.conf*
    * `Alias /JDS/Packages /usr/local/jds/shares/CasperShare`
    * **Ubuntu** File: */etc/apache2/sites-enabled/default-ssl*
    * `Alias /JDS/Packages /usr/local/jds/shares/CasperShare`
    * **MacOS** File: */Library/Server/Web/Config/apache2/sites/0000_any_443_.conf*
    * `Alias /JDS/Packages /Library/JDS/shares/CasperShare`
6. Restart apache: `sudo apachectl restart`
7. To test, you should be able to download a specified package from https://jds.company.com/JDS/Packages/Package_Name.dmg

License
=======
Licensed under the BSD-style license found in the LICENSE file in the same directory.