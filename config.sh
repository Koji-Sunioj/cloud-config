#!/bin/sh
export LC_ALL=C.UTF-8

CheckState() {
        running=0
        instance_state=$(aws ec2 describe-instances --instance-ids $1 \
                --query 'Reservations[].Instances[].State.Name' --output text)

        case $instance_state in

                pending)
                echo "instance in pending state"
                ;;

                running)
                echo "instance is running"
                running=1
                ;;
        esac
        return $running

}

bm_instances=$(aws ec2 describe-instances  --query 'Reservations[].Instances[]' \
	--filters Name=instance-state-name,Values=running Name=tag:Name,Values=bm_server | jq length)
running=0
new_bm_instance=""
pub_key=$(cat ~/.ssh/id_rsa.pub)
config=$(cat <<LINE
#cloud-config

package_update: true

packages:
 - postgresql-14
 - nginx
 - python3-pip

write_files:
 - path: /etc/needrestart/needrestart.conf
   content: \$nrconf{restart} = 'a';
   append: true
 - path: /etc/nginx/sites-available/fast-api.conf
   content: |
     server {
        listen 80;
        location / {
                proxy_pass http://127.0.0.1:8000;
        }
     }

runcmd:
 - git clone https://github.com/Koji-Sunioj/nginx-api.git /home/ubuntu/nginx-api
 - cd /home/ubuntu/nginx-api
 - pip install -r requirements.txt
 - sudo -u postgres psql -c "alter user postgres with password '${ROOT_DB_PASSWORD}';"
 - echo 'localhost:5432:postgres:postgres:${ROOT_DB_PASSWORD}' >> \$HOME/.pgpass
 - echo 'localhost:5432:blackmetal:postgres:${ROOT_DB_PASSWORD}' >> \$HOME/.pgpass
 - chmod 0600 \$HOME/.pgpass
 - export PGPASSFILE="\$HOME/.pgpass"
 - psql -U postgres -h localhost -d postgres -a -f init.sql
 - echo "FE_SECRET=${FE_SECRET}
 - DB_PASSWORD=${DB_PASSWORD} 
 - GUEST_LIST=${GUEST_LIST}" > .env
 - rm /etc/nginx/sites-enabled/default
 - ln -s /etc/nginx/sites-available/fast-api.conf /etc/nginx/sites-enabled/fast-api.conf
 - nginx -s reload
 - python3 -m uvicorn fast:app --reload

users:
  - default
  - name: ubuntu
    ssh_authorized_keys:
      - ${pub_key}
LINE
)

echo $config

if [[ $bm_instances == 0 ]]
then
        new_bm_instance=$(aws ec2 run-instances --count 1 --image-id ami-0c3d6a10a198d282d \
                --security-group-ids sg-0c6e934d0f8aa9a8e --instance-type t4g.nano \
                --output text --query 'Instances[].InstanceId' \
                --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bm_server}]'\
		--user-data="$config")

	echo "$new_bm_instance initialized"

	while [ $running == 0 ]
	do
		echo "waiting for instance to run before login"
		sleep 5s
		CheckState $new_bm_instance
		running=$?
	done
fi

if [[ $running == 1 ]]
then
	bm_instance_dns=$(aws ec2 describe-instances --instance-ids $new_bm_instance \
		--query 'Reservations[].Instances[].PublicDnsName' --output text)
	echo "$new_bm_instance ready to login via: ubuntu@$bm_instance_dns"
fi

