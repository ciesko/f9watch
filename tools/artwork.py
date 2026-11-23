"""Regenerate device resources from the four recovered master scenes."""

from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
PHASES = ("dawn", "day", "dusk", "night")
TARGETS = {"fenix9pro51mm": (466, 65, 6), "fenix5x": (240, 40, 4)}

BIG = {
    "0": ".####./######/##..##/##..##/##..##/##..##/##..##/######/.####.",
    "1": "..##../.###../####../..##../..##../..##../..##../######/######",
    "2": ".####./######/##..##/....##/...###/..###./.###../######/######",
    "3": "#####./######/....##/..####/..####/....##/....##/######/#####.",
    "4": "...###/..####/.##.##/##..##/######/######/....##/....##/....##",
    "5": "######/######/##..../#####./######/....##/....##/######/#####.",
    "6": ".####./#####./##..../#####./######/##..##/##..##/######/.####.",
    "7": "######/######/....##/...##./..###./..##../.##.../.##.../.##...",
    "8": ".####./######/##..##/##..##/.####./##..##/##..##/######/.####.",
    "9": ".####./######/##..##/##..##/######/.#####/....##/.#####/.####.",
    ":": "../../##/##/../../##/##/..",
}
SMALL = {
    "0": ".###./#...#/#..##/#.#.#/##..#/#...#/.###.",
    "1": "..#../.##../..#../..#../..#../..#../.###.",
    "2": ".###./#...#/....#/...#./..#../.#.../#####",
    "3": "####./....#/....#/.###./....#/....#/####.",
    "4": "...#./..##./.#.#./#..#./#####/...#./...#.",
    "5": "#####/#..../####./....#/....#/#...#/.###.",
    "6": ".###./#..../#..../####./#...#/#...#/.###.",
    "7": "#####/....#/...#./..#../.#.../.#.../.#...",
    "8": ".###./#...#/#...#/.###./#...#/#...#/.###.",
    "9": ".###./#...#/#...#/.####/....#/....#/.###.",
    "A": ".###./#...#/#...#/#####/#...#/#...#/#...#",
    "B": "####./#...#/#...#/####./#...#/#...#/####.",
    "C": ".###./#...#/#..../#..../#..../#...#/.###.",
    "D": "####./#...#/#...#/#...#/#...#/#...#/####.",
    "E": "#####/#..../#..../####./#..../#..../#####",
    "F": "#####/#..../#..../####./#..../#..../#....",
    "G": ".###./#...#/#..../#.###/#...#/#...#/.####",
    "H": "#...#/#...#/#...#/#####/#...#/#...#/#...#",
    "I": "###/.#./.#./.#./.#./.#./###",
    "J": "..###/...#./...#./...#./...#./#..#./.##..",
    "K": "#...#/#..#./#.#../##.../#.#../#..#./#...#",
    "L": "#..../#..../#..../#..../#..../#..../#####",
    "M": "#...#/##.##/#.#.#/#.#.#/#...#/#...#/#...#",
    "N": "#...#/#...#/##..#/#.#.#/#..##/#...#/#...#",
    "O": ".###./#...#/#...#/#...#/#...#/#...#/.###.",
    "P": "####./#...#/#...#/####./#..../#..../#....",
    "Q": ".###./#...#/#...#/#...#/#.#.#/#..#./.##.#",
    "R": "####./#...#/#...#/####./#.#../#..#./#...#",
    "S": ".####/#..../#..../.###./....#/....#/####.",
    "T": "#####/..#../..#../..#../..#../..#../..#..",
    "U": "#...#/#...#/#...#/#...#/#...#/#...#/.###.",
    "V": "#...#/#...#/#...#/#...#/#...#/.#.#./..#..",
    "W": "#...#/#...#/#...#/#.#.#/#.#.#/#.#.#/.#.#.",
    "X": "#...#/#...#/.#.#./..#../.#.#./#...#/#...#",
    "Y": "#...#/#...#/.#.#./..#../..#../..#../..#..",
    "Z": "#####/....#/...#./..#../.#.../#..../#####",
    "%": "##..#/##..#/...#./..#../.#.../#..##/#..##",
    ",": "../../../../../.#/#.",
    "-": ".../.../.../###/.../.../...",
    ":": "././#/././#/.",
    " ": ".../.../.../.../.../.../...",
    "<": ".#.#./#####/#####/#####/.###./..#../.....",
    "^": ".##.../###.../###.##/.#.###/##.###/....#./...##.",
    "*": "..#../.###./#####/.###./..#../...../.....",
}


