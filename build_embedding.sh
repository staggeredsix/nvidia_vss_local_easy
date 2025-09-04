export NGC_API_KEY=
export LOCAL_NIM_CACHE=~/.cache/nim
mkdir -p "$LOCAL_NIM_CACHE"
docker run -d -it \
   --gpus '"device=1"' \
   --shm-size=16GB \
   -e NGC_API_KEY \
   -e NIM_TRT_ENGINE_HOST_CODE_ALLOWED=1 \
   -e NIM_MODEL_PROFILE="f7391ddbcb95b2406853526b8e489fedf20083a2420563ca3e65358ff417b10f" \
   -v "$LOCAL_NIM_CACHE:/opt/nim/.cache" \
   -u $(id -u) \
   -p 8006:8000 \
   nvcr.io/nim/nvidia/llama-3.2-nv-embedqa-1b-v2:1.6.0
