#!/bin/bash

echo -e "\033[1;34m[VAST][INFO]\033[0m Loading model-list.sh"

DOWNLOADS=(
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Stable-diffusion|Juggernaut-XL-v9.safetensors|357609"
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Stable-diffusion|svd_xt_1_1.safetensors|https://huggingface.co/thesudio/SVD1.1/resolve/main/svd_xt_1_1.safetensors"
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|film_grain_cinematic.safetensors|518040"
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|detail_tweaker_xl.safetensors|135929"
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|real-vis-xl-enhancer.safetensors|135010"
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|perfect_eyes_xl.safetensors|128461"
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|skin_detail_xl.safetensors|340833"
  "${WORKSPACE}/stable-diffusion-webui-forge/models/ESRGAN|4x-UltraSharp.pth|https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth"
  "${WORKSPACE}/stable-diffusion-webui-forge/models/ESRGAN|Siax_200k.pth|2052724"
  "${WORKSPACE}/stable-diffusion-webui-forge/models/torch_deepdanbooru|wd-v1-4-swinv2-tagger-v2.onnx|https://huggingface.co/SmilingWolf/wd-v1-4-swinv2-tagger-v2/resolve/main/model.onnx"
)

EXTENSIONS=(
  "https://github.com/thomasasfk/sd-webui-aspect-ratio-helper"
  "https://github.com/Mikubill/sd-webui-controlnet"
)

echo -e "\033[1;34m[VAST][INFO]\033[0m modell-list.sh loaded: ${#DOWNLOADS[@]} downloads, ${#EXTENSIONS[@]} extensions"
