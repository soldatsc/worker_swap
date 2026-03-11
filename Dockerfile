# syntax=docker/dockerfile:1
FROM runpod/worker-comfyui:5.7.1-base

# ============================================================
# STEP 1: Install insightface 0.7.3 from prebuilt wheel
# This wheel was compiled against numpy 1.x (dtype size=88).
# We MUST keep numpy <2 throughout the build.
# ============================================================
RUN pip install --no-cache-dir \
    "numpy==1.26.4" \
    onnxruntime \
    https://huggingface.co/AlienMachineAI/insightface-0.7.3-cp312-cp312-linux_x86_64.whl/resolve/main/insightface-0.7.3-cp312-cp312-linux_x86_64.whl

# Diagnostics (never fail build)
RUN pip show insightface 2>&1 | head -5 || true
RUN python3 -c "exec('try:\n import insightface\n print(\"v\"+insightface.__version__)\nexcept Exception as e:\n print(\"FAIL:\",e)')" || true
RUN python3 -c "exec('try:\n from insightface.model_zoo.retinaface import RetinaFace\n print(\"retinaface OK\")\nexcept Exception as e:\n print(\"retinaface:\",e)')" || true
RUN python3 -c "exec('try:\n from insightface.model_zoo.model_zoo import PickableInferenceSession\n print(\"Pickable OK\")\nexcept Exception as e:\n print(\"Pickable:\",e)')" || true

# ============================================================
# STEP 2: Other Python deps (before nodes)
# ============================================================
RUN pip install --no-cache-dir \
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
# STEP 3: Install custom nodes
# ============================================================
RUN comfy-node-install rgthree-comfy
RUN comfy-node-install comfyui-easy-use
RUN comfy-node-install comfyui-custom-scripts
RUN comfy-node-install comfyui-detail-daemon
RUN comfy-node-install comfyui-kjnodes
RUN comfy-node-install comfyui-reactor
RUN comfy-node-install comfyui-impact-pack
RUN comfy-node-install comfyui-impact-subpack
RUN comfy-node-install was-node-suite-comfyui
RUN comfy-node-install comfyui-tooling-nodes
RUN comfy-node-install comfyui-qwenvl || \
    comfy-node-install https://github.com/1038lab/ComfyUI-QwenVL

# Run install scripts for Impact packs
RUN IMPACT_DIR=$(find /comfyui/custom_nodes -maxdepth 1 -iname "*impact-pack*" -type d | head -1) && \
    if [ -n "$IMPACT_DIR" ] && [ -f "$IMPACT_DIR/install.py" ]; then \
        cd "$IMPACT_DIR" && python install.py; \
    fi

RUN SUBPACK_DIR=$(find /comfyui/custom_nodes -maxdepth 1 -iname "*impact-subpack*" -type d | head -1) && \
    if [ -n "$SUBPACK_DIR" ] && [ -f "$SUBPACK_DIR/install.py" ]; then \
        cd "$SUBPACK_DIR" && python install.py; \
    fi

# ============================================================
# STEP 3.5: Patch ReActor — disable NSFW filter
# Fix 1: set SCORE = 1.1 so threshold is never reached
# Fix 2: symlink correct model path
# ============================================================
RUN REACTOR_DIR=$(find /comfyui/custom_nodes -maxdepth 1 -iname "*reactor*" -type d | head -1) && \
    echo "Patching ReActor NSFW in: $REACTOR_DIR" && \
    SFW_FILE="$REACTOR_DIR/scripts/reactor_sfw.py" && \
    echo "--- BEFORE ---" && grep -n "SCORE\|nsfw\|threshold" "$SFW_FILE" || true && \
    sed -i 's/SCORE = [0-9][0-9.]*/SCORE = 1.1/g' "$SFW_FILE" && \
    sed -i 's/score > SCORE/score > 999/g' "$SFW_FILE" && \
    sed -i 's/nsfw_score > /nsfw_score > 999 and nsfw_score > /g' "$SFW_FILE" && \
    echo "--- AFTER ---" && grep -n "SCORE\|nsfw\|threshold" "$SFW_FILE" || true && \
    mkdir -p "$REACTOR_DIR/models/nsfw_detector/vit-base-nsfw-detector" && \
    ln -sfn "$REACTOR_DIR/models/nsfw_detector/vit-base-nsfw-detector" \
            "$REACTOR_DIR/models/nsfw_vit_b_tag" && \
    echo "Symlink: $(ls -la $REACTOR_DIR/models/nsfw_vit_b_tag)" && \
    echo "NSFW patch done"

