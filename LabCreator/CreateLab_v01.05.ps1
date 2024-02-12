# VMName: The name of the new VM to create
# VMPath: Where to create the VM's files
# DiskType: Differencing, Fixed, or Dynamic (the default). No value = Dynamic.
# DiffParent: Used when DiskType = Dynamic. Specifies the parent for the differencing disk
# DiskSize: Used if DiskType = Fixed or Dynamic (or blank). Size in GB for the new VHDX
# ProcessorCount: How many vCPUs the VM will have
# StartupRAM: Amount in MB that the VM will boot up with (Dynamic Memory or not)
# DynamicMemory: Yes or No (default). Do you enable DM or not?
# MinRAM: Amount in MB for Minimum RAM if DM is enabled.
# MaxRAM: Amount in MB for Maximum RAM if DM is enabled.
# MemPriority: 0-100 value if for Memory Weight DM is enabled
# MemBuffer: 5-2000 value for Memory Buffer is DM is enabled
#############Write-Host "Name:             "$VMName
#############Write-Host "VM location:      "$VMBaseLocation = VMPath
#############Write-Host "Memory:           "$VMMemory = StartupRam
#############Write-Host "Ref Disk:         "$VMRefDisk = = DiffParent
#############"Network:                     "$VMNetwork = SwitchName
#"Template file: 2 by OS (Domain or WRKGRP):    "$UAtpl
#"Password:                                     "$PW
#"IP:                                           "$IP
#"Default Gateway:                              "$GW
#"DNS Server:                                   "$DNS

#[CmdletBinding()]
Param ( 
    [Alias("InputFile")]
	[String] $In="vms.csv"
)

$PSScriptRoot = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent

$DataStamp = get-date -Format yyyyMMddTHHmmss

# Clear the screen
cls

#If($In -notcontains "\")
#{
#	$CSVPath = $PSScriptRoot + "\Src_VMS" + $In
#}else{
	$CSVPath = $In
#}
#$CSVPath = $PSScriptRoot + "\" + "VMs.csv"
#$CSVPath = $PSScriptRoot + "\" + "VM.csv"
#$CSVPath = $PSScriptRoot + "\" + "vms7.csv"
$LogPath = $PSScriptRoot + "\Logs\" + "VMsLog_$DataStamp.txt"
$FolderOEM = $PSScriptRoot + "\OEM\*"


# Remove the log file
Remove-Item -Path $LogPath -ErrorAction SilentlyContinue

Function ActiveTPM
{
	param (
	 [parameter(Mandatory=$true)]
	 [ValidateNotNullOrEmpty()]$VMName
	)
	
	# Check if TPM already installed
	$TPMENable = get-vmsecurity $VMName
	$TpmVMStatus = $TPMENable.TpmEnabled	
	if("$TpmVMStatus" -eq "False")
	{
		try
		{
			Set-VMKeyProtector -VMName $VMName -NewLocalKeyProtector
			
		}
		catch{
			# old method
			$owner=Get-HgsGuardian untrustedguardian
			$kp=New-HgsKeyProtector -Owner $owner -AllowUntrustedRoot
			Set-VMKeyProtector -VMName $VMName -KeyProtector $kp.RawData
			#get-vmsecurity $VMName
		}
		Enable-VMTPM $VMName
	}
}


Function CheckAvailableMemoryBeforeStartingVM
{
	param(
		[parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]$VMName,
		[parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]$VMMemory		
	)
	
	$ComputerMemory =  Get-WmiObject -Class WIN32_OperatingSystem
	$TotalMemory = $ComputerMemory.TotalVisibleMemorySize
	$FreeMemory = $ComputerMemory.FreePhysicalMemory
    $Memory = ((($TotalMemory - $FreeMemory)*100)/ $TotalMemory)
	$MemLimit4VM = ($VMMemory*1.5)
    
	write-host -BackgroundColor Green -ForegroundColor White "Checking $VMName : $VMMemory/$FreeMemory KBytes free - RatioFreeMem : $Memory"
	if(($Memory -lt 90) -and (($FreeMemory) -gt $MemLimit4VM ) )
	{
		# Starting VM
		Write-Host -BackgroundColor Green -ForegroundColor White "Starting VM: " + $VMName + " ..."
        #Always let the VM start for 2 secs, no matter what!
		Start-Sleep -Seconds 2
	}
	else{
		Write-Host -BackgroundColor Red -ForegroundColor White "SAFETY FIRST : Waiting 240 Seconds for Memory: please free Mem ..."
		#Always let the VM start for 5 secs, no matter what!
		Start-Sleep -Seconds 240
	}
}

Function WorkingHours
{
    #Wait for Disk Queue to get under 2 before firing a new VM!
    While (((Get-Counter -ComputerName MOUSE "\\mouse\\disque physique(_total)\taille de file d’attente du disque actuelle" ).Countersamples).CookedValue -gt 2){
		Write-Host -BackgroundColor Green -ForegroundColor White "WORKING HOURS : Waiting 5 Seconds to continue...Storage spike (over 2)!"
		Start-Sleep -Seconds 5
    }
}

