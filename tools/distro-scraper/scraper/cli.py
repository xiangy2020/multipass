import argparse
import asyncio
import json
import pathlib
import sys
import logging
from importlib.metadata import entry_points
from pydantic import ValidationError
from scraper.base import BaseScraper
from scraper.models import ScraperResult


logger = logging.getLogger(__name__)


def configure_logging() -> None:
    """
    Configure root logger for CLI usage.
    """
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        stream=sys.stdout,
    )


def load_scrapers() -> list[BaseScraper]:
    """
    Load all scraper classes from registered entry points.
    """
    scrapers = []

    eps = entry_points(group="dist_scraper.scrapers")
    for ep in eps:
        logger.info("Loading scraper plugin: %s", ep.name)
        scraper_class = ep.load()
        if isinstance(scraper_class, type) and issubclass(scraper_class, BaseScraper):
            scrapers.append(scraper_class())
        else:
            logger.warning(
                "Entry point %s did not provide a valid scraper class", ep.name
            )

    return scrapers


def write_output_file(output: dict, path: pathlib.Path) -> None:
    """
    Attempt to merge output with existing data at the given path.

    If the file exists, load it and merge with new data. Only distributions
    present in 'output' will be updated; others are preserved.

    If the file does not exist or is invalid, it will be created anew.
    """
    # Load existing data if file exists
    existing_data = {}
    if path.exists():
        try:
            raw_data = json.loads(path.read_text())
            # Validate existing data against schema
            for dist_name, dist_data in raw_data.items():
                try:
                    validated = ScraperResult(**dist_data)
                    existing_data[dist_name] = validated.model_dump()
                except ValidationError as e:
                    logger.warning(
                        "Existing data for '%s' is invalid and will be discarded: %s",
                        dist_name,
                        e,
                    )
            logger.info(
                "Loaded existing data from %s (%d valid distribution(s))",
                path,
                len(existing_data),
            )
        except (json.JSONDecodeError, OSError) as e:
            logger.warning("Could not load existing output file: %s", e)

    # Merge new data into existing
    for dist_name, dist_data in output.items():
        if dist_name in existing_data:
            merged_items = existing_data[dist_name].get("items", {})
            merged_items.update(dist_data.get("items", {}))
            existing_data[dist_name] = {**dist_data, "items": merged_items}
        else:
            existing_data[dist_name] = dist_data

    # Write merged output
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as f:
        json.dump(existing_data, f, indent=4, sort_keys=True)
        f.write("\n")

    logger.info("Output written to %s", path)


async def run_scraper(scraper_instance: BaseScraper) -> tuple[str, dict[str, dict] | None]:
    """
    Run a single scraper.fetch and capture exceptions.

    Returns a tuple of (scraper_name, entries_dict) where entries_dict maps
    distribution keys to their validated data. A scraper may return a single
    dict (one distribution) or a list of dicts (multiple distributions, e.g.
    multiple versions of the same OS).
    """
    name = scraper_instance.name

    try:
        result = await scraper_instance.fetch()
    except Exception as e:
        logger.exception("Scraper '%s' failed: %s", name, e)
        return name, None

    # Normalize to list for uniform processing
    if isinstance(result, dict):
        result_list = [(name, result)]
    elif isinstance(result, list):
        # Each item in the list should have a 'release_title' to form a unique key
        result_list = []
        for item in result:
            version = item.get("release_title", "")
            key = f"{name}{version}" if version else name
            result_list.append((key, item))
    else:
        logger.error("Scraper '%s' returned unexpected type: %s", name, type(result))
        return name, None

    # Validate each entry
    entries: dict[str, dict] = {}
    for key, data in result_list:
        try:
            validated = ScraperResult(**data)
            entries[key] = validated.model_dump()
            logger.info("Scraper '%s' entry '%s' succeeded", name, key)
        except ValidationError as e:
            logger.error("Scraper '%s' entry '%s' returned invalid structure:\n%s", name, key, e)
        except Exception as e:
            logger.exception("Unexpected error validating scraper '%s' entry '%s': %s", name, key, e)

    if not entries:
        return name, None

    return name, entries


async def run_all_scrapers(output_file: pathlib.Path) -> None:
    """
    Run all registered scrapers concurrently and write output.
    """
    scrapers = load_scrapers()
    output = {}

    # Run scrapers concurrently using asyncio.gather
    tasks = [run_scraper(s) for s in scrapers]
    completed = await asyncio.gather(*tasks)

    # Populate output
    failed_scrapers = []
    for name, data in completed:
        if data:
            # data is now a dict[str, dict] mapping keys to distribution entries
            output.update(data)
        else:
            failed_scrapers.append(name)

    # Write final JSON output
    write_output_file(output, output_file)
    if not failed_scrapers:
        logger.info("All scrapers succeeded.")
    else:
        logger.warning("Some scrapers failed: %s", ", ".join(failed_scrapers))

def main():
    parser = argparse.ArgumentParser(
        description="Scrape distribution information from various Linux distributions"
    )
    parser.add_argument(
        "output_file", type=pathlib.Path, help="Path to the output JSON file"
    )
    args = parser.parse_args()

    configure_logging()

    try:
        asyncio.run(run_all_scrapers(args.output_file))
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
        exit(130)
