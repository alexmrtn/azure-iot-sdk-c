#
#  Routines to help *experiment* (not necessarily productize) CA certificates.
#

# This will make PowerShell complain more on unsafe practices
Set-StrictMode -Version 2.0

#
#  Globals
#

# Errors in system routines will stop script execution
$errorActionPreference    = "stop"

$_basePath                   = "."
$_rootCertCommonName         = "Azure IoT CA TestOnly Root CA"
$_rootCertSubject            = "/CN='$_rootCertCommonName'"
$_intermediateCertCommonName = "Azure IoT CA TestOnly Intermediate {0} CA"
$_intermediateCertSubject    = "CN=$_intermediateCertCommonName"
$_privateKeyPassword         = "1234"
$_keyBitsLength              = "4096"
$_days_until_expiration      = 30
$_opensslRootConfigFile      = "$_basePath/openssl_root_ca.cnf"
$_opensslIntermediateConfigFile = "$_basePath/openssl_device_intermediate_ca.cnf"

$rootCAPrefix                = "azure-iot-test-only.root.ca"
$intermediateCAPrefix        = "azure-iot-test-only.intermediate"
$keySuffix                   = "key.pem"
$certSuffix                  = "cert.pem"

$rootCAPemFileName          = "./RootCA.pem"
$intermediate1CAPemFileName = "./Intermediate1.pem"

# Variables containing file paths for Edge certificates
$edgePublicCertDir          = "certs"
$edgePrivateCertDir         = "private"
$edgeDeviceCertificate      = Join-Path $edgePublicCertDir "new-edge-device.cert.pem"
$edgeDevicePrivateKey       = Join-Path $edgePrivateCertDir "new-edge-device.key.pem"
$edgeDeviceFullCertChain    = Join-Path $edgePublicCertDir "new-edge-device-full-chain.cert.pem"
$edgeIotHubOwnerCA          = Join-Path $edgePublicCertDir "azure-iot-test-only.root.ca.cert.pem"

# Whether to use ECC or RSA is stored in a file.  If it doesn't exist, we default to ECC.
$algorithmUsedFile       = "./algorithmUsed.txt"

function Print-WarningCertsNotForProduction()
{
    Write-Warning "This script is provided for prototyping only."
    Write-Warning "DO NOT USE CERTIFICATES FROM THIS SCRIPT FOR PRODUCTION!"
}

# The script puts certs into the global certificate store.  If there is already a cert of the
# same name present, we're not going to be able to tell the new apart from the old, so error out.
function Test-CACertNotInstalledAlready([bool]$printMsg=$true)
{
    if ($TRUE -eq $printMsg)
    {
        Write-Host ("Testing if any test certificates have already been installed...")
    }
    $certInstalled = $null
    try
    {
        $certInstalled = Get-CACertsCertBySubjectName $_rootCertSubject
    }
    catch
    {

    }

    if ($NULL -ne $certInstalled)
    {
        $nl = [Environment]::NewLine
        $cleanup_msg  = "$nl$nl"
        $cleanup_msg += "To fix this, cleanup any certificates in the certificate store and try running this script again.$nl"
        $cleanup_msg += "Steps to cleanup, from Start menu, 'open manage computer certificates':$nl"
        $cleanup_msg += " - Navigate to Certificates -> Trusted Root Certification Authority -> Certificates. Remove certificates issued by 'Azure IoT CA TestOnly*'.$nl"
        $cleanup_msg += " - Navigate to Certificates -> Intermediate Certificate Authorities -> Certificates. Remove certificates issued by 'Azure IoT CA TestOnly*'.$nl"
        $cleanup_msg += " - Navigate to Certificates -> Local Computer -> Personal. Remove certificates issued by 'Azure IoT CA TestOnly*'.$nl"
        $cleanup_msg += "$nl$nl"
        Write-Error("Certificate {0} already installed in the certificate store. {1}" -f $_rootCertSubject,  $cleanup_msg)
        throw ("Certificate {0} already installed." -f $_rootCertSubject)
    }
    if ($TRUE -eq $printMsg)
    {
        Write-Host ("  Ok.")
    }
}

