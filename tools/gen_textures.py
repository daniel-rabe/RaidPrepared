"""Generates the ornamental art for the Dark & Gold theme with a local ComfyUI.

Build-time tool, not part of the shipped addon. It only produces the organic,
ornamental pieces - gold filigree and the like. The geometric primitives (tab
pills, glow) are drawn in png2tga.py instead, because a diffusion model has no
way to hit a crisp rounded rectangle at 128x64.

Everything is rendered as gold on pure black; png2tga.py turns the luminance
into the alpha channel afterwards.

Usage:
    python tools/gen_textures.py            # everything that is missing
    python tools/gen_textures.py corner     # one asset, forced re-render
"""

import json
import os
import sys
import time
import urllib.parse
import urllib.request

SERVER = "http://127.0.0.1:8188"
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")

UNET = "flux1-dev.safetensors"
CLIP1 = "t5xxl_fp16.safetensors"
CLIP2 = "clip_l.safetensors"
VAE = "ae.safetensors"

# Shared tail of every prompt: it keeps the model away from photographs and
# from putting the ornament on anything other than a flat black field.
STYLE = (
    "ornate gold filigree, warm antique gold and amber, polished metal with dark "
    "engraved recesses, symmetrical, crisp clean edges, centered, isolated on a "
    "pure solid black background, no text, no letters, no frame, no border box, "
    "flat lighting, high contrast, 2D game user interface asset, vector-like"
)

NEGATIVE = (
    "photograph, person, face, hands, cluttered, busy, noisy background, grey "
    "background, white background, text, watermark, signature, blurry, soft focus"
)

# The tab glyphs. Rendered white rather than gold: they are tinted per palette in
# Dialog.lua, so one set serves both themes. Flat solid silhouettes, because the
# client draws them at 18 pixels and anything with interior detail turns to mush.
ICON_STYLE = (
    "a flat minimalist icon glyph, solid pure white silhouette on a pure solid "
    "black background, bold thick even strokes, simple geometric shapes, "
    "perfectly centered, filling the frame, no text, no letters, no gradient, "
    "no shading, no outline, no border, no drop shadow, monochrome, "
    "mobile app icon, pictogram"
)

ICONS = {
    "icon-check":    (410733, "a shield with a large check mark inside it"),
    "icon-group":    (118402, "three simple people silhouettes standing side by side, a group"),
    "icon-talents":  (774501, "a single bold six pointed star burst"),
    "icon-travel":   (250914, "a swirling circular portal ring with an arrow pointing into it"),
    # Coins drawn edge-on turn into an unreadable smear at tab size; overlapping
    # discs seen face-on keep their shape.
    "icon-shopping": (204881, "three overlapping flat circular coins seen face on, "
                              "each a plain circle, arranged in a loose triangle"),
    "icon-options":  (901277, "a single mechanical gear cog wheel with six teeth"),
}


# seed is pinned so a rerun reproduces the same art.
ASSETS = {
    "corner": {
        "file": "corner-ornament.png",
        "width": 1024,
        "height": 1024,
        "seed": 770412,
        "prompt": (
            "a single ornate gold corner ornament for a fantasy UI panel, an "
            "elegant curling acanthus scroll occupying only the upper left "
            "corner of the image, the remaining three quarters of the image "
            "completely empty black, " + STYLE
        ),
    },
    "flourish": {
        "file": "header-flourish.png",
        "width": 1024,
        "height": 256,
        "seed": 118837,
        "prompt": (
            "a long horizontal gold heraldic divider, a faceted amber gemstone "
            "diamond at the exact center flanked by symmetrical tapering "
            "filigree scrollwork that thins out towards both ends, " + STYLE
        ),
    },
    "ring": {
        "file": "check-ring.png",
        "width": 1024,
        "height": 1024,
        "seed": 559021,
        "prompt": (
            "a perfectly circular ornate gold ring centered in the image, a "
            "thin beaded laurel wreath torc with a hollow empty black center, "
            "the ring occupies most of the frame, " + STYLE
        ),
    },
}


