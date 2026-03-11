import os
import re
import json
import zipfile
import logging
import cv2
import numpy as np
import pandas as pd
import albumentations as A
from datasets_config import DATASETS
from pathlib import Path
from dotenv import load_dotenv
from PIL import Image, UnidentifiedImageError
from collections import defaultdict
from kaggle.api.kaggle_api_extended import KaggleApi

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger(__name__)

RAW_DIR = Path("data/raw")
OUTPUT_DIR = Path("data/processed")
IMG_SIZE = (224, 224)
MEAN = [0.485, 0.456, 0.406]
STD = [0.229, 0.224, 0.225]
MIN_FILE_SIZE = 2_000
MIN_DIM = 64
BLUR_THRESHOLD = 80.0
AUGMENT_COPIES = 3


def get_kaggle_api() -> KaggleApi:
    log.info("[Auth] Loading .env credentials ...")
    load_dotenv()
    os.environ["KAGGLE_USERNAME"]  = os.getenv("KAGGLE_USERNAME", "")
    os.environ["KAGGLE_API_TOKEN"] = os.getenv("KAGGLE_API_TOKEN", "")
    if not os.environ["KAGGLE_USERNAME"] or not os.environ["KAGGLE_API_TOKEN"]:
        raise ValueError("KAGGLE_USERNAME or KAGGLE_API_TOKEN missing from .env file")
    log.info(f"[Auth] Authenticating as '{os.environ['KAGGLE_USERNAME']}' ...")
    api = KaggleApi()
    api.authenticate()
    log.info("[Auth] Authentication successful")
    return api


def download_and_unzip(api: KaggleApi, slug: str, dest: Path) -> Path:
    dest.mkdir(parents=True, exist_ok=True)
    dataset_dir = dest / slug.split("/")[-1]

    if dataset_dir.exists() and any(dataset_dir.iterdir()):
        log.info(f"[Kaggle] Skipping {slug} — already exists at {dataset_dir}")
        return dataset_dir

    log.info(f"[Kaggle] Starting download: {slug}")
    api.dataset_download_files(slug, path=str(dest), quiet=False, unzip=False)
    log.info(f"[Kaggle] Download complete: {slug}")

    zip_path = dest / (slug.split("/")[-1] + ".zip")
    if not zip_path.exists():
        zips = list(dest.glob("*.zip"))
        if not zips:
            raise FileNotFoundError(f"No zip found in {dest} after downloading {slug}")
        zip_path = zips[-1]

    log.info(f"[Kaggle] Unzipping {zip_path} ...")
    dataset_dir.mkdir(exist_ok=True)
    with zipfile.ZipFile(zip_path, "r") as zf:
        zf.extractall(dataset_dir)
    zip_path.unlink()
    log.info(f"[Kaggle] Unzip complete → {dataset_dir}")
    return dataset_dir


def download_all(api: KaggleApi) -> dict[str, Path]:
    log.info(f"[Kaggle] Preparing to download {len(DATASETS)} datasets ...")
    paths = {}
    for i, (name, slug) in enumerate(DATASETS.items(), 1):
        log.info(f"[Kaggle] [{i}/{len(DATASETS)}] {name}")
        paths[name] = download_and_unzip(api, slug, RAW_DIR / name)
    log.info("[Kaggle] All datasets ready")
    return paths


def load_food101(root: Path) -> dict:
    log.info(f"[Food-101] Searching for images/ under {root}")
    candidates = [p for p in root.rglob("images") if p.is_dir()]
    log.info(f"[Food-101] Found {len(candidates)} images/ folder(s): {[str(c) for c in candidates]}")
    images_dir = max(candidates, key=lambda p: len(list(p.iterdir())), default=None)
    if images_dir is None:
        log.warning(f"[Food-101] images/ folder not found under {root}")
        return {}
    log.info(f"[Food-101] Using {images_dir}")
    ds = defaultdict(list)
    for cls_dir in images_dir.iterdir():
        if cls_dir.is_dir():
            imgs = list(cls_dir.glob("*.jpg"))
            ds[cls_dir.name].extend(imgs)
            log.info(f"[Food-101]   {cls_dir.name}: {len(imgs)} images")
    log.info(f"[Food-101] Total: {sum(len(v) for v in ds.values())} images across {len(ds)} classes")
    return dict(ds)


