#!/usr/bin/env python3
"""Export pinned upstream MobileSAM ViT-T into encoder/decoder ONNX artifacts.

This is a development qualification utility, not a production inference path.
The upstream model code/checkpoint must be obtained separately from its
official pinned source. No masks or model outputs are synthesized here.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import onnx
import torch


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path,
                        help="Pinned official MobileSAM source checkout")
    parser.add_argument("--checkpoint", required=True, type=Path,
                        help="Official MobileSAM ViT-T checkpoint")
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--opset", type=int, default=17)
    args = parser.parse_args()

    source = args.source.resolve()
    checkpoint = args.checkpoint.resolve()
    output_dir = args.output_dir.resolve()
    if not (source / "LICENSE").is_file() or not (source / "mobile_sam").is_dir():
        parser.error("--source must point to the pinned official source tree")
    if not checkpoint.is_file():
        parser.error("--checkpoint must point to an existing checkpoint")
    output_dir.mkdir(parents=True, exist_ok=True)
    sys.path.insert(0, str(source))

    from mobile_sam import sam_model_registry
    from mobile_sam.utils.onnx import SamOnnxModel

    model = sam_model_registry["vit_t"](checkpoint=str(checkpoint)).eval().cpu()
    encoder_path = output_dir / "mobilesam_vit_t_encoder.onnx"
    decoder_path = output_dir / "mobilesam_vit_t_box_decoder.onnx"

    # SAM preprocessing (RGB 0..255 normalization and bottom/right zero pad)
    # happens before this boundary in the Android runner; the exported encoder
    # therefore consumes NCHW float32 tensors exactly as MobileSAM expects.
    encoder_example = torch.zeros((1, 3, 1024, 1024), dtype=torch.float32)
    torch.onnx.export(
        model.image_encoder,
        (encoder_example,),
        str(encoder_path),
        export_params=True,
        opset_version=args.opset,
        do_constant_folding=True,
        input_names=["normalized_image"],
        output_names=["image_embeddings"],
        dynamic_axes=None,
        dynamo=False,
    )

    # The official wrapper selects the highest predicted-IoU mask before
    # resizing, keeping the full-resolution output to one mask per prompt.
    decoder = SamOnnxModel(model, return_single_mask=True).eval().cpu()
    decoder_inputs = (
        torch.zeros((1, 256, 64, 64), dtype=torch.float32),
        torch.tensor([[[128.0, 128.0], [896.0, 896.0]]], dtype=torch.float32),
        torch.tensor([[2.0, 3.0]], dtype=torch.float32),
        torch.zeros((1, 1, 256, 256), dtype=torch.float32),
        torch.zeros((1,), dtype=torch.float32),
        torch.tensor([720.0, 1280.0], dtype=torch.float32),
    )
    input_names = [
        "image_embeddings", "point_coords", "point_labels", "mask_input",
        "has_mask_input", "orig_im_size",
    ]
    output_names = ["masks", "iou_predictions", "low_res_masks"]
    torch.onnx.export(
        decoder,
        decoder_inputs,
        str(decoder_path),
        export_params=True,
        opset_version=args.opset,
        do_constant_folding=True,
        input_names=input_names,
        output_names=output_names,
        dynamic_axes={
            "point_coords": {1: "box_corner_count"},
            "point_labels": {1: "box_corner_count"},
        },
        dynamo=False,
    )

    for path in (encoder_path, decoder_path):
        graph = onnx.load(str(path))
        onnx.checker.check_model(graph)

    record = {
        "model": "MobileSAM ViT-T",
        "upstream_commit": "f706ad9c4eb7f219c00d9050e46328518ffb65d2",
        "checkpoint_sha256": sha256(checkpoint),
        "source_license": "Apache-2.0",
        "opset": args.opset,
        "prompt_contract": "two oriented-image box corners, labels 2 and 3",
        "artifacts": {
            path.name: {"bytes": path.stat().st_size, "sha256": sha256(path)}
            for path in (encoder_path, decoder_path)
        },
    }
    record_path = output_dir / "mobilesam_export_manifest.json"
    record_path.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(record, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
