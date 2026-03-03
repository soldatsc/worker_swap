# syntax=docker/dockerfile:1
FROM runpod/worker-comfyui:5.7.1-base

# ============================================================
# STEP 1: Install insightface==0.7.3 from prebuilt Linux wheel
# This is THE fix. Latest insightface removed retinaface module
# and PickableInferenceSession. We need exactly 0.7.3.
# Prebuilt wheel = no compilation needed.
# ============================================================

RUN pip install --no-cache-dir \
    https://huggingface.co/AlienMachineAI/insightface-0.7.3-cp312-cp312-linux_x86_64.whl/resolve/main/insightface-0.7.3-cp312-cp312-linux_x86_64.whl

# Verify insightface 0.7.3 has what ReActor needs
RUN python3 -c "\
from insightface.model_zoo.model_zoo import PickableInferenceSession; \
from insightface.model_zoo.retinaface import RetinaFace; \
import insightface; print('insightface', insightface.__version__, 'OK')"

# Other dependencies needed by nodes
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
# STEP 2: Install custom nodes
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
RUN comfy-node-install comfyui-qwenvl || \
    comfy-node-install https://github.com/1038lab/ComfyUI-QwenVL

# Run install scripts for Impact Pack
RUN IMPACT_DIR=$(find /comfyui/custom_nodes -maxdepth 1 -iname "*impact-pack*" -type d | head -1) && \
    if [ -n "$IMPACT_DIR" ] && [ -f "$IMPACT_DIR/install.py" ]; then \
        cd "$IMPACT_DIR" && python install.py; \
    fi

RUN SUBPACK_DIR=$(find /comfyui/custom_nodes -maxdepth 1 -iname "*impact-subpack*" -type d | head -1) && \
    if [ -n "$SUBPACK_DIR" ] && [ -f "$SUBPACK_DIR/install.py" ]; then \
        cd "$SUBPACK_DIR" && python install.py; \
    fi

# ============================================================
# STEP 3: Force-reinstall insightface 0.7.3 AGAIN
# Because comfy-node-install for reactor runs install.py
# which may try to install a different insightface version.
# This ensures 0.7.3 is the final installed version.
# ============================================================

RUN pip install --no-cache-dir --force-reinstall \
    https://huggingface.co/AlienMachineAI/insightface-0.7.3-cp312-cp312-linux_x86_64.whl/resolve/main/insightface-0.7.3-cp312-cp312-linux_x86_64.whl

# Verify AGAIN after all node installs
RUN python3 -c "\
from insightface.model_zoo.model_zoo import PickableInferenceSession; \
from insightface.model_zoo.retinaface import RetinaFace; \
import insightface; print('FINAL insightface', insightface.__version__, 'OK')"

# ============================================================
# STEP 4: Download models
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

RUN mkdir -p /comfyui/models/insightface/models/buffalo_l && \
    cd /tmp && \
    wget -q https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_l.zip && \
    python3 -c "import zipfile; z=zipfile.ZipFile('buffalo_l.zip'); z.extractall('buffalo_tmp'); z.close()" && \
    find buffalo_tmp -name "*.onnx" -exec cp {} /comfyui/models/insightface/models/buffalo_l/ \; && \
    rm -rf buffalo_l.zip buffalo_tmp

# ============================================================
# STEP 5: Verify everything
# ============================================================

RUN echo "=== Nodes ===" && \
    ls /comfyui/custom_nodes/ && \
    test -d "$(find /comfyui/custom_nodes -maxdepth 1 -iname '*reactor*' -type d | head -1)" && echo "ReActor OK" || (echo "FAIL: ReActor" && exit 1) && \
    test -d "$(find /comfyui/custom_nodes -maxdepth 1 -iname '*impact-pack*' -type d | head -1)" && echo "Impact Pack OK" || (echo "FAIL: Impact Pack" && exit 1) && \
    test -d "$(find /comfyui/custom_nodes -maxdepth 1 -iname '*impact-subpack*' -type d | head -1)" && echo "Impact Subpack OK" || (echo "FAIL: Impact Subpack" && exit 1) && \
    echo "=== Models ===" && \
    test -f /comfyui/models/vae/ae.safetensors && echo "VAE OK" && \
    test -f /comfyui/models/clip/ZIT/qwen_3_4b.safetensors && echo "CLIP OK" && \
    test -f /comfyui/models/unet/2602_ZIT_BSY_fp8_scaled-c63.safetensors && echo "UNET OK" && \
    test -f /comfyui/models/insightface/inswapper_128.onnx && echo "inswapper OK" && \
    test -f /comfyui/models/facerestore_models/codeformer-v0.1.0.pth && echo "CodeFormer OK" && \
    test -f /comfyui/models/ultralytics/bbox/face_yolov8m.pt && echo "YOLO OK" && \
    ls /comfyui/models/insightface/models/buffalo_l/*.onnx > /dev/null && echo "buffalo_l OK" && \
    echo "=== ALL OK ==="
