#!/bin/sh
export LC_ALL=C.UTF-8

CheckState() {
        init_done=0
        raw_status=$(ssh ubuntu@$1 -o StrictHostKeyChecking=no cloud-init status)
        echo "$raw_status... at $(date +"%T")"
        init_status="${raw_status##*: }"

        case $init_status in

                "done")
                init_done=1
                ;;

                "running" | "not started")
                ;;

                *)
                ;;
        esac
        return $init_done

}

bm_instances=$(aws ec2 describe-instances  --query 'Reservations[].Instances[]' \
	--filters Name=instance-state-name,Values=running Name=tag:Name,Values=bm_server | jq length)
config_done=0
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
 - gunicorn -k uvicorn.workers.UvicornWorker -D fast:app

users:
  - default
  - name: ubuntu
    ssh_authorized_keys:
      - ${pub_key}
LINE
)

if [[ $bm_instances == 0 ]]
then
    new_bm_instance=$(aws ec2 run-instances --count 1 --image-id ami-0c3d6a10a198d282d \
            --security-group-ids sg-0c6e934d0f8aa9a8e --instance-type t4g.nano \
            --output text --query 'Instances[].InstanceId' \
            --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bm_server}]'\
    --user-data="$config")

    echo "$new_bm_instance initialized"
    
    bm_instance_dns=$(aws ec2 describe-instances --instance-ids $new_bm_instance \
    --query 'Reservations[].Instances[].PublicDnsName' --output text)

    echo "$bm_instance_dns booting"

    while [ $config_done == 0 ]
    do
        sleep 5s
        CheckState $bm_instance_dns
        config_done=$?
    done
fi

if [[ $running == 1 ]]
then
    echo "ready"
    bm_server_ipv4=$(aws ec2 describe-instances --instance-ids $new_bm_instance \ 
        --query 'Reservations[].Instances[].PublicIpAddress' --output text)
fi

