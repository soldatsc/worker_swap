FROM runpod/worker-comfyui:5.7.1-base

# ============================================================
# STEP 1: Pre-install critical Python dependencies
# These MUST be installed BEFORE nodes, otherwise node imports
# fail silently and nodes don't register their class mappings.
# ============================================================

# Build tools needed to compile insightface==0.7.3 from source
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake && \
    rm -rf /var/lib/apt/lists/*

# insightface + onnxruntime — REQUIRED by ReActor (most common failure cause)
# ultralytics — REQUIRED by Impact-Subpack (UltralyticsDetectorProvider)
# segment-anything, scikit-image, piexif — REQUIRED by Impact-Pack
# transformers>=4.47, accelerate, sentencepiece, einops — REQUIRED by QwenVL
# Install insightface build deps first, then insightface separately
RUN pip install --no-cache-dir Cython "numpy<2" onnx

RUN pip install --no-cache-dir --no-build-isolation insightface==0.7.3

# Other dependencies
RUN pip install --no-cache-dir \
    onnxruntime \
    ultralytics \
    segment-anything \
    scikit-image \
    piexif \
    numba \
    dill \
    blend-modes \
    accelerate \
    "transformers>=4.47" \
    sentencepiece \
    einops \
    timm \
    gguf

# ============================================================
# STEP 2: Install custom nodes via comfy-node-install
# RunPod's own wrapper that surfaces errors (unlike comfy-cli).
# Each node = separate RUN so build fails at the exact step.
# Names from Comfy Registry (https://registry.comfy.org).
# ============================================================

# Core workflow nodes (already verified working in previous build)
RUN comfy-node-install rgthree-comfy
RUN comfy-node-install comfyui-easy-use
RUN comfy-node-install comfyui-custom-scripts
RUN comfy-node-install comfyui-detail-daemon
RUN comfy-node-install comfyui-kjnodes

# ReActor face swap (registry: comfyui-reactor)
RUN comfy-node-install comfyui-reactor

# Impact Pack — FaceDetailer and detection nodes
RUN comfy-node-install comfyui-impact-pack

# Impact Subpack — UltralyticsDetectorProvider (separate since V8.0)
RUN comfy-node-install comfyui-impact-subpack

# WAS Node Suite — various utility nodes
RUN comfy-node-install was-node-suite-comfyui

# QwenVL — vision-language model for image description
# Try registry name first, fall back to GitHub URL
RUN comfy-node-install comfyui-qwenvl || \
    comfy-node-install https://github.com/1038lab/ComfyUI-QwenVL

# ============================================================
# STEP 3: Run install scripts that some nodes require
# Impact Pack V7.6+ needs install.py to be run explicitly.
# Using find to handle different possible folder names.
# ============================================================
RUN IMPACT_DIR=$(find /comfyui/custom_nodes -maxdepth 1 -iname "*impact-pack*" -type d | head -1) && \
    if [ -n "$IMPACT_DIR" ] && [ -f "$IMPACT_DIR/install.py" ]; then \
        cd "$IMPACT_DIR" && python install.py; \
    fi

RUN SUBPACK_DIR=$(find /comfyui/custom_nodes -maxdepth 1 -iname "*impact-subpack*" -type d | head -1) && \
    if [ -n "$SUBPACK_DIR" ] && [ -f "$SUBPACK_DIR/install.py" ]; then \
        cd "$SUBPACK_DIR" && python install.py; \
    fi

# ============================================================
# STEP 4: Download models
# ============================================================

# VAE for ZIT
RUN comfy model download \
    --url https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors \
    --relative-path models/vae \
    --filename ae.safetensors

# CLIP text encoder for ZIT
RUN comfy model download \
    --url https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors \
    --relative-path models/clip/ZIT \
    --filename qwen_3_4b.safetensors

# ZIT UNET model
RUN comfy model download \
    --url https://huggingface.co/soldatsc/zit-bsy-model/resolve/main/2602_ZIT_BSY_fp8_scaled-c63.safetensors \
    --relative-path models/unet \
    --filename 2602_ZIT_BSY_fp8_scaled-c63.safetensors

# ReActor: inswapper face swap model
RUN comfy model download \
    --url https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/inswapper_128.onnx \
    --relative-path models/insightface \
    --filename inswapper_128.onnx

# ReActor: CodeFormer face restoration
RUN comfy model download \
    --url https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/facerestore_models/codeformer-v0.1.0.pth \
    --relative-path models/facerestore_models \
    --filename codeformer-v0.1.0.pth

# FaceDetailer: YOLO face detection model
RUN comfy model download \
    --url https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/detection/bbox/face_yolov8m.pt \
    --relative-path models/ultralytics/bbox \
    --filename face_yolov8m.pt

# ============================================================
# STEP 5: buffalo_l face analysis models for insightface
# Zip archive — wget + python unzip
# ============================================================
RUN mkdir -p /comfyui/models/insightface/models/buffalo_l && \
    cd /tmp && \
    wget -q https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_l.zip && \
    python3 -c "import zipfile; z=zipfile.ZipFile('buffalo_l.zip'); z.extractall('buffalo_tmp'); z.close()" && \
    find buffalo_tmp -name "*.onnx" -exec cp {} /comfyui/models/insightface/models/buffalo_l/ \; && \
    rm -rf buffalo_l.zip buffalo_tmp

# ============================================================
# STEP 6: Verify critical nodes exist
# Build FAILS if any node directory is missing
# ============================================================
RUN echo "=== Verifying custom nodes ===" && \
    ls /comfyui/custom_nodes/ && \
    echo "---" && \
    REACTOR_DIR=$(find /comfyui/custom_nodes -maxdepth 1 -iname "*reactor*" -type d | head -1) && \
    test -n "$REACTOR_DIR" && echo "ReActor: $REACTOR_DIR OK" || (echo "FAIL: ReActor not found" && exit 1) && \
    IMPACT_DIR=$(find /comfyui/custom_nodes -maxdepth 1 -iname "*impact-pack*" -type d | head -1) && \
    test -n "$IMPACT_DIR" && echo "Impact Pack: $IMPACT_DIR OK" || (echo "FAIL: Impact Pack not found" && exit 1) && \
    SUBPACK_DIR=$(find /comfyui/custom_nodes -maxdepth 1 -iname "*impact-subpack*" -type d | head -1) && \
    test -n "$SUBPACK_DIR" && echo "Impact Subpack: $SUBPACK_DIR OK" || (echo "FAIL: Impact Subpack not found" && exit 1) && \
    WAS_DIR=$(find /comfyui/custom_nodes -maxdepth 1 -iname "*was*" -type d | head -1) && \
    test -n "$WAS_DIR" && echo "WAS: $WAS_DIR OK" || (echo "FAIL: WAS not found" && exit 1) && \
    echo "=== All critical nodes present ==="

# ============================================================
# STEP 7: Verify critical models exist
# ============================================================
RUN echo "=== Verifying models ===" && \
    test -f /comfyui/models/vae/ae.safetensors && echo "VAE OK" && \
    test -f /comfyui/models/clip/ZIT/qwen_3_4b.safetensors && echo "CLIP OK" && \
    test -f /comfyui/models/unet/2602_ZIT_BSY_fp8_scaled-c63.safetensors && echo "UNET OK" && \
    test -f /comfyui/models/insightface/inswapper_128.onnx && echo "inswapper OK" && \
    test -f /comfyui/models/facerestore_models/codeformer-v0.1.0.pth && echo "CodeFormer OK" && \
    test -f /comfyui/models/ultralytics/bbox/face_yolov8m.pt && echo "YOLO OK" && \
    ls /comfyui/models/insightface/models/buffalo_l/*.onnx > /dev/null && echo "buffalo_l OK" && \
    echo "=== All models present ==="
