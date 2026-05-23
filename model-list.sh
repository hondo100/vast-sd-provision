#!/usr/bin/env bash

DOWNLOADS=(
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|film_grain_cinematic.safetensors|518040"
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|detail_tweaker_xl.safetensors|https://huggingface.co/tyDiffusion/LoRAs/resolve/main/detail-tweaker-xl.safetensors"
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|real-vis-xl-enhancer.safetensors|135010"
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|perfect_eyes_xl.safetensors|128461"
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|skin_detail_xl.safetensors|340833"
  "${WORKSPACE}/stable-diffusion-webui-forge/models/ESRGAN|4x-UltraSharp.pth|https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth"
  "${WORKSPACE}/stable-diffusion-webui-forge/models/ESRGAN|Siax_200k.pth|https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x_NMKD-Siax_200k.pth"
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Stable-diffusion|Juggernaut-XL-v9.safetensors|357609"
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Stable-diffusion|svd_xt_1_1.safetensors|https://huggingface.co/thesudio/SVD1.1/resolve/main/svd_xt_1_1.safetensors"
  "${WORKSPACE}/stable-diffusion-webui-forge/models/torch_deepdanbooru|wd-v1-4-swinv2-tagger-v2.onnx|https://huggingface.co/SmilingWolf/wd-v1-4-swinv2-tagger-v2/resolve/main/model.onnx"
)

EXTENSIONS=(
  "https://github.com/thomasasfk/sd-webui-aspect-ratio-helper"
  "https://github.com/Mikubill/sd-webui-controlnet"
  "https://github.com/pharmapsychotic/clip-interrogator-ext"
)
