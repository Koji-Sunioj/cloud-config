# What does this thing do?

1. scans AWS for any running EC2 instances with the name "bm_server"
2. if it does not exist, a new one is created with an Ubuntu ami, using t4g.nano (the cheapest available). user data is passed as cloud-config file which has utilities for writing data to configuration files, setting up the server, cloning repositories and initializing a database. the public key from requesting system is also passed to the config so that the user can log in securely without a .pem file. file is passed as plain text instead of from file, to easier pass environment variables from linux system to it.

## What technologies are utilized?

1. [Cloud-init](https://cloudinit.readthedocs.io/en/latest/reference/examples.html) - standard for cross-platform instance initialization - a more streamlined way to set things up instead of using a list of linux commands, although this also uses commands. 
2. [PostgreSQL](https://www.postgresql.org/) -  modern SQL database engine with added features, such as aggregating JSON among other things. 
3. [FastAPI](https://fastapi.tiangolo.com/tutorial/) - Python based REST API server. Very simple to use, and easy to set up since Ubuntu 22.4 comes with Python 3.10.
4. [Nginx](https://www.nginx.com/) - linux based web server to serve FastAPI to the public web
5. [AWS Cli](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/ec2/index.html) - AWS command line tool for handling EC2 instances.

## What was the point of that?

Well, to see how launching and configuring an EC2 instance with bells and whistles without using some high level tool like AWS CDK. This is see how things are done from a very low level. AWS Cli is quite powerful when combined with Cloud-init, where things can be programmatically set up with your own scripts.

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
```
... and finally running the file to load those values:
```
source ~/.bashrc
```
