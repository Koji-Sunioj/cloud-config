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

bm_apis=$(aws ec2 describe-instances  --query 'Reservations[].Instances[]' \
	--filters Name=instance-state-name,Values=running Name=tag:Name,Values=bm_api | jq length)

bm_frontends=$(aws ec2 describe-instances  --query 'Reservations[].Instances[]' \
	--filters Name=instance-state-name,Values=running Name=tag:Name,Values=bm_frontend | jq length)

api_config_done=0

frontend_config_done=0

new_bm_api_id=""

new_bm_frontend_id=""

bm_api_ipv4=""

frontend_ipv4=""

pub_key=$(cat ~/.ssh/id_rsa.pub)

api_config=$(cat <<LINE
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
 - sed -i 's/LOGIN PASSWORD/LOGIN PASSWORD '\''${DB_PASSWORD}'\''/' init.sql 
 - psql -U postgres -h localhost -d postgres -a -f init.sql
 - echo "FE_SECRET=${FE_SECRET}
 - DB_PASSWORD=${DB_PASSWORD} 
 - GUEST_LIST=${GUEST_LIST}" > .env
 - rm /etc/nginx/sites-enabled/default
 - ln -s /etc/nginx/sites-available/fast-api.conf /etc/nginx/sites-enabled/fast-api.conf
 - nginx -s reload
 - gunicorn -k uvicorn.workers.UvicornWorker -D main:app

users:
  - default
  - name: ubuntu
    ssh_authorized_keys:
      - ${pub_key}
LINE
)




if [[ $bm_apis == 0 ]] && [[ $bm_frontends == 0 ]]
then
    new_bm_api_id=$(aws ec2 run-instances --count 1 --image-id ami-0c3d6a10a198d282d \
        --security-group-ids sg-0c6e934d0f8aa9a8e --instance-type t4g.nano \
        --output text --query 'Instances[].InstanceId' \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bm_api}]'\
        --user-data="$api_config")

    echo "rest API instance $new_bm_api_id initialized"
    
    bm_api_dns=$(aws ec2 describe-instances --instance-ids $new_bm_api_id \
        --query 'Reservations[].Instances[].PublicDnsName' --output text)

    echo "$bm_api_dns booting"

    while [ $api_config_done == 0 ]
    do
        sleep 10s
        CheckState $bm_api_dns
        api_config_done=$?
    done

    if [[ $api_config_done == 1 ]]
    then
        bm_api_ipv4=$(aws ec2 describe-instances --instance-ids $new_bm_api_id \
            --query 'Reservations[].Instances[].PublicIpAddress' --output text)
    fi
fi

frontend_config=$(cat <<LINE
#cloud-config

package_update: true

packages:
 - nginx

write_files:
 - path: /etc/needrestart/needrestart.conf
   content: \$nrconf{restart} = 'a';
   append: true

runcmd:
 - git clone https://github.com/Koji-Sunioj/blackmetal.git /var/www/blackmetal
 - git clone https://github.com/Koji-Sunioj/nginx-block.git /etc/nginx/sites-available/nginx-block
 - sed -i 's/localhost:8000/${bm_api_ipv4}/g' /etc/nginx/sites-available/nginx-block/blackmetal.conf 
 - rm /etc/nginx/sites-enabled/default
 - ln -s /etc/nginx/sites-available/nginx-block/blackmetal.conf /etc/nginx/sites-enabled/blackmetal.conf
 - nginx -s reload

users:
  - default
  - name: ubuntu
    ssh_authorized_keys:
      - ${pub_key}
LINE
)

if [[ ${#bm_api_ipv4} > 0 ]] && [[ $api_config_done == 1 ]]
then
    echo "ready to configure front end instance with ipv4 from rest API $new_bm_api_id with ip $bm_api_ipv4"

    new_bm_frontend_id=$(aws ec2 run-instances --count 1 --image-id ami-0c3d6a10a198d282d \
        --security-group-ids sg-0c6e934d0f8aa9a8e --instance-type t4g.nano \
        --output text --query 'Instances[].InstanceId' \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bm_frontend}]'\
        --user-data="$frontend_config")
    
    echo "front end instance $new_bm_frontend_id initialized"
    
    bm_frontend_dns=$(aws ec2 describe-instances --instance-ids $new_bm_frontend_id \
        --query 'Reservations[].Instances[].PublicDnsName' --output text)
    
    echo "$bm_frontend_dns booting"

    while [ $frontend_config_done == 0 ]
    do
        sleep 10s
        CheckState $bm_frontend_dns
        frontend_config_done=$?
    done

    if [[ $frontend_config_done == 1 ]]
    then
        frontend_ipv4=$(aws ec2 describe-instances --instance-ids $new_bm_frontend_id \
            --query 'Reservations[].Instances[].PublicIpAddress' --output text)
    fi
fi

deny_commands=$(cat <<LINE
sed -i '\''/8000;/a\\\tallow ${frontend_ipv4};\n\tdeny all;'\'' /etc/nginx/sites-available/fast-api.conf
nginx -s reload
LINE
)

if [[ ${#frontend_ipv4} > 0 ]] && [[ $frontend_config_done == 1 ]]
then   
    echo "whitelisting connectivity between $frontend_ipv4 to $bm_api_ipv4"
    ssh ubuntu@$bm_api_dns "/usr/bin/sudo bash -c '$deny_commands'"
    echo "everything done."
fi






