# Generate Self-Signed SSL Certificates for Local Development On A Mac

Have you ever need to develop HTTPS sites locally? To make it work you need to generate a SSL certificate of your own and tell your computer to trust it so you don't get weird Your connection is not private errors in your browser. 

Generating the certs is a complicated hassle. So I made a bash script to do it all for you.

(Props to https://deliciousbrains.com/ssl-certificate-authority-for-local-https-development/ for most of the background info to get this script working)

## How do I use this?
 - Clone or download a zip of this repo
 - Navigate to the directory containing `generate-ssl.sh`
 - Edit the `options.conf` file to add all of the domain names you want included in the certificate
 - Edit the `certificate-authority-options.conf` file if you want to tweak the settings used to generate the certificate authority certificate (optional)
 - Run `sudo ./generate-ssl.sh local.dev` where `local.dev` is the name of the cert that will be generated
 - The script will ask you for your system password which it needs to add the root certificate to Keychain
 - The next prompts for passwords will be just for the generation of the certs. It doesn't matter what your password is so long as you enter the same one every time it asks
 - That's it! Your certificate and private key will be in the `your-certs/` directory. Do with them what you like.

Here is the sample output after running the script:

 ```
sudo ./generate-ssl.sh local.dev
Password:
Generating RSA private key, 2048 bit long modulus
..........+++
..............................................+++
e is 65537 (0x10001)
Enter pass phrase for tmp/local.devCA.key:
Verifying - Enter pass phrase for tmp/local.devCA.key:
Enter pass phrase for tmp/local.devCA.key:
Generating RSA private key, 2048 bit long modulus
...............+++
.........+++
e is 65537 (0x10001)
Signature ok
subject=/C=US/ST=Fake State/L=Fake Locality/O=Fake Company/CN=local.dev
Getting CA Private Key
Enter pass phrase for tmp/local.devCA.key:
All done! Check the your-certs directory for your certs.
 ```

## What does this script do?
When you run this script it will

 - Create a fake certificate authority used to sign your own SSL certificate so your browser will trust it
 - Run all of the `openssl` commands to generate a root certificate (`.pem`) so your system will trust your self-signed certificate, a public certificate (`.crt`) that your server sends to clients, and a private key for the certificate (`.key`) to encrypt and decrypt data sent between the server and client
 - Add the generated root certificate to MacOS' Keychain so the operating system can trust the certificates you sign yourself
 - Reads all options from two configuration files so you can customize things to meet your needs

## "It Didn't Work"

 - `-bash: ./generate-ssl.sh: Permission denied` If the script isn't executeable you can make it executeable by typing: `chmod +x generate-ssl.sh`

 - `OpenSSL isn't installed. You need that to generate SSL certificates.` You can install `openssl` using Brew: `brew install openssl`. If you don't have Brew see https://brew.sh/

 - Open keychain and search for a certificate with the name you passed as an argument to the script. If you ran the script as `sudo ./generate-ssl.sh local.dev` then look for a certificate named `local.dev`

 - Firefox doesn't use the macOS keychain (it maintains its own certificate store), In order for your CA-signed certificates to be recognized by Firefox you'll need to go into the Firefox settings and manually add the `pem` file to Firefox.
 
 ## Other Scripts
  - If you need a more robust solution for Windows or Linux check out https://github.com/FiloSottile/mkcert