def load_food_ingredients(root: Path) -> dict:
    log.info(f"[Food-Ingredients] Searching for CSV under {root}")
    csv_path = next(root.rglob("*Mapping*.csv"), None) or next(root.rglob("*.csv"), None)
    if csv_path is None:
        log.warning("[Food-Ingredients] No CSV found.")
        return {}
    log.info(f"[Food-Ingredients] Found CSV: {csv_path}")
    df = pd.read_csv(csv_path)
    log.info(f"[Food-Ingredients] CSV loaded: {len(df)} rows")

    img_dirs = [p for p in root.rglob("*") if p.is_dir()]
    img_dir = max(img_dirs, key=lambda d: len(list(d.glob("*.jpg"))), default=root)
    log.info(f"[Food-Ingredients] Using image folder: {img_dir} ({len(list(img_dir.glob('*.jpg')))} jpgs)")

    ds = defaultdict(list)
    missing = 0
    for _, row in df.iterrows():
        title    = str(row.get("Title", "unknown")).strip()
        img_name = str(row.get("Image_Name", "")).strip()
        if not img_name:
            continue
        p = img_dir / (img_name + ".jpg")
        if p.exists():
            ds[title].append(p)
        else:
            missing += 1

    log.info(f"[Food-Ingredients] Matched: {sum(len(v) for v in ds.values())} images, Missing: {missing}")
    log.info(f"[Food-Ingredients] Total: {sum(len(v) for v in ds.values())} images across {len(ds)} classes")
    return dict(ds)


def load_food_recognition_2022(root: Path) -> dict:
    log.info(f"[Food-Recog-2022] Loading from {root}")
    ds = defaultdict(list)
    for split in ("train", "val", "test"):
        split_dir = root / split
        if not split_dir.exists():
            log.info(f"[Food-Recog-2022] No {split}/ split found, skipping")
            continue
        ann_path = split_dir / "annotations.json"
        img_dir  = split_dir / "images"
        if not ann_path.exists() or not img_dir.exists():
            log.warning(f"[Food-Recog-2022] Missing annotations.json or images/ in {split_dir}")
            continue
        log.info(f"[Food-Recog-2022] Processing {split} split ...")
        ann     = json.loads(ann_path.read_text())
        cat_map = {c["id"]: c["name"] for c in ann.get("categories", [])}
        img_map = {i["id"]: i["file_name"] for i in ann.get("images", [])}
        log.info(f"[Food-Recog-2022]   {split}: {len(img_map)} images, {len(cat_map)} categories")
        img_label: dict[int, str] = {}
        for a in ann.get("annotations", []):
            if a["image_id"] not in img_label:
                img_label[a["image_id"]] = cat_map.get(a["category_id"], "unknown")
        matched = 0
        for img_id, label in img_label.items():
            p = img_dir / img_map.get(img_id, "")
            if p.exists():
                ds[label].append(p)
                matched += 1
        log.info(f"[Food-Recog-2022]   {split}: matched {matched} images")

    log.info(f"[Food-Recog-2022] Total: {sum(len(v) for v in ds.values())} images across {len(ds)} classes")
    return dict(ds)


def load_food11(root: Path) -> dict:
    CLASS_MAP = {
        "0": "Bread", "1": "Dairy_product", "2": "Dessert", "3": "Egg",
        "4": "Fried_food", "5": "Meat", "6": "Noodles_Pasta", "7": "Rice",
        "8": "Seafood", "9": "Soup", "10": "Vegetable_Fruit",
    }
    log.info(f"[Food-11] Loading from {root}")
    ds = defaultdict(list)
    for split in ("training", "validation", "evaluation"):
        split_dir = root / split
        if not split_dir.exists():
            log.warning(f"[Food-11] {split}/ not found, skipping")
            continue
        split_count = 0
        for cls_dir in split_dir.iterdir():
            if cls_dir.is_dir():
                label = CLASS_MAP.get(cls_dir.name, cls_dir.name)
                imgs = [img for img in cls_dir.glob("*") if img.suffix.lower() in {".jpg", ".jpeg", ".png"}]
                ds[label].extend(imgs)
                split_count += len(imgs)
        log.info(f"[Food-11] {split}: {split_count} images")

    log.info(f"[Food-11] Total: {sum(len(v) for v in ds.values())} images across {len(ds)} classes")
    return dict(ds)