<#
    Verify that the prerequisites for this script are met
#>
function Test-CACertsPrerequisites([bool]$printMsg=$true)
{
    Test-CACertNotInstalledAlready($printMsg)
    if ($TRUE -eq $printMsg)
    {
        Write-Host ("Testing if openssl.exe is set in PATH...")
    }
    if ((Get-Command "openssl.exe" -ErrorAction SilentlyContinue) -eq $NULL)
    {
        throw ("Openssl is unavailable. Please install openssl and set it in the PATH before proceeding.")
    }
    if ($TRUE -eq $printMsg)
    {
        Write-Host ("  Ok.")
        Write-Host ("Success")
    }
}

function PrepareFilesystem()
{
    Remove-Item -Path $_basePath/csr -Recurse -ErrorAction Ignore
    Remove-Item -Path $_basePath/private -Recurse -ErrorAction Ignore
    Remove-Item -Path $_basePath/certs -Recurse -ErrorAction Ignore
    Remove-Item -Path $_basePath/intermediateCerts -Recurse -ErrorAction Ignore
    Remove-Item -Path $_basePath/newcerts -Recurse -ErrorAction Ignore

    MD csr
    MD private
    MD certs
    MD intermediateCerts
    MD newcerts

    Remove-Item -Path $_basePath/index.txt -ErrorAction Ignore
    New-Item $_basePath/index.txt -ItemType file

    Remove-Item -Path $_basePath/serial -ErrorAction Ignore
    New-Item $_basePath/serial -ItemType file
    "01" | Out-File $_basePath/serial
}

function New-PrivateKey([string]$prefix, [string]$keypass=$NULL)
{
    Write-Host ("Creating the $prefix private Key")
    $keyFile = "$_basePath/private/$prefix.$keySuffix"
    $passwordCreateCmd = ""
    if ($keypass -ne $NULL)
    {
        $passwordCreateCmd = "-aes256 -passout pass:$keypass"
    }
    $algorithm = ""

    if ((Get-CACertsCertUseRSA) -eq $TRUE)
    {
        $algorithm = "genrsa $_keyBitsLength"
    }
    else
    {
        $algorithm = "ecparam -genkey -name secp256k1"
        $passwordCreateCmd = "| openssl ec $passwordCreateCmd"
    }

    $cmd = "openssl $algorithm $passwordCreateCmd -out $keyFile"
    Write-Host ("Executing command: $cmd")
    Invoke-Expression -Command $cmd
    return $keyFile
}

function New-IntermediateCACertificate([string]$prefix, [string]$keypass=$NULL, [string]$issuerPrefix)
{
    $keyFile = New-PrivateKey $prefix $keypass
    $certFile = "$_basePath/certs/$prefix.$certSuffix"

}

function New-ClientCertificate()
{

}

function New-RootCACertificate()
{
    Write-Host ("Creating the Root CA private key")
    $keyFile = New-PrivateKey $rootCAPrefix $_privateKeyPassword
    $certFile = "$_basePath/certs/$rootCAPrefix.$certSuffix"

    Write-Host ("Creating the Root CA certificate")
    $passwordUseCmd = "-passin pass:$_privateKeyPassword"
    $cmd =  "openssl req -new -x509 -config $_opensslRootConfigFile $passwordUseCmd "
    $cmd += "-key $keyFile -subj $_rootCertSubject -days $_days_until_expiration "
    $cmd += "-sha256 -extensions v3_ca -out $certFile"

    Write-Host ("Executing command: $cmd")
    Invoke-Expression -Command $cmd

    Write-Host ("CA Root Certificate Generated At:")
    Write-Host ("---------------------------------")
    Write-Host ("    $certFile`r`n")
    Invoke-Expression -Command "openssl x509 -noout -text -in $certFile"
    Print-WarningCertsNotForProduction
}

