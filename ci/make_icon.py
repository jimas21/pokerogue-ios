"""Makes the 1024x1024 app icon from the game's own 512x512 icon (Game/logo512.png).

Pixel art, so it is scaled with nearest-neighbour (crisp pixels, no blur). App Store icons must have no
transparency, so it is flattened onto the game's background colour.

Usage: python3 ci/make_icon.py Game/logo512.png App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
"""
import sys

from PIL import Image

BACKGROUND = (72, 64, 80)  # #484050, the game's page background


def main(src: str, dst: str) -> None:
    icon = Image.open(src).convert("RGBA").resize((1024, 1024), Image.NEAREST)
    flat = Image.new("RGB", icon.size, BACKGROUND)
    flat.paste(icon, mask=icon.getchannel("A"))
    flat.save(dst, "PNG")
    print(f"Icon written: {dst} ({flat.size[0]}x{flat.size[1]}, no alpha)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
