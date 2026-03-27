"""EGX (Egyptian Exchange) sector classification for stock symbols."""
from __future__ import annotations
from typing import Dict, List, Set

# Sector mapping: sector name -> set of ticker symbols (without EGX: prefix)
EGX_SECTORS: Dict[str, Set[str]] = {

    "banks": {
        "CANA",  # Suez Canal Bank
        "EXPA",  # Export Development Bank
        "CIEB",  # Credit Agricole Egypt
        "SAUD",  # Al Baraka Bank
        "UBEE",  # The United Bank
        "EGBE",  # Egyptian Gulf Bank
        "HDBK",  # Housing & Development Bank
        "FAIT",  # Faisal Islamic Bank
        "QNBE",  # QNB Alahli
        "COMI",  # CIB
        "ADIB",  # ADIB Egypt
    },

    "basic_resources": {
        "ATQA",
        "MICH",
        "KZPC",
        "FERC",
        "ASCM",
        "SKPC",
        "ISMQ",
        "EGCH",
        "MFPC",
        "IRON",
        "ALUM",
        "MFSC",
        "EGAL",
        "ABUK",
    },

    "healthcare_and_pharma": {
        "MIPH",
        "RMDA",
        "AXPH",
        "OCPH",
        "APPC",
        "SPMD",
        "MCRO",
        "ISPH",
        "CLHO",
        "PRMH",
    },

    "industrial_goods_and_services": {
        "ENGC",
        "MBEN",
        "SWDY",
        "GDWA",
        "PACK",
        "ELEC",
        "AUTO",
    },

    "real_estate": {
        "ELKA",
        "MAAL",
        "ASPI",
        "EGTS",
        "ORHD",
        "MNHD",
        "OCDI",
        "EMFD",
        "TMGH",
        "PHDC",
        "HELI",
        "ZMID",
        "ARAB",
        "PRES",
        "SCCD",
    },

    "tourism_and_entertainment": {
        "MHOT",
        "MARS",
        "SHAR",
        "ROWA",
        "WADI",
        "PHTV",
        "RMCO",
    },

    "utilities": {
        "EGAS",
        "TAQA",
    },

    "telecommunications_media_and_technology": {
        "DGTZ",
        "MCIT",
        "EGSA",
        "EFIH",
        "RACC",
        "ORAS",
        "FWRY",
        "ETEL",
    },

    "food_and_beverages": {
        "NATR",
        "NKPD",
        "GSSC",
        "SUGR",
        "ADPC",
        "ISMA",
        "MPCO",
        "EAST",
        "OILS",
        "JUFO",
        "EFID",
        "DOMT",
        "OBRI",
    },

    "energy_and_support_services": {
        "MOIL",
        "AMOC",
    },

    "transportation_and_logistics": {
        "ETRS",
        "ALCN",
        "CSAG",
    },

    "education_services": {
        "MOED",
        "SCTS",
        "TALM",
        "CAED",
        "CIRA",
    },

    "non_bank_financial_services": {
        "ACTF",
        "ARAB",
        "NAHO",
        "RAYA",
        "CICH",
        "BTFH",
        "EAC",
        "PRMH",
        "ASPI",
        "CCAP",
        "UFIN",
        "ODIN",
        "CNFN",
    },

    "contracting_and_construction_engineering": {
        "WKOL",
        "AALR",
        "GIZA",
        "ORAS",
        "ICON",
    },

    "textiles_and_durables": {
        "DSCW",
        "UNIR",
        "GTEX",
        "KABO",
        "ORWE",
    },

    "building_materials": {
        "CERA",
        "MBSC",
        "ARCC",
        "SVCE",
        "LCSW",
        "SCEM",
        "MCQE",
    },

    "paper_and_packaging": {
        "RAKT",
        "UNIP",
        "PRNT",
        "NAPR",
    },
}

# Reverse lookup: symbol -> sector
_SYMBOL_TO_SECTOR: Dict[str, str] = {}
for _sector, _symbols in EGX_SECTORS.items():
    for _sym in _symbols:
        if _sym not in _SYMBOL_TO_SECTOR:
            _SYMBOL_TO_SECTOR[_sym] = _sector


def get_sector(symbol: str) -> str:
    """Return the sector for an EGX symbol, or 'other' if not classified."""
    clean = symbol.upper().replace("EGX:", "")
    return _SYMBOL_TO_SECTOR.get(clean, "other")


def get_symbols_by_sector(sector: str) -> List[str]:
    """Return list of EGX symbols for a given sector."""
    symbols = EGX_SECTORS.get(sector.lower().replace(" ", "_"), set())
    return [f"EGX:{s}" for s in sorted(symbols)]


def get_all_sectors() -> List[str]:
    """Return list of all available EGX sectors."""
    return sorted(EGX_SECTORS.keys())
