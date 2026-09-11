# GDSkills Style LoRAs

Trained on ternary Bonsai (FLUX.2 Klein 4B gemlite) for style-consistent game asset generation.

## Available adapters

| File | Style family | Rank | Size | Checksum |
|------|-------------|------|------|----------|
| `lora-pixel.safetensors` | pixel | TBD | TBD | TBD |
| `lora-painted.safetensors` | painted | TBD | TBD | TBD |
| `lora-flat.safetensors` | flat | TBD | TBD | TBD |
| `lora-cel.safetensors` | cel | TBD | TBD | TBD |
| `lora-ink.safetensors` | ink | TBD | TBD | TBD |

## Download

Adapters are not committed to git (too large). Download from the latest GitHub release:

```bash
# When available:
gh release download v0.1.0 --repo thedivergentai/gd-agentic-skills --pattern "*.safetensors" --dir models/
```

## Usage

```bash
python generate.py --preset char-idle --lora pixel --seed 42
```

The `--lora` flag loads the matching adapter and applies it as a side-adapter on the frozen Bonsai transformer. Works on both ternary and binary gemlite variants.

## Training

These adapters were trained on license-clean CC0/CC-BY game art using the iterative bootstrap method:
1. Curate real CC0 data per style family
2. Train initial LoRA on frozen ternary Bonsai
3. Use trained LoRA to generate synthetic augmentation
4. Retrain on combined real + synthetic data
5. SVD-downrank to minimum viable rank

See the Creation Station skill for full details.