Function AggressiveProvisionning
{
    #SAFETY - Big Tempo for Big queue - That one should stay, High risk of Storage Freeze
    While (((Get-Counter -ComputerName MOUSE "\\mouse\\disque physique(_total)\taille de file d’attente du disque actuelle" ).Countersamples).CookedValue -gt 25){
		Write-Host -BackgroundColor Red -ForegroundColor White "SAFETY FIRST : Waiting 60 Seconds for Storage: Queue Lenght WAY TOO HIGH (over 20)...Someone said SSD?"
		Start-Sleep -Seconds 60
    }

    #PERF - Little Tempo for little queue - Can be bypassed Off Working Hours also
    #While (((Get-Counter -ComputerName MOUSE "\\mouse\\disque physique(_total)\taille de file d’attente du disque actuelle" ).Countersamples).CookedValue -gt 7){
    #Write-Host -BackgroundColor DarkGray -ForegroundColor White "PERF : Waiting 5 Seconds for Storage: Queue Lenght too high (over 7)..."
    #Start-Sleep -Seconds 5
    #}
}


Import-Csv $CSVPath | ForEach-Object {

	# Construct some paths
	$Path = $_.VMPath
	$VMName = $_.VMName
	$VHDPath = "$Path\$VMName"
	$SwitchName = $_.SwitchName
	$generation = $_.VMGen
	$VMEnableTPM = $_.VMEnableTPM
	$VMParent = $_.DiffParent -replace '[d-f]?\:\\SyspreppedVHDX\\MADREF_',"" -replace ".vhdx" ,""

	
	#Ajouts pour Unattend.xml basé sur Template
	$Unattend = $_.Unattend
	$LPASSWORD = $_.LPASSWORD
	$IP = $_.IP
	$GW = $_.GW
	$DNS = $_.DNS
	$DJDOMAIN = $_.DJDOMAIN
	$DJPASSWORD = $_.DJPASSWORD 
	$DJUSERNAME = $_.DJUSERNAME
	#write-host $PW
	
	# Only create the virtual machine if it does not already exist
	if ((Get-VM $VMName -ErrorAction SilentlyContinue))
    {
		Add-Content $LogPath "FAIL: $VMName already existed."
    }
    else
    {

		# Create a new folder for the VM if it does not already exist
		if (!(Test-Path $VHDPath))
		{ 
			New-Item -Path $VHDPath -ItemType "Directory"
		}

		# Create a new folder for the VHD if it does not already exist
		if (!(Test-Path "$VHDPath\Virtual Hard Disks"))
		{    
			$VhdDir = New-Item -Path "$VHDPath\Virtual Hard Disks" -ItemType "Directory"
		}

		# Create the VHD if it does not already exist
		$NewVHD = "$VhdDir\$VMName-Disk0.vhdx"
		if (!(Test-Path $NewVHD))
		{
			# Have to set these variables because $_.Variables are not available inside the switch.
			$ParentDisk = $_.DiffParent
			$DiskSize = [int64]$_.DiskSize * 1073741824
			switch ($_.DiskType)
			{
				'Differencing' {New-VHD -Differencing -Path $NewVHD -ParentPath $ParentDisk}
				'Fixed' {New-VHD -Fixed -Path $NewVHD -SizeBytes $DiskSize}
				Default {New-VHD -Dynamic -Path $NewVHD -SizeBytes $DiskSize}
			}
			if (Test-Path $NewVHD)
			{
				Add-Content $LogPath "  Progress: $NewVHD was created."
			}
			else
			{
				Add-Content $LogPath "  Error: $NewVHD was not created."
			}
		}
		else
		{
			Add-Content $LogPath "  Progress: $NewVHD already existed"
		}


		 # Mount the disk to insert Unattend.xml if available
		 # And pushes the variables from CSV in XML.
		 # Unmount the drive.
		 #
		 # $VMLocation = New-Item -Path "$VMBaseLocation\$VMName" -ItemType Directory -Force
		 # $VMDiskLocation = New-Item -Path "$VMLocation\Virtual Hard Disks" -ItemType Directory -Force
		 # $VMDisk01 = New-VHD –Path $VMDiskLocation\$VMName-OSDisk.vhdx -Differencing –ParentPath $VMRefDisk 
		 # $VMDisk02 = New-VHD –Path $VMDiskLocation\$VMName-DataDisk01.vhdx -SizeBytes 60GB
		 # $VM = New-VM –Name $VMname –MemoryStartupBytes $VMMemory –VHDPath $VMDisk01.path -SwitchName $VMNetwork -Path $VMBaseLocation
		 # Add-VMHardDiskDrive -VM $VM -Path $VMDisk02.path –ControllerType SCSI -ControllerNumber 0
		 # Set-VM -VM $VM -DynamicMemory
	
		 $TEMPVHD = "$VhdDir\$VMName-Disk0.vhdx"

		 Mount-DiskImage -ImagePath $TEMPVHD

		 $VHDImage = Get-DiskImage -ImagePath $TEMPVHD | Get-Disk | Get-Partition | Get-Volume | Where-Object { $_.Size -gt 2048000000 }
		 $VHDDrive = [string]$VHDImage.DriveLetter
		 $VHDDrive = $VHDDrive + ":"

		 $UAXml = Join-Path $VHDDrive "\unattend.xml"
		 copy $unattend $UAXml

			foreach ($str in $UAxml) 
			{
				$content = Get-Content -path $str
				$content | foreach {$_ -replace "OSDComputerName", $VMNAME} | Set-Content $str
			}

			foreach ($str in $UAxml) 
			{
				$content = Get-Content -path $str
				$content | foreach {$_ -replace "LPASSWORD", $LPASSWORD} | Set-Content $str
			}
			foreach ($str in $UAxml) 
			{
				$content = Get-Content -path $str
				$content | foreach {$_ -replace "DJDOMAIN", $DJDOMAIN} | Set-Content $str
			}
			foreach ($str in $UAxml) 
			{
				$content = Get-Content -path $str
				$content | foreach {$_ -replace "DJPASSWORD", $DJPASSWORD} | Set-Content $str
			}
			foreach ($str in $UAxml) 
			{
				$content = Get-Content -path $str
				$content | foreach {$_ -replace "DJUSERNAME", $DJUSERNAME} | Set-Content $str
			}           
			foreach ($str in $UAxml) 
			{
				$content = Get-Content -path $str
				$content | foreach {$_ -replace "OSDIP", $IP} | Set-Content $str
			}

			foreach ($str in $UAxml) 
			{
				$content = Get-Content -path $str
				$content | foreach {$_ -replace "OSDDNS", $DNS} | Set-Content $str
			}

			foreach ($str in $UAxml) 
			{
				$content = Get-Content -path $str
				$content | foreach {$_ -replace "OSDGW", $GW} | Set-Content $str
			}
			
			#Adding specific on VHDDisk
			copy-item "$FolderOEM" -Destination "$VHDDrive\" -Recurse -Force


			
			Dismount-DiskImage -ImagePath $TEMPVHD
  
			# $VMDisk02 = New-VHD –Path $VMDiskLocation\$VMName-DataDisk01.vhdx -SizeBytes 60GB
			# Add-VMHardDiskDrive -VM $VM -Path $VMDisk02.path –ControllerType SCSI -ControllerNumber 0

	
			# Create the VM
			New-VM -Name $_.VMName -Generation $generation -Path $Path -SwitchName $_.SwitchName -VHDPath $NewVHD -MemoryStartupBytes ([int64]$_.StartupRam * 1048576)

			# Configure the processors
			Set-VMProcessor $_.VMName -Count $_.ProcessorCount

			# Configure Dynamic Memory if required
			If ($_.DynamicMemory -Eq "Yes")
			{
				Set-VMMemory -VMName $_.VMName -DynamicMemoryEnabled $True -MaximumBytes ([int64]$_.MaxRAM * 1048576) -MinimumBytes ([int64]$_.MinRAM * 1048576) -Priority $_.MemPriority -Buffer $_.MemBuffer
			}

			# Record the result
			if ((Get-VM $VMName -ErrorAction SilentlyContinue))
			{
				Add-Content $LogPath "Success: $VMName was created."
			}
			else
			{
				Add-Content $LogPath "FAIL: $VMName was created."
			}

			#Activation TPM or Not
			if("$VMEnableTPM" -eq "Y")
			{
				ActiveTPM -VMName $VMName
			}
			
		
			#Throttling function goes here!
			#WorkingHours or AggressiveProvisionning
			#WorkingHours

			# Starting VM
			CheckAvailableMemoryBeforeStartingVM -VMName $VMName -VMMemory ([int64]$_.MaxRAM*1024)
			Start-vm -Name $VMName
            #Get VM serial (vm must be running at the time) 
            $VMSerial="NULL"    
            $wmiVMObject = Get-WmiObject -Namespace root\virtualization\v2 -Class Msvm_ComputerSystem -Filter "ElementName='$VMName'"
            $settings = $wmiVMObject.GetRelated('Msvm_VirtualSystemSettingData') 
            $VMSerial = $settings.BIOSSerialNumber

           		
            #Adding VM Notes
            $VMNotes = "OSRef: " + $VMParent + "; TPM: " + $VMEnableTPM + "; DOMAIN: " + $DJDOMAIN + "; SERIALNUMBER:" + $VMSerial 
			Set-VM -name $VMName -Notes "$VMNotes"      

	}


		#Uncomment to connect to each VM created to follow up setup (test phase)
		vmconnect localhost $VMName
		
}