def load_multiclass(root: Path) -> dict:
    log.info(f"[Multi-Class] Loading from {root}")
    ds = defaultdict(list)
    for cls_dir in root.iterdir():
        if cls_dir.is_dir():
            imgs = [img for img in cls_dir.glob("*") if img.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}]
            ds[cls_dir.name].extend(imgs)
            log.info(f"[Multi-Class]   {cls_dir.name}: {len(imgs)} images")
    log.info(f"[Multi-Class] Total: {sum(len(v) for v in ds.values())} images across {len(ds)} classes")
    return dict(ds)


def load_uecfood256(root: Path) -> dict:
    log.info(f"[UECFOOD256] Loading from {root}")
    uec_dir  = root / "UECFOOD256" if (root / "UECFOOD256").exists() else root
    cat_file = uec_dir / "category.txt"
    if not cat_file.exists():
        log.warning(f"[UECFOOD256] category.txt not found under {uec_dir}")
        return {}
    log.info(f"[UECFOOD256] Reading category.txt from {cat_file}")
    cat_map = {}
    for line in cat_file.read_text(encoding="utf-8", errors="ignore").splitlines():
        parts = line.strip().split("\t")
        if len(parts) >= 2:
            cat_map[parts[0].strip()] = parts[1].strip()
    log.info(f"[UECFOOD256] {len(cat_map)} categories found")
    ds = defaultdict(list)
    for folder in uec_dir.iterdir():
        if folder.is_dir() and folder.name in cat_map:
            imgs = list(folder.glob("*.jpg"))
            ds[cat_map[folder.name]].extend(imgs)
            log.info(f"[UECFOOD256]   {cat_map[folder.name]}: {len(imgs)} images")
    log.info(f"[UECFOOD256] Total: {sum(len(v) for v in ds.values())} images across {len(ds)} classes")
    return dict(ds)


def sanitize_label(label: str) -> str:
    label = re.sub(r'[^\w\s-]', '', label)
    label = re.sub(r'[\s]+', '_', label.strip())
    return label[:64]


def merge_datasets(*datasets: dict) -> dict:
    log.info(f"[Merge] Merging {len(datasets)} datasets ...")
    merged = defaultdict(list)
    for ds in datasets:
        for label, paths in ds.items():
            merged[label].extend(paths)
    total = sum(len(v) for v in merged.values())
    log.info(f"[Merge] Done — {total} total images across {len(merged)} classes")
    return dict(merged)


def is_blurry(arr: np.ndarray) -> bool:
    gray = cv2.cvtColor(arr, cv2.COLOR_RGB2GRAY)
    return cv2.Laplacian(gray, cv2.CV_64F).var() < BLUR_THRESHOLD


def quality_check(img_path: Path) -> tuple[bool, str]:
    if img_path.stat().st_size < MIN_FILE_SIZE:
        return False, "file_too_small"
    try:
        with Image.open(img_path) as img:
            img.verify()
        with Image.open(img_path) as img:
            arr = np.array(img.convert("RGB"))
    except Exception:
        return False, "corrupted"
    if min(arr.shape[:2]) < MIN_DIM:
        return False, "too_small"
    if is_blurry(arr):
        return False, "blurry"
    return True, "ok"


def preprocess(arr_u8: np.ndarray) -> np.ndarray:
    resized = cv2.resize(arr_u8, (IMG_SIZE[1], IMG_SIZE[0]), interpolation=cv2.INTER_LANCZOS4)
    return ((resized.astype(np.float32) / 255.0) - MEAN) / STD


