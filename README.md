This is a collection of drop in scripts you can place in /deploy/docker/local_*
They're built so you can run start_vss.sh and immediately deploy the VSS blueprint.

start_vss does a few things :

1- It will automagically detect and deploy (or restart) previous VSS containers.
2- It detects when the LLM is running. VSS startup is coded in a way that it will immediately barf and kill itself if it cannot get a response from the LLM. This script tests the LLM endpoint so VSS doesn't freak out.
2- It will cache models so you don't have to redownload them.
3- It makes NGC API key management easier.
4- It makes NVIDIA software easier to use. The way it's meant to be played.


Usage - there are build_* scripts that will allow the user to swap models out easily, the first line of each file contains a ngc key variable - you can comment this out and change the docker deployment command to run a different model example : HF/Ollama.
Running start_vss.sh will execute each build script, test the endpoints of the LLM and then bring up VSS.
The VSS webui will take a little while to start. Be patient.
The LLama NIM will take a little while to start, docker logs -f the container and watch it come up for happy fun times.

NOTE : You MUST change the which GPU(s) the models run on. The .env file in the VSS github cloned directory must still be changed so your NGC key is availble to VSS itself. You can modify start_vss if you want, I'm too lazy to do this.

To change GPU(s) in the build_* scripts :

export LOCAL_NIM_CACHE=~/.cache/nim
mkdir -p "$LOCAL_NIM_CACHE"
docker run -d -it \
--gpus '"device=0"' \       <----------- change this to whatever you need to. Example - I am running on two 6000 Blackwell Workstation Edition 600w boards. I am running this NIM on GPU 0 and have assigned the other models to GPU 1.
--shm-size=16GB \
-e NGC_API_KEY \
-e NIM_LOW_MEMORY_MODE=1 -e NIM_RELAX_MEM_CONSTRAINTS=1 \
-v "$LOCAL_NIM_CACHE:/opt/nim/.cache" \
-u $(id -u) \
-p 8007:8000 \
nvcr.io/nim/meta/llama-3.1-8b-instruct:1.8.6
