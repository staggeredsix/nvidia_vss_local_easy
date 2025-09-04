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

