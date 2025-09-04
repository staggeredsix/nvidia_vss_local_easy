export NGC_API_KEY=
export CONTAINER_NAME=parakeet-ctc-asr

docker run -d -it --name=$CONTAINER_NAME \
--runtime=nvidia \
--gpus '"device=0"' \
--shm-size=8GB \
-e NGC_API_KEY=$NGC_API_KEY \
-e NIM_HTTP_API_PORT=9000 \
-e NIM_GRPC_API_PORT=50051 \
-e NIM_TAGS_SELECTOR=name=parakeet-0-6b-ctc-riva-en-us,mode=all  \
--network=via-engine-${USER}  \
nvcr.io/nim/nvidia/parakeet-0-6b-ctc-en-us:2.0.0