# ============================================================
# STEP 4: Force-reinstall insightface 0.7.3 + pin numpy 1.26.4
# Nodes may have overwritten insightface or upgraded numpy.
# --no-deps prevents pulling numpy 2.x back.
# Then we explicitly pin numpy==1.26.4 to match wheel's ABI.
# ============================================================
RUN pip install --no-cache-dir --no-deps --force-reinstall \
    https://huggingface.co/AlienMachineAI/insightface-0.7.3-cp312-cp312-linux_x86_64.whl/resolve/main/insightface-0.7.3-cp312-cp312-linux_x86_64.whl

RUN pip install --no-cache-dir "numpy==1.26.4"

# Final diagnostics
RUN pip show insightface 2>&1 | head -3 || true
RUN python3 -c "exec('try:\n from insightface.model_zoo.retinaface import RetinaFace\n print(\"FINAL retinaface OK\")\nexcept Exception as e:\n print(\"FINAL retinaface:\",e)')" || true
RUN python3 -c "exec('try:\n from insightface.model_zoo.model_zoo import PickableInferenceSession\n print(\"FINAL Pickable OK\")\nexcept Exception as e:\n print(\"FINAL Pickable:\",e)')" || true

# ============================================================
# STEP 5: Download models
# ============================================================
RUN comfy model download \
    --url https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors \
    --relative-path models/vae \
    --filename ae.safetensors

RUN comfy model download \
    --url https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors \
    --relative-path models/clip/ZIT \
    --filename qwen_3_4b.safetensors

RUN comfy model download \
    --url https://huggingface.co/soldatsc/zit-bsy-model/resolve/main/2602_ZIT_BSY_fp8_scaled-c63.safetensors \
    --relative-path models/unet \
    --filename 2602_ZIT_BSY_fp8_scaled-c63.safetensors

RUN comfy model download \
    --url https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/inswapper_128.onnx \
    --relative-path models/insightface \
    --filename inswapper_128.onnx

RUN comfy model download \
    --url https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/facerestore_models/codeformer-v0.1.0.pth \
    --relative-path models/facerestore_models \
    --filename codeformer-v0.1.0.pth

RUN comfy model download \
    --url https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/detection/bbox/face_yolov8m.pt \
    --relative-path models/ultralytics/bbox \
    --filename face_yolov8m.pt

# buffalo_l face analysis models
RUN mkdir -p /comfyui/models/insightface/models/buffalo_l && \
    cd /tmp && \
    wget -q https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_l.zip && \
    python3 -c "import zipfile; z=zipfile.ZipFile('buffalo_l.zip'); z.extractall('buffalo_tmp'); z.close()" && \
    find buffalo_tmp -name "*.onnx" -exec cp {} /comfyui/models/insightface/models/buffalo_l/ \; && \
    rm -rf buffalo_l.zip buffalo_tmp

# ============================================================
# STEP 6: Final verification
# ============================================================
RUN echo "=== Nodes ===" && \
    ls /comfyui/custom_nodes/ && \
    test -d "$(find /comfyui/custom_nodes -maxdepth 1 -iname '*reactor*' -type d | head -1)" && echo "ReActor OK" || (echo "FAIL: ReActor" && exit 1) && \
    test -d "$(find /comfyui/custom_nodes -maxdepth 1 -iname '*impact-pack*' -type d | head -1)" && echo "Impact Pack OK" || (echo "FAIL: Impact Pack" && exit 1) && \
    test -d "$(find /comfyui/custom_nodes -maxdepth 1 -iname '*impact-subpack*' -type d | head -1)" && echo "Impact Subpack OK" || (echo "FAIL: Impact Subpack" && exit 1) && \
    test -d "$(find /comfyui/custom_nodes -maxdepth 1 -iname '*tooling*' -type d | head -1)" && echo "Tooling Nodes OK" || echo "WARNING: tooling-nodes not found" && \
    echo "=== Models ===" && \
    test -f /comfyui/models/vae/ae.safetensors && echo "VAE OK" && \
    test -f /comfyui/models/clip/ZIT/qwen_3_4b.safetensors && echo "CLIP OK" && \
    test -f /comfyui/models/unet/2602_ZIT_BSY_fp8_scaled-c63.safetensors && echo "UNET OK" && \
    test -f /comfyui/models/insightface/inswapper_128.onnx && echo "inswapper OK" && \
    test -f /comfyui/models/facerestore_models/codeformer-v0.1.0.pth && echo "CodeFormer OK" && \
    test -f /comfyui/models/ultralytics/bbox/face_yolov8m.pt && echo "YOLO OK" && \
    ls /comfyui/models/insightface/models/buffalo_l/*.onnx > /dev/null && echo "buffalo_l OK" && \
    echo "=== NSFW patch verify ===" && \
    REACTOR_DIR=$(find /comfyui/custom_nodes -maxdepth 1 -iname '*reactor*' -type d | head -1) && \
    grep -r "SCORE = 1.1" "$REACTOR_DIR" && echo "NSFW PATCH CONFIRMED" || echo "WARNING: patch not found" && \
    echo "=== ALL OK ==="
