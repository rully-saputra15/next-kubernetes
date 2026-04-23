VERSION=$(node -p "require('./package.json').version")
docker push <GKE_URL>:$VERSION