FROM runpod/worker-comfyui:5.7.1-base

RUN comfy-node-install \
    rgthree-comfy \
    comfyui-easy-use \
    comfyui-custom-scripts \
    comfyui-detail-daemon \
    comfyui-kjnodes

RUN cd /comfyui/custom_nodes && \
    git clone https://github.com/Gourieff/ComfyUI-ReActor && \
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack && \
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Subpack && \
    git clone https://github.com/1038lab/ComfyUI-QwenVL && \
    git clone https://github.com/WASasquatch/was-node-suite-comfyui

RUN pip install --no-cache-dir \
    ultralytics insightface onnxruntime scikit-image \
    numba piexif gguf segment-anything dill blend-modes accelerate

RUN cd /comfyui/custom_nodes/ComfyUI-ReActor && pip install --no-cache-dir -r requirements.txt || true
RUN cd /comfyui/custom_nodes/ComfyUI-Impact-Pack && pip install --no-cache-dir -r requirements.txt || true
RUN cd /comfyui/custom_nodes/ComfyUI-Impact-Subpack && pip install --no-cache-dir -r requirements.txt || true
RUN cd /comfyui/custom_nodes/ComfyUI-QwenVL && pip install --no-cache-dir -r requirements.txt || true
RUN cd /comfyui/custom_nodes/was-node-suite-comfyui && pip install --no-cache-dir -r requirements.txt || true

RUN comfy model download \
    --url https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors \
    --relative-path models/vae \
    --filename ae.safetensors

RUN mkdir -p /comfyui/models/clip/ZIT && \
    wget -O /comfyui/models/clip/ZIT/qwen_3_4b.safetensors \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors"

RUN mkdir -p /comfyui/models/unet && \
    wget -O /comfyui/models/unet/2602_ZIT_BSY_fp8_scaled-c63.safetensors \
    "https://huggingface.co/soldatsc/zit-bsy-model/resolve/main/2602_ZIT_BSY_fp8_scaled-c63.safetensors"

RUN mkdir -p /comfyui/models/insightface && \
    wget -O /comfyui/models/insightface/inswapper_128.onnx \
    "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/inswapper_128.onnx"

RUN mkdir -p /comfyui/models/facerestore_models && \
    wget -O /comfyui/models/facerestore_models/codeformer-v0.1.0.pth \
    "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/facerestore_models/codeformer-v0.1.0.pth"

RUN mkdir -p /comfyui/models/insightface/models/buffalo_l && \
    cd /tmp && \
    wget https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_l.zip && \
    python3 -c "import zipfile; zipfile.ZipFile('buffalo_l.zip').extractall('buffalo_l_extracted')" && \
    find buffalo_l_extracted -name "*.onnx" -exec mv {} /comfyui/models/insightface/models/buffalo_l/ \; && \
    rm -rf buffalo_l.zip buffalo_l_extracted

RUN mkdir -p /comfyui/models/ultralytics/bbox && \
    wget -O /comfyui/models/ultralytics/bbox/face_yolov8m.pt \
    "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/detection/bbox/face_yolov8m.pt"