for name, (seed, subject) in ICONS.items():
    ASSETS[name] = {
        "file": name + ".png",
        "width": 512,
        "height": 512,
        "seed": seed,
        "prompt": subject + ", " + ICON_STYLE,
    }


def build_workflow(spec):
    """A minimal FLUX.1-dev text-to-image graph in ComfyUI's API format."""
    return {
        "1": {"class_type": "UNETLoader",
              "inputs": {"unet_name": UNET, "weight_dtype": "default"}},
        "2": {"class_type": "DualCLIPLoader",
              "inputs": {"clip_name1": CLIP1, "clip_name2": CLIP2,
                         "type": "flux", "device": "default"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": VAE}},
        "4": {"class_type": "CLIPTextEncode",
              "inputs": {"clip": ["2", 0], "text": spec["prompt"]}},
        "5": {"class_type": "CLIPTextEncode",
              "inputs": {"clip": ["2", 0], "text": NEGATIVE}},
        "6": {"class_type": "FluxGuidance",
              "inputs": {"conditioning": ["4", 0], "guidance": 3.5}},
        "7": {"class_type": "EmptySD3LatentImage",
              "inputs": {"width": spec["width"], "height": spec["height"],
                         "batch_size": 1}},
        "8": {"class_type": "KSampler",
              "inputs": {"model": ["1", 0], "positive": ["6", 0],
                         "negative": ["5", 0], "latent_image": ["7", 0],
                         "seed": spec["seed"], "steps": 24, "cfg": 1.0,
                         "sampler_name": "euler", "scheduler": "simple",
                         "denoise": 1.0}},
        "9": {"class_type": "VAEDecode",
              "inputs": {"samples": ["8", 0], "vae": ["3", 0]}},
        "10": {"class_type": "SaveImage",
               "inputs": {"images": ["9", 0], "filename_prefix": "pullready_theme"}},
    }


def post(path, payload):
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(SERVER + path, data=data,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read())


def get(path):
    with urllib.request.urlopen(SERVER + path, timeout=60) as resp:
        return json.loads(resp.read())


def render(name, spec):
    print("[%s] queueing %dx%d ..." % (name, spec["width"], spec["height"]))
    prompt_id = post("/prompt", {"prompt": build_workflow(spec)})["prompt_id"]

    # FLUX at 1024px takes a while on most cards; poll rather than guess.
    deadline = time.time() + 1800
    while time.time() < deadline:
        history = get("/history/%s" % prompt_id)
        if prompt_id in history:
            entry = history[prompt_id]
            status = entry.get("status", {})
            if status.get("status_str") == "error":
                raise RuntimeError("ComfyUI reported an error for %s:\n%s"
                                   % (name, json.dumps(status, indent=2)[:2000]))
            images = [img for out in entry.get("outputs", {}).values()
                      for img in out.get("images", [])]
            if images:
                return download(images[0], spec["file"])
        time.sleep(3)
    raise RuntimeError("timed out waiting for %s" % name)


def download(image, filename):
    query = urllib.parse.urlencode({
        "filename": image["filename"],
        "subfolder": image.get("subfolder", ""),
        "type": image.get("type", "output"),
    })
    with urllib.request.urlopen(SERVER + "/view?" + query, timeout=120) as resp:
        blob = resp.read()
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, filename)
    with open(path, "wb") as handle:
        handle.write(blob)
    print("    -> %s (%d KiB)" % (path, len(blob) // 1024))
    return path


def main():
    wanted = sys.argv[1:] or list(ASSETS)
    for name in wanted:
        if name not in ASSETS:
            raise SystemExit("unknown asset %r, expected one of: %s"
                             % (name, ", ".join(ASSETS)))
        spec = ASSETS[name]
        target = os.path.join(OUT_DIR, spec["file"])
        if not sys.argv[1:] and os.path.exists(target):
            print("[%s] already rendered, skipping" % name)
            continue
        render(name, spec)
    print("done - review the PNGs in %s, then run tools/png2tga.py" % OUT_DIR)


if __name__ == "__main__":
    main()
