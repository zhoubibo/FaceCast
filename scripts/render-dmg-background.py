#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        "/System/Library/Fonts/SFNSRounded.ttf" if bold else "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Avenir Next.ttc",
        "/System/Library/Fonts/HelveticaNeue.ttc",
    ]

    for candidate in candidates:
        path = Path(candidate)
        if path.exists():
            try:
                return ImageFont.truetype(str(path), size=size)
            except OSError:
                continue

    return ImageFont.load_default()


def lerp_channel(start: int, end: int, progress: float) -> int:
    return int(start + (end - start) * progress)


def vertical_gradient(size: tuple[int, int], top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    width, height = size
    image = Image.new("RGB", size)
    draw = ImageDraw.Draw(image)

    for y in range(height):
        progress = y / max(height - 1, 1)
        color = tuple(lerp_channel(top[i], bottom[i], progress) for i in range(3))
        draw.line((0, y, width, y), fill=color)

    return image


def add_glow(base: Image.Image, box: tuple[int, int, int, int], color: tuple[int, int, int], blur: int, alpha: int) -> None:
    overlay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    draw.ellipse(box, fill=(*color, alpha))
    overlay = overlay.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(overlay)


def add_noise(base: Image.Image) -> Image.Image:
    width, height = base.size
    noise = Image.effect_noise((width, height), 10).convert("L")
    noise = ImageChops.multiply(noise, Image.new("L", (width, height), 72))
    noise_layer = Image.new("RGBA", (width, height), (255, 255, 255, 0))
    noise_layer.putalpha(noise)
    return Image.alpha_composite(base, noise_layer)


def draw_arrow(draw: ImageDraw.ImageDraw, start: tuple[int, int], end: tuple[int, int]) -> None:
    x1, y1 = start
    x2, y2 = end
    draw.rounded_rectangle((x1, y1 - 6, x2 - 18, y1 + 6), radius=6, fill=(119, 146, 255, 120))
    draw.polygon(
        [
            (x2 - 24, y2 - 18),
            (x2, y2),
            (x2 - 24, y2 + 18),
        ],
        fill=(160, 127, 255, 180),
    )


def render_background(output_path: Path, icon_path: Path) -> None:
    size = (960, 620)
    base = vertical_gradient(size, (7, 14, 39), (12, 24, 58)).convert("RGBA")

    add_glow(base, (-160, -120, 420, 360), (70, 196, 255), blur=90, alpha=110)
    add_glow(base, (540, -60, 1020, 320), (140, 96, 255), blur=110, alpha=120)
    add_glow(base, (120, 360, 380, 620), (49, 117, 255), blur=80, alpha=90)
    add_glow(base, (620, 360, 900, 620), (143, 94, 255), blur=90, alpha=80)
    base = add_noise(base)

    shadow_layer = Image.new("RGBA", size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow_layer)
    shadow_draw.rounded_rectangle((46, 96, 382, 420), radius=36, fill=(5, 8, 22, 175))
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(16))
    base.alpha_composite(shadow_layer)

    card = Image.new("RGBA", size, (0, 0, 0, 0))
    card_draw = ImageDraw.Draw(card)
    card_draw.rounded_rectangle((58, 84, 370, 396), radius=32, fill=(9, 17, 46, 210), outline=(108, 161, 255, 62), width=1)
    base.alpha_composite(card)

    icon = Image.open(icon_path).convert("RGBA")
    icon.thumbnail((244, 244), Image.LANCZOS)
    icon_shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    shadow = icon.copy()
    shadow.putalpha(160)
    icon_shadow.alpha_composite(shadow, (86, 124))
    icon_shadow = icon_shadow.filter(ImageFilter.GaussianBlur(22))
    base.alpha_composite(icon_shadow)
    base.alpha_composite(icon, (92, 104))

    content = ImageDraw.Draw(base)
    title_font = load_font(44, bold=True)
    subtitle_font = load_font(21)
    pill_font = load_font(17, bold=True)
    footnote_font = load_font(16)

    content.rounded_rectangle((420, 92, 630, 132), radius=18, fill=(15, 29, 70, 215), outline=(96, 160, 255, 110), width=1)
    content.text((444, 102), "Universal macOS app", font=pill_font, fill=(184, 225, 255))

    content.text((420, 170), "Install FaceCast", font=title_font, fill=(244, 248, 255))
    content.text((420, 224), "Drag the app into Applications to install.", font=subtitle_font, fill=(181, 198, 240))
    content.text((420, 260), "Built for screen, camera and audio capture on macOS.", font=subtitle_font, fill=(138, 158, 209))

    content.rounded_rectangle((420, 316, 540, 352), radius=16, fill=(14, 27, 64, 180))
    content.text((443, 325), "1  Open", font=footnote_font, fill=(194, 231, 255))
    content.rounded_rectangle((554, 316, 710, 352), radius=16, fill=(14, 27, 64, 180))
    content.text((577, 325), "2  Drag to install", font=footnote_font, fill=(194, 231, 255))

    draw_arrow(content, (320, 465), (706, 465))
    content.text((182, 514), "FaceCast", font=footnote_font, fill=(201, 219, 255))
    content.text((684, 514), "Applications", font=footnote_font, fill=(201, 219, 255))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    base.save(output_path)


def main() -> None:
    parser = argparse.ArgumentParser(description="Render the branded DMG background for FaceCast.")
    parser.add_argument("--output", required=True, help="Path to the background PNG to write.")
    parser.add_argument(
        "--icon",
        default="FaceCast/Assets.xcassets/AppIcon.appiconset/icon_1024.png",
        help="Path to the source icon PNG.",
    )
    args = parser.parse_args()

    output_path = Path(args.output).resolve()
    icon_path = Path(args.icon).resolve()
    render_background(output_path, icon_path)


if __name__ == "__main__":
    main()
