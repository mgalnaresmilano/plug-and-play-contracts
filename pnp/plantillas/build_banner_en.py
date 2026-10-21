"""Repaint the template's cover banner in English.

The banner is a bitmap inside the .docx, so its Spanish title cannot be
translated by editing the document text. This repaints the title band of the
original artwork, keeping the Plug and Play logo and the background intact.

Usage: python3 build_banner_en.py
"""

import zipfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).parent
SOURCE = HERE / "original" / "PlugAndPlay_Contract_Template.docx"
OUTPUT = HERE / "original" / "banner_en.png"

TITLE = "MEMBERSHIP AGREEMENT"
SUBTITLE = "Ecosystem Plus  |  Plug and Play Tech Center"

# Geometry measured on the original 2100x470 artwork.
BAND = (230, 435)          # rows holding the Spanish title, bar and subtitle
CLEAN_ROW = 220            # the band has no vertical gradient, so one row tiles it
SAFE_WIDTH = 1340          # left of the decorative circles
LEFT = 130
TITLE_TOP, TITLE_MAX = 250, 1150
BAR = (128, 338, 371, 350)
SUBTITLE_TOP = 374
ACCENT = (2, 244, 228)
BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
REGULAR = "/System/Library/Fonts/Supplemental/Arial.ttf"


def fitted(path, text, max_width, start):
    for size in range(start, 20, -2):
        font = ImageFont.truetype(path, size)
        if font.getbbox(text)[2] <= max_width:
            return font
    raise ValueError("Text does not fit")


def main():
    with zipfile.ZipFile(SOURCE) as docx:
        OUTPUT.write_bytes(docx.read("word/media/image1.png"))

    image = Image.open(OUTPUT).convert("RGB")
    background = image.crop((0, CLEAN_ROW, SAFE_WIDTH, CLEAN_ROW + 1))
    for y in range(*BAND):
        image.paste(background, (0, y))

    draw = ImageDraw.Draw(image)
    title_font = fitted(BOLD, TITLE, TITLE_MAX - LEFT, 76)
    draw.text((LEFT, TITLE_TOP), TITLE, font=title_font, fill=(255, 255, 255))
    draw.rectangle(BAR, fill=ACCENT)
    draw.text((LEFT, SUBTITLE_TOP), SUBTITLE,
              font=ImageFont.truetype(REGULAR, 26), fill=(198, 208, 232))

    image.save(OUTPUT)
    print(f"Saved {OUTPUT}")


if __name__ == "__main__":
    main()