function New-GenerateIntermediateCertificate([string]$commonName, [string]$signingCert, [bool]$isASigner=$true)
{
    Write-Host ("Creating the Root CA Private Key")
    $keyFile = New-PrivateKey $rootCAPrefix $_privateKeyPassword
    $certFile = "$_basePath/certs/$rootCAPrefix.$certSuffix"

    Write-Host ("Creating intermediate certificate private key")
    $keyFile = "$_basePath/private/$rootCAPrefix.$keySuffix"
    $certFile = "$_basePath/certs/$rootCAPrefix.$certSuffix"
    $passwordCreateCmd = "-aes256 -passout pass:$_privateKeyPassword"
    $algorithm = ""

    if ((Get-CACertsCertUseRSA) -eq $TRUE)
    {
        $algorithm = "genrsa $_keyBitsLength"
    }
    else
    {
        $algorithm = "ecparam -genkey -name secp256k1"
        $passwordCreateCmd = "| openssl ec $passwordCreateCmd"
    }

}

function New-CACertsSelfsignedCertificate([string]$commonName, [object]$signingCert, [bool]$isASigner=$true)
{
    # Build up argument list
    $selfSignedArgs =@{"-DnsName"=$commonName;
                       "-CertStoreLocation"="cert:LocalMachine\My";
                       "-NotAfter"=(get-date).AddDays(30);
                      }

    if ($isASigner -eq $true)
    {
        $selfSignedArgs += @{"-KeyUsage"="CertSign"; }
        $selfSignedArgs += @{"-TextExtension"= @(("2.5.29.19={text}ca=TRUE&pathlength=12"))  ; }
    }
    else
    {
        $selfSignedArgs += @{"-TextExtension"= @("2.5.29.37={text}1.3.6.1.5.5.7.3.2,1.3.6.1.5.5.7.3.1", "2.5.29.19={text}ca=FALSE&pathlength=0")  }
    }

    if ($signingCert -ne $null)
    {
        $selfSignedArgs += @{"-Signer"=$signingCert }
    }

    if ((Get-CACertsCertUseRSA) -eq $false)
    {
        $selfSignedArgs += @{"-KeyAlgorithm"="ECDSA_nistP256";
                             "-CurveExport"="CurveName" }
    }

    # Now use splatting to process this
    Write-Warning ("Generating certificate CN={0} which is for prototyping, NOT PRODUCTION.  It has a hard-coded password and will expire in 30 days." -f $commonName)
    write (New-SelfSignedCertificate @selfSignedArgs)
}


function New-CACertsIntermediateCert([string]$commonName, [Microsoft.CertificateServices.Commands.Certificate]$signingCert, [string]$pemFileName)
{
    $certFileName = ($commonName + ".cer")
    $newCert = New-CACertsSelfsignedCertificate $commonName $signingCert
    Export-Certificate -Cert $newCert -FilePath $certFileName -Type CERT | Out-Null
    Import-Certificate -CertStoreLocation "cert:\LocalMachine\CA" -FilePath $certFileName | Out-Null

    # Store public PEM for later chaining
    openssl x509 -inform der -in $certFileName -out $pemFileName

    del $certFileName

    Write-Output $newCert
}

# Creates a new certificate chain.
function New-CACertsCertChain([Parameter(Mandatory=$TRUE)][ValidateSet("rsa","ecc")][string]$algorithm)
{
    Write-Host "Beginning to install certificate chain to your LocalMachine\My store"
    Test-CACertsPrerequisites($FALSE)
    PrepareFilesystem

    # Store the algorithm we're using in a file so later stages always use the same one (without forcing user to keep passing it around)
    Set-Content $algorithmUsedFile $algorithm

    New-RootCACertificate

    $intermediateCert1 = New-CACertsIntermediateCert ($_intermediateCertCommonName -f "1") $rootCACert $intermediate1CAPemFileName
    $intermediateCert2 = New-CACertsIntermediateCert ($_intermediateCertCommonName -f "2") $intermediateCert1 $intermediate2CAPemFileName
    Write-Host "Success"
}

