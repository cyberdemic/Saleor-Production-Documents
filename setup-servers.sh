#!/bin/bash

# IMPORTANT VARIABLES #
# ------------------- #
do_servers="ddvc1 ddvc2 ddvc3"
do_manager="ddvc1"
server1="ddvc1"
server2="ddvc2"
server3="ddvc3"
server_ips=() # Holds IPs for Glusterfs setup
# ------------------- #

if [ -z $DO_TOKEN ] || [ -z $DO_SIZE ] || [ -z $SSH_FINGERPRINT ] || [ -z $DO_REGION ]; then
    echo "Please make sure the following environment variables are properly set:"
    echo "DO_TOKEN, DO_SIZE, SSH_FINGERPRINT, DO_REGION"
    exit 1
fi

# Check to see if servers exist.
for server in $do_servers; do
    if docker-machine ls | grep $server &>/dev/null; then
        serversExist=true
        break
    else
        serversExist=false
    fi
done

# If server names exist, ask to delete, or move forward
if [ $serversExist = true ]; then
    read -p "Do you want to remove the servers '$do_servers'?(yes or no) " removeServers
    if [ $removeServers = "yes" ]; then
        read -p "Confirm. 'c' to continue: " confirmRemoveServers
        if [ $confirmRemoveServers = "c" ]; then
            for server in $do_servers; do
                docker-machine rm -f $server &>/dev/null
            done
            # Set to false to trigger creation statement
            serversExist=false
        else
            echo "Cancelling remove servers."
        fi
    else
        echo "Not removing servers."
    fi
fi

# Create servers.
# Exit if not created as we need servers to continue.
if [ $serversExist = false ]; then
    read -p "No servers exist. Create them(yes or no)? " createServers
    if [ $createServers = "yes" ]; then
        for server in $do_servers; do
            docker-machine create \
                --driver=digitalocean \
                --digitalocean-image="ubuntu-18-04-x64" \
                --digitalocean-access-token="${DO_TOKEN}" \
                --digitalocean-size="${DO_SIZE}" \
                --digitalocean-ssh-key-fingerprint="${SSH_FINGERPRINT}" \
                --digitalocean-tags=saleor \
                --digitalocean-region="${DO_REGION}" \
                --digitalocean-private-networking="true" \
                --digitalocean-monitoring="true" \
                ${server}
        done
    else
        echo "Not creating servers. Exiting."
        exit 1
    fi
fi

# Update servers and install GlusterFS
for server in $do_servers; do
    url=$(docker-machine url $server)
    url=${url:6:-5}
    server_ips+="$url "
    ssh-keyscan -H "$url" >>~/.ssh/known_hosts
    docker-machine ssh ${server} <<'EOF'
    apt-get --assume-yes update && apt-get --assume-yes dist-upgrade && \
    echo fs.inotify.max_user_watches=1048576 | tee -a /etc/sysctl.conf && sysctl -p && \
    apt-get --assume-yes purge do-agent && \
    curl -sSL https://repos.insights.digitalocean.com/install.sh | sudo bash && \
    usermod -aG docker $USER && newgrp docker && \
    apt-get --assume-yes install software-properties-common && \
    add-apt-repository --yes ppa:gluster/glusterfs-3.12 && \
    apt-get --assume-yes update && apt --assume-yes install glusterfs-server && \
    apt --assume-yes autoremove && apt clean && \
    systemctl start glusterd && systemctl enable glusterd && \
    mkdir -p /gluster/volume1 && chmod 666 /var/run/docker.sock;
EOF
    docker-machine scp daemon.json ${server}:/etc/docker/
    docker-machine ssh ${server} systemctl restart docker
done

# Create variables to be able to add GlusterFS ips to /etc/hosts
for server in $do_servers; do
    if [ $server = $do_manager ]; then
        manager_url=$(docker-machine url $server)
        manager_url=${manager_url:6:-5}
    elif [ $server = $server2 ]; then
        server2_url=$(docker-machine url $server)
        server2_url=${server2_url:6:-5}
    elif [ $server = $server3 ]; then
        server3_url=$(docker-machine url $server)
        server3_url=${server3_url:6:-5}
    fi
done

# Add server ips w/ correct node names to /etc/hosts
for server in $do_servers; do
    docker-machine ssh ${server} "echo '$manager_url docker-master' >>/etc/hosts"
    docker-machine ssh ${server} "echo '$server2_url docker-node1' >>/etc/hosts"
    docker-machine ssh ${server} "echo '$server3_url docker-node2' >>/etc/hosts"
done

if docker-machine ssh ${do_manager} "gluster peer probe docker-node1 && gluster peer probe docker-node2;"; then
    echo
    echo "GlusterFS is successfully running."
    echo "------------------------------------------"
    docker-machine ssh ${do_manager} "gluster pool list"
    echo "------------------------------------------"
else
    echo "There was a problem setting up your nodes."
    echo "Check '/etc/hosts' and make sure all nodes exist."
    exit 1
fi

# Create GlusterFS volumes and mount for persistent restarts
docker-machine ssh ${do_manager} <<'EOF'
    gluster volume create staging-gfs replica 3 \
        docker-master:/gluster/volume1 \
        docker-node1:/gluster/volume1 \
        docker-node2:/gluster/volume1 force && \
    gluster volume start staging-gfs && \
    echo "localhost:/staging-gfs /mnt glusterfs defaults,_netdev,backupvolfile-server=localhost 0 0" >> /etc/fstab && \
    mount.glusterfs localhost:/staging-gfs /mnt && \
    echo && echo "$HOSTNAME volumes:" && df -h;
    mkdir /mnt/saleor-redis /mnt/traefik-public-certificates && \
    chmod 777 /mnt/saleor-redis /mnt/traefik-public-certificates;
EOF

# Create the swarm
LEADER_IP=$(docker-machine ssh $do_manager ifconfig eth0 | grep 'inet' | cut -d: -f2 | awk '{print $2}')

docker-machine ssh $do_manager docker swarm init --advertise-addr "$LEADER_IP"

JOIN_TOKEN=$(docker-machine ssh $do_manager docker swarm join-token -q manager)

for server in $server2 $server3; do
    docker-machine ssh $server docker swarm join --token "$JOIN_TOKEN" "$LEADER_IP":2377
done

if eval $(docker-machine env $do_manager); then
    echo "ENV COMMAND"
    docker-machine env $do_manager
else
    echo "Oops, it seems there was a problem activating the manager machine"
    echo "Please run the following commands to finish"
    echo "-----------------------------------"
    docker-machine env $do_manager
    echo "-----------------------------------"
fi
