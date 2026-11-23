import importlib.util
from pathlib import Path
import struct
import unittest
import xml.etree.ElementTree as ET

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("artwork", ROOT / "tools/artwork.py")
artwork = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artwork)


class ArtworkTests(unittest.TestCase):
    def test_compact_backgrounds_fit_four_bits_and_device_palette(self):
        for phase in artwork.PHASES:
            path = ROOT / "resources-fenix5x" / f"{phase}.png"
            with Image.open(path) as image:
                self.assertEqual(image.size, (240, 240))
                self.assertLessEqual(len(image.getcolors()), 16)
                for _, rgb in image.convert("RGB").getcolors():
                    self.assertTrue(all(channel in (0, 85, 170, 255) for channel in rgb))
            header = path.read_bytes()[:29]
            self.assertEqual(struct.unpack(">B", header[24:25])[0], 4)

    def test_resource_references_resolve_for_each_device(self):
        for target, (size, icon_size, _) in artwork.TARGETS.items():
            directory = ROOT / f"resources-{target}"
            resources = ET.parse(directory / "resources.xml").getroot()
            for element in resources:
                self.assertTrue((directory / element.attrib["filename"]).is_file())
            for phase in artwork.PHASES:
                with Image.open(directory / f"{phase}.png") as image:
                    self.assertEqual(image.size, (size, size))
            with Image.open(directory / "icon.png") as image:
                self.assertEqual(image.size, (icon_size, icon_size))

    def test_low_power_positions_are_disjoint_and_sparse(self):
        # Mirrors the actual native-font geometry used by drawAlwaysOn.
        width = 466
        text_width = sum((len(artwork.SMALL[c].split("/")[0]) + 1) * 2 for c in "00:00")
        height = 14
        boxes = []
        for minute in range(4):
            x = round(width * (0.28 if minute % 2 == 0 else 0.55))
            y = round(width * (0.42 if minute < 2 else 0.58))
            boxes.append((x, y, x + text_width, y + height))
        for index, (x0, y0, x1, y1) in enumerate(boxes):
            self.assertLess(text_width * height, 0.1 * 3.14159 * (width / 2) ** 2)
            for a0, b0, a1, b1 in boxes[index + 1:]:
                self.assertFalse(x0 < a1 and a0 < x1 and y0 < b1 and b0 < y1)


if __name__ == "__main__":
    unittest.main()
