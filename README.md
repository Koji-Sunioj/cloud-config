# What does this thing do?

1. scans AWS for any running EC2 instances with the name "bm_api" and "bm_frontend" (under the credentials of the AWS user set by the system), by running:
```
source config.sh
```
2. if it does not exist, a series of commands are executed for launching two instances with inter-dependencies: "bm_api" instance will act as the rest API for the "bm_frontend" instance, whitelisting it's ipv4 address. "bm_frontend" will forward all api requests to the "bm_api" instance's ipv4 address including authentication.

## How exactly is that done? 

AWS Cli has a command for running instances, and accepts "user-data" which can be commands for iniliazing whatever libraries, packages or software is desired. in this case, the "user-data" is Cloud-init configuration data, which is a more streamlined solution for settings things up. essentially, the bash script waits for the rest API to be initaliazed completely (cloning repos, setting up nginx, fast-api server and sql database) then proceeds to create an instance with the front end code. 

Cloud-init takes about two minutes maximum for it to complete.

## What technologies are utilized?

1. [Cloud-init](https://cloudinit.readthedocs.io/en/latest/reference/examples.html) - standard for cross-platform instance initialization - a more streamlined way to set things up instead of using a list of linux commands, although this also uses commands. 
2. [PostgreSQL](https://www.postgresql.org/) -  modern SQL database engine with added features, such as aggregating JSON among other things. 
3. [FastAPI](https://fastapi.tiangolo.com/tutorial/) - Python based REST API server. Very simple to use, and easy to set up since Ubuntu 22.4 comes with Python 3.10.
4. [Nginx](https://www.nginx.com/) - linux based web server to serve FastAPI to the public web
5. [AWS Cli](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/ec2/index.html) - AWS command line tool for handling EC2 instances.

## What was the point of that?

Let's imagine that high level infrastructure-as-code tools like AWS CDK or Cloud Fomration did not exist. How could we implement similar concepts on our own? In this example, things are being implemented through a combination of bash scripting, command line and cloud-config - which is the lowest level I can currently imagine it.

AWS Cli is quite powerful when combined with Cloud-init, where things can be programmatically set up with your own scripts.

### Things to note

Environment variables are set and interpolated in the .sh file. This can be achieved by editing ~/.bashrc:
```
sudo vim ~/.bashrc
```
Then pasting in the values:
```
export FE_SECRET=whateveryouwant
export DB_PASSWORD=whateveryouwant2
export GUEST_LIST=whateveryouwant3
export ROOT_DB_PASSWORD=whateveryouwant4
```
... and finally running the file to load those values:
```
source ~/.bashrc
```
