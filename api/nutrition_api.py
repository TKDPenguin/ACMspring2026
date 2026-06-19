import os
import logging
import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger(__name__)

USDA_API_KEY = os.getenv("USDA_API_KEY")
USDA_SEARCH_URL = "https://api.nal.usda.gov/fdc/v1/foods/search"

app = FastAPI(title="Food Nutrition API")


class NutritionInfo(BaseModel):
    food_name:       str
    serving_size_g:  float | None = None
    calories_kcal:   float | None = None
    total_fat_g:     float | None = None
    saturated_fat_g: float | None = None
    trans_fat_g:     float | None = None
    cholesterol_mg:  float | None = None
    sodium_mg:       float | None = None
    total_carbs_g:   float | None = None
    dietary_fiber_g: float | None = None
    total_sugars_g:  float | None = None
    protein_g:       float | None = None
    vitamin_d_mcg:   float | None = None
    calcium_mg:      float | None = None
    iron_mg:         float | None = None
    potassium_mg:    float | None = None


# Map USDA nutrient names to our response fields
NUTRIENT_MAP = {
    "Energy":                 "calories_kcal",
    "Total lipid (fat)":      "total_fat_g",
    "Fatty acids, total saturated": "saturated_fat_g",
    "Fatty acids, total trans": "trans_fat_g",
    "Cholesterol":            "cholesterol_mg",
    "Sodium, Na":             "sodium_mg",
    "Carbohydrate, by difference": "total_carbs_g",
    "Fiber, total dietary":   "dietary_fiber_g",
    "Sugars, total including NLEA": "total_sugars_g",
    "Total Sugars":           "total_sugars_g",
    "Protein":                "protein_g",
    "Vitamin D (D2 + D3)":    "vitamin_d_mcg",
    "Calcium, Ca":            "calcium_mg",
    "Iron, Fe":               "iron_mg",
    "Potassium, K":           "potassium_mg",
}


def parse_nutrients(food: dict) -> NutritionInfo:
    """Extract nutrition fields from a USDA food item."""
    nutrients = {}
    for n in food.get("foodNutrients", []):
        name = n.get("nutrientName", "")
        if name in NUTRIENT_MAP:
            field = NUTRIENT_MAP[name]
            # Only set if not already populated (first match wins)
            if field not in nutrients:
                nutrients[field] = n.get("value")

    return NutritionInfo(
        food_name=food.get("description", "Unknown"),
        serving_size_g=food.get("servingSize"),
        **nutrients,
    )


async def search_usda(food_name: str) -> NutritionInfo | None:
    """Search the USDA FoodData Central database for a food item."""
    if not USDA_API_KEY:
        raise HTTPException(status_code=500, detail="USDA_API_KEY is not configured")

    log.info(f"[USDA] Searching for '{food_name}' ...")
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(USDA_SEARCH_URL, params={
                "api_key":    USDA_API_KEY,
                "query":      food_name,
                "pageSize":   1,
                "dataType":   "SR Legacy,Foundation",
            })
            resp.raise_for_status()
        except httpx.HTTPStatusError as e:
            log.error(f"[USDA] API returned {e.response.status_code}")
            raise HTTPException(status_code=502, detail="USDA nutrition service returned an error")
        except httpx.RequestError as e:
            log.error(f"[USDA] Request failed: {e}")
            raise HTTPException(status_code=502, detail="Could not reach USDA nutrition service")

    foods = resp.json().get("foods", [])
    if not foods:
        log.info(f"[USDA] No results for '{food_name}'")
        return None

    log.info(f"[USDA] Found '{foods[0].get('description')}'")
    return parse_nutrients(foods[0])


@app.get("/nutrition/{food_name}", response_model=NutritionInfo)
async def get_nutrition(food_name: str):
    log.info(f"[API] GET /nutrition/{food_name}")
    result = await search_usda(food_name)
    if not result:
        raise HTTPException(status_code=404, detail=f"No nutrition data found for '{food_name}'")
    return result


@app.get("/health")
async def health():
    return {"status": "ok"}