augment = A.Compose([
    A.RandomBrightnessContrast(brightness_limit=0.4, contrast_limit=0.4, p=0.7),
    A.RandomGamma(gamma_limit=(60, 140), p=0.5),
    A.CLAHE(clip_limit=4.0, p=0.3),
    A.OneOf([A.MotionBlur(blur_limit=(3, 9)), A.GaussianBlur(blur_limit=(3, 7))], p=0.5),
    A.ShiftScaleRotate(shift_limit=0.05, scale_limit=0.1, rotate_limit=15, p=0.7),
    A.HorizontalFlip(p=0.5),
    A.CoarseDropout(max_holes=4, max_height=32, max_width=32, fill_value=0, p=0.4),
    A.ISONoise(color_shift=(0.01, 0.05), intensity=(0.1, 0.5), p=0.3),
    A.ImageCompression(quality_lower=60, quality_upper=95, p=0.3),
])


def run_pipeline(dataset: dict, output_dir: Path = OUTPUT_DIR):
    output_dir.mkdir(parents=True, exist_ok=True)
    total_images = sum(len(v) for v in dataset.values())
    log.info(f"[Pipeline] Starting — {total_images} images across {len(dataset)} classes")

    stats = {"kept": 0, "dropped": defaultdict(int), "augmented": 0}
    label_map: dict[str, int] = {}
    manifest: list[dict] = []
    processed_classes = 0

    for label, paths in dataset.items():
        processed_classes += 1
        cls_id  = label_map.setdefault(label, len(label_map))
        cls_dir = output_dir / sanitize_label(label)
        cls_dir.mkdir(exist_ok=True)
        cls_kept = 0
        cls_dropped = 0

        log.info(f"[Pipeline] [{processed_classes}/{len(dataset)}] '{label}' — {len(paths)} images")

        for img_path in paths:
            keep, reason = quality_check(img_path)
            if not keep:
                stats["dropped"][reason] += 1
                cls_dropped += 1
                log.debug(f"[Pipeline] Dropped ({reason}): {img_path.name}")
                continue
            try:
                with Image.open(img_path) as img:
                    arr_u8 = np.array(img.convert("RGB"))
            except Exception as e:
                stats["dropped"]["read_error"] += 1
                cls_dropped += 1
                log.warning(f"[Pipeline] Read error: {img_path.name} — {e}")
                continue

            stem = img_path.stem
            np.save(cls_dir / f"{stem}.npy", preprocess(arr_u8).astype(np.float32))
            manifest.append({"path": str(cls_dir / f"{stem}.npy"), "label": label,
                              "class_id": cls_id, "augmented": False})
            stats["kept"] += 1
            cls_kept += 1

            for i, aug_u8 in enumerate([augment(image=arr_u8)["image"] for _ in range(AUGMENT_COPIES)]):
                aug_path = cls_dir / f"{stem}_aug{i}.npy"
                np.save(aug_path, preprocess(aug_u8).astype(np.float32))
                manifest.append({"path": str(aug_path), "label": label,
                                  "class_id": cls_id, "augmented": True})
                stats["augmented"] += 1

        log.info(f"[Pipeline] Kept: {cls_kept}, Dropped: {cls_dropped}, Augmented: {cls_kept * AUGMENT_COPIES}")

    log.info("[Pipeline] Writing manifest.json and label_map.json ...")
    (output_dir / "manifest.json").write_text(json.dumps(manifest, indent=2))
    (output_dir / "label_map.json").write_text(json.dumps(label_map, indent=2))

    log.info("Pipeline Complete")
    log.info(f" Kept (original): {stats['kept']}")
    log.info(f" Augmented copies: {stats['augmented']}")
    log.info(f" Total saved: {stats['kept'] + stats['augmented']}")
    log.info(f" Dropped: {dict(stats['dropped'])}")
    log.info(f" Classes: {len(label_map)}")
    return manifest, label_map


if __name__ == "__main__":
    log.info("Food Image Pipeline Starting")
    api = get_kaggle_api()
    paths = download_all(api)

    log.info("Loading Datasets")
    combined = merge_datasets(
        load_food101(paths["food-101"]),
        load_food_ingredients(paths["food-ingredients-and-recipe-dataset-with-images"]),
        load_food_recognition_2022(paths["food-recognition-2022"]),
        load_food11(paths["food11-image-dataset"]),
        load_multiclass(paths["multi-class-food-image-dataset"]),
        load_uecfood256(paths["uecfood256"]),
    )

    log.info("Running Pipeline")
    run_pipeline(combined)
    log.info("All Done")