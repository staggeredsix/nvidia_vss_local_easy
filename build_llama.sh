export NGC_API_KEY=
export LOCAL_NIM_CACHE=~/.cache/nim
mkdir -p "$LOCAL_NIM_CACHE"
docker run -d -it \
--gpus '"device=0"' \
--shm-size=16GB \
-e NGC_API_KEY \
-e NIM_LOW_MEMORY_MODE=1 -e NIM_RELAX_MEM_CONSTRAINTS=1 \
-v "$LOCAL_NIM_CACHE:/opt/nim/.cache" \
-u $(id -u) \
-p 8007:8000 \
nvcr.io/nim/meta/llama-3.1-8b-instruct:1.8.6
