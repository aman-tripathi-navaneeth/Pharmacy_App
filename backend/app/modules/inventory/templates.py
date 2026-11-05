"""Ready-made inventory templates for pharmacy owners.

Each template mirrors a real Indian pharmacy shelf section. Owners pick a
template, tick exactly the items they stock, adjust quantity/price/batch
per line in the app, and import. Template item barcodes use fixed unique
ranges (0001-9999 under 8901234567) so an imported line never collides
with a real barcode unless the owner edits it.
"""

from dataclasses import dataclass, field


@dataclass(frozen=True)
class TemplateItem:
    medicineName: str
    barcode: str
    sellingPrice: float
    reorderLevel: int = 10
    unit: str = "pack"


@dataclass(frozen=True)
class InventoryTemplate:
    id: str
    name: str
    description: str
    items: list[TemplateItem] = field(default_factory=list)


def _item(name: str, code: str, price: float, reorder: int = 10, unit: str = "pack") -> TemplateItem:
    return TemplateItem(name, f"8901234567{code}", price, reorder, unit)


TEMPLATES: list[InventoryTemplate] = [
    InventoryTemplate(
        id="general-otc",
        name="General medical store / OTC",
        description="Everyday tablets, syrup, first-aid, antiseptic and rest picks every shop needs",
        items=[
            _item("Paracetamol 500mg tablets", "0001", 15.0, 20),
            _item("Cetrizine 10mg tablets", "0002", 12.0, 15),
            _item("Amoxicillin 250mg capsules", "0003", 45.0, 10),
            _item("Ibuprofen 200mg tablets", "0004", 18.0, 15),
            _item("ORS powder sachet", "0005", 20.0, 25),
            _item("Digene antacid gel 200ml", "0006", 95.0, 8),
            _item("Vicks VapoRub 50g", "0007", 135.0, 6),
            _item("Bandage roll 5cm", "0008", 30.0, 15),
            _item("Cotton roll 100g", "0009", 65.0, 8),
            _item("Antiseptic liquid 250ml", "0010", 85.0, 6),
            _item("Hand sanitizer 100ml", "0011", 60.0, 12),
            _item("Crepe bandage 6cm", "0012", 42.0, 10),
        ],
    ),
    InventoryTemplate(
        id="tablets-capsules",
        name="Tablets & capsules (prescription)",
        description="The tablet strip rack: antibiotics, painkillers, allergy and acidity tablets",
        items=[
            _item("Azithromycin 500mg tablets", "0101", 105.0, 10),
            _item("Rantac Ranitidine 150mg tablets", "0102", 28.0, 15),
            _item("Pantoprazole 40mg tablets", "0103", 68.0, 15),
            _item("Montelukast 10mg tablets", "0104", 122.0, 8),
            _item("Levocetirizine 5mg tablets", "0105", 24.0, 15),
            _item("Dolo 650mg tablets", "0106", 30.0, 20),
            _item("Meftal Spas tablets", "0107", 55.0, 12),
            _item("Cephalexin 500mg capsules", "0108", 96.0, 10),
            _item("Ofloxacin Ornidazole tablets", "0109", 78.0, 10),
            _item("Domperidone 10mg tablets", "0110", 26.0, 15),
            _item("Thyronorm 50mcg tablets", "0111", 145.0, 8, unit="bottle"),
            _item("Serta 100mg tablets", "0112", 118.0, 6),
        ],
    ),
    InventoryTemplate(
        id="syrups-tonics",
        name="Syrups, tonics & liquids",
        description="Cough syrups, digestive tonics and vitamin suspensions",
        items=[
            _item("Cough syrup Benadryl 150ml", "0201", 118.0, 8, unit="bottle"),
            _item("Ascoril LS syrup 100ml", "0202", 126.0, 8, unit="bottle"),
            _item("Zincovit syrup 200ml", "0203", 132.0, 6, unit="bottle"),
            _item("Iron tonic Dexorange 200ml", "0204", 158.0, 6, unit="bottle"),
            _item("Liv 52 DS syrup 200ml", "0205", 165.0, 5, unit="bottle"),
            _item("Gripe water 200ml", "0206", 95.0, 6, unit="bottle"),
            _item("Pan-D suspension 60ml", "0207", 140.0, 5, unit="bottle"),
            _item("Centrum Junior tonic 200ml", "0208", 285.0, 4, unit="bottle"),
        ],
    ),
    InventoryTemplate(
        id="drops",
        name="Drops (eye, ear, nasal)",
        description="Eye drops, ear drops and nasal sprays in small bottles",
        items=[
            _item("Refresh Tears eye drops 10ml", "0301", 138.0, 8, unit="bottle"),
            _item("Ciplox eye drops 10ml", "0302", 24.0, 10, unit="bottle"),
            _item("Otek AC ear drops 10ml", "0303", 145.0, 6, unit="bottle"),
            _item("Sinarest nasal spray 10ml", "0304", 118.0, 8, unit="bottle"),
            _item("Otrivin nasal drops 10ml", "0305", 105.0, 8, unit="bottle"),
            _item("Moisturex eye drops 10ml", "0306", 132.0, 6, unit="bottle"),
            _item("Vigamox eye drops 5ml", "0307", 172.0, 6, unit="bottle"),
        ],
    ),
    InventoryTemplate(
        id="injections",
        name="Injections & ampules",
        description="Ampoules, vials and prefilled pens a counter pharmacy keeps ready",
        items=[
            _item("Deriphyllin injection 2ml", "0401", 32.0, 10, unit="amp"),
            _item("Emeset injection 4mg", "0402", 28.0, 10, unit="amp"),
            _item("TT vaccine ampoule", "0403", 25.0, 8, unit="amp"),
            _item("Insulin mixture 100IU vial", "0404", 320.0, 4, unit="vial"),
            _item("Ceftriaxone 1g vial", "0405", 88.0, 8, unit="vial"),
            _item("Dexona injection 2ml", "0406", 9.0, 15, unit="amp"),
            _item("Heparin 5000IU injection", "0407", 78.0, 6, unit="vial"),
        ],
    ),
    InventoryTemplate(
        id="creams-ointments",
        name="Creams, ointments & gels",
        description="Skin creams, antifungal ointments and pain gels",
        items=[
            _item("ItchGuard cream 30g", "0501", 88.0, 10, unit="tube"),
            _item("Candid dusting powder 100g", "0502", 120.0, 8, unit="pack"),
            _item("Volini pain gel 60g", "0503", 148.0, 8, unit="tube"),
            _item("Moisturex cream 100g", "0504", 175.0, 6, unit="tube"),
            _item("Betadine ointment 20g", "0505", 68.0, 10, unit="tube"),
            _item("Fourderm cream 15g", "0506", 98.0, 8, unit="tube"),
            _item("Ring Guard cream 50g", "0507", 108.0, 8, unit="tube"),
        ],
    ),
    InventoryTemplate(
        id="inhalers-sprays",
        name="Inhalers & sprays",
        description="Asthma inhalers, nasal sprays and throat sprays",
        items=[
            _item("Asthalin HFA inhaler", "0601", 145.0, 6, unit="inhaler"),
            _item("Seroflo 250 inhaler", "0602", 588.0, 4, unit="inhaler"),
            _item("Asthalin Rotacaps inhaler", "0603", 176.0, 5, unit="pack"),
            _item("Rotahaler device", "0604", 65.0, 5, unit="piece"),
            _item("Betadine throat spray", "0605", 132.0, 4, unit="bottle"),
        ],
    ),
    InventoryTemplate(
        id="vitamins-supplements",
        name="Vitamins & supplements",
        description="Daily multivitamins, calcium, protein powders and probiotic picks",
        items=[
            _item("Shelcal 500 tablets", "0701", 118.0, 10, unit="strip"),
            _item("Neurobion Forte tablets", "0702", 34.0, 15, unit="strip"),
            _item("Zincovit tablets", "0703", 105.0, 10, unit="strip"),
            _item("Protein powder chocolate 500g", "0704", 1350.0, 3, unit="jar"),
            _item("B-Complex forte capsules", "0705", 48.0, 12, unit="strip"),
            _item("Omega 3 fish oil capsules", "0706", 380.0, 6, unit="bottle"),
            _item("Enterogermina probiotic vials", "0707", 210.0, 5, unit="pack"),
        ],
    ),
    InventoryTemplate(
        id="chronic-cardio",
        name="BP, sugar & heart medicines",
        description="Long-term prescriptions for BP, diabetes and cholesterol",
        items=[
            _item("Amlodipine 5mg tablets", "0801", 55.0, 15),
            _item("Telmisartan 40mg tablets", "0802", 95.0, 15),
            _item("Metformin 500mg tablets", "0803", 35.0, 20),
            _item("Glimepiride 2mg tablets", "0804", 65.0, 15),
            _item("Atorvastatin 10mg tablets", "0805", 85.0, 12),
            _item("Aspirin 75mg tablets", "0806", 22.0, 15),
            _item("Insulin glargine 100IU pen", "0807", 550.0, 5, unit="pen"),
        ],
    ),
    InventoryTemplate(
        id="ayurvedic",
        name="Ayurvedic & herbal",
        description="Ayurvedic tonics, oils and chyawanprash",
        items=[
            _item("Chyawanprash 1kg", "0901", 320.0, 5),
            _item("Ashwagandha tablets 60", "0902", 180.0, 8),
            _item("Kesari kalp tonic 500ml", "0903", 260.0, 5, unit="bottle"),
            _item("Pain relief herbal oil 60ml", "0904", 140.0, 8, unit="bottle"),
            _item("Triphala churna 100g", "0905", 90.0, 10),
            _item("Aloe vera juice 1L", "0906", 220.0, 6, unit="bottle"),
        ],
    ),
    InventoryTemplate(
        id="surgical",
        name="Surgical & consumables",
        description="Dressings, gloves, syringes and wheeling supplies",
        items=[
            _item("Disposable gloves pair M", "1001", 25.0, 30, unit="pair"),
            _item("Syringe 5ml", "1002", 8.0, 50),
            _item("IV cannula 20G", "1003", 35.0, 20),
            _item("Surgical mask 3-ply box", "1004", 150.0, 5, unit="box"),
            _item("Crepe bandage 10cm", "1005", 55.0, 10),
            _item("Gauze cloth sterile pack", "1006", 40.0, 15),
            _item("Digital thermometer", "1007", 180.0, 3),
            _item("Pulse oximeter", "1008", 950.0, 2),
        ],
    ),
    InventoryTemplate(
        id="baby-care",
        name="Baby & mother care",
        description="Baby food, diapers, feeding and mother care",
        items=[
            _item("Baby diapers pants M pack", "1101", 420.0, 5, unit="pack"),
            _item("Baby milk powder 400g", "1102", 380.0, 5, unit="tin"),
            _item("Baby massage oil 200ml", "1103", 195.0, 6, unit="bottle"),
            _item("Baby lotion 100ml", "1104", 120.0, 8, unit="bottle"),
            _item("Feeding bottle 250ml", "1105", 230.0, 4, unit="piece"),
            _item("Iron folic syrup 200ml", "1106", 145.0, 6, unit="bottle"),
        ],
    ),
]

TEMPLATE_IDS = [t.id for t in TEMPLATES]


def get_template(template_id: str | None) -> InventoryTemplate | None:
    if not template_id:
        return None
    for template in TEMPLATES:
        if template.id == template_id:
            return template
    return None


def describe(template: InventoryTemplate) -> dict:
    return {
        "id": template.id,
        "name": template.name,
        "description": template.description,
        "items": [
            {
                "medicineName": item.medicineName,
                "barcode": item.barcode,
                "sellingPrice": item.sellingPrice,
                "reorderLevel": item.reorderLevel,
                "unit": item.unit,
            }
            for item in template.items
        ],
    }