# Get-CACertsCertUseEdge retrieves the algorithm (RSA vs ECC) that was specified during New-CACertsCertChain
function Get-CACertsCertUseRsa()
{
    Write-Output ((Get-Content $algorithmUsedFile -ErrorAction SilentlyContinue) -eq "rsa")
}

function Get-CACertsCertBySubjectName([string]$subjectName)
{
    $certificates = gci -Recurse Cert:\LocalMachine\ |? { $_.gettype().name -eq "X509Certificate2" }
    $cert = $certificates |? { $_.subject -eq $subjectName -and $_.PSParentPath -eq "Microsoft.PowerShell.Security\Certificate::LocalMachine\My" }
    if ($NULL -eq $cert)
    {
        throw ("Unable to find certificate with subjectName {0}" -f $subjectName)
    }

    Write-Output $cert
}

function New-CACertsVerificationCert([string]$requestedCommonName)
{
    $verifyRequestedFileName = ".\verifyCert4.cer"
    $rootCACert = Get-CACertsCertBySubjectName $_rootCertSubject
    Write-Host "Using Signing Cert:::"
    Write-Host $rootCACert

    $verifyCert = New-CACertsSelfsignedCertificate $requestedCommonName $rootCACert $false

    Export-Certificate -cert $verifyCert -filePath $verifyRequestedFileName -Type Cert
    if (-not (Test-Path $verifyRequestedFileName))
    {
        throw ("Error: CERT file {0} doesn't exist" -f $verifyRequestedFileName)
    }

    Write-Host ("Certificate with subject CN={0} has been output to {1}" -f $requestedCommonName, (Join-Path (get-location).path $verifyRequestedFileName))
}


function New-CACertsDevice([string]$deviceName, [string]$signingCertSubject=$_rootCertSubject, [bool]$isEdgeDevice=$false)
{
    $newDevicePfxFileName = ("./{0}.pfx" -f $deviceName)
    $newDevicePemAllFileName      = ("./{0}-all.pem" -f $deviceName)
    $newDevicePemPrivateFileName  = ("./{0}-private.pem" -f $deviceName)
    $newDevicePemPublicFileName   = ("./{0}-public.pem" -f $deviceName)

    $signingCert = Get-CACertsCertBySubjectName $signingCertSubject ## "CN=Azure IoT CA TestOnly Intermediate 1 CA"

    # Certificates for edge devices need to be able to sign other certs.
    if ($isEdgeDevice -eq $true)
    {
        $isASigner = $true
    }
    else
    {
        $isASigner = $false
    }

    $newDeviceCertPfx = New-CACertsSelfSignedCertificate $deviceName $signingCert $isASigner

    $certSecureStringPwd = ConvertTo-SecureString -String $_privateKeyPassword -Force -AsPlainText

    # Export the PFX of the cert we've just created.  The PFX is a format that contains both public and private keys but is NOT something
    # clients written to IOT Hub SDK's now how to process, so we'll need to do some massaging.
    Export-PFXCertificate -cert $newDeviceCertPfx -filePath $newDevicePfxFileName -password $certSecureStringPwd
    if (-not (Test-Path $newDevicePfxFileName))
    {
        throw ("Error: CERT file {0} doesn't exist" -f $newDevicePfxFileName)
    }

    # Begin the massaging.  First, turn the PFX into a PEM file which contains public key, private key, and bunches of attributes.
    # We're closer to what IOTHub SDK's can handle but not there yet.
    openssl pkcs12 -in $newDevicePfxFileName -out $newDevicePemAllFileName -nodes -password pass:$_privateKeyPassword

    # Now that we have a PEM, do some conversions on it to get formats we can process
    if ((Get-CACertsCertUseRSA) -eq $true)
    {
        openssl rsa -in $newDevicePemAllFileName -out $newDevicePemPrivateFileName
    }
    else
    {
        openssl ec -in $newDevicePemAllFileName -out $newDevicePemPrivateFileName
    }
    openssl x509 -in $newDevicePemAllFileName -out $newDevicePemPublicFileName

    Write-Host ("Certificate with subject CN={0} has been output to {1}" -f $deviceName, (Join-Path (get-location).path $newDevicePemPublicFileName))
}