def rgb222_16(image):
    colors = [(r, g, b) for r in (0, 85, 170, 255)
              for g in (0, 85, 170, 255) for b in (0, 85, 170, 255)]
    full = Image.new("P", (1, 1))
    full.putpalette([c for rgb in colors for c in rgb] + [0] * (768 - 192))
    first = image.convert("RGB").quantize(palette=full, dither=Image.Dither.FLOYDSTEINBERG)
    chosen = [colors[index] for _, index in sorted(first.getcolors(), reverse=True)[:16]]
    palette = Image.new("P", (1, 1))
    padded = chosen + [chosen[0]] * (256 - len(chosen))
    palette.putpalette([c for rgb in padded for c in rgb])
    output = image.convert("RGB").quantize(palette=palette, dither=Image.Dither.FLOYDSTEINBERG)
    return output, chosen


def write_font(directory, name, glyphs, scale):
    rows = {char: pattern.split("/") for char, pattern in glyphs.items()}
    height = len(next(iter(rows.values()))) * scale
    widths = {char: len(pattern[0]) * scale for char, pattern in rows.items()}
    width = sum(w + scale for w in widths.values())
    atlas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(atlas)
    entries = []
    x = 0
    for char, pattern in rows.items():
        for y, row in enumerate(pattern):
            for column, pixel in enumerate(row):
                if pixel == "#":
                    left, top = x + column * scale, y * scale
                    draw.rectangle((left, top, left + scale - 1, top + scale - 1),
                                   fill=(255, 255, 255, 255))
        w = widths[char]
        entries.append(f"char id={ord(char)} x={x} y=0 width={w} height={height} "
                       f"xoffset=0 yoffset=0 xadvance={w + scale} page=0 chnl=15")
        x += w + scale
    atlas.save(directory / f"{name}.png")
    header = [
        f'info face="MarsPixel" size={height} bold=0 italic=0 charset="" unicode=1 '
        'stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=0,0',
        f"common lineHeight={height} base={height} scaleW={width} scaleH={height} "
        "pages=1 packed=0 alphaChnl=1 redChnl=0 greenChnl=0 blueChnl=0",
        f'page id=0 file="{name}.png"',
        f"chars count={len(entries)}",
    ]
    (directory / f"{name}.fnt").write_text("\n".join(header + entries) + "\n")


def main():
    for target, (size, icon_size, time_scale) in TARGETS.items():
        directory = ROOT / f"resources-{target}"
        directory.mkdir(exist_ok=True)
        xml = ["<resources>"]
        for phase in PHASES:
            with Image.open(ROOT / "art" / f"{phase}.png") as master:
                image = master.convert("RGB").resize((size, size), Image.Resampling.LANCZOS)
            if target == "fenix5x":
                image, palette = rgb222_16(image)
                image.save(directory / f"{phase}.png", bits=4, optimize=True)
                xml.append(f'    <bitmap id="{phase.title()}" filename="{phase}.png" dithering="none">')
                xml.append('        <palette disableTransparency="true">')
                xml.extend(f"            <color>{r:02x}{g:02x}{b:02x}</color>" for r, g, b in palette)
                xml.extend(["        </palette>", "    </bitmap>"])
            else:
                image.save(directory / f"{phase}.png", optimize=True)
                xml.append(f'    <bitmap id="{phase.title()}" filename="{phase}.png" '
                           'automaticPalette="true" compress="true"/>')
        with Image.open(ROOT / "art" / "night.png") as master:
            icon = master.convert("RGB").resize((icon_size, icon_size), Image.Resampling.LANCZOS)
        if target == "fenix5x":
            icon, _ = rgb222_16(icon)
        icon.save(directory / "icon.png")
        xml.extend([
            '    <bitmap id="LauncherIcon" filename="icon.png"/>',
            '    <font id="TimeFont" filename="time.fnt" antialias="false"/>',
            '    <font id="SmallFont" filename="small.fnt" antialias="false"/>',
            "</resources>",
        ])
        write_font(directory, "time", BIG, time_scale)
        write_font(directory, "small", SMALL, 2)
        (directory / "resources.xml").write_text("\n".join(xml) + "\n")
        print(f"Generated {target}: {size}x{size}")


if __name__ == "__main__":
    main()
