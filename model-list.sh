#!/bin/bash

echo -e "\033[1;34m[VAST][INFO]\033[0m  Loading model-list.sh v4"

DOWNLOADS=(
 # ── LoRAs ──────────────────────────────────────────────────────────────
  # film_grain_cinematic: kein HF-Mirror verfügbar → Civitai
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|film_grain_cinematic.safetensors|518040"

  # detail_tweaker_xl: ✅ HF statt Civitai (135929) → ~100 MB/s statt ~53 MB/s
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|detail_tweaker_xl.safetensors|https://huggingface.co/tyDiffusion/LoRAs/resolve/main/detail-tweaker-xl.safetensors"
  # FALLBACK: "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|detail_tweaker_xl.safetensors|135929"

  # real-vis-xl-enhancer: kein HF-Mirror → Civitai
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|real-vis-xl-enhancer.safetensors|135010"

  # perfect_eyes_xl: kein HF-Mirror → Civitai
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|perfect_eyes_xl.safetensors|128461"

  # skin_detail_xl: kein HF-Mirror → Civitai
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|skin_detail_xl.safetensors|340833"

  # ── Upscaler ───────────────────────────────────────────────────────────
  "${WORKSPACE}/stable-diffusion-webui-forge/models/ESRGAN|4x-UltraSharp.pth|https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth"

  # ── Checkpoints ───────────────────────────────────────────────────────
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Stable-diffusion|Juggernaut-XL-v9.safetensors|357609"
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Stable-diffusion|svd_xt_1_1.safetensors|https://huggingface.co/thesudio/SVD1.1/resolve/main/svd_xt_1_1.safetensors"

  # ── LoRAs ──────────────────────────────────────────────────────────────
  # film_grain_cinematic: kein HF-Mirror verfügbar → Civitai
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|film_grain_cinematic.safetensors|518040"

  # detail_tweaker_xl: ✅ HF statt Civitai (135929) → ~100 MB/s statt ~53 MB/s
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|detail_tweaker_xl.safetensors|https://huggingface.co/tyDiffusion/LoRAs/resolve/main/detail-tweaker-xl.safetensors"
  # FALLBACK: "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|detail_tweaker_xl.safetensors|135929"

  # real-vis-xl-enhancer: kein HF-Mirror → Civitai
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|real-vis-xl-enhancer.safetensors|135010"

  # perfect_eyes_xl: kein HF-Mirror → Civitai
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|perfect_eyes_xl.safetensors|128461"

  # skin_detail_xl: kein HF-Mirror → Civitai
  "${WORKSPACE}/stable-diffusion-webui-forge/models/Lora|skin_detail_xl.safetensors|340833"

  # ── Upscaler ───────────────────────────────────────────────────────────
  "${WORKSPACE}/stable-diffusion-webui-forge/models/ESRGAN|4x-UltraSharp.pth|https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth"

  # Siax_200k: ✅ HF statt Civitai (2052724) → kein Rate-Limiting mehr
  "${WORKSPACE}/stable-diffusion-webui-forge/models/ESRGAN|Siax_200k.pth|https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x_NMKD-Siax_200k.pth"
  # FALLBACK: "${WORKSPACE}/stable-diffusion-webui-forge/models/ESRGAN|Siax_200k.pth|2052724"

  # ── Tagger / Interrogator ──────────────────────────────────────────────
  # wd-v1-4-swinv2: Booru-Style Tags (Anime/Realismus)
  "${WORKSPACE}/stable-diffusion-webui-forge/models/torch_deepdanbooru|wd-v1-4-swinv2-tagger-v2.onnx|https://huggingface.co/SmilingWolf/wd-v1-4-swinv2-tagger-v2/resolve/main/model.onnx"
)

EXTENSIONS=(
  # Aspect Ratio Helper
  "https://github.com/thomasasfk/sd-webui-aspect-ratio-helper"

  # ControlNet
  "https://github.com/Mikubill/sd-webui-controlnet"

  # ✅ NEU: WD14 Tagger + CLIP Interrogator (Bild → Text)
  # Analysiert ein Bild und gibt Tags/Prompt zurück → Basis für Neugenerierung
  # "https://github.com/toriato/stable-diffusion-webui-wd14-tagger"

  # ✅ NEU: CLIP Interrogator – natürlichsprachliche Bildbeschreibung (kein Booru-Style)
  # Ideal für realistische Bilder und SDXL-Prompts
  "https://github.com/pharmapsychotic/clip-interrogator-ext"
)

OPTIONAL_CONFIGS=(
  "${WORKSPACE}/stable-diffusion-webui-forge|ui-config.json|https://raw.githubusercontent.com/hondo100/vast-sd-provision/refs/heads/main/configs/ui-config.json"
  "${WORKSPACE}/stable-diffusion-webui-forge|config.json|https://raw.githubusercontent.com/hondo100/vast-sd-provision/refs/heads/main/configs/config.json"
)

echo -e "\033[1;32m[VAST][OK]\033[0m    model-list.sh geladen: ${#DOWNLOADS[@]} Downloads, ${#EXTENSIONS[@]} Extensions"
