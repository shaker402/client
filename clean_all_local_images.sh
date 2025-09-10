# 1. Stop all running containers
docker stop $(docker ps -q)

# 2. Remove all containers
docker rm $(docker ps -aq)

docker system prune -a --volumes -f
./pull-from-dockerhub.sh
