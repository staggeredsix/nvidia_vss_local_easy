export NGC_API_KEY=
export LOCAL_NIM_CACHE=~/.cache/nim
mkdir -p "$LOCAL_NIM_CACHE"
docker run -d -it \
   --gpus '"device=0"' \
   --shm-size=16GB \
   --gpus '"device=0"' --shm-size=16GB \
   -e NGC_API_KEY=$NGC_API_KEY  \
   -v "$LOCAL_NIM_CACHE:/opt/nim/.cache" \
   -p 8005:8000 -e NIM_SERVER_PORT=8000 \
   -e NIM_MODEL_PROFILE="f7391ddbcb95b2406853526b8e489fedf20083a2420563ca3e65358ff417b10f" \
   nvcr.io/nim/nvidia/llama-3.2-nv-rerankqa-1b-v2:1.5.0
