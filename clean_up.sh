#!/bin/bash

docker stop $(docker ps -a -q) # stop all containers
docker container prune -f      # remove all stopped containers
docker network prune -f        # remove all unused networks
docker volume prune -af        # remove all volumes

# list everything
docker ps -a
docker volume ls
docker network ls
docker images

rm -rfv ~/.ssh/glab-task*
rm -rfv ./hometask/
echo -n > ~/.ssh/known_hosts