function New-CACertsEdgeDevice([string]$deviceName, [string]$signingCertSubject=($_intermediateCertSubject -f "1"))
{
    New-CACertsDevice $deviceName $signingCertSubject $true
}

function Write-CACertsCertificatesToEnvironment([string]$deviceName, [string]$iothubName, [bool]$useIntermediate)
{
    $newDevicePemPrivateFileName  = ("./{0}-private.pem" -f $deviceName)
    $newDevicePemPublicFileName  = ("./{0}-public.pem" -f $deviceName)

    $rootCAPem          = Get-CACertsPemEncodingForEnvironmentVariable $rootCAPemFileName
    $devicePublicPem    = Get-CACertsPemEncodingForEnvironmentVariable $newDevicePemPublicFileName
    $devicePrivatePem   = Get-CACertsPemEncodingForEnvironmentVariable $newDevicePemPrivateFileName

    if ($useIntermediate -eq $true)
    {
        $intermediate1CAPem = Get-CACertsPemEncodingForEnvironmentVariable $intermediate1CAPemFileName
    }
    else
    {
        $intermediate1CAPem = $null
    }

    $env:IOTHUB_CA_X509_PUBLIC                 = $devicePublicPem + $intermediate1CAPem + $rootCAPem
    $env:IOTHUB_CA_X509_PRIVATE_KEY            = $devicePrivatePem
    $env:IOTHUB_CA_CONNECTION_STRING_TO_DEVICE = "HostName={0};DeviceId={1};x509=true" -f $iothubName, $deviceName
    if ((Get-CACertsCertUseRSA) -eq $true)
    {
        $env:IOTHUB_CA_USE_ECC = "0"
    }
    else
    {
        $env:IOTHUB_CA_USE_ECC = "1"
    }

    Write-Host "Success"
}

# Outputs certificates for Edge device using naming conventions from tutorials
function Write-CACertsCertificatesForEdgeDevice([string]$deviceName)
{
    $originalDevicePublicPem  = ("./{0}-public.pem" -f $deviceName)
    $originalDevicePrivatePem  = ("./{0}-private.pem" -f $deviceName)

    if (-not (Test-Path $edgePublicCertDir))
    {
        mkdir $edgePublicCertDir | Out-Null
    }

    if (-not (Test-Path $edgePrivateCertDir))
    {
        mkdir $edgePrivateCertDir | Out-Null
    }

    Copy-Item $originalDevicePublicPem $edgeDeviceCertificate
    Copy-Item $originalDevicePrivatePem $edgeDevicePrivateKey
    Get-Content $originalDevicePublicPem, $intermediate1CAPemFileName, $rootCAPemFileName | Set-Content $edgeDeviceFullCertChain
    Copy-Item $rootCAPemFileName $edgeIotHubOwnerCA
    Write-Host "Success"
}

# This will read in a given .PEM file and output it in a format that we can
# immediately set ENV variable in it with \r\n done right.
function Get-CACertsPemEncodingForEnvironmentVariable([string]$fileName)
{
    $outputString = $null
    $data = Get-Content $fileName
    foreach ($line in $data)
    {
        $outputString += ($line + "`r`n")
    }

    Write-Output $outputString
}

Print-WarningCertsNotForProduction
