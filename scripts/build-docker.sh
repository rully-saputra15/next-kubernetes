VERSION=$(node -p "require('./package.json').version")
docker build -t <GKE_URL>:$VERSION .