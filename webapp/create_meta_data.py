"""Create meta-data json file with all test names"""

import argparse
from pathlib import Path
import json


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    args = parser.parse_args()

    meta_data = {
        "tests": names(args.path / "tests"),
        "snippets": names(args.path / "snippets"),
        "apps": names(args.path / "apps"),
    }
    meta_data_filename = args.path / "meta-data.json"
    with open(meta_data_filename, "w") as f:
        json.dump(meta_data, f)
    print(f"Generated: {meta_data_filename}")


def names(path):
    return sorted([p.stem for p in path.glob("*.wasm")])


if __name__ == "__main__":
    main()
