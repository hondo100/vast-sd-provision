#!/bin/bash

# ==============================================================================
# 📋 MODELL-KONFIGURATION FÜR SD-FORGE
# Wird von vast-sd-forge-provisioning.sh eingelesen (via `source`).
# Jede Zeile: DOWNLOADS+=("DEST_DIR|NAME|SOURCE")
#
# SOURCE kann sein:
#   - Reine Civitai-ID (z.B. "357609")     → curl + CIVITAI_API_KEY
#   - Vollständige URL (http/https)         → aria2c (oder curl für HF-Gated)
#
# ⚠️  WICHTIG: SVD benötigt HF_TOKEN (Gated Model bei stabilityai).
#              Alternativ: ungated Mirror bei thesudio/SVD1.1 (siehe unten).
# ==============================================================================

WORKSPACE="/root/stable-diffusion-webui-forge"

DOWNLOADS=(
    # ── Checkpoints ──────────────────────────────────────────────────────────
    # Juggernaut XL v9 (Civitai ID – curl + API-Token)
    "${WORKSPACE}/models/Stable-diffusion|Juggernaut-XL-v9.safetensors|357609"

    # ── SVD (Stable Video Diffusion) ─────────────────────────────────────────
    # Option A: Offizielles Repo – benötigt HF_TOKEN (Gated Model)
    # "${WORKSPACE}/models/Stable-diffusion|svd_xt_1_1.safetensors|HF_GATED:stabilityai/stable-video-diffusion-img2vid-xt-1-1/svd_xt_1_1.safetensors"
    #
    # Option B: Ungated Mirror – kein Token nötig (empfohlen für Automatisierung)
    "${WORKSPACE}/models/Stable-diffusion|svd_xt_1_1.safetensors|https://huggingface.co/thesudio/SVD1.1/resolve/main/svd_xt_1_1.safetensors"

    # ── LoRAs ─────────────────────────────────────────────────────────────────
    "${WORKSPACE}/models/Lora|film_grain_cinematic.safetensors|518040"
    "${WORKSPACE}/models/Lora|detail_tweaker_xl.safetensors|135929"
    "${WORKSPACE}/models/Lora|real-vis-xl-enhancer.safetensors|135010"
    "${WORKSPACE}/models/Lora|perfect_eyes_xl.safetensors|128461"
    "${WORKSPACE}/models/Lora|skin_detail_xl.safetensors|340833"

    # ── ESRGAN Upscaler ───────────────────────────────────────────────────────
    # 4x-UltraSharp: öffentlich auf HuggingFace, kein Token nötig
    "${WORKSPACE}/models/ESRGAN|4x-UltraSharp.pth|https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth"
    # Siax_200k: Civitai ID
    "${WORKSPACE}/models/ESRGAN|Siax_200k.pth|2052724"

    # ── Tagger Modell ─────────────────────────────────────────────────────────
    # WD14 SwinV2 Tagger – öffentlich auf HuggingFace, kein Token nötig
    "${WORKSPACE}/models/torch_deepdanbooru|wd-v1-4-swinv2-tagger-v2.onnx|https://huggingface.co/SmilingWolf/wd-v1-4-swinv2-tagger-v2/resolve/main/model.onnx"
)

# ── Extensions ───────────────────────────────────────────────────────────────
EXTENSIONS=(
    "https://github.com/Kataragi/stable-diffusion-webui-tagger-fork"
    "https://github.com/thomasasfk/sd-webui-aspect-ratio-helper"
    "https://github.com/Mikubill/sd-webui-controlnet"
)